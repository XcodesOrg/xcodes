import Foundation
import AppleAPI
import Path

public class FastlaneSessionManager {

    public enum Constants {
        public static let fastlaneSessionEnvVarName = "FASTLANE_SESSION"
        public static let fastlaneSpaceshipDir = Path.environmentHome.url
                                                    .appendingPathComponent(".fastlane")
                                                    .appendingPathComponent("spaceship")
    }

    public init() {}

    public func setupFastlaneAuth(fastlaneUser: String) {
        // Use ephemeral session so that cookies don't conflict with normal usage
        AppleAPI.Current.network.session = URLSession(configuration: .ephemeral)
        switch fastlaneUser {
        case Constants.fastlaneSessionEnvVarName:
            importFastlaneCookiesFromEnv()
        default:
            importFastlaneCookiesFromFile(fastlaneUser: fastlaneUser)
        }
    }

    private func importFastlaneCookiesFromEnv() {
        guard let cookieString = Current.shell.env(Constants.fastlaneSessionEnvVarName) else {
            Current.logging.log("\(Constants.fastlaneSessionEnvVarName) not set")
            return
        }
        do {
            let cookies = try Current.fastlaneCookieParser.parse(cookieString: cookieString)
            cookies.forEach(AppleAPI.Current.network.session.configuration.httpCookieStorage!.setCookie)
        } catch {
            Current.logging.log("Failed to parse cookies from \(Constants.fastlaneSessionEnvVarName)")
            return
        }
    }

    private func importFastlaneCookiesFromFile(fastlaneUser: String) {
        let cookieFilePath = Constants
                                .fastlaneSpaceshipDir
                                .appendingPathComponent(fastlaneUser)
                                .appendingPathComponent("cookie")
        guard
            let cookieString = try? String(contentsOf: cookieFilePath)
        else {
            Current.logging.log("Could not read cookies from \(cookieFilePath)")
            return
        }
        do {
            let cookies = try Current.fastlaneCookieParser.parse(cookieString: cookieString)
            cookies.forEach(AppleAPI.Current.network.session.configuration.httpCookieStorage!.setCookie)
        } catch {
            Current.logging.log("Failed to parse cookies from \(cookieFilePath)")
            return
        }
    }
}
