import Foundation
import Path
import Version

public struct InstalledXcode: Equatable {
    public let path: Path
    public let bundleVersion: Version

    public init?(path: Path) {
        self.path = path

        let infoPlistPath = path.join("Contents").join("Info.plist")
        guard 
            let infoPlistData = Current.files.contents(atPath: infoPlistPath.string),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData),
            let bundleShortVersion = infoPlist.bundleShortVersion,
            let bundleVersion = Version(tolerant: bundleShortVersion)
        else { return nil }

        self.bundleVersion = bundleVersion
    }
}

public struct Xcode: Codable {
    public let version: Version
    public let url: URL
    public let filename: String

    public init(version: Version, url: URL, filename: String) {
        self.version =  version
        self.url = url
        self.filename = filename
    }
}

public struct Download: Decodable {
    public let name: String
    public let files: [File]

    public struct File: Decodable {
        public let remotePath: String
    }
}

public struct InfoPlist: Decodable {
    public let bundleID: String?
    public let bundleShortVersion: String?

    public enum CodingKeys: String, CodingKey {
        case bundleID = "CFBundleIdentifier"
        case bundleShortVersion = "CFBundleShortVersionString"
    }
}
