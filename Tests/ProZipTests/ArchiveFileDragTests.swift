import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import XCTest
import ProZipShared
import ProZipUI

@MainActor
final class ArchiveFileDragTests: XCTestCase {
    private func dragView(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).contains("ArchiveFileDragView") { return view }
        return view.subviews.lazy.compactMap { self.dragView(in: $0) }.first
    }

    func testHostedRowOverlayFillsHitAreaAndReceivesClicksInAMovableBorderlessWindow() throws {
        _ = NSApplication.shared
        var clicks: [(Int, NSEvent.ModifierFlags)] = []
        var hoverEvents: [Bool] = []
        let entry = ArchiveEntry(path: "readme.txt", type: .file)
        let row = Text(entry.name)
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(Rectangle())
            .overlay {
                ArchiveFileDragSource(entries: { [entry] }, exportEntry: { _ in
                    XCTFail("A click must not materialize a promised file")
                    throw CocoaError(.fileReadUnknown)
                }, onClick: { clicks.append(($0, $1)) }, onError: { XCTFail("\($0)") }, onHover: { hoverEvents.append($0) })
                .accessibilityHidden(true)
            }
            .contextMenu { Button("Context item") {} }
        let hosting = NSHostingView(rootView: VStack(spacing: 0) {
            Color.clear.frame(height: 96)
            row.frame(height: 38)
            Spacer(minLength: 0)
        }.frame(width: 560, height: 422))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 422), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 422)
        hosting.layoutSubtreeIfNeeded()
        let native = try XCTUnwrap(dragView(in: hosting))
        XCTAssertEqual(native.bounds.width, 560, accuracy: 0.5)
        XCTAssertEqual(native.bounds.height, 38, accuracy: 0.5)
        XCTAssertFalse(native.mouseDownCanMoveWindow)
        let frame = hosting.convert(native.bounds, from: native)
        for point in [NSPoint(x: frame.midX, y: frame.midY), NSPoint(x: frame.minX + 2, y: frame.midY), NSPoint(x: frame.maxX - 2, y: frame.midY)] {
            let hit = hosting.hitTest(hosting.convert(point, to: hosting.superview))
            XCTAssertTrue(hit === native, "Row point \(point) hit \(String(describing: hit)) instead of the native drag source")
        }
        let location = native.convert(NSPoint(x: native.bounds.midX, y: native.bounds.midY), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [.command], timestamp: 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 2, pressure: 0))
        native.mouseDown(with: down)
        XCTAssertEqual(hoverEvents, [true])
        native.mouseUp(with: up)
        XCTAssertEqual(clicks.count, 1)
        XCTAssertEqual(clicks.first?.0, 2)
        XCTAssertEqual(clicks.first?.1, [.command])
        XCTAssertFalse(window.isVisible)
    }

    func testHoverTrackingUsesCurrentConfigurationWithoutAccumulatingAndExitsOnRemoval() throws {
        _ = NSApplication.shared
        let entry = ArchiveEntry(path: "preview.mp4", type: .file)
        var originalEvents: [Bool] = []
        var updatedEvents: [Bool] = []
        func source(onHover: @escaping @MainActor (Bool) -> Void) -> ArchiveFileDragSource {
            ArchiveFileDragSource(entries: { [entry] }, exportEntry: { _ in throw CocoaError(.fileReadUnknown) }, onClick: { _, _ in }, onError: { XCTFail("\($0)") }, onHover: onHover)
        }
        let hosting = NSHostingView(rootView: source { originalEvents.append($0) })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 38), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: 240, height: 38)
        hosting.layoutSubtreeIfNeeded()
        let native = try XCTUnwrap(dragView(in: hosting))
        for _ in 0..<3 { native.updateTrackingAreas() }
        let areas = native.trackingAreas.filter { ($0.owner as? NSView) === native }
        XCTAssertEqual(areas.count, 1)
        XCTAssertTrue(try XCTUnwrap(areas.first).options.contains([.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]))
        let entered = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, trackingNumber: 1, userData: nil))
        let exited = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0.01, windowNumber: window.windowNumber, context: nil, eventNumber: 2, trackingNumber: 1, userData: nil))
        native.mouseEntered(with: entered)
        native.mouseEntered(with: entered)
        native.mouseExited(with: exited)
        XCTAssertEqual(originalEvents, [true, false])

        hosting.rootView = source { updatedEvents.append($0) }
        hosting.layoutSubtreeIfNeeded()
        XCTAssertTrue(dragView(in: hosting) === native)
        native.mouseEntered(with: entered)
        XCTAssertEqual(originalEvents, [true, false])
        XCTAssertEqual(updatedEvents, [true])
        ArchiveFileDragSource.dismantleNSView(native, coordinator: ())
        XCTAssertEqual(updatedEvents, [true, false])
        XCTAssertTrue(native.trackingAreas.filter { ($0.owner as? NSView) === native }.isEmpty)

        native.updateTrackingAreas()
        native.mouseEntered(with: entered)
        native.removeFromSuperview()
        XCTAssertNil(native.window)
        XCTAssertEqual(updatedEvents, [true, false, true, false])
        XCTAssertTrue(native.trackingAreas.filter { ($0.owner as? NSView) === native }.isEmpty)
        native.mouseExited(with: exited)
        XCTAssertEqual(updatedEvents, [true, false, true, false])
        XCTAssertFalse(window.isVisible)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-drag-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ provider: NSFilePromiseProvider, to destination: URL) async throws {
        let delegate = try XCTUnwrap(provider.delegate)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.filePromiseProvider(provider, writePromiseTo: destination) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func testNativePasteboardAdvertisesMultiplePromisesAndProviderWritesRealBytesLazily() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("received", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let entries = [ArchiveEntry(path: "nested/first.txt", type: .file), ArchiveEntry(path: "second.bin", type: .file)]
        let bytes = [Data("promised 文本\n".utf8), Data([0, 1, 127, 128, 255])]
        var sources: [String: URL] = [:]
        for (index, entry) in entries.enumerated() {
            let source = root.appendingPathComponent(entry.name)
            try bytes[index].write(to: source)
            sources[entry.id] = source
        }
        var exports = 0
        let providers = try ArchiveFileDrag.makeProviders(entries: entries, exportEntry: { entry in
            exports += 1
            return try XCTUnwrap(sources[entry.id])
        }, onError: { XCTFail("Unexpected promise error: \($0)") })
        XCTAssertEqual(exports, 0)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects(providers))
        let receivers = try XCTUnwrap(pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver])
        XCTAssertEqual(receivers.count, 2)
        XCTAssertEqual(exports, 0)
        // macOS 27 restricts receiver fulfillment to a live drop; exercise the provider's real writer without a UI drag.
        for (index, receiver) in receivers.enumerated() {
            XCTAssertEqual(receiver.fileTypes, [providers[index].fileType])
            let received = destination.appendingPathComponent(entries[index].name)
            try await write(providers[index], to: received)
            XCTAssertEqual(received.deletingLastPathComponent().standardizedFileURL, destination.standardizedFileURL)
            XCTAssertEqual(received.lastPathComponent, entries[index].name)
            XCTAssertEqual(try Data(contentsOf: received), bytes[index])
        }
        XCTAssertEqual(exports, 2)
    }

    func testDirectoryPromiseCopiesSubtreeAndSymlinkWithoutDuplicatingSelectedChild() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("received", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("subtree".utf8).write(to: source.appendingPathComponent("nested/readme.txt"))
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("readme-link").path, withDestinationPath: "nested/readme.txt")
        let directory = ArchiveEntry(path: "archive/folder", type: .directory)
        let child = ArchiveEntry(path: "archive/folder/nested/readme.txt", type: .file)
        let providers = try ArchiveFileDrag.makeProviders(entries: [directory, child, directory], exportEntry: { entry in
            XCTAssertEqual(entry.id, directory.id)
            return source
        }, onError: { XCTFail("Unexpected directory promise error: \($0)") })
        XCTAssertEqual(providers.count, 1)
        XCTAssertEqual(providers[0].fileType, UTType.folder.identifier)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects(providers))
        let receivers = try XCTUnwrap(pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver])
        XCTAssertEqual(receivers.count, 1)
        let received = destination.appendingPathComponent("folder", isDirectory: true)
        try await write(providers[0], to: received)
        XCTAssertEqual(received.lastPathComponent, "folder")
        XCTAssertEqual(try String(contentsOf: received.appendingPathComponent("nested/readme.txt")), "subtree")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: received.appendingPathComponent("readme-link").path), "nested/readme.txt")
    }

    func testPromiseUsesReceiverFilenameAndRefusesToOverwriteExistingFiles() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.txt")
        let destination = root.appendingPathComponent("Finder chosen name.txt")
        try Data("exported".utf8).write(to: source)
        let entry = ArchiveEntry(path: "original.txt", type: .file)
        let providers = try ArchiveFileDrag.makeProviders(entries: [entry], exportEntry: { _ in source }, onError: { XCTFail("\($0)") })
        try await write(XCTUnwrap(providers.first), to: destination)
        XCTAssertEqual(try String(contentsOf: destination), "exported")

        let keep = Data("keep existing".utf8)
        try keep.write(to: destination)
        var reported = false
        let conflicting = try ArchiveFileDrag.makeProviders(entries: [entry], exportEntry: { _ in source }, onError: { _ in reported = true })
        do {
            try await write(XCTUnwrap(conflicting.first), to: destination)
            XCTFail("An existing destination must not be overwritten")
        } catch { XCTAssertEqual((error as NSError).code, Int(EEXIST)) }
        XCTAssertTrue(reported)
        XCTAssertEqual(try Data(contentsOf: destination), keep)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".prozip-drop-") }))
    }

    func testExportFailureReturnsErrorWithoutCreatingAPlaceholder() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("secret.txt")
        var reported = false
        let providers = try ArchiveFileDrag.makeProviders(entries: [ArchiveEntry(path: "secret.txt", type: .file)], exportEntry: { _ in
            throw ProZipError.passwordRequired("secret.txt")
        }, onError: { _ in reported = true })
        do {
            try await write(XCTUnwrap(providers.first), to: destination)
            XCTFail("A failed export must fail the promise")
        } catch { XCTAssertTrue(error.localizedDescription.contains("secret.txt")) }
        XCTAssertTrue(reported)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testDirectoryPromiseRejectsItsOwnDescendantIncludingSymlinkedDestinations() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let child = source.appendingPathComponent("child", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
        let entry = ArchiveEntry(path: "folder", type: .directory)
        for destination in [child.appendingPathComponent("folder"), alias.appendingPathComponent("child/folder")] {
            let providers = try ArchiveFileDrag.makeProviders(entries: [entry], exportEntry: { _ in source }, onError: { _ in })
            do {
                try await write(XCTUnwrap(providers.first), to: destination)
                XCTFail("A promised directory must not recursively copy into itself")
            } catch { XCTAssertTrue(error.localizedDescription.contains("自身")) }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
    }

    func testCancellationStopsDelayedMaterializationAndReturnsCancellation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("cancelled.txt")
        let started = expectation(description: "Delayed materialization starts")
        let providers = try ArchiveFileDrag.makeProviders(entries: [ArchiveEntry(path: "cancelled.txt", type: .file)], exportEntry: { _ in
            started.fulfill()
            try await Task.sleep(for: .seconds(30))
            return root.appendingPathComponent("never-created")
        }, onError: { XCTFail("Cancellation should not show an error alert: \($0)") })
        let transfer = Task { try await write(XCTUnwrap(providers.first), to: destination) }
        await fulfillment(of: [started], timeout: 3)
        ArchiveFileDrag.cancel(providers)
        do {
            try await transfer.value
            XCTFail("A cancelled promise must not report success")
        } catch { XCTAssertEqual((error as NSError).code, CocoaError.userCancelled.rawValue) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}
