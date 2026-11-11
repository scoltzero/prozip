import XCTest
import ProZipShared

final class ProZipBasicTests: XCTestCase {
    func testFormatDetection() {
        let zipURL = URL(fileURLWithPath: "/tmp/sample.zip")
        XCTAssertEqual(ArchiveFormat.detect(from: zipURL), .zip)
    }
}
