import AppKit
import SwiftUI
import XCTest
import ProZipShared
@testable import ProZipUI

@MainActor
final class WindowDragAreaTests: XCTestCase {
    private final class MockSheetWindow: NSWindow {
        var mockedSheetParent: NSWindow?
        override var sheetParent: NSWindow? { mockedSheetParent }
    }

    func testResolveRootWindowWalksSheetParentChain() {
        let root = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 560, height: 390),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let firstSheet = MockSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        firstSheet.mockedSheetParent = root

        let nestedSheet = MockSheetWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        nestedSheet.mockedSheetParent = firstSheet

        XCTAssertTrue(WindowDragArea.resolveRootWindow(from: root) === root)
        XCTAssertTrue(WindowDragArea.resolveRootWindow(from: firstSheet) === root)
        XCTAssertTrue(WindowDragArea.resolveRootWindow(from: nestedSheet) === root)
        XCTAssertNil(WindowDragArea.resolveRootWindow(from: nil))
    }

    func testArchiveCreationDialogContainsInteractiveWindowDragAreas() {
        let vm = makeTestAppViewModel()
        let dialog = ArchiveCreationDialogView(defaultName: "drag-test", appViewModel: vm)
            .environmentObject(vm)
        let hosting = NSHostingView(rootView: dialog)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        hosting.layoutSubtreeIfNeeded()

        func collectDragViews(in view: NSView) -> [NSView] {
            var matches: [NSView] = []
            if view.mouseDownCanMoveWindow && String(describing: type(of: view)).contains("DragStripView") {
                matches.append(view)
            }
            for subview in view.subviews {
                matches.append(contentsOf: collectDragViews(in: subview))
            }
            return matches
        }

        let dragViews = collectDragViews(in: hosting)
        XCTAssertGreaterThanOrEqual(dragViews.count, 2)
    }
}
