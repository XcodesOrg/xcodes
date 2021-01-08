import ArgumentParser
import LegibleError
import XcodesKit

extension ParsableArguments {
    static func exit(withLegibleError error: Error) -> Never {
        Current.logging.log(error.legibleLocalizedDescription)
        Self.exit(withError: ExitCode.failure)
    }
}
