import Path
import Version
import XcodesKit

public extension Version {
    /// Attempt to instantiate a `Version` using the `.xcode-version` file in the provided directory.
    static func fromXcodeVersionFile(inDirectory: Path = Path(.cwd)) -> Version? {
        XcodeVersionFileService(
            fileExists: { path in Current.files.fileExists(atPath: path) },
            contentsAtPath: { path in Current.files.contents(atPath: path) }
        )
        .version(inDirectory: inDirectory)
    }
}
