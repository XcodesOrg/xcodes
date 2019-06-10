import XCTest
import Version
@testable import XcodesKit

class VersionXcodeTests: XCTestCase {
    func test_InitXcodeVersion() {
        XCTAssertEqual(Version(xcodeVersion: "Xcode 11 beta"), Version("11.0.0-beta"))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2 Beta 4"), Version("10.2.0-beta.4"))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2 GM"), Version("10.2.0-gm"))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2"), Version("10.2.0"))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2.1"), Version("10.2.1"))
        XCTAssertEqual(Version(xcodeVersion: "10.2 Beta 4"), Version("10.2.0-beta.4"))
        XCTAssertEqual(Version(xcodeVersion: "10.2 GM"), Version("10.2.0-gm"))
        XCTAssertEqual(Version(xcodeVersion: "10.2"), Version("10.2.0"))
        XCTAssertEqual(Version(xcodeVersion: "10.2.1"), Version("10.2.1"))
    }
}