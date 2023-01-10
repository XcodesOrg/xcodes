//
//  FastlaneCookieLoader.swift
//  
//
//  Created by Omar Zuñiga on 09/01/23.
//

import Foundation
import Yams

struct FastlaneCookieLoader {
    
    private let fastlaneSession = "FASTLANE_SESSION"
    
    func load(in storage: HTTPCookieStorage?) {
        do {
            guard let storage, var sessionVar = Current.shell.env(fastlaneSession) else { return }
            // We need to convert literal line break into actual ones
            sessionVar = sessionVar.replacingOccurrences(of: "\\n", with: "\n")
            let decoder = YAMLDecoder()
            let cookies: [Cookie] = try decoder.decode(from: sessionVar)
            cookies.forEach { add(cookie: $0, in: storage) }
        } catch {
          print("Error decoding Fastlane cookie: \(error)")
        }
    }
}

private extension FastlaneCookieLoader {
    func add(cookie: Cookie, in storage: HTTPCookieStorage) {
        
        // apple.com cookies are supposed to be for all apple.com requests
        let domain = cookie.domain == "apple.com" ? ".apple.com" : cookie.domain
        
        let properties: [HTTPCookiePropertyKey: Any] =  [
            .name: cookie.name,
            .value: cookie.value,
            .domain: domain,
            .path: cookie.path,
            .expires: cookie.expires,
            .secure: cookie.secure.flatMap { String($0) },
            .maximumAge: cookie.maxAge.flatMap { String($0) },
            .originURL: cookie.origin,
        ].compactMapValues { $0 }
        
        guard let httpCookie = HTTPCookie(properties: properties) else { return }
        storage.setCookie(httpCookie)
    }
}

private struct Cookie: Decodable {
     let name: String?
     let value: String?
     let domain: String?
     let path: String?
     let expires: String?
     let secure: Bool?
     let maxAge: UInt?
     let origin: String?
 }
