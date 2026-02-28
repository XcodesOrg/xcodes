import PromiseKit
import Foundation
import AppleAPI
import Path

public class AppleSessionService {

    private let xcodesUsername = "XCODES_USERNAME"
    private let xcodesPassword = "XCODES_PASSWORD"

    var configuration: Configuration

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    private func findUsername() -> String? {
        if let username = Current.shell.env(xcodesUsername) {
            return username
        }
        else if let username = configuration.defaultUsername {
            return username
        }
        return nil
    }

    private func findPassword(withUsername username: String) -> String? {
        if let password = Current.shell.env(xcodesPassword) {
            return password
        }
        else if let password = try? Current.keychain.getString(username){
            return password
        }
        return nil
    }

    func validateADCSession(path: String) -> Promise<Void> {
        return Current.network.dataTask(with: URLRequest.downloadADCAuth(path: path)).asVoid()
    }

    func loginIfNeeded(withUsername providedUsername: String? = nil, shouldPromptForPassword: Bool = false) -> Promise<Void> {
        // Restore any previously saved session cookies before validating
        loadSessionCookies()

        return firstly { () -> Promise<Void> in
            return Current.network.validateSession()
        }
        // Don't have a valid session, so we'll need to log in
        .recover { error -> Promise<Void> in
            var possibleUsername = providedUsername ?? self.findUsername()
            var hasPromptedForUsername = false
            if possibleUsername == nil {
                possibleUsername = Current.shell.readLine(prompt: "Apple ID: ")
                hasPromptedForUsername = true
            }
            guard let username = possibleUsername else { throw Error.missingUsernameOrPassword }

            // Check if this account uses federated authentication before prompting for a password
            return Current.network.checkIsFederated(accountName: username)
                .then { federationResponse -> Promise<Void> in
                    if federationResponse.federated {
                        return self.handleFederatedLogin(username: username, federationResponse: federationResponse)
                    }

                    // Not federated — proceed with normal password-based login
                    let passwordPrompt: String
                    if hasPromptedForUsername {
                        passwordPrompt = "Apple ID Password: "
                    } else {
                        passwordPrompt = "Apple ID Password (\(username)): "
                    }
                    var possiblePassword = self.findPassword(withUsername: username)
                    if possiblePassword == nil || shouldPromptForPassword {
                        possiblePassword = Current.shell.readSecureLine(prompt: passwordPrompt)
                    }
                    guard let password = possiblePassword else { throw Error.missingUsernameOrPassword }

                    return firstly { () -> Promise<Void> in
                        self.login(username, password: password)
                    }
                    .recover { error -> Promise<Void> in
                        Current.logging.log(error.legibleLocalizedDescription.red)

                        if case Client.Error.invalidUsernameOrPassword = error {
                            Current.logging.log("Try entering your password again")
                            return self.loginIfNeeded(withUsername: username, shouldPromptForPassword: true)
                        }
                        else {
                            return Promise(error: error)
                        }
                    }
                }
        }
    }

    func login(_ username: String, password: String) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            Current.network.login(accountName: username, password: password)
        }
        .recover { error -> Promise<Void> in

            if let error = error as? Client.Error {
                switch error {
                    case .invalidUsernameOrPassword(_):
                        // remove any keychain password if we fail to log with an invalid username or password so it doesn't try again.
                        try? Current.keychain.remove(username)
                    default:
                        break
                }
            }

            return Promise(error: error)
        }
        .done { _ in
            try? Current.keychain.set(password, key: username)

            if self.configuration.defaultUsername != username {
                self.configuration.defaultUsername = username
                try? self.configuration.save()
            }
        }
    }

    private func handleFederatedLogin(username: String, federationResponse: FederationResponse) -> Promise<Void> {
        guard let idpURL = federationResponse.idpURL else {
            return Promise(error: Client.Error.federatedAuthenticationRequired)
        }

        let orgName = federationResponse.federatedAuthIntro?.orgName ?? "your organization"
        let idpName = federationResponse.federatedAuthIntro?.idpName
        let orgNameWithIdp = idpName.map { "\(orgName) (\($0))" } ?? orgName

        Current.logging.log("\n- This account uses federated authentication via \(orgNameWithIdp)")
        Current.logging.log("- Your browser will open to complete sign-in")
        Current.logging.log("- After signing in, you will be redirected to a blank page")
        Current.logging.log("- Copy the URL from your browser's address bar, then return here and paste it")

        Current.shell.waitForKeypress(prompt: "\nPress any key to open your browser...")
        Current.shell.openURL(idpURL)

        let callbackURLString = Current.shell.readLongLine(prompt: "\nPaste the URL here: ")
        guard let callbackURLString = callbackURLString,
              let callbackURL = URL(string: callbackURLString),
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return Promise(error: Error.missingUsernameOrPassword)
        }

        let widgetKey = queryItems.first(where: { $0.name == "widgetKey" })?.value
        let token = queryItems.first(where: { $0.name == "token" })?.value
        let relayState = queryItems.first(where: { $0.name == "relayState" })?.value

        guard let widgetKey = widgetKey, let token = token, let relayState = relayState else {
            Current.logging.log("The URL is missing required parameters (widgetKey, token, relayState).")
            return Promise(error: Client.Error.invalidSession)
        }

        return Current.network.validateFederatedToken(widgetKey: widgetKey, token: token, relayState: relayState)
            .done {
                self.saveSessionCookies()

                if self.configuration.defaultUsername != username {
                    self.configuration.defaultUsername = username
                    try? self.configuration.save()
                }
            }
    }

    // MARK: - Session Cookie Persistence

    private struct SerializableCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let isSecure: Bool
        let expiresDate: Date?

        init(cookie: HTTPCookie) {
            self.name = cookie.name
            self.value = cookie.value
            self.domain = cookie.domain
            self.path = cookie.path
            self.isSecure = cookie.isSecure
            self.expiresDate = cookie.expiresDate
        }

        var httpCookie: HTTPCookie? {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path,
                .secure: isSecure ? "TRUE" : "FALSE",
            ]
            if let expiresDate = expiresDate {
                properties[.expires] = expiresDate
            }
            return HTTPCookie(properties: properties)
        }
    }

    private func saveSessionCookies() {
        let appleDomains = [".apple.com", ".idmsa.apple.com", "appstoreconnect.apple.com"]
        let cookies = AppleAPI.Current.network.session.configuration.httpCookieStorage?.cookies ?? []
        let relevantCookies = cookies.filter { cookie in
            appleDomains.contains(where: { cookie.domain.hasSuffix($0) })
        }
        guard !relevantCookies.isEmpty else { return }

        let serializable = relevantCookies.map(SerializableCookie.init)
        if let data = try? JSONEncoder().encode(serializable) {
            try? Current.files.write(data, Path.sessionCookiesFile.url)
        }
    }

    private func loadSessionCookies() {
        guard let data = Current.files.contents(atPath: Path.sessionCookiesFile.string) else { return }
        guard let serialized = try? JSONDecoder().decode([SerializableCookie].self, from: data) else { return }

        let cookieStorage = AppleAPI.Current.network.session.configuration.httpCookieStorage
        for cookie in serialized {
            if let expired = cookie.expiresDate, expired < Date() { continue }
            cookie.httpCookie.map { cookieStorage?.setCookie($0) }
        }
    }

    public func logout() -> Promise<Void> {
        guard let username = findUsername() else { return Promise<Void>(error: Client.Error.notAuthenticated) }

        return Promise { seal in
            // Remove cookies in the shared URLSession
            AppleAPI.Current.network.session.reset {
                seal.fulfill(())
            }
        }
        .done {
            // Remove all keychain items
            try Current.keychain.remove(username)

            // Remove saved session cookies
            try? Current.files.removeItem(Path.sessionCookiesFile.url)

            // Set `defaultUsername` in Configuration to nil
            self.configuration.defaultUsername = nil
            try self.configuration.save()
        }
    }
}

extension AppleSessionService {
    enum Error: LocalizedError, Equatable {
        case missingUsernameOrPassword

        public var errorDescription: String? {
            switch self {
                case .missingUsernameOrPassword:
                    return "Missing username or a password. Please try again."
            }
        }

    }
}
