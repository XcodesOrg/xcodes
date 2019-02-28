import Foundation
import PromiseKit

public class Client {
    public enum Error: Swift.Error {
        case invalidSession
    }

    /// Use the olympus session endpoint to see if the existing session is still valid
    public func validateSession() -> Promise<Void> {
        return URLSession.shared.dataTask(.promise, with: URLRequest.olympusSession)
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
            URLSession.shared.dataTask(.promise, with: URLRequest.itcServiceKey)
        }
        .then { (data, _) -> Promise<(data: Data, response: URLResponse)> in
            struct ServiceKeyResponse: Decodable {
                let authServiceKey: String
            }

            let response = try JSONDecoder().decode(ServiceKeyResponse.self, from: data)
            serviceKey = response.authServiceKey

            return URLSession.shared.dataTask(.promise, with: URLRequest.signIn(serviceKey: serviceKey, accountName: accountName, password: password))
        }
        .then { (data, response) -> Promise<Void> in
            let httpResponse = response as! HTTPURLResponse
            switch httpResponse.statusCode {
            case 200:
                return URLSession.shared.dataTask(.promise, with: URLRequest.olympusSession).asVoid()
            case 409:
                return self.handleTwoFactor(data: data, response: response, serviceKey: serviceKey)
            default:
                fatalError("Unexpected response status code while signing in: \(httpResponse)")
            }
        }
    }

    public func handleTwoFactor(data: Data, response: URLResponse, serviceKey: String) -> Promise<Void> {
        let httpResponse = response as! HTTPURLResponse
        let sessionID = (httpResponse.allHeaderFields["X-Apple-ID-Session-Id"] as! String)
        let scnt = (httpResponse.allHeaderFields["scnt"] as! String)

        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            URLSession.shared.dataTask(.promise, with: URLRequest.authOptions(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
        }
        .then { (data, response) -> Promise<(data: Data, response: URLResponse)> in
            print("Enter the code: ")
            let code = readLine() ?? ""
            return URLSession.shared.dataTask(.promise, with: try URLRequest.submitSecurityCode(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt, code: code))
        }
        .then { (data, response) -> Promise<(data: Data, response: URLResponse)>  in
            URLSession.shared.dataTask(.promise, with: URLRequest.trust(serviceKey: serviceKey, sessionID: sessionID, scnt: scnt))
        }
        .then { (data, response) -> Promise<Void> in
            URLSession.shared.dataTask(.promise, with: URLRequest.olympusSession).asVoid()
        }
    }
}

