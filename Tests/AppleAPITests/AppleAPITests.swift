import XCTest
import PromiseKit
import PMKFoundation
@testable import AppleAPI

func fixture(for url: URL, fileURL: URL? = nil, statusCode: Int, headers: [String: String]) -> Promise<(data: Data, response: URLResponse)> {
    .value((data: fileURL != nil ? try! Data(contentsOf: fileURL!) : Data(),
            response: HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!))
}

final class AppleAPITests: XCTestCase {
    override class func setUp() {
        super.setUp()
        PromiseKit.conf.Q.map = nil
        PromiseKit.conf.Q.return = nil
    }

    override func setUp() {
        Current = .mock
    }
    
    func test_Login_2FA_Succeeds() {
        var log = ""
        Current.logging.log = { log.append($0 + "\n") }
        
        var readLineCount = 0
        Current.shell.readLine = { prompt in
            defer { readLineCount += 1 }
            
            Current.logging.log(prompt)

            // security code
            return "000000"
        }

        Current.network.dataTask = { convertible in
         
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey, 
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .signIn:
                if convertible.pmkRequest.httpMethod == "GET" {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "Federate", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                                   statusCode: 200,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-HC-Bits": "10",
                                             "X-Apple-HC-Challenge": "somestring",
                                             "scnt": ""])
                } else {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "SignIn", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                                   statusCode: 409,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-ID-Session-Id": "",
                                             "scnt": ""])
                }
            case .authOptions:
                return fixture(for: .authOptions, 
                               fileURL: Bundle.module.url(forResource: "AuthOptions", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .submitSecurityCode(.device(code: "000000")):
                return fixture(for: .submitSecurityCode(.device(code: "000000")), 
                               statusCode: 204,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .trust:
                return fixture(for: .trust, 
                               statusCode: 204,
                               headers: [:])
            case .olympusSession:
                return fixture(for: .olympusSession,
                               fileURL: Bundle.module.url(forResource: "OlympusSession", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            default:
                print(convertible.pmkRequest.url!)
                XCTFail()
                return .init(error: PMKError.invalidCallingConvention)
            }
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
        
        XCTAssertEqual(log, """
        Two-factor authentication is enabled for this account.
        
        Enter "sms" without quotes to exit this prompt and choose a phone number to send an SMS security code to.
        Enter the 6 digit code from one of your trusted devices: 
        
        """)
    }
    
    func test_Login_2FA_IncorrectPassword() {
        var log = ""
        Current.logging.log = { log.append($0 + "\n") }
        
        var readLineCount = 0
        Current.shell.readLine = { prompt in
            defer { readLineCount += 1 }
            
            Current.logging.log(prompt)

            // security code
            return "000000"
        }

        Current.network.dataTask = { convertible in
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey, 
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_2FA_IncorrectPassword")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .signIn:
                if convertible.pmkRequest.httpMethod == "GET" {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "Federate", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                                   statusCode: 200,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-HC-Bits": "10",
                                             "X-Apple-HC-Challenge": "somestring",
                                             "scnt": ""])
                } else {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "SignIn", withExtension: "json", subdirectory: "Fixtures/Login_2FA_IncorrectPassword")!,
                                   statusCode: 401,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-ID-Session-Id": "",
                                             "scnt": ""])
                }
            default:
                XCTFail()
                return .init(error: PMKError.invalidCallingConvention)
            }
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
        
        XCTAssertEqual(log, "")
    }
    
    func test_Login_SMS_SentAutomatically_Succeeds() {
        var log = ""
        Current.logging.log = { log.append($0 + "\n") }
        
        var readLineCount = 0
        Current.shell.readLine = { prompt in
            defer { readLineCount += 1 }
            
            Current.logging.log(prompt)

            // security code
            return "000000"
        }

        Current.network.dataTask = { convertible in
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey, 
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_SMS_SentAutomatically_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .signIn:
                if convertible.pmkRequest.httpMethod == "GET" {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "Federate", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                                   statusCode: 200,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-HC-Bits": "10",
                                             "X-Apple-HC-Challenge": "somestring",
                                             "scnt": ""])
                } else {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "SignIn", withExtension: "json", subdirectory: "Fixtures/Login_SMS_SentAutomatically_Succeeds")!,
                                   statusCode: 409,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-ID-Session-Id": "",
                                             "scnt": ""])
                }
            case .authOptions:
                return fixture(for: .authOptions, 
                               fileURL: Bundle.module.url(forResource: "AuthOptions", withExtension: "json", subdirectory: "Fixtures/Login_SMS_SentAutomatically_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .requestSecurityCode:
                return fixture(for: .requestSecurityCode, 
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .submitSecurityCode(.sms(code: "000000", phoneNumberId: 1)):
                return fixture(for: .submitSecurityCode(.sms(code: "000000", phoneNumberId: 1)), 
                               statusCode: 204,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .trust:
                return fixture(for: .trust, 
                               statusCode: 204,
                               headers: [:])
            case .olympusSession:
                return fixture(for: .olympusSession,
                               fileURL: Bundle.module.url(forResource: "OlympusSession", withExtension: "json", subdirectory: "Fixtures/Login_SMS_SentAutomatically_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            default:
                XCTFail("Unexpected request to \(convertible.pmkRequest.url!)")
                return .init(error: PMKError.invalidCallingConvention)
            }
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
        
        XCTAssertEqual(log, """
        Two-factor authentication is enabled for this account.
        
        Enter the 6 digit code sent to +1 (•••) •••-••00: 
        
        """)
    }
    
    func test_Login_SMS_SentAutomatically_IncorrectCode() {
        var log = ""
        Current.logging.log = { log.append($0 + "\n") }
        
        var readLineCount = 0
        Current.shell.readLine = { prompt in
            defer { readLineCount += 1 }
            
            Current.logging.log(prompt)

            // security code
            return "000000"
        }
        
        Current.network.dataTask = { convertible in
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey, 
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_SMS_SentAutomatically_IncorrectCode")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .signIn:
                if convertible.pmkRequest.httpMethod == "GET" {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "Federate", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                                   statusCode: 200,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-HC-Bits": "10",
                                             "X-Apple-HC-Challenge": "somestring",
                                             "scnt": ""])
                } else {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "SignIn", withExtension: "json", subdirectory: "Fixtures/Login_SMS_SentAutomatically_IncorrectCode")!,
                                   statusCode: 409,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-ID-Session-Id": "",
                                             "scnt": ""])
                }
            case .authOptions:
                return fixture(for: .authOptions, 
                               fileURL: Bundle.module.url(forResource: "AuthOptions", withExtension: "json", subdirectory: "Fixtures/Login_SMS_SentAutomatically_IncorrectCode")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .requestSecurityCode:
                return fixture(for: .requestSecurityCode, 
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .submitSecurityCode(.sms(code: "000000", phoneNumberId: 1)):
                return fixture(for: .submitSecurityCode(.sms(code: "000000", phoneNumberId: 1)), 
                               statusCode: 401,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            default:
                XCTFail("Unexpected request to \(convertible.pmkRequest.url!)")
                return .init(error: PMKError.invalidCallingConvention)
            }
        }
        
        let expectation = self.expectation(description: "promise rejects")

        let client = Client()
        client.login(accountName: "test@example.com", password: "ABC123")
            .tap { result in
                guard case .rejected(let error as AppleAPI.Client.Error) = result else { 
                    XCTFail("login fulfilled, but should have rejected with .incorrectSecurityCode error")
                    return
                }
                XCTAssertEqual(error, AppleAPI.Client.Error.incorrectSecurityCode)
                expectation.fulfill()
            }
            .cauterize()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(log, """
        Two-factor authentication is enabled for this account.
        
        Enter the 6 digit code sent to +1 (•••) •••-••00: 
        
        """)
    }
    
    func test_Login_SMS_MultipleNumbers_Succeeds() {
        var log = ""
        Current.logging.log = { log.append($0 + "\n") }

        var readLineCount = 0
        Current.shell.readLine = { prompt in
            defer { readLineCount += 1 }
            
            Current.logging.log(prompt)

            switch readLineCount {
            case 0:
                // invalid phone number index
                return "3"
            case 1:
                // phone number index
                return "1"
            case 2:
                // security code
                return "000000"
            default:
                XCTFail()
                return ""
            }
        }

        Current.network.dataTask = { convertible in
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey, 
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_SMS_MultipleNumbers_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .signIn:
                if convertible.pmkRequest.httpMethod == "GET" {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "Federate", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                                   statusCode: 200,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-HC-Bits": "10",
                                             "X-Apple-HC-Challenge": "somestring",
                                             "scnt": ""])
                } else {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "SignIn", withExtension: "json", subdirectory: "Fixtures/Login_SMS_MultipleNumbers_Succeeds")!,
                                   statusCode: 409,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-ID-Session-Id": "",
                                             "scnt": ""])
                }
            case .authOptions:
                return fixture(for: .authOptions, 
                               fileURL: Bundle.module.url(forResource: "AuthOptions", withExtension: "json", subdirectory: "Fixtures/Login_SMS_MultipleNumbers_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .requestSecurityCode:
                return fixture(for: .requestSecurityCode, 
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .submitSecurityCode(.sms(code: "000000", phoneNumberId: 1)):
                return fixture(for: .submitSecurityCode(.sms(code: "000000", phoneNumberId: 1)), 
                               statusCode: 204,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .trust:
                return fixture(for: .trust, 
                               statusCode: 204,
                               headers: [:])
            case .olympusSession:
                return fixture(for: .olympusSession,
                               fileURL: Bundle.module.url(forResource: "OlympusSession", withExtension: "json", subdirectory: "Fixtures/Login_SMS_MultipleNumbers_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            default:
                XCTFail("Unexpected request to \(convertible.pmkRequest.url!)")
                return .init(error: PMKError.invalidCallingConvention)
            }
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
        
        XCTAssertEqual(log, """
        Two-factor authentication is enabled for this account.

        Trusted phone numbers:
        1: +1 (•••) •••-••00
        2: +1 (•••) •••-••01
        Select a trusted phone number to receive a code via SMS: 
        Not a valid phone number index. Expecting a whole number between 1-2, but was given 3.
        
        Trusted phone numbers:
        1: +1 (•••) •••-••00
        2: +1 (•••) •••-••01
        Select a trusted phone number to receive a code via SMS: 
        Enter the 6 digit code sent to +1 (•••) •••-••00: 
        
        """)
    }
    
    func test_Login_SMS_MultipleNumbers_IncorrectCode() {
        var log = ""
        Current.logging.log = { log.append($0 + "\n") }

        var readLineCount = 0
        Current.shell.readLine = { prompt in
            defer { readLineCount += 1 }
            
            Current.logging.log(prompt)

            if readLineCount == 0 {
                // phone number index
                return "1" 
            } else {
                // security code
                return "000000"
            }
        }

        Current.network.dataTask = { convertible in
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey, 
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_SMS_MultipleNumbers_IncorrectCode")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .signIn:
                if convertible.pmkRequest.httpMethod == "GET" {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "Federate", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                                   statusCode: 200,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-HC-Bits": "10",
                                             "X-Apple-HC-Challenge": "somestring",
                                             "scnt": ""])
                } else {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "SignIn", withExtension: "json", subdirectory: "Fixtures/Login_SMS_MultipleNumbers_IncorrectCode")!,
                                   statusCode: 409,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-ID-Session-Id": "",
                                             "scnt": ""])
                }
            case .authOptions:
                return fixture(for: .authOptions, 
                               fileURL: Bundle.module.url(forResource: "AuthOptions", withExtension: "json", subdirectory: "Fixtures/Login_SMS_MultipleNumbers_IncorrectCode")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .requestSecurityCode:
                return fixture(for: .requestSecurityCode, 
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .submitSecurityCode(.sms(code: "000000", phoneNumberId: 1)):
                return fixture(for: .submitSecurityCode(.sms(code: "000000", phoneNumberId: 1)), 
                               statusCode: 401,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            default:
                XCTFail("Unexpected request to \(convertible.pmkRequest.url!)")
                return .init(error: PMKError.invalidCallingConvention)
            }
        }
        
        let expectation = self.expectation(description: "promise rejects")

        let client = Client()
        client.login(accountName: "test@example.com", password: "ABC123")
            .tap { result in
                guard case .rejected(let error as AppleAPI.Client.Error) = result else { 
                    XCTFail("login fulfilled, but should have rejected with .incorrectSecurityCode error")
                    return
                }
                XCTAssertEqual(error, AppleAPI.Client.Error.incorrectSecurityCode)
                expectation.fulfill()
            }
            .cauterize()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(log, """
        Two-factor authentication is enabled for this account.
        
        Trusted phone numbers:
        1: +1 (•••) •••-••00
        2: +1 (•••) •••-••01
        Select a trusted phone number to receive a code via SMS: 
        Enter the 6 digit code sent to +1 (•••) •••-••00: 
        
        """)
    }
    
    func test_Login_SMS_NoNumbers() {
        var log = ""
        Current.logging.log = { log.append($0 + "\n") }

        var readLineCount = 0
        Current.shell.readLine = { prompt in
            defer { readLineCount += 1 }
            
            Current.logging.log(prompt)

            switch readLineCount {
            case 0:
                // invalid phone number index
                return "3"
            case 1:
                // phone number index
                return "1"
            case 2:
                // security code
                return "000000"
            default:
                XCTFail()
                return ""
            }
        }

        Current.network.dataTask = { convertible in
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey, 
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_SMS_NoNumbers")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .signIn:
                if convertible.pmkRequest.httpMethod == "GET" {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "Federate", withExtension: "json", subdirectory: "Fixtures/Login_2FA_Succeeds")!,
                                   statusCode: 200,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-HC-Bits": "10",
                                             "X-Apple-HC-Challenge": "somestring",
                                             "scnt": ""])
                } else {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "SignIn", withExtension: "json", subdirectory: "Fixtures/Login_SMS_NoNumbers")!,
                                   statusCode: 409,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-ID-Session-Id": "",
                                             "scnt": ""])
                }
            case .authOptions:
                return fixture(for: .authOptions, 
                               fileURL: Bundle.module.url(forResource: "AuthOptions", withExtension: "json", subdirectory: "Fixtures/Login_SMS_NoNumbers")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            default:
                XCTFail("Unexpected request to \(convertible.pmkRequest.url!)")
                return .init(error: PMKError.invalidCallingConvention)
            }
        }
        
        let expectation = self.expectation(description: "promise rejects")

        let client = Client()
        client.login(accountName: "test@example.com", password: "ABC123")
            .tap { result in
                guard case .rejected(let error as AppleAPI.Client.Error) = result else { 
                    XCTFail("login fulfilled, but should have rejected with .noTrustedPhoneNumbers error")
                    return
                }
                XCTAssertEqual(error, AppleAPI.Client.Error.noTrustedPhoneNumbers)
                expectation.fulfill()
            }
            .cauterize()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(log, """
        Two-factor authentication is enabled for this account.


        """)
    }
    
    func test_Login_Service_Temporarily_Unavailable() {
        var log = ""
        Current.logging.log = { log.append($0 + "\n") }
        
        var readLineCount = 0
        Current.shell.readLine = { prompt in
            defer { readLineCount += 1 }
            
            Current.logging.log(prompt)

            // security code
            return "000000"
        }

        Current.network.dataTask = { convertible in
         
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey,
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_Service_Temporarily_Unavailable")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .signIn:
                if convertible.pmkRequest.httpMethod == "GET" {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "Federate", withExtension: "json", subdirectory: "Fixtures/Login_Service_Temporarily_Unavailable")!,
                                   statusCode: 200,
                                   headers: ["Content-Type": "application/json",
                                             "X-Apple-HC-Bits": "10",
                                             "X-Apple-HC-Challenge": "somestring",
                                             "scnt": ""])
                } else {
                    return fixture(for: .signIn,
                                   fileURL: Bundle.module.url(forResource: "SignIn", withExtension: "json", subdirectory: "Fixtures/Login_Service_Temporarily_Unavailable")!,
                                   statusCode: 503,
                                   headers: ["Content-Type": "text/html",
                                             "X-Apple-ID-Session-Id": "",
                                             "scnt": ""])
                }
            case .authOptions:
                return fixture(for: .authOptions,
                               fileURL: Bundle.module.url(forResource: "AuthOptions", withExtension: "json", subdirectory: "Fixtures/Login_Service_Temporarily_Unavailable")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .submitSecurityCode(.device(code: "000000")):
                return fixture(for: .submitSecurityCode(.device(code: "000000")),
                               statusCode: 204,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            case .trust:
                return fixture(for: .trust,
                               statusCode: 204,
                               headers: [:])
            case .olympusSession:
                return fixture(for: .olympusSession,
                               fileURL: Bundle.module.url(forResource: "OlympusSession", withExtension: "json", subdirectory: "Fixtures/Login_Service_Temporarily_Unavailable")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json",
                                         "X-Apple-ID-Session-Id": "",
                                         "scnt": ""])
            default:
                print(convertible.pmkRequest.url!)
                XCTFail()
                return .init(error: PMKError.invalidCallingConvention)
            }
        }

        let expectation = self.expectation(description: "promise fulfills")

        let client = Client()
        client.login(accountName: "test@example.com", password: "ABC123")
            .tap { result in
                guard case .rejected(let error as AppleAPI.Client.Error) = result else {
                    XCTFail("login fulfilled, but should have rejected with .noTrustedPhoneNumbers error")
                    return
                }
                XCTAssertEqual(error, AppleAPI.Client.Error.serviceTemporarilyUnavailable)
                expectation.fulfill()
            }
            .cauterize()
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(log, "")
    }

    
    func test_CheckFederation_FederatedAccount() {
        Current.network.dataTask = { convertible in
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey,
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_Federated_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .federateCheck:
                return fixture(for: .federateCheck,
                               fileURL: Bundle.module.url(forResource: "FederateCheck", withExtension: "json", subdirectory: "Fixtures/Login_Federated_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            default:
                XCTFail("Unexpected request to \(convertible.pmkRequest.url!)")
                return .init(error: PMKError.invalidCallingConvention)
            }
        }

        let expectation = self.expectation(description: "promise fulfills")

        let client = Client()
        client.checkIsFederated(accountName: "test@company.com")
            .tap { result in
                guard case .fulfilled(let response) = result else {
                    XCTFail("checkIsFederated rejected")
                    return
                }
                XCTAssertTrue(response.federated)
                XCTAssertEqual(response.federatedAuthIntro?.orgName, "Test Corp")
                XCTAssertEqual(response.federatedAuthIntro?.idpName, "Microsoft Entra")
                XCTAssertEqual(response.federatedIdpRequest?.idPUrl, "https://login.microsoftonline.com/test-tenant/oauth2/authorize")
                XCTAssertEqual(response.federatedIdpRequest?.requestParams["login_hint"], "test@company.com")
                XCTAssertNotNil(response.idpURL)
                expectation.fulfill()
            }
            .cauterize()

        wait(for: [expectation], timeout: 1.0)
    }

    func test_CheckFederation_NonFederatedAccount() {
        Current.network.dataTask = { convertible in
            switch convertible.pmkRequest.url! {
            case .itcServiceKey:
                return fixture(for: .itcServiceKey,
                               fileURL: Bundle.module.url(forResource: "ITCServiceKey", withExtension: "json", subdirectory: "Fixtures/Login_Federated_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            case .federateCheck:
                return fixture(for: .federateCheck,
                               fileURL: Bundle.module.url(forResource: "FederateCheckNonFederated", withExtension: "json", subdirectory: "Fixtures/Login_Federated_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            default:
                XCTFail("Unexpected request to \(convertible.pmkRequest.url!)")
                return .init(error: PMKError.invalidCallingConvention)
            }
        }

        let expectation = self.expectation(description: "promise fulfills")

        let client = Client()
        client.checkIsFederated(accountName: "test@example.com")
            .tap { result in
                guard case .fulfilled(let response) = result else {
                    XCTFail("checkIsFederated rejected")
                    return
                }
                XCTAssertFalse(response.federated)
                XCTAssertNil(response.federatedIdpRequest)
                XCTAssertNil(response.federatedAuthIntro)
                XCTAssertNil(response.idpURL)
                expectation.fulfill()
            }
            .cauterize()

        wait(for: [expectation], timeout: 1.0)
    }

    func test_ValidateFederatedToken_Succeeds() {
        Current.network.dataTask = { convertible in
            let url = convertible.pmkRequest.url!
            if url.absoluteString.contains("federate/validate") {
                return fixture(for: url,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            } else if url == .olympusSession {
                return fixture(for: .olympusSession,
                               fileURL: Bundle.module.url(forResource: "OlympusSession", withExtension: "json", subdirectory: "Fixtures/Login_Federated_Succeeds")!,
                               statusCode: 200,
                               headers: ["Content-Type": "application/json"])
            } else {
                XCTFail("Unexpected request to \(url)")
                return .init(error: PMKError.invalidCallingConvention)
            }
        }

        let expectation = self.expectation(description: "promise fulfills")

        let client = Client()
        client.validateFederatedToken(widgetKey: "test-widget-key", token: "test-token", relayState: "test-relay-state")
            .tap { result in
                guard case .fulfilled = result else {
                    XCTFail("validateFederatedToken rejected")
                    return
                }
                expectation.fulfill()
            }
            .cauterize()

        wait(for: [expectation], timeout: 1.0)
    }

    func test_ValidateFederatedToken_UnexpectedStatusCode() {
        Current.network.dataTask = { convertible in
            let url = convertible.pmkRequest.url!
            if url.absoluteString.contains("federate/validate") {
                return fixture(for: url,
                               statusCode: 401,
                               headers: ["Content-Type": "application/json"])
            } else {
                XCTFail("Unexpected request to \(url)")
                return .init(error: PMKError.invalidCallingConvention)
            }
        }

        let expectation = self.expectation(description: "promise rejects")

        let client = Client()
        client.validateFederatedToken(widgetKey: "test-widget-key", token: "test-token", relayState: "test-relay-state")
            .tap { result in
                guard case .rejected(let error as AppleAPI.Client.Error) = result else {
                    XCTFail("validateFederatedToken fulfilled, but should have rejected")
                    return
                }
                XCTAssertEqual(error, AppleAPI.Client.Error.unexpectedSignInResponse(statusCode: 401, message: nil))
                expectation.fulfill()
            }
            .cauterize()

        wait(for: [expectation], timeout: 1.0)
    }

    func testValidHashCashMint() {
        let bits: UInt = 11
        let resource = "4d74fb15eb23f465f1f6fcbf534e5877"
        let testDate = "20230223170600"
 
        let stamp = Hashcash().mint(resource: resource, bits: bits, date: testDate)
        XCTAssertEqual(stamp, "1:11:20230223170600:4d74fb15eb23f465f1f6fcbf534e5877::6373")
    }
    func testValidHashCashMint2() {
        let bits: UInt = 10
        let resource = "bb63edf88d2f9c39f23eb4d6f0281158"
        let testDate = "20230224001754"
 
        let stamp = Hashcash().mint(resource: resource, bits: bits, date: testDate)
        XCTAssertEqual(stamp, "1:10:20230224001754:bb63edf88d2f9c39f23eb4d6f0281158::866")
    }
}
