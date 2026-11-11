import Foundation
import XCTest
import ProZipShared

final class FinderActionRequestTests: XCTestCase {
    func testRoundTripPreservesUnicodeAndReservedFilenameCharacters() throws {
        let files = [URL(fileURLWithPath: "/tmp/测试 # & ? +.zip"), URL(fileURLWithPath: "/tmp/literal%00.zip")]
        for action in FinderAction.allCases {
            let request = try FinderActionRequest(action: action, files: files + [files[0]])
            XCTAssertEqual(request.files, files)
            XCTAssertEqual(try FinderActionRequest(url: request.url), request)
        }
    }

    func testRejectsUnknownActionsDuplicateActionsAndForeignParameters() {
        let file = URL(fileURLWithPath: "/tmp/file.zip").absoluteString
        for items in [
            [URLQueryItem(name: "action", value: "delete"), URLQueryItem(name: "file", value: file)],
            [URLQueryItem(name: "action", value: "extractHere"), URLQueryItem(name: "action", value: "browseArchive"), URLQueryItem(name: "file", value: file)],
            [URLQueryItem(name: "action", value: "browseArchive"), URLQueryItem(name: "file", value: file), URLQueryItem(name: "destination", value: "/tmp/other")]
        ] {
            var components = URLComponents(string: "prozip://finder-action")!
            components.queryItems = items
            XCTAssertThrowsError(try FinderActionRequest(url: components.url!))
        }
    }

    func testRejectsRemoteRelativeAndCredentialedFiles() throws {
        for value in ["https://example.com/file.zip", "file://remote-server/private/file.zip", "file:relative.zip", "file://user:password@localhost/tmp/file.zip", "file:///tmp/file.zip?query=1", "file:///tmp/bad%00name"] {
            let file = try XCTUnwrap(URL(string: value))
            XCTAssertThrowsError(try FinderActionRequest(action: .browseArchive, files: [file]), value)
        }
        XCTAssertThrowsError(try FinderActionRequest(action: .browseArchive, files: []))
        XCTAssertThrowsError(try FinderActionRequest(action: .browseArchive, files: Array(repeating: URL(fileURLWithPath: "/tmp/a"), count: 1001)))
        let longFiles = (0..<1000).map { URL(fileURLWithPath: "/tmp/" + String(repeating: "字", count: 300) + "\($0).zip") }
        XCTAssertThrowsError(try FinderActionRequest(action: .browseArchive, files: longFiles))
    }

    func testRejectsOtherRoutesAndFragments() {
        for value in ["https://finder-action?action=browseArchive", "prozip://other?action=browseArchive", "prozip://finder-action/unexpected?action=browseArchive", "prozip://finder-action?action=browseArchive#fragment", "prozip://finder-action?action=browseArchive"] {
            XCTAssertThrowsError(try FinderActionRequest(url: URL(string: value)!))
        }
    }
}
