//
//  RecentsStripView.swift
//  boringNotch
//
//  Compact last-N recents row for the open notch (home + shelf).
//

import AppKit
import Defaults
import SwiftUI

struct RecentsStripView: View {
    @ObservedObject private var recents = RecentsMonitor.shared
    var excludingPaths: Set<String> = []
    var wrappingScroll: Bool = true

    private var visible: [RecentFile] {
        recents.files.filter { !excludingPaths.contains($0.url.standardizedFileURL.path) }
    }

    var body: some View {
        Group {
            if visible.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.gray)
                    Text("No recent files yet")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if wrappingScroll {
                ScrollView(.horizontal, showsIndicators: false) {
                    tiles
                }
            } else {
                tiles
            }
        }
        .onAppear {
            RecentsMonitor.shared.start()
        }
    }

    private var tiles: some View {
        HStack(spacing: 8) {
            ForEach(visible) { file in
                RecentFileTile(file: file)
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct RecentFileTile: View {
    let file: RecentFile
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: hovering ? 4 : 2, y: 1)

            Text(file.name)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 56)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
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
        let size = NSSize(width: 80, height: 80)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let ratio = min(size.width / image.size.width, size.height / image.size.height)
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
