import XCTest
@testable import XcodesKit

class BuildXcodeTests: XCTestCase {
    
    func test_InitXcodeVersion() {
        XCTAssertNotNil(Build(identifier: "13E500a"))
        XCTAssertNotNil(Build(identifier: "12E507"))
        XCTAssertNotNil(Build(identifier: "7B85"))
        XCTAssertNil(Build(identifier: "13.1.0"))
        XCTAssertNil(Build(identifier: "13"))
        XCTAssertNil(Build(identifier: "14B"))
    }
    
}
