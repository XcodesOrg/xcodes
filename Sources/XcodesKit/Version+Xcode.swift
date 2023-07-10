import Foundation
import Path
import Version

public extension Version {
    /**
     E.g.:
     Xcode 10.2 Beta 4
     Xcode 10.2 GM
     Xcode 10.2 GM seed 2
     Xcode 10.2
     Xcode 10.2.1
     10.2 Beta 4
     10.2 GM
     10.2
     10.2.1
     13.2 Release Candidate
     */
    init?(xcodeVersion: String, buildMetadataIdentifier: String? = nil) {
        let nsrange = NSRange(xcodeVersion.startIndex..<xcodeVersion.endIndex, in: xcodeVersion)
        // https://regex101.com/r/K7530Z/1
        let pattern = "^(Xcode )?(?<major>\\d+)\\.?(?<minor>\\d*)\\.?(?<patch>\\d*) ?(?<prereleaseType>[a-zA-Z ]+)? ?(?<prereleaseVersion>\\d*)"

        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
            let match = regex.firstMatch(in: xcodeVersion, options: [], range: nsrange),
            let majorString = match.groupNamed("major", in: xcodeVersion),
            let major = Int(majorString),
            let minorString = match.groupNamed("minor", in: xcodeVersion),
            let patchString = match.groupNamed("patch", in: xcodeVersion)
        else { return nil }

        let minor = Int(minorString) ?? 0
        let patch = Int(patchString) ?? 0
        let prereleaseType: [String] = match.groupNamed("prereleaseType", in: xcodeVersion)?.trimmingCharacters(in: .whitespaces).split(separator: " ").compactMap { $0.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }.filter { !$0.isEmpty } ?? []

        var optionalPrereleaseIdentifiers: [String?] = []
        prereleaseType.forEach { type in
            if type == "seed" {
                let lastIndex = optionalPrereleaseIdentifiers.endIndex - 1
                if optionalPrereleaseIdentifiers.indices.contains(lastIndex),
                    let lastItem = optionalPrereleaseIdentifiers[lastIndex] {

                    optionalPrereleaseIdentifiers[lastIndex] = "\(lastItem)-seed"
                }
            } else if type == "b" {
                optionalPrereleaseIdentifiers.append("beta")
            } else {
                optionalPrereleaseIdentifiers.append(type)
            }
        }
        optionalPrereleaseIdentifiers.append(match.groupNamed("prereleaseVersion", in: xcodeVersion))

        let prereleaseIdentifiers = optionalPrereleaseIdentifiers
                                        .compactMap { $0?.lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "-") }
                                        .filter { !$0.isEmpty }

        self = Version(major: major, minor: minor, patch: patch, prereleaseIdentifiers: prereleaseIdentifiers, buildMetadataIdentifiers: [buildMetadataIdentifier].compactMap { $0 })
    }

    /// Attempt to instatiate a `Version` using the `.xcode-version` file in the provided directory
    static func fromXcodeVersionFile(inDirectory: Path = Path.cwd) -> Version? {
        let xcodeVersionFilePath = inDirectory.join(".xcode-version")
        guard
            Current.files.fileExists(atPath: xcodeVersionFilePath.string),
            let contents = Current.files.contents(atPath: xcodeVersionFilePath.string),
            let versionString = String(data: contents, encoding: .utf8),
            let version = Version(gemVersion: versionString)
        else {
            return nil
        }

        return version
    }

    /// The intent here is to match Apple's marketing version
    ///
    /// Only show the patch number if it's not 0
    /// Format prerelease identifiers
    /// Don't include build identifiers
    var appleDescription: String {
        var base = "\(major).\(minor)"
        if patch != 0 {
            base += ".\(patch)"
        }
        if !prereleaseIdentifiers.isEmpty {
            base += " " + prereleaseIdentifiers
                .map { identifier in
                    identifier
                        .replacingOccurrences(of: "-", with: " ")
                        .capitalized
                        .replacingOccurrences(of: "Gm", with: "GM")
                        .replacingOccurrences(of: "Rc", with: "RC")
                }
                .joined(separator: " ")
        }
        return base
    }
    var appleDescriptionWithBuildIdentifier: String {
        [appleDescription, buildMetadataIdentifiersDisplay].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension NSTextCheckingResult {
    func groupNamed(_ name: String, in string: String) -> String? {
        let nsrange = range(withName: name)
        guard let range = Range(nsrange, in: string) else { return nil }
        return String(string[range])
    }
}
