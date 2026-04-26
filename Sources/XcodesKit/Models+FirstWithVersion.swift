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

    /// Returns the best compatible Xcode for the given version and host architecture.
    ///
    /// Selection priority:
    /// 1. Universal build (contains both arm64 and x86_64)
    /// 2. Architecture-specific build matching host (arm64 for Apple Silicon, x86_64 for Intel)
    /// 3. First match (fallback)
    func firstCompatible(withVersion version: Version, hostArchitecture: String) -> Xcode? {
        // First try to find using the standard version matching
        let matches = findAllXcodes(version: version, in: self, versionKeyPath: \.version)
        guard !matches.isEmpty else { return nil }

        // Priority 1: Universal build (contains both architectures)
        if let universal = matches.first(where: { ($0.architectures ?? []).contains("arm64") && $0.architectures!.contains("x86_64") }) {
            return universal
        }

        // Priority 2: Architecture-specific build matching host
        if let matching = matches.first(where: { ($0.architectures ?? []).contains(hostArchitecture) }) {
            return matching
        }

        // Priority 3: Fall back to first match
        return matches.first
    }

    /// Returns all Xcodes with the same version (helper for architecture-aware selection)
    private func findAllXcodes<XcodeType>(version: Version, in xcodes: [XcodeType], versionKeyPath: KeyPath<XcodeType, Version>) -> [XcodeType] {
        // Look for equivalent matches
        let equivalentMatches = xcodes.filter { $0[keyPath: versionKeyPath].isEquivalent(to: version) }
        if !equivalentMatches.isEmpty {
            return equivalentMatches
        }
        // If version without prerelease/build identifiers, find matches without all identifiers
        if version.prereleaseIdentifiers.isEmpty && version.buildMetadataIdentifiers.isEmpty {
            return xcodes.filter { $0[keyPath: versionKeyPath].isEqualWithoutAllIdentifiers(to: version) }
        }
        return []
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
