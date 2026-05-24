import Foundation
import Path
import XcodesLoginKit

public final class FastlaneSessionManager: Sendable {
    public typealias Constants = XcodesLoginKit.FastlaneSessionLoader.Constants

    public init() {}

    private let loginKitManager = XcodesLoginKit.FastlaneSessionLoader()

    public func setupFastlaneAuth(fastlaneUser: String) {
        do {
            Current.network.session = try loginKitManager.session(
                fastlaneUser: fastlaneUser,
                environmentValue: Current.shell.env
            )
        } catch XcodesLoginKit.FastlaneSessionLoader.Error.missingEnvironmentVariable(let variableName) {
            Current.logging.log("\(variableName) not set".red)
        } catch {
            let source = fastlaneUser == Constants.fastlaneSessionEnvVarName
                ? Constants.fastlaneSessionEnvVarName
                : XcodesLoginKit.FastlaneSessionLoader.cookieFileURL(fastlaneUser: fastlaneUser).path
            Current.logging.log("Failed to parse cookies from \(source)".red)
        }
    }
}
