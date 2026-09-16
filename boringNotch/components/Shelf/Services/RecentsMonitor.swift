//
//  RecentsMonitor.swift
//  boringNotch
//
//  Watches Downloads, the screenshot folder, and Desktop and publishes
//  the newest files for the notch recents strip.
//

import AppKit
import Combine
import Darwin
import Defaults
import Foundation

struct RecentFile: Identifiable, Equatable, Hashable {
    let url: URL
    let date: Date
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

@MainActor
final class RecentsMonitor: ObservableObject {
    static let shared = RecentsMonitor()

    @Published private(set) var files: [RecentFile] = []

    private var watchers: [DispatchSourceFileSystemObject] = []
    private var directoryFDs: [Int32] = []
    private var debounceTask: Task<Void, Never>?
    private var started = false

    private let skipExtensions: Set<String> = [
        "crdownload", "download", "part", "tmp", "temp", "incomplete",
        "filepart", "aria2", "dsstore",
    ]

    private init() {}

    func start() {
        guard !started else {
            refresh()
            return
        }
        started = true
        refresh()
        startWatching()
    }

    func refresh() {
        guard Defaults[.showRecentFiles] else {
            if !files.isEmpty { files = [] }
            return
        }
        files = scan(limit: Defaults[.recentFilesLimit])
    }

    func watchFolders() -> [URL] {
        var folders: [URL] = []
        let fm = FileManager.default
        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            folders.append(downloads)
        }
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            folders.append(desktop)
        }
        if let shots = screenshotFolder() {
            folders.append(shots)
        }
        return folders.filter { fm.fileExists(atPath: $0.path) }
    }

    private func screenshotFolder() -> URL? {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let path = defaults?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        return pictures?.appendingPathComponent("Screenshots", isDirectory: true)
    }

    private func scan(limit: Int) -> [RecentFile] {
        let fm = FileManager.default
        var seen = Set<String>()
        var collected: [RecentFile] = []

        for folder in watchFolders() {
            let contents = (try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .isHiddenKey, .isAliasFileKey,
                    .creationDateKey, .contentModificationDateKey,
                    .addedToDirectoryDateKey, .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents {
                let path = url.standardizedFileURL.path
                guard !seen.contains(path) else { continue }
                guard shouldInclude(url) else { continue }
                let date = recencyDate(for: url)
                seen.insert(path)
                collected.append(RecentFile(url: url, date: date))
            }
        }

        collected.sort { $0.date > $1.date }
        return Array(collected.prefix(max(limit, 1)))
    }

    private func shouldInclude(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .isHiddenKey, .isAliasFileKey, .fileSizeKey,
        ])
        if values?.isDirectory == true { return false }
        if values?.isHidden == true { return false }
        if values?.isAliasFile == true { return false }
        if (values?.fileSize ?? 0) == 0 { return false }

        let ext = url.pathExtension.lowercased()
        if skipExtensions.contains(ext) { return false }

        let name = url.lastPathComponent
        if name.hasPrefix(".") { return false }
        if name.hasPrefix("~") { return false }
        return true
    }

    private func recencyDate(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [
            .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey,
        ])
        return [values?.addedToDirectoryDate, values?.creationDate, values?.contentModificationDate]
            .compactMap { $0 }
            .max() ?? Date.distantPast
    }

    private func startWatching() {
        stopWatching()
        let queue = DispatchQueue(label: "theboringteam.boringnotch.recents", qos: .utility)

        for folder in watchFolders() {
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            directoryFDs.append(fd)
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .delete, .rename, .link],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in
                    self?.scheduleRefresh()
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            watchers.append(source)
        }
    }

    private func stopWatching() {
        watchers.forEach { $0.cancel() }
        watchers.removeAll()
        directoryFDs.removeAll()
    }

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }
}
