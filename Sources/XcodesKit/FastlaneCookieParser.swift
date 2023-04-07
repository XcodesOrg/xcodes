import Foundation
import Yams

public class FastlaneCookieParser {
    public func parse(cookieString: String) throws -> [HTTPCookie] {
        let fixed = cookieString.replacingOccurrences(of: "\\n", with: "\n")
        let cookies = try YAMLDecoder().decode([FastlaneCookie].self, from: fixed)
        return cookies.compactMap(\.httpCookie)
    }
}

struct FastlaneCookie: Decodable {

    enum CodingKeys: String, CodingKey {
        case name
        case value
        case domain
        case forDomain = "for_domain"
        case path
        case secure
        case expires
        case maxAge = "max_age"
        case createdAt = "created_at"
        case accessedAt = "accessed_at"
    }

    let name: String
    let value: String
    let domain: String
    let forDomain: Bool
    let path: String
    let secure: Bool
    let expires: Date?
    let maxAge: Int?
    let createdAt: Date
    let accessedAt: Date
}

protocol HTTPCookieConvertible {
    var httpCookie: HTTPCookie? { get }
}

extension FastlaneCookie: HTTPCookieConvertible {
    var httpCookie: HTTPCookie? {

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: self.name,
            .value: self.value,
            .domain: self.domain,
            .path: self.path,
            .secure: self.secure,
        ]

        if forDomain {
            properties[.domain] = ".\(self.domain)"
        } else {
            properties[.domain] = "\(self.domain)"
        }

        if let expires = self.expires {
            properties[.expires] = expires
        }

        if let maxAge = self.maxAge {
            properties[.maximumAge] = maxAge
        }

        return HTTPCookie(properties: properties)
    }
}
