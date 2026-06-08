import ArgumentParser
import LegibleError
import XcodesCLIKit
import Rainbow

extension ParsableArguments {
    static func exit(withLegibleError error: Error) -> Never {
        Current.logging.log(error.legibleLocalizedDescription.red)
        Self.exit(withError: ExitCode.failure)
    }
}
