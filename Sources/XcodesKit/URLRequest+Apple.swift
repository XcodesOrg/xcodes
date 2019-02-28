import Foundation

extension URL {
    static let itcServiceKey = URL(string: "https://olympus.itunes.apple.com/v1/app/config?hostname=itunesconnect.apple.com")!
    static let signIn = URL(string: "https://idmsa.apple.com/appleauth/auth/signin")!
    static let authOptions = URL(string: "https://idmsa.apple.com/appleauth/auth")!
    static let submitSecurityCode = URL(string: "https://idmsa.apple.com/appleauth/auth/verify/trusteddevice/securitycode")!
    static let trust = URL(string: "https://idmsa.apple.com/appleauth/auth/2sv/trust")!
    static let olympusSession = URL(string: "https://olympus.itunes.apple.com/v1/session")!
    static let downloads = URL(string: "https://developer.apple.com/services-account/QH65B2/downloadws/listDownloads.action")!
    static let downloadXcode = URL(string: "https://developer.apple.com/devcenter/download.action")!
}

extension URLRequest {
    static var itcServiceKey: URLRequest {
        return URLRequest(url: .itcServiceKey)
    }

    static func signIn(serviceKey: String, accountName: String, password: String) -> URLRequest {
        struct Body: Encodable {
            let accountName: String
            let password: String
            let rememberMe = true
        }

        var request = URLRequest(url: .signIn)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.allHTTPHeaderFields?["X-Requested-With"] = "XMLHttpRequest"
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["Accept"] = "application/json, text/javascript"
        request.httpMethod = "POST"
        request.httpBody = try! JSONEncoder().encode(Body(accountName: accountName, password: password))
        return request
    }

    static func authOptions(serviceKey: String, sessionID: String, scnt: String) -> URLRequest {
        var request = URLRequest(url: .authOptions)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["accept"] = "application/json"
        return request
    }

    static func submitSecurityCode(serviceKey: String, sessionID: String, scnt: String, code: String) throws -> URLRequest {
        struct SecurityCode: Encodable {
            let code: String

            enum CodingKeys: String, CodingKey {
                case securityCode
            }
            enum SecurityCodeCodingKeys: String, CodingKey {
                case code
            }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                var securityCode = container.nestedContainer(keyedBy: SecurityCodeCodingKeys.self, forKey: .securityCode)
                try securityCode.encode(code, forKey: .code)
            }
        }

        var request = URLRequest(url: .submitSecurityCode)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        request.allHTTPHeaderFields?["Content-Type"] = "application/json"
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(SecurityCode(code: code))
        return request
    }

    static func trust(serviceKey: String, sessionID: String, scnt: String) -> URLRequest {
        var request = URLRequest(url: .trust)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["X-Apple-ID-Session-Id"] = sessionID
        request.allHTTPHeaderFields?["X-Apple-Widget-Key"] = serviceKey
        request.allHTTPHeaderFields?["scnt"] = scnt
        request.allHTTPHeaderFields?["Accept"] = "application/json"
        return request
    }

    static var olympusSession: URLRequest {
        return URLRequest(url: .olympusSession)
    }

    static var downloads: URLRequest {
        var request = URLRequest(url: .downloads)
        request.httpMethod = "POST"
        return request
    }

    static func downloadXcode(path: String) -> URLRequest {
        var components = URLComponents(url: .downloadXcode, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        var request = URLRequest(url: components.url!)
        request.allHTTPHeaderFields = request.allHTTPHeaderFields ?? [:]
        request.allHTTPHeaderFields?["Accept"] = "*/*"
        return request
    }
}
