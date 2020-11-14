import Foundation
import Version

/// Returns the first XcodeType that unambiguously has the same version as `version`.
///
/// If there's an exact match that takes prerelease identifiers into account, that's returned.
/// Otherwise, if a version without prerelease or build metadata identifiers is provided, and there's a single match based on only the major, minor and patch numbers, that's returned.
/// If there are multiple matches, or no matches, nil is returned.
public func findXcode<XcodeType>(version: Version, in xcodes: [XcodeType], versionKeyPath: KeyPath<XcodeType, Version>) -> XcodeType? {
    // Look for the exact provided version first
    if let installedXcode = xcodes.first(where: { $0[keyPath: versionKeyPath].isEqualWithoutBuildMetadataIdentifiers(to: version) }) {
        return installedXcode
    }
    // If a short version is provided, look again for a match, ignore all
    // identifiers this time. Ignore if there are more than one match.
    else if version.prereleaseIdentifiers.isEmpty && version.buildMetadataIdentifiers.isEmpty,
        xcodes.filter({ $0[keyPath: versionKeyPath].isEqualWithoutAllIdentifiers(to: version) }).count == 1 {
        let installedXcode = xcodes.first(where: { $0[keyPath: versionKeyPath].isEqualWithoutAllIdentifiers(to: version) })!
        return installedXcode
    } else {
        return nil
    }
}

public extension Array where Element == Xcode {
    /// Returns the first Xcode that unambiguously has the same version as `version`.
    ///
    /// If there's an exact match that takes prerelease identifiers into account, that's returned.
    /// Otherwise, if a version without prerelease or build metadata identifiers is provided, and there's a single match based on only the major, minor and patch numbers, that's returned.
    /// If there are multiple matches, or no matches, nil is returned.
    func first(withVersion version: Version) -> Xcode? {
        findXcode(version: version, in: self, versionKeyPath: \.version)
    }
}

public extension Array where Element == InstalledXcode {
    /// Returns the first InstalledXcode that unambiguously has the same version as `version`.
    ///
    /// If there's an exact match that takes prerelease identifiers into account, that's returned.
    /// Otherwise, if a version without prerelease or build metadata identifiers is provided, and there's a single match based on only the major, minor and patch numbers, that's returned.
    /// If there are multiple matches, or no matches, nil is returned.
    func first(withVersion version: Version) -> InstalledXcode? {
        findXcode(version: version, in: self, versionKeyPath: \.version)
    } 
}
