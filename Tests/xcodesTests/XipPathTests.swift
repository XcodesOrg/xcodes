import XCTest
import Path
@testable import xcodes

final class XipPathTests: XCTestCase {
    func test_xipPath_nilWhenNoPathIsGiven() {
        XCTAssertNil(xipPath(from: nil))
    }

    func test_xipPath_keepsAbsolutePath() {
        XCTAssertEqual(xipPath(from: "/tmp/Xcode-14.0.0.xip"), Path.root/"tmp/Xcode-14.0.0.xip")
    }

    func test_xipPath_resolvesRelativePathAgainstCurrentDirectory() {
        XCTAssertEqual(xipPath(from: "Xcode-14.0.0.xip"), Path.cwd/"Xcode-14.0.0.xip")
        XCTAssertEqual(xipPath(from: "Downloads/Xcode-14.0.0.xip"), Path.cwd/"Downloads/Xcode-14.0.0.xip")
    }
}
