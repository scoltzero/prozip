import Combine
import XCTest
import ProZipCore
import ProZipUI

@MainActor
final class SessionObservationTests: XCTestCase {
    func testSessionChangesAreForwardedOnlyWhileTheSessionIsAttached() async throws {
        let model = makeTestAppViewModel()
        let removed = ArchiveBrowsingSession()
        let current = ArchiveBrowsingSession()
        var notifications = 0
        let subscription = model.objectWillChange.sink { notifications += 1 }
        defer { subscription.cancel() }
        model.sessions = [removed]
        notifications = 0
        removed.isMiniMode.toggle()
        for _ in 0..<100 where notifications == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertGreaterThan(notifications, 0)

        model.sessions = [current]
        notifications = 0
        removed.isMiniMode.toggle()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(notifications, 0)
        current.isMiniMode.toggle()
        for _ in 0..<100 where notifications == 0 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertGreaterThan(notifications, 0)
    }
}
