import AppKit
import AVFoundation
import AVKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import ProZipCore
import ProZipShared

enum ArchiveHoverPreviewRequest: Equatable {
    case text
    case image
    case media(isVideo: Bool, autoplay: Bool, muted: Bool)
    case icon(message: String?)
}

enum ArchiveHoverPreviewPolicy {
    static let textByteLimit = 64 * 1024
    static let imageByteLimit = 16 * 1024 * 1024
    static let imagePixelLimit = 640

    static func mediaByteLimit(megabytes: Int) -> Int64 {
        guard megabytes > 0 else { return 0 }
        let (bytes, overflow) = Int64(megabytes).multipliedReportingOverflow(by: 1024 * 1024)
        return overflow ? .max : bytes
    }

    static func request(for entry: ArchiveEntry, videoEnabled: Bool, audioAutoplay: Bool, videoMuted: Bool, mediaLimitMB: Int) -> ArchiveHoverPreviewRequest {
        guard entry.type == .file else { return .icon(message: nil) }
        let ext = entry.fileExtension
        let type = UTType(filenameExtension: ext)
        if type?.conforms(to: .image) == true {
            guard entry.uncompressedSize >= 0, entry.uncompressedSize <= Int64(imageByteLimit) else {
                return .icon(message: "图片超过 16 MB 或大小未知，无法悬浮预览")
            }
            return .image
        }
        let isVideo = type?.conforms(to: .movie) == true || ["mp4", "mov", "m4v", "mkv", "avi", "webm"].contains(ext)
        let isAudio = type?.conforms(to: .audio) == true || ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "ogg", "opus"].contains(ext)
        if isVideo || isAudio {
            if isVideo && !videoEnabled { return .icon(message: "已关闭视频悬浮播放") }
            let limit = mediaByteLimit(megabytes: mediaLimitMB)
            guard limit > 0, entry.uncompressedSize >= 0, entry.uncompressedSize <= limit else {
                return .icon(message: "媒体超过预览大小上限或大小未知")
            }
            return .media(isVideo: isVideo, autoplay: isVideo || audioAutoplay, muted: isVideo && videoMuted)
        }
        if type?.conforms(to: .text) == true || ["json", "yaml", "yml", "toml", "md", "log", "swift", "js", "ts", "py", "sh", "csv", "ini", "conf"].contains(ext) {
            return .text
        }
        return .icon(message: nil)
    }

    static func text(from data: Data) -> String? {
        guard data.count <= textByteLimit else { return nil }
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            if let text = String(data: data, encoding: .utf16) { return text }
            return data.count == textByteLimit ? String(data: data.dropLast(2), encoding: .utf16) : nil
        }
        guard !data.contains(0) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        // The byte cap may split the last UTF-8 character; keep only a valid, unchanged prefix.
        if data.count == textByteLimit {
            for count in 1...3 {
                if let text = String(data: data.dropLast(count), encoding: .utf8) { return text }
            }
        }
        return nil
    }

    static func thumbnail(from data: Data) async throws -> CGImage? {
        try Task.checkCancellation()
        guard data.count <= imageByteLimit,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: imagePixelLimit,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
        try Task.checkCancellation()
        return image
    }
}

@MainActor
private final class ArchiveHoverPreviewModel: ObservableObject {
    enum Content {
        case loading
        case text(String, truncated: Bool)
        case image(NSImage)
        case media(AVPlayer, isVideo: Bool)
        case icon(String?)
    }

    @Published private(set) var content: Content = .icon(nil)
    private var generation = UUID()
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var failureObservation: NSObjectProtocol?

    func stop() {
        generation = UUID()
        clearPlayer()
        content = .icon(nil)
    }

    private func clearPlayer() {
        statusObservation?.invalidate()
        statusObservation = nil
        if let failureObservation { NotificationCenter.default.removeObserver(failureObservation) }
        failureObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    func load(_ entry: ArchiveEntry, in session: ArchiveBrowsingSession, using model: ProZipAppViewModel, request: ArchiveHoverPreviewRequest, mediaLimit: Int64) async {
        guard !Task.isCancelled else { return }
        stop()
        let token = generation
        content = .loading
        do {
            switch request {
            case .icon(let message):
                content = .icon(message)
            case .text:
                let data = try await model.previewBytes(for: entry, in: session, maximumCount: ArchiveHoverPreviewPolicy.textByteLimit)
                try Task.checkCancellation()
                guard token == generation else { return }
                guard let text = ArchiveHoverPreviewPolicy.text(from: data) else { throw ProZipError.invalidArchive("无法识别文本编码") }
                content = .text(text, truncated: entry.uncompressedSize > Int64(ArchiveHoverPreviewPolicy.textByteLimit))
            case .image:
                let data = try await model.previewBytes(for: entry, in: session, maximumCount: ArchiveHoverPreviewPolicy.imageByteLimit)
                guard let image = try await ArchiveHoverPreviewPolicy.thumbnail(from: data) else { throw ProZipError.invalidArchive("无法解码此图片") }
                try Task.checkCancellation()
                guard token == generation else { return }
                content = .image(NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
            case .media(let isVideo, let autoplay, let muted):
                let url = try await model.exportEntry(entry, in: session)
                try Task.checkCancellation()
                guard token == generation else { return }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard url.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize, size >= 0, Int64(size) <= mediaLimit else {
                    throw ProZipError.invalidArchive("媒体来源不可读或超过预览大小上限")
                }
                let asset = AVURLAsset(url: url)
                let playable = try await withTaskCancellationHandler {
                    try await asset.load(.isPlayable)
                } onCancel: {
                    asset.cancelLoading()
                }
                try Task.checkCancellation()
                guard token == generation else { return }
                guard playable else { throw ProZipError.invalidArchive("系统无法播放此媒体格式") }
                let item = AVPlayerItem(asset: asset)
                let player = AVPlayer(playerItem: item)
                player.isMuted = muted
                self.player = player
                content = .media(player, isVideo: isVideo)
                statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak player] item, _ in
                    Task { @MainActor in
                        guard let self, self.generation == token, let player, self.player === player else { return }
                        if item.status == .failed {
                            self.fail(item.error?.localizedDescription ?? "媒体无法播放", token: token)
                        } else if item.status == .readyToPlay && autoplay {
                            player.play()
                        }
                    }
                }
                failureObservation = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
                    let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "媒体无法继续播放"
                    Task { @MainActor in self?.fail(message, token: token) }
                }
            }
        } catch is CancellationError {
            if token == generation { stop() }
        } catch {
            guard !Task.isCancelled else { return }
            fail(error.localizedDescription, token: token)
        }
    }

    private func fail(_ message: String, token: UUID) {
        guard token == generation else { return }
        clearPlayer()
        content = .icon("无法预览：\(message)")
    }

    deinit {
        statusObservation?.invalidate()
        if let failureObservation { NotificationCenter.default.removeObserver(failureObservation) }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }
}

@MainActor
public struct ArchiveHoverContent: View {
    public let entry: ArchiveEntry
    @ObservedObject public var session: ArchiveBrowsingSession
    @EnvironmentObject private var appViewModel: ProZipAppViewModel
    @ObservedObject private var preferences = ProZipPreferences.shared
    @StateObject private var preview = ArchiveHoverPreviewModel()

    public init(entry: ArchiveEntry, session: ArchiveBrowsingSession) {
        self.entry = entry
        self.session = session
    }

    private var request: ArchiveHoverPreviewRequest {
        ArchiveHoverPreviewPolicy.request(for: entry, videoEnabled: preferences.hoverVideoEnabled, audioAutoplay: preferences.hoverAudioAutoplay, videoMuted: preferences.hoverVideoMuted, mediaLimitMB: preferences.hoverVideoLimitMB)
    }

    private var requestID: String {
        "\(session.id):\(session.url):\(session.displayedEntriesRevision):\(entry.id):\(entry.type):\(entry.modifiedAt):\(preferences.hoverVideoEnabled):\(preferences.hoverAudioAutoplay):\(preferences.hoverVideoMuted):\(preferences.hoverVideoLimitMB)"
    }

    public var body: some View {
        Group {
            switch preview.content {
            case .loading:
                ProgressView().controlSize(.small).accessibilityLabel("正在读取预览")
            case .text(let text, let truncated):
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if truncated { Text("仅显示文件开头").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                .padding(10)
            case .image(let image):
                Image(nsImage: image).resizable().scaledToFit().padding(2)
            case .media(let player, let isVideo):
                VideoPlayer(player: player)
                    .overlay {
                        if !isVideo {
                            Image(systemName: "waveform")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.45))
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(isVideo ? "视频预览" : "音频预览")
            case .icon(let message):
                VStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(for: entry.isDirectory ? .folder : UTType(filenameExtension: entry.fileExtension) ?? .data))
                        .resizable().scaledToFit().frame(width: 48, height: 48)
                    if let message {
                        Text(message).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 160)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: requestID) {
            await preview.load(entry, in: session, using: appViewModel, request: request, mediaLimit: ArchiveHoverPreviewPolicy.mediaByteLimit(megabytes: preferences.hoverVideoLimitMB))
        }
        .onDisappear { preview.stop() }
    }
}
