import Foundation
import PromiseKit
import PMKFoundation

public class Client {
    private(set) public var session = URLSession.shared
    private static let authTypes = ["sa", "hsa", "non-sa", "hsa2"]

    public init() {}

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidSession
        case invalidUsernameOrPassword(username: String)
        case unexpectedSignInResponse(statusCode: Int, message: String?)
        case appleIDAndPrivacyAcknowledgementRequired

        public var errorDescription: String? {
            switch self {
            case .invalidUsernameOrPassword(let username):
                return "Invalid username and password combination. Attempted to sign in with username \(username)."
            case .appleIDAndPrivacyAcknowledgementRequired:
                return "You must sign in to https://appstoreconnect.apple.com and acknowledge the Apple ID & Privacy agreement."
            default:
                return String(describing: self)
            }
        }
    }

    /// Use the olympus session endpoint to see if the existing session is still valid
    public func validateSession() -> Promise<Void> {
        return session.dataTask(.promise, with: URLRequest.olympusSession)
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
            self.session.dataTask(.promise, with: URLRequest.itcServiceKey)
        }
        .then { (data, _) -> Promise<(data: Data, response: URLResponse)> in
            struct ServiceKeyResponse: Decodable {
                let authServiceKey: String
            }

            let response = try JSONDecoder().decode(ServiceKeyResponse.self, from: data)
            serviceKey = response.authServiceKey

            return self.session.dataTask(.promise, with: URLRequest.signIn(serviceKey: serviceKey, accountName: accountName, password: password))
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
                return self.session.dataTask(.promise, with: URLRequest.olympusSession).asVoid()
            case 401:
                throw Error.invalidUsernameOrPassword(username: accountName)
            case 409:
                return self.handleTwoFactor(data: data, response: response, serviceKey: serviceKey)
            case 412 where Client.authTypes.contains(responseBody.authType ?? ""):
                throw Error.appleIDAndPrivacyAcknowledgementRequired
            default:
                throw Error.unexpectedSignInResponse(statusCode: httpResponse.statusCode,
                                                     message: responseBody.serviceErrors?.map { $0.description }.joined(separator: ", "))
            }
        }
    }

    public func handleTwoFactor(data: Data, response: URLResponse, serviceKey: String) -> Promise<Void> {
        let httpResponse = response as! HTTPURLResponse
        let sessionID = (httpResponse.allHeaderFields["X-Apple-ID-Session-Id"] as! String)
        let scnt = (httpResponse.allHeaderFields["scnt"] as! String)

        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            self.session.dataTask(.promise, with: URLRequest.authOptions(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
        }
        .then { (data, response) -> Promise<(data: Data, response: URLResponse)> in
            print("Enter the code: ")
            let code = readLine() ?? ""
            return self.session.dataTask(.promise, with: try URLRequest.submitSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, code: code))
        }
        .then { (data, response) -> Promise<(data: Data, response: URLResponse)>  in
            self.session.dataTask(.promise, with: URLRequest.trust(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
        }
        .then { (data, response) -> Promise<Void> in
            self.session.dataTask(.promise, with: URLRequest.olympusSession).asVoid()
        }
    }
}
