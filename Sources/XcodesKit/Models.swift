import Foundation
import Path
import Version

public struct InstalledXcode: Equatable {
    public let path: Path
    /// Composed of the bundle short version from Info.plist and the product build version from version.plist
    public let version: Version
    
    init(path: Path, version: Version) {
        self.path = path
        self.version = version
    }

    public init?(path: Path) {
        self.path = path

        let infoPlistPath = path.join("Contents").join("Info.plist")
        let versionPlistPath = path.join("Contents").join("version.plist")
        guard 
            let infoPlistData = Current.files.contents(atPath: infoPlistPath.string),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData),
            let bundleShortVersion = infoPlist.bundleShortVersion,
            let bundleVersion = Version(tolerant: bundleShortVersion),

            let versionPlistData = Current.files.contents(atPath: versionPlistPath.string),
            let versionPlist = try? PropertyListDecoder().decode(VersionPlist.self, from: versionPlistData)
        else { return nil }

        // Installed betas don't include the beta number anywhere, so try to parse it from the filename or fall back to simply "beta"
        var prereleaseIdentifiers = bundleVersion.prereleaseIdentifiers
        if let filenameVersion = Version(path.basename(dropExtension: true).replacingOccurrences(of: "Xcode-", with: "")) {
            prereleaseIdentifiers = filenameVersion.prereleaseIdentifiers
        }
        else if infoPlist.bundleIconName == "XcodeBeta", !prereleaseIdentifiers.contains("beta") {
            prereleaseIdentifiers = ["beta"]
        }

        self.version = Version(major: bundleVersion.major,
                               minor: bundleVersion.minor,
                               patch: bundleVersion.patch,
                               prereleaseIdentifiers: prereleaseIdentifiers,
                               buildMetadataIdentifiers: [versionPlist.productBuildVersion].compactMap { $0 })
    }
}

public struct Xcode: Codable, Equatable {
    public let version: Version
    public let url: URL
    public let filename: String
    public let releaseDate: Date?

    public var downloadPath: String {
        return url.path
    }
    
    public init(version: Version, url: URL, filename: String, releaseDate: Date?) {
        self.version =  version
        self.url = url
        self.filename = filename
        self.releaseDate = releaseDate
    }
}

struct Downloads: Codable {
    let downloads: [Download]
}

public struct Download: Codable {
    public let name: String
    public let files: [File]
    public let dateModified: Date

    public struct File: Codable {
        public let remotePath: String
    }
}

public struct InfoPlist: Decodable {
    public let bundleID: String?
    public let bundleShortVersion: String?
    public let bundleIconName: String?

    public enum CodingKeys: String, CodingKey {
        case bundleID = "CFBundleIdentifier"
        case bundleShortVersion = "CFBundleShortVersionString"
        case bundleIconName = "CFBundleIconName"
    }
}

public struct VersionPlist: Decodable {
    public let productBuildVersion: String

    public enum CodingKeys: String, CodingKey {
        case productBuildVersion = "ProductBuildVersion"
    }
}

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
    let source: String
    let dictionaryVersion: Int
    let contentType: ContentType
    let platform: Platform
    let identifier: String
    let version: String
    let fileSize: Int
    let hostRequirements: HostRequirements?
    let name: String
    let authentication: Authentication?
}

struct SDKToSeedMapping: Decodable {
    let buildUpdate: String
    let platform: DownloadableRuntime.Platform
    let seedNumber: Int
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
    }

    enum Platform: String, Decodable {
        case tvOS = "com.apple.platform.appletvos"
        case iOS = "com.apple.platform.iphoneos"
        case macOS = "com.apple.platform.macosx"
        case watchOS = "com.apple.platform.watchos"

        var order: Int {
            switch self {
                case .iOS: return 1
                case .macOS: return 2
                case .watchOS: return 3
                case .tvOS: return 4
            }
        }

        var shortName: String {
            switch self {
                case .iOS: return "iOS"
                case .macOS: return "macOS"
                case .watchOS: return "watchOS"
                case .tvOS: return "tvOS"
            }
        }
    }
}

struct SDKToSimulatorMapping: Decodable {
    let sdkBuildUpdate: String
    let simulatorBuildUpdate: String
    let sdkIdentifier: String
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
        case bundled = "Bundled with Xcode"
        case legacyDownload = "Legacy Download"
    }

    enum Platform: String, Decodable {
        case tvOS = "com.apple.platform.appletvsimulator"
        case iOS = "com.apple.platform.iphonesimulator"
        case watchOS = "com.apple.platform.watchsimulator"
    }
}
