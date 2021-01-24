import Foundation
import Version

/// Returns the first XcodeType that unambiguously has the same version as `version`.
///
/// If there's an equivalent match that takes prerelease identifiers into account, that's returned.
/// Otherwise, if a version without prerelease or build metadata identifiers is provided, and there's a single match based on only the major, minor and patch numbers, that's returned.
/// If there are multiple matches, or no matches, nil is returned.
public func findXcode<XcodeType>(version: Version, in xcodes: [XcodeType], versionKeyPath: KeyPath<XcodeType, Version>) -> XcodeType? {
    // Look for the equivalent provided version first
    if let equivalentXcode = xcodes.first(where: { $0[keyPath: versionKeyPath].isEquivalent(to: version) }) {
        return equivalentXcode
    }
    // If a version without prerelease or build identifiers is provided, then ignore all identifiers this time. 
    // There must be exactly one match.
    else if version.prereleaseIdentifiers.isEmpty && version.buildMetadataIdentifiers.isEmpty,
        xcodes.filter({ $0[keyPath: versionKeyPath].isEqualWithoutAllIdentifiers(to: version) }).count == 1 {
        let matchedXcode = xcodes.first(where: { $0[keyPath: versionKeyPath].isEqualWithoutAllIdentifiers(to: version) })!
        return matchedXcode
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

extension Version {
    func isEqualWithoutAllIdentifiers(to other: Version) -> Bool {
        return major == other.major &&
               minor == other.minor &&
               patch == other.patch
    }
}
