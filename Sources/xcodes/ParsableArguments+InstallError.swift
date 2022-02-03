import ArgumentParser
import Foundation
import LegibleError
import PromiseKit
import XcodesKit
import Rainbow

extension ParsableArguments {
    static func processDownloadOrInstall(error: Error) -> Never {
        var exitCode: ExitCode = .failure
        switch error {
        case Process.PMKError.execution(let process, let standardOutput, let standardError):
            Current.logging.log("""
                Failed executing: `\(process)` (\(process.terminationStatus))
                \([standardOutput, standardError].compactMap { $0 }.joined(separator: "\n"))
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
