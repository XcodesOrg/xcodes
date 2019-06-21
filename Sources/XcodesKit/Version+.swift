import Version

public extension Version {
    func isEqualWithoutBuildMetadataIdentifiers(to other: Version) -> Bool {
        return major == other.major && 
               minor == other.minor &&
               patch == other.patch &&
               prereleaseIdentifiers == other.prereleaseIdentifiers
    }

    /// If release versions, don't compare build metadata because that's not provided in the /downloads/more list
    /// if beta versions, compare build metadata because it's available in versions.plist
    func isEquivalentForDeterminingIfInstalled(to other: Version) -> Bool {
        let isBeta = !prereleaseIdentifiers.isEmpty
        let otherIsBeta = !other.prereleaseIdentifiers.isEmpty

        if isBeta && otherIsBeta {
            return major == other.major && 
                   minor == other.minor &&
                   patch == other.patch &&
                   buildMetadataIdentifiers.map { $0.lowercased() } == other.buildMetadataIdentifiers.map { $0.lowercased() }
        }
        else if !isBeta && !otherIsBeta {
            return major == other.major && 
                   minor == other.minor &&
                   patch == other.patch
        }

        return false
    }

    var descriptionWithoutBuildMetadata: String {
        var base = "\(major).\(minor).\(patch)"
        if !prereleaseIdentifiers.isEmpty {
            base += "-" + prereleaseIdentifiers.joined(separator: ".")
        }
        return base
    }
}
