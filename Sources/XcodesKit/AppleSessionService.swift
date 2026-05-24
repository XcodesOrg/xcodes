import Foundation
import os
import XcodesLoginKit

public typealias AppleSessionService = XcodesLoginKit.AppleSessionService

public extension XcodesLoginKit.AppleSessionService {
    init(configuration: Configuration) {
        let configurationStorage = OSAllocatedUnfairLock(initialState: configuration)
        self.init(dependencies: .init(
            environmentValue: { Current.shell.env($0) },
            defaultUsername: {
                configurationStorage.withLock { $0.defaultUsername }
            },
            setDefaultUsername: { username in
                try configurationStorage.withLock {
                    $0.defaultUsername = username
                    try $0.save()
                }
            },
            keychainString: { try Current.keychain.getString($0) },
            keychainSet: { try Current.keychain.set($0, key: $1) },
            keychainRemove: { try Current.keychain.remove($0) },
            readLine: { Current.shell.readLine(prompt: $0) },
            readSecureLine: { Current.shell.readSecureLine(prompt: $0) },
            validateSession: { try await Current.network.validateSessionAsync() },
            login: { accountName, password in
                try await Current.network.loginAsync(accountName: accountName, password: password)
            },
            signout: { await Current.network.signout() },
            loadData: { request in
                try await Current.network.data(for: request)
            },
            log: { Current.logging.log($0) }
        ))
    }
}
