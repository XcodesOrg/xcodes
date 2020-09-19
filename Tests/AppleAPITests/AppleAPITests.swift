import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift
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
    
    override func tearDown() {
      HTTPStubs.removeAllStubs()
      super.tearDown()
    }
    
    func test_Login_2FA_Succeeds() {
        stub(condition: isAbsoluteURLString(URL.itcServiceKey.absoluteString)) { _ in
            fixture(filePath: Bundle.module.path(forResource: "ITCServiceKey", ofType: "json", inDirectory: "Fixtures/Login_2FA_Succeeds")!, 
                    headers: ["Content-Type": "application/json"])
        }
        stub(condition: isAbsoluteURLString(URL.signIn.absoluteString)) { _ in
            fixture(filePath: Bundle.module.path(forResource: "SignIn", ofType: "json", inDirectory: "Fixtures/Login_2FA_Succeeds")!, 
                    headers: ["Content-Type": "application/json"])
        }
        stub(condition: isAbsoluteURLString(URL.authOptions.absoluteString)) { _ in
            fixture(filePath: Bundle.module.path(forResource: "AuthOptions", ofType: "json", inDirectory: "Fixtures/Login_2FA_Succeeds")!, 
                    headers: ["Content-Type": "application/json"])
        }
        stub(condition: isAbsoluteURLString(URL.submitSecurityCode.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 204, headers: ["Content-Type": "application/json"])
        }
        stub(condition: isAbsoluteURLString(URL.trust.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 204, headers: nil)
        }
        stub(condition: isAbsoluteURLString(URL.olympusSession.absoluteString)) { _ in
            fixture(filePath: Bundle.module.path(forResource: "OlympusSession", ofType: "json", inDirectory: "Fixtures/Login_2FA_Succeeds")!, 
                    headers: ["Content-Type": "application/json"])
        }
        
        let expectation = self.expectation(description: "promise fulfills")

        let client = Client()
        client.login(accountName: "test@example.com", password: "ABC123")
            .tap { result in
                guard case .fulfilled = result else { 
                    XCTFail("login rejected")
                    return
                }
                expectation.fulfill()
            }
            .cauterize()
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func test_Login_2FA_IncorrectPassword() {
        stub(condition: isAbsoluteURLString(URL.itcServiceKey.absoluteString)) { _ in
            fixture(filePath: Bundle.module.path(forResource: "ITCServiceKey", ofType: "json", inDirectory: "Fixtures/Login_2FA_IncorrectPassword")!, 
                    headers: ["Content-Type": "application/json"])
        }
        stub(condition: isAbsoluteURLString(URL.signIn.absoluteString)) { _ in
            fixture(filePath: Bundle.module.path(forResource: "SignIn", ofType: "json", inDirectory: "Fixtures/Login_2FA_IncorrectPassword")!,
                    status: 401,
                    headers: ["Content-Type": "application/json"])
        }
        stub(condition: isAbsoluteURLString(URL.authOptions.absoluteString)) { _ in
            fixture(filePath: Bundle.module.path(forResource: "AuthOptions", ofType: "json", inDirectory: "Fixtures/Login_2FA_IncorrectPassword")!, 
                    headers: ["Content-Type": "application/json"])
        }
        stub(condition: isAbsoluteURLString(URL.submitSecurityCode.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 204, headers: ["Content-Type": "application/json"])
        }
        stub(condition: isAbsoluteURLString(URL.trust.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 204, headers: nil)
        }
        stub(condition: isAbsoluteURLString(URL.olympusSession.absoluteString)) { _ in
            fixture(filePath: Bundle.module.path(forResource: "OlympusSession", ofType: "json", inDirectory: "Fixtures/Login_2FA_IncorrectPassword")!, 
                    headers: ["Content-Type": "application/json"])
        }
        
        let expectation = self.expectation(description: "promise rejects")

        let client = Client()
        client.login(accountName: "test@example.com", password: "ABC123")
            .tap { result in
                guard case .rejected(let error as AppleAPI.Client.Error) = result else { 
                    XCTFail("login fulfilled, but should have rejected with .invalidUsernameOrPassword error")
                    return
                }
                XCTAssertEqual(error, AppleAPI.Client.Error.invalidUsernameOrPassword(username: "test@example.com"))
                expectation.fulfill()
            }
            .cauterize()
        
        wait(for: [expectation], timeout: 1.0)
    }
}
