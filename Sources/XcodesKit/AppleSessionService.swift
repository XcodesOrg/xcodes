import PromiseKit
import Foundation
import AppleAPI

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
                if self.configuration.defaultUsername != username {
                    self.configuration.defaultUsername = username
                    try? self.configuration.save()
                }
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
