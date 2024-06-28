import Foundation

struct DownloadableRuntimesResponse: Decodable {
    let sdkToSimulatorMappings: [SDKToSimulatorMapping]
    let sdkToSeedMappings: [SDKToSeedMapping]
    let refreshInterval: Int
    let downloadables: [DownloadableRuntime]
    let version: String
}

public struct DownloadableRuntime: Decodable {
    let category: Category
    let simulatorVersion: SimulatorVersion
    let source: String?
    let dictionaryVersion: Int
    let contentType: ContentType
    let platform: Platform
    let identifier: String
    let version: String
    let fileSize: Int
    let hostRequirements: HostRequirements?
    let name: String
    let authentication: Authentication?

    var betaNumber: Int? {
        enum Regex { static let shared = try! NSRegularExpression(pattern: "b[0-9]+$") }
        guard var foundString = Regex.shared.firstString(in: identifier) else { return nil }
        foundString.removeFirst()
        return Int(foundString)!
    }

    var completeVersion: String {
        makeVersion(for: simulatorVersion.version, betaNumber: betaNumber)
    }

    var visibleIdentifier: String {
        return platform.shortName + " " + completeVersion
    }
}

func makeVersion(for osVersion: String, betaNumber: Int?) -> String {
    let betaSuffix = betaNumber.flatMap { "-beta\($0)" } ?? ""
    return osVersion + betaSuffix
}

struct SDKToSeedMapping: Decodable {
    let buildUpdate: String
    let platform: DownloadableRuntime.Platform
    let seedNumber: Int
}

struct SDKToSimulatorMapping: Decodable {
    let sdkBuildUpdate: String
    let simulatorBuildUpdate: String
    let sdkIdentifier: String
}

extension DownloadableRuntime {
    struct SimulatorVersion: Decodable {
        let buildUpdate: String
        let version: String
    }

    struct HostRequirements: Decodable {
        let maxHostVersion: String?
        let excludedHostArchitectures: [String]?
        let minHostVersion: String?
        let minXcodeVersion: String?
    }

    enum Authentication: String, Decodable {
        case virtual = "virtual"
    }

    enum Category: String, Decodable {
        case simulator = "simulator"
    }

    enum ContentType: String, Decodable {
        case diskImage = "diskImage"
        case package = "package"
        case cryptexDiskImage = "cryptexDiskImage"
    }

    enum Platform: String, Decodable {
        case iOS = "com.apple.platform.iphoneos"
        case macOS = "com.apple.platform.macosx"
        case watchOS = "com.apple.platform.watchos"
        case tvOS = "com.apple.platform.appletvos"
        case visionOS = "com.apple.platform.xros"

        var order: Int {
            switch self {
                case .iOS: return 1
                case .macOS: return 2
                case .watchOS: return 3
                case .tvOS: return 4
                case .visionOS: return 5
            }
        }

        var shortName: String {
            switch self {
                case .iOS: return "iOS"
                case .macOS: return "macOS"
                case .watchOS: return "watchOS"
                case .tvOS: return "tvOS"
                case .visionOS: return "visionOS"
            }
        }
    }
}

public struct InstalledRuntime: Decodable {
    let build: String
    let deletable: Bool
    let identifier: UUID
    let kind: Kind
    let lastUsedAt: Date?
    let path: String
    let platformIdentifier: Platform
    let runtimeBundlePath: String
    let runtimeIdentifier: String
    let signatureState: String
    let state: String
    let version: String
    let sizeBytes: Int?
}

extension InstalledRuntime {
    enum Kind: String, Decodable {
        case diskImage = "Disk Image"
        case bundled = "Bundled with Xcode"
        case legacyDownload = "Legacy Download"
    }

    enum Platform: String, Decodable {
        case tvOS = "com.apple.platform.appletvsimulator"
        case iOS = "com.apple.platform.iphonesimulator"
        case watchOS = "com.apple.platform.watchsimulator"
        case visionOS = "com.apple.platform.xrsimulator"

        var asPlatformOS: DownloadableRuntime.Platform {
            switch self {
                case .watchOS: return .watchOS
                case .iOS: return .iOS
                case .tvOS: return .tvOS
                case .visionOS: return .visionOS
            }
        }
    }
}
