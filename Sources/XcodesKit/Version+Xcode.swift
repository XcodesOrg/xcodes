import Foundation
import Version

public extension Version {
    /**
     E.g.:
     Xcode 10.2 Beta 4
     Xcode 10.2 GM
     Xcode 10.2
     Xcode 10.2.1
     10.2 Beta 4
     10.2 GM
     10.2
     10.2.1
     */
    init?(xcodeVersion: String, buildMetadataIdentifier: String? = nil) {
        let nsrange = NSRange(xcodeVersion.startIndex..<xcodeVersion.endIndex, in: xcodeVersion)
        let pattern = "^(Xcode )?(?<major>\\d+)\\.?(?<minor>\\d?)\\.?(?<patch>\\d?) ?(?<prereleaseType>\\w+)? ?(?<prereleaseVersion>\\d?)"

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
        let prereleaseIdentifiers = [match.groupNamed("prereleaseType", in: xcodeVersion), 
                                     match.groupNamed("prereleaseVersion", in: xcodeVersion)]
                                        .compactMap { $0?.lowercased() }
                                        .filter { !$0.isEmpty }

        self = Version(major: major, minor: minor, patch: patch, prereleaseIdentifiers: prereleaseIdentifiers, buildMetadataIdentifiers: [buildMetadataIdentifier].compactMap { $0 })
    }

    var xcodeDescription: String {
        var base = "\(major).\(minor)"
        if patch != 0 {
            base += ".\(patch)"
        }
        if !prereleaseIdentifiers.isEmpty {
            base += " " + prereleaseIdentifiers.map { $0.capitalized }.joined(separator: " ")
        }
        return base
    }
}

extension NSTextCheckingResult {
    func groupNamed(_ name: String, in string: String) -> String? {
        let nsrange = range(withName: name)
        guard let range = Range(nsrange, in: string) else { return nil }
        return String(string[range])
    }
}
