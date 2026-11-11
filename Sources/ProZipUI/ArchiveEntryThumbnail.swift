import SwiftUI
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers
import ProZipCore
import ProZipShared

@MainActor
private enum ArchiveThumbnailCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    static let texts: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 256
        cache.totalCostLimit = 2 * 1024 * 1024
        return cache
    }()
}

struct ArchiveEntryThumbnail: View {
    let entry: ArchiveEntry
    @ObservedObject var session: ArchiveBrowsingSession
    var size: CGSize = CGSize(width: 116, height: 114)
    @EnvironmentObject private var appViewModel: ProZipAppViewModel
    @State private var image: NSImage?
    @State private var text: String?

    private var cacheKey: String {
        "\(session.id):\(session.displayedEntriesRevision):\(entry.id):\(Int(size.width))"
    }

    var body: some View {
        Group {
            if let text {
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.name).font(.system(size: 7.5))
                    Text(text).font(.system(size: 6.5, design: .monospaced)).lineSpacing(2).lineLimit(8)
                }
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
                .frame(width: 230)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                .scaleEffect(size.width / 230)
            } else if let image {
                let factor = min(size.width / max(1, image.size.width), size.height / max(1, image.size.height))
                Image(nsImage: image).resizable()
                    .frame(width: image.size.width * factor, height: image.size.height * factor)
                    .clipShape(RoundedRectangle(cornerRadius: size.width > 200 ? 14 : 3))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(for: entry.isDirectory ? .folder : UTType(filenameExtension: entry.fileExtension) ?? .data))
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width < 40 ? size.width : min(size.width * 0.74, 88), height: size.height < 40 ? size.height : min(size.height * 0.74, 88))
            }
        }
        .offset(y: size.width >= 40 && size.width < 150 ? 3 : 0)
        .frame(width: size.width, height: size.height)
        .task(id: cacheKey) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        image = nil
        text = nil
        guard !entry.isDirectory else { return }
        let key = cacheKey as NSString
        if let cached = ArchiveThumbnailCache.texts.object(forKey: key) { text = cached as String; return }
        if let cached = ArchiveThumbnailCache.images.object(forKey: key) { image = cached; return }
        let type = UTType(filenameExtension: entry.fileExtension)
        if type?.conforms(to: .text) == true || ["json", "yaml", "yml", "toml", "md", "log", "swift", "js", "ts", "py", "sh"].contains(entry.fileExtension.lowercased()) {
            if let data = try? await appViewModel.previewBytes(for: entry, in: session, maximumCount: 4096), !data.contains(0), !Task.isCancelled {
                let value = String(decoding: data, as: UTF8.self)
                ArchiveThumbnailCache.texts.setObject(value as NSString, forKey: key, cost: data.count)
                text = value
            }
            return
        }
        // shortcut: cap automatic materialization at 32 MiB; add format-specific thumbnail readers for larger files.
        guard entry.uncompressedSize <= 32 * 1024 * 1024 else { return }
        do {
            let url = try await appViewModel.exportEntry(entry, in: session)
            try Task.checkCancellation()
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: size,
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            let representation = try await withTaskCancellationHandler {
                try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            } onCancel: {
                QLThumbnailGenerator.shared.cancel(request)
            }
            try Task.checkCancellation()
            let result = representation.nsImage
            ArchiveThumbnailCache.images.setObject(result, forKey: key, cost: Int(size.width * size.height * 16))
            image = result
        } catch {
            // Locked and unsupported entries keep their file icon until a preview can be read.
        }
    }
}
