import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
import ProZipShared
@testable import ProZipUI

@MainActor
final class ArchiveHoverContentTests: XCTestCase {
    private func request(_ path: String, size: Int64 = 100, type: EntryType = .file, video: Bool = true, autoplay: Bool = true, muted: Bool = true, limitMB: Int = 10) -> ArchiveHoverPreviewRequest {
        ArchiveHoverPreviewPolicy.request(for: ArchiveEntry(path: path, type: type, uncompressedSize: size), videoEnabled: video, audioAutoplay: autoplay, videoMuted: muted, mediaLimitMB: limitMB)
    }

    private func assertIcon(_ request: ArchiveHoverPreviewRequest, file: StaticString = #filePath, line: UInt = #line) {
        guard case .icon = request else { return XCTFail("Expected an icon without automatic content loading", file: file, line: line) }
    }

    func testTextPrefixesAndImageSizeBoundariesUseTheirOwnLimits() {
        XCTAssertEqual(ArchiveHoverPreviewPolicy.textByteLimit, 64 * 1024)
        XCTAssertEqual(request("large.txt", size: .max), .text)
        XCTAssertEqual(request("script.SWIFT"), .text)
        XCTAssertEqual(request("image.PNG", size: 16 * 1024 * 1024), .image)
        assertIcon(request("image.png", size: 16 * 1024 * 1024 + 1))
        assertIcon(request("image.png", size: -1))
    }

    func testVideoSwitchAndSizeLimitApplyBeforeMediaMaterialization() {
        assertIcon(request("movie.mp4", video: false))
        let limit = Int64(10 * 1024 * 1024)
        XCTAssertEqual(request("movie.mov", size: limit), .media(isVideo: true, autoplay: true, muted: true))
        XCTAssertEqual(request("sound.m4a", size: limit), .media(isVideo: false, autoplay: true, muted: false))
        assertIcon(request("movie.mp4", size: limit + 1))
        assertIcon(request("sound.mp3", size: limit + 1))
        assertIcon(request("sound.mp3", size: -1))
        assertIcon(request("sound.mp3", limitMB: 0))
        XCTAssertEqual(ArchiveHoverPreviewPolicy.mediaByteLimit(megabytes: .max), .max)
        XCTAssertEqual(ArchiveHoverPreviewPolicy.mediaByteLimit(megabytes: -1), 0)
    }

    func testAudioAutoplayAndVideoMuteHaveSeparateEffects() {
        XCTAssertEqual(request("sound.wav", autoplay: false, muted: true), .media(isVideo: false, autoplay: false, muted: false))
        XCTAssertEqual(request("sound.wav", video: false, autoplay: true, muted: true), .media(isVideo: false, autoplay: true, muted: false))
        XCTAssertEqual(request("movie.m4v", autoplay: false, muted: false), .media(isVideo: true, autoplay: true, muted: false))
    }

    func testDirectoriesLinksAndUnsupportedFilesDoNotStartAContentReader() {
        assertIcon(request("folder.mp4", type: .directory))
        assertIcon(request("link.png", type: .symlink))
        assertIcon(request("socket.wav", type: .special))
        assertIcon(request("unknown.prozip-test-binary"))
    }

    func testTextDecoderPreservesRealTextAndOnlyTrimsACutCharacterAtTheCap() throws {
        let value = "实际文本\nsecond line"
        XCTAssertEqual(ArchiveHoverPreviewPolicy.text(from: Data(value.utf8)), value)
        let utf16 = Data([0xff, 0xfe]) + (try XCTUnwrap(value.data(using: .utf16LittleEndian)))
        XCTAssertEqual(ArchiveHoverPreviewPolicy.text(from: utf16), value)
        XCTAssertNil(ArchiveHoverPreviewPolicy.text(from: Data([0x61, 0, 0x62])))
        XCTAssertNil(ArchiveHoverPreviewPolicy.text(from: Data([0xff])))
        var cut = Data(repeating: 0x61, count: 64 * 1024 - 1)
        cut.append(0xe7)
        XCTAssertEqual(ArchiveHoverPreviewPolicy.text(from: cut)?.utf8.count, 64 * 1024 - 1)
        XCTAssertNil(ArchiveHoverPreviewPolicy.text(from: Data(repeating: 0x61, count: 64 * 1024 + 1)))
    }

    func testImageDecodeProducesABoundedThumbnailAndRejectsInvalidBytes() async throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 1024, height: 768, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1024, height: 768))
        let source = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, source, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let decoded = try await ArchiveHoverPreviewPolicy.thumbnail(from: data as Data)
        let thumbnail = try XCTUnwrap(decoded)
        XCTAssertLessThanOrEqual(thumbnail.width, ArchiveHoverPreviewPolicy.imagePixelLimit)
        XCTAssertLessThanOrEqual(thumbnail.height, ArchiveHoverPreviewPolicy.imagePixelLimit)
        XCTAssertEqual(Double(thumbnail.width) / Double(thumbnail.height), 4.0 / 3.0, accuracy: 0.01)
        let invalid = try await ArchiveHoverPreviewPolicy.thumbnail(from: Data("not an image".utf8))
        XCTAssertNil(invalid)
    }

    func testCancelledThumbnailWorkStopsBeforeDecoding() async throws {
        let task = Task { try await ArchiveHoverPreviewPolicy.thumbnail(from: Data()) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {}
    }
}
