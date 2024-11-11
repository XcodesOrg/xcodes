import Foundation
import PromiseKit
import PMKFoundation
import Rainbow

public class Client {
    private static let authTypes = ["sa", "hsa", "non-sa", "hsa2"]

    public init() {}

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidSession
        case invalidUsernameOrPassword(username: String)
        case invalidPhoneNumberIndex(min: Int, max: Int, given: String?)
        case incorrectSecurityCode
        case unexpectedSignInResponse(statusCode: Int, message: String?)
        case appleIDAndPrivacyAcknowledgementRequired
        case noTrustedPhoneNumbers
        case notAuthenticated
        case invalidHashcash
        case missingSecurityCodeInfo
        case accountUsesHardwareKey
        
        public var errorDescription: String? {
            switch self {
            case .invalidUsernameOrPassword(let username):
                return "Invalid username and password combination. Attempted to sign in with username \(username)."
            case .appleIDAndPrivacyAcknowledgementRequired:
                return "You must sign in to https://appstoreconnect.apple.com and acknowledge the Apple ID & Privacy agreement."
            case .invalidPhoneNumberIndex(let min, let max, let given):
                return "Not a valid phone number index. Expecting a whole number between \(min)-\(max), but was given \(given ?? "nothing")."
            case .noTrustedPhoneNumbers:
                return "Your account doesn't have any trusted phone numbers, but they're required for two-factor authentication. See https://support.apple.com/en-ca/HT204915."
            case .notAuthenticated:
                return "You are already signed out"
            case .invalidHashcash:
                return "Could not create a hashcash for the session."
            case .missingSecurityCodeInfo:
                return "Expected security code info but didn't receive any."
            case .accountUsesHardwareKey:
                return "Account uses a hardware key for authentication but this is not supported yet."
            default:
                return String(describing: self)
            }
        }
    }

    /// Use the olympus session endpoint to see if the existing session is still valid
    public func validateSession() -> Promise<Void> {
        return Current.network.dataTask(with: URLRequest.olympusSession)
            .done { data, response in
                guard
                    let jsonObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                    jsonObject["provider"] != nil
                else { throw Error.invalidSession }
            }
    }
    
    public func login(accountName: String, password: String) -> Promise<Void> {
        var serviceKey: String!
        
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            Current.network.dataTask(with: URLRequest.itcServiceKey)
        }
        .then { (data, _) -> Promise<(serviceKey: String, hashcash: String)> in
            struct ServiceKeyResponse: Decodable {
                let authServiceKey: String?
            }
            
            let response = try JSONDecoder().decode(ServiceKeyResponse.self, from: data)
            serviceKey = response.authServiceKey
            
            return self.loadHashcash(accountName: accountName, serviceKey: serviceKey).map { (serviceKey, $0) }
        }
        .then { (serviceKey, hashcash) -> Promise<(data: Data, response: URLResponse)> in
            
            return Current.network.dataTask(with: URLRequest.signIn(serviceKey: serviceKey, accountName: accountName, password: password, hashcash: hashcash))
        }
        .then { (data, response) -> Promise<Void> in
            struct SignInResponse: Decodable {
                let authType: String?
                let serviceErrors: [ServiceError]?
                
                struct ServiceError: Decodable, CustomStringConvertible {
                    let code: String
                    let message: String
                    
                    var description: String {
                        return "\(code): \(message)"
                    }
                }
            }
            
            let httpResponse = response as! HTTPURLResponse
            let responseBody = try JSONDecoder().decode(SignInResponse.self, from: data)
            
            switch httpResponse.statusCode {
            case 200:
                return Current.network.dataTask(with: URLRequest.olympusSession).asVoid()
            case 401:
                throw Error.invalidUsernameOrPassword(username: accountName)
            case 409:
                return self.handleTwoStepOrFactor(data: data, response: response, serviceKey: serviceKey)
            case 412 where Client.authTypes.contains(responseBody.authType ?? ""):
                throw Error.appleIDAndPrivacyAcknowledgementRequired
            default:
                throw Error.unexpectedSignInResponse(statusCode: httpResponse.statusCode,
                                                     message: responseBody.serviceErrors?.map { $0.description }.joined(separator: ", "))
            }
        }
    }
    
    func handleTwoStepOrFactor(data: Data, response: URLResponse, serviceKey: String) -> Promise<Void> {
        let httpResponse = response as! HTTPURLResponse
        let sessionID = (httpResponse.allHeaderFields["X-Apple-ID-Session-Id"] as! String)
        let scnt = (httpResponse.allHeaderFields["scnt"] as! String)
        
        return firstly { () -> Promise<AuthOptionsResponse> in
            return Current.network.dataTask(with: URLRequest.authOptions(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
                .map { try JSONDecoder().decode(AuthOptionsResponse.self, from: $0.data) }
        }
        .then { authOptions -> Promise<Void> in
            switch authOptions.kind {
            case .twoStep:
                Current.logging.log("Received a response from Apple that indicates this account has two-step authentication enabled. xcodes currently only supports the newer two-factor authentication, though. Please consider upgrading to two-factor authentication, or open an issue on GitHub explaining why this isn't an option for you here: https://github.com/RobotsAndPencils/xcodes/issues/new".yellow)
                return Promise.value(())
            case .twoFactor:
                return self.handleTwoFactor(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, authOptions: authOptions)
            case .hardwareKey:
                throw Error.accountUsesHardwareKey
            case .unknown:
                Current.logging.log("Received a response from Apple that indicates this account has two-step or two-factor authentication enabled, but xcodes is unsure how to handle this response:".red)
                String(data: data, encoding: .utf8).map { Current.logging.log($0) }
                return Promise.value(())
            }
        }
    }
    
    func handleTwoFactor(serviceKey: String, sessionID: String, scnt: String, authOptions: AuthOptionsResponse) -> Promise<Void> {
        Current.logging.log("Two-factor authentication is enabled for this account.\n")
        
        // SMS was sent automatically 
        if authOptions.smsAutomaticallySent {
            return firstly { () throws -> Promise<(data: Data, response: URLResponse)> in
                guard let securityCode = authOptions.securityCode else { throw Error.missingSecurityCodeInfo }
                let code = self.promptForSMSSecurityCode(length: securityCode.length, for: authOptions.trustedPhoneNumbers!.first!)
                return Current.network.dataTask(with: try URLRequest.submitSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, code: code))
                    .validateSecurityCodeResponse()
            }
            .then { (data, response) -> Promise<Void>  in
                self.updateSession(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
            }
            // SMS wasn't sent automatically because user needs to choose a phone to send to
        } else if authOptions.canFallBackToSMS {
            return handleWithPhoneNumberSelection(authOptions: authOptions, serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
            // Code is shown on trusted devices
        } else {
            let securityCodeLength: Int = authOptions.securityCode?.length ?? 0
            let code = Current.shell.readLine("""
            Enter "sms" without quotes to exit this prompt and choose a phone number to send an SMS security code to.
            Enter the \(securityCodeLength) digit code from one of your trusted devices: 
            """) ?? ""
            
            if code == "sms" {
                return handleWithPhoneNumberSelection(authOptions: authOptions, serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
            }
            
            return firstly {
                Current.network.dataTask(with: try URLRequest.submitSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, code: .device(code: code)))
                    .validateSecurityCodeResponse()
                
            }
            .then { (data, response) -> Promise<Void>  in
                self.updateSession(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
            }
        }
    }
    
    func updateSession(serviceKey: String, sessionID: String, scnt: String) -> Promise<Void> {
        return Current.network.dataTask(with: URLRequest.trust(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
            .then { (data, response) -> Promise<Void> in
                Current.network.dataTask(with: URLRequest.olympusSession).asVoid()
            }
    }
    
    func selectPhoneNumberInteractively(from trustedPhoneNumbers: [AuthOptionsResponse.TrustedPhoneNumber]) -> Promise<AuthOptionsResponse.TrustedPhoneNumber> {
        return firstly { () throws -> Guarantee<AuthOptionsResponse.TrustedPhoneNumber> in
            Current.logging.log("Trusted phone numbers:")
            trustedPhoneNumbers.enumerated().forEach { (index, phoneNumber) in
                Current.logging.log("\(index + 1): \(phoneNumber.numberWithDialCode)")
            }
            
            let possibleSelectionNumberString = Current.shell.readLine("Select a trusted phone number to receive a code via SMS: ")
            guard
                let selectionNumberString = possibleSelectionNumberString,
                let selectionNumber = Int(selectionNumberString) ,
                trustedPhoneNumbers.indices.contains(selectionNumber - 1)
            else {
                throw Error.invalidPhoneNumberIndex(min: 1, max: trustedPhoneNumbers.count, given: possibleSelectionNumberString)
            }
            
            return .value(trustedPhoneNumbers[selectionNumber - 1])
        }
        .recover { error throws -> Promise<AuthOptionsResponse.TrustedPhoneNumber> in
            guard case Error.invalidPhoneNumberIndex = error else { throw error }
            Current.logging.log("\(error.localizedDescription)\n".red)
            return self.selectPhoneNumberInteractively(from: trustedPhoneNumbers)
        }
    }
    
    func promptForSMSSecurityCode(length: Int, for trustedPhoneNumber: AuthOptionsResponse.TrustedPhoneNumber) -> SecurityCode {
        let code = Current.shell.readLine("Enter the \(length) digit code sent to \(trustedPhoneNumber.numberWithDialCode): ") ?? ""
        return .sms(code: code, phoneNumberId: trustedPhoneNumber.id)
    }
    
    func handleWithPhoneNumberSelection(authOptions: AuthOptionsResponse, serviceKey: String, sessionID: String, scnt: String) -> Promise<Void> {
        return firstly { () throws -> Promise<AuthOptionsResponse.TrustedPhoneNumber> in
            // I don't think this should ever be nil or empty, because 2FA requires at least one trusted phone number,
            // but if it is nil or empty it's better to inform the user so they can try to address it instead of crashing.
            guard let trustedPhoneNumbers = authOptions.trustedPhoneNumbers, trustedPhoneNumbers.isEmpty == false else {
                throw Error.noTrustedPhoneNumbers
            }
            
            return selectPhoneNumberInteractively(from: trustedPhoneNumbers)
        }
        .then { trustedPhoneNumber in
            Current.network.dataTask(with: try URLRequest.requestSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, trustedPhoneID: trustedPhoneNumber.id))
                .map { _ in
                    guard let securityCodeLength = authOptions.securityCode?.length else { throw Error.missingSecurityCodeInfo }
                    return self.promptForSMSSecurityCode(length: securityCodeLength, for: trustedPhoneNumber)
                }
        }
        .then { code in
            Current.network.dataTask(with: try URLRequest.submitSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, code: code))
                .validateSecurityCodeResponse()
        }
        .then { (data, response) -> Promise<Void>  in
            self.updateSession(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt)
        }
    }
    
    // Fixes issue https://github.com/RobotsAndPencils/XcodesApp/issues/360
    // On 2023-02-23, Apple added a custom implementation of hashcash to their auth flow
    // Without this addition, Apple ID's would get set to locked
    func loadHashcash(accountName: String, serviceKey: String) -> Promise<String> {
        return firstly{ () -> Promise<(data: Data, response: URLResponse)> in
            Current.network.dataTask(with: try URLRequest.federate(account: accountName, serviceKey: serviceKey))
        }
        .then { (_ response) -> Promise<String> in
            guard let urlResponse = response.response as? HTTPURLResponse else {
                throw Client.Error.invalidSession
            }
            
            guard let bitString = urlResponse.allHeaderFields["X-Apple-HC-Bits"] as? String, let bits = UInt(bitString) else {
                throw Client.Error.invalidHashcash
            }
            guard let challenge = urlResponse.allHeaderFields["X-Apple-HC-Challenge"] as? String else {
                throw Client.Error.invalidHashcash
            }
            guard let hashcash = Hashcash().mint(resource: challenge, bits: bits) else {
                throw Client.Error.invalidHashcash
            }
            
            return .value(hashcash)
        }
    }
}

public extension Promise where T == (data: Data, response: URLResponse) {
    func validateSecurityCodeResponse() -> Promise<T> {
        validate()
            .recover { error -> Promise<(data: Data, response: URLResponse)> in
                switch error {
                case PMKHTTPError.badStatusCode(let code, _, _):
                    if code == 401 {
                        throw Client.Error.incorrectSecurityCode
                    } else {
                        throw error
                    }
                default:
                    throw error
                }
            }
    }
}

struct AuthOptionsResponse: Decodable {
    let trustedPhoneNumbers: [TrustedPhoneNumber]?
    let trustedDevices: [TrustedDevice]?
    let securityCode: SecurityCodeInfo?
    let noTrustedDevices: Bool?
    let serviceErrors: [ServiceError]?
    let fsaChallenge: FSAChallenge?
    
    var kind: Kind {
        if trustedDevices != nil {
            return .twoStep
        } else if trustedPhoneNumbers != nil {
            return .twoFactor
        } else if fsaChallenge != nil {
            return .hardwareKey
        } else {
            return .unknown
        }
    }
    
    // One time with a new testing account I had a response where noTrustedDevices was nil, but the account didn't have any trusted devices.
    // This should have been a situation where an SMS security code was sent automatically.
    // This resolved itself either after some time passed, or by signing into appleid.apple.com with the account.
    // Not sure if it's worth explicitly handling this case or if it'll be really rare.
    var canFallBackToSMS: Bool {
        noTrustedDevices == true
    }
    
    var smsAutomaticallySent: Bool {
        trustedPhoneNumbers?.count == 1 && canFallBackToSMS
    }
    
    struct TrustedPhoneNumber: Decodable {
        let id: Int
        let numberWithDialCode: String
    }
    
    struct TrustedDevice: Decodable {
        let id: String
        let name: String
        let modelName: String
    }
    
    struct SecurityCodeInfo: Decodable {
        let length: Int
        let tooManyCodesSent: Bool
        let tooManyCodesValidated: Bool
        let securityCodeLocked: Bool
        let securityCodeCooldown: Bool
    }
    
    struct FSAChallenge: Decodable {
        let challenge: String
        let keyHandles: [String]
        let rpId: String
        let allowedCredentials: String
    }
    
    enum Kind {
        case twoStep, twoFactor, hardwareKey, unknown
    }
}

public struct ServiceError: Decodable, Equatable {
    let code: String
    let message: String
}

enum SecurityCode {
    case device(code: String)
    case sms(code: String, phoneNumberId: Int)
    
    var urlPathComponent: String {
        switch self {
        case .device: return "trusteddevice"
        case .sms: return "phone"
        }
    }
}
