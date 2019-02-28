import Foundation
import Path
import Version

public struct InstalledXcode {
    public let path: Path
    public let bundleVersion: Version


    public init(path: Path) {
        self.path = path
        let infoPlistPath = path.join("Contents").join("Info.plist")
        let infoPlist = try! PropertyListDecoder().decode(InfoPlist.self, from: try! Data(contentsOf: infoPlistPath.url))
        self.bundleVersion = Version(tolerant: infoPlist.bundleShortVersion!)!
    }
}

public struct Xcode: Codable {
    public let version: Version
    public let url: URL
    public let filename: String

    public init?(name: String, url: URL, filename: String) {
        let versionString = name.replacingOccurrences(of: "Xcode ", with: "").split(separator: " ").map(String.init).first ?? ""
        guard let version = Version(tolerant: versionString) else { return nil }
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
