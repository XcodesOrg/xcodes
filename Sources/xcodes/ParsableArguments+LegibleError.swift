import ArgumentParser
import LegibleError
import XcodesKit
import Rainbow

extension ParsableArguments {
    static func exit(withLegibleError error: Error) -> Never {
        Current.logging.log(error.legibleLocalizedDescription.red)
        Self.exit(withError: ExitCode.failure)
    }
}
