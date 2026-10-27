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

    /// The prerelease identifiers on one line, with the well-known names abbreviated: "Release Candidate 2" becomes "rc2".
    internal var compactPrereleaseIdentifier: String {
        var suffix = prereleaseIdentifiers.joined(separator: " ")
        for (name, abbreviation) in Self.prereleaseAbbreviations {
            suffix = suffix.replacingOccurrences(of: name, with: abbreviation, options: [.caseInsensitive])
        }
        return suffix.filter { !$0.isWhitespace }
    }

    private static let prereleaseAbbreviations = [
        ("developer preview", "dp"),
        ("release candidate", "rc"),
        ("gold master", "gm"),
        ("beta", "b"),
        ("seed", "s"),
    ]
}
