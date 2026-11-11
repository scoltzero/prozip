import Foundation
import XCTest
@testable import ProZipCore
import ProZipUI

extension XCTestCase {
    @MainActor
    func makeTestAppViewModel() -> ProZipAppViewModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prozip-vm-test-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let book = PasswordBook(storageURL: directory.appendingPathComponent("password-book.dat"), keyStore: TestPasswordBookKeyStore())
        return ProZipAppViewModel(passwordBook: book)
    }
}
