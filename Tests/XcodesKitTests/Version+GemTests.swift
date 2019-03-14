import XCTest
import Version
@testable import XcodesKit

class VersionGemTests: XCTestCase {
    func test_InitGemVersion() {
        XCTAssertEqual(Version(gemVersion: "9.2b3"), Version("9.2.0-Beta.3"))
        XCTAssertEqual(Version(gemVersion: "9.1.2"), Version("9.1.2"))
        XCTAssertEqual(Version(gemVersion: "9.2"), Version("9.2.0"))
        XCTAssertEqual(Version(gemVersion: "9"), Version("9.0.0"))
    }
}