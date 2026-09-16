//
//  RecentsStripView.swift
//  boringNotch
//
//  Last-N recents row styled like the rest of the open notch.
//

import AppKit
import Defaults
import SwiftUI

struct RecentsStripView: View {
    @ObservedObject private var recents = RecentsMonitor.shared
    var excludingPaths: Set<String> = []

    private var visible: [RecentFile] {
        recents.files.filter { !excludingPaths.contains($0.url.standardizedFileURL.path) }
    }

    var body: some View {
        Group {
            if visible.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                    Text("No recent files")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(visible) { file in
                            RecentFileTile(file: file)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .onAppear {
            RecentsMonitor.shared.start()
        }
    }
}

private struct RecentFileTile: View {
    let file: RecentFile
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.opened,
                        style: .continuous
                    )
                )

            Text(file.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(hovering ? .white : Color(white: 0.65))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 64)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(hovering ? Color.white.opacity(0.08) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering = $0 }
        .help(file.url.path)
        .onTapGesture {
            NSWorkspace.shared.open(file.url)
        }
        .onDrag {
            NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(file.url) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Divider()
            Button("Move to Trash", role: .destructive) {
                NSWorkspace.shared.recycle([file.url]) { _, _ in
                    RecentsMonitor.shared.refresh()
                }
            }
        }
        .task(id: file.id) {
            thumbnail = await loadThumbnail(for: file.url)
        }
    }

    private func loadThumbnail(for url: URL) async -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"]
        guard imageExts.contains(ext), let image = NSImage(contentsOf: url) else {
            return icon
        }
        let size = NSSize(width: 88, height: 88)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let ratio = min(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
        let drawSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let origin = NSPoint(x: (size.width - drawSize.width) / 2, y: (size.height - drawSize.height) / 2)
        image.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        thumb.unlockFocus()
        return thumb
    }
}
