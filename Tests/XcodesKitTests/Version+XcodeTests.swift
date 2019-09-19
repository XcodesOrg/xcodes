import XCTest
import Version
@testable import XcodesKit

class VersionXcodeTests: XCTestCase {
    func test_InitXcodeVersion() {
        XCTAssertEqual(Version(xcodeVersion: "10.2"),                 Version(major: 10, minor: 2, patch: 0))
        XCTAssertEqual(Version(xcodeVersion: "10.2.1"),               Version(major: 10, minor: 2, patch: 1))
        XCTAssertEqual(Version(xcodeVersion: "10.2 Beta 4"),          Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["beta", "4"]))
        XCTAssertEqual(Version(xcodeVersion: "10.2 GM"),              Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["gm"]))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2"),           Version(major: 10, minor: 2, patch: 0))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2.1"),         Version(major: 10, minor: 2, patch: 1))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 11 beta"),        Version(major: 11, minor: 0, patch: 0, prereleaseIdentifiers: ["beta"]))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2 Beta 4"),    Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["beta", "4"]))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2 GM"),        Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["gm"]))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2 GM seed"),   Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["gm-seed"]))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2 GM seed 1"), Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["gm-seed", "1"]))
        XCTAssertEqual(Version(xcodeVersion: "Xcode 10.2 GM seed 2"), Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["gm-seed", "2"]))
    }

    func test_XcodeDescription() {
        XCTAssertEqual(Version(major: 10, minor: 2, patch: 0).xcodeDescription,                                          "10.2")
        XCTAssertEqual(Version(major: 10, minor: 2, patch: 1).xcodeDescription,                                          "10.2.1")
        XCTAssertEqual(Version(major: 11, minor: 0, patch: 0, prereleaseIdentifiers: ["beta"]).xcodeDescription,         "11.0 Beta")
        XCTAssertEqual(Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["beta", "4"]).xcodeDescription,    "10.2 Beta 4")
        XCTAssertEqual(Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["gm"]).xcodeDescription,           "10.2 GM")
        XCTAssertEqual(Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["gm-seed"]).xcodeDescription,      "10.2 GM Seed")
        XCTAssertEqual(Version(major: 10, minor: 2, patch: 0, prereleaseIdentifiers: ["gm-seed", "1"]).xcodeDescription, "10.2 GM Seed 1")
    }

    func test_Equivalence() {
        XCTAssertTrue(Version("10.2.1")!.isEquivalentForDeterminingIfInstalled(toInstalled: Version("10.2.1+abcdef")!))
        XCTAssertFalse(Version("10.2.1-beta+qwerty")!.isEquivalentForDeterminingIfInstalled(toInstalled: Version("10.2.1-beta+abcdef")!))
        XCTAssertTrue(Version("10.2.1-beta+qwerty")!.isEquivalentForDeterminingIfInstalled(toInstalled: Version("10.2.1-beta+QWERTY")!))
    }
}
