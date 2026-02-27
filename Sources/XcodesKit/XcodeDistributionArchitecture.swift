import Foundation

/// `XcodeDistributionArchitecture` describes a CPU architecture advertised by
/// an Xcode download entry from xcodereleases metadata.
/// Raw values are normalized lowercase identifiers used by the upstream data.
/// Only known architectures are representable (`arm64`, `x86_64`).
/// `rawValue` is stable and suitable for persistence/comparison.
public enum XcodeDistributionArchitecture: String, CaseIterable, Codable, Hashable {
    case arm64
    case x86_64
}
