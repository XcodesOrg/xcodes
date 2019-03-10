import XCTest
import PromiseKit
import PMKFoundation
@testable import AppleAPI

final class AppleAPITests: XCTestCase {
    override class func setUp() {
        super.setUp()
        PromiseKit.conf.Q.map = nil
        PromiseKit.conf.Q.return = nil
    }

    override func setUp() {
    }
}
