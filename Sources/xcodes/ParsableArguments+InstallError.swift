import ArgumentParser
import Foundation
import LegibleError
import XcodesCLIKit
import Rainbow

extension ParsableArguments {
    static func processDownloadOrInstall(error: Error) -> Never {
        var exitCode: ExitCode = .failure
        switch error {
        case let error as ProcessExecutionError:
            Current.logging.log("""
                Failed executing: `\(error.processDescription)` (\(error.terminationStatus))
                \([error.standardOutput, error.standardError].filter { !$0.isEmpty }.joined(separator: "\n"))
                """.red)
        case let error as XcodeInstaller.Error:
            if case .versionAlreadyInstalled = error {
                Current.logging.log(error.legibleLocalizedDescription.green)
                exitCode = .success
            } else {
                Current.logging.log(error.legibleLocalizedDescription.red)
            }
        default:
            Current.logging.log(error.legibleLocalizedDescription.red)
        }

        Self.exit(withError: exitCode)
    }
}
