import Foundation
import Path
import Version

struct InstalledXcode {
    let path: Path
    let bundleVersion: Version


    init(path: Path) {
        self.path = path
        let infoPlistPath = path.join("Contents").join("Info.plist")
        let infoPlist = try! PropertyListDecoder().decode(InfoPlist.self, from: try! Data(contentsOf: infoPlistPath.url))
        self.bundleVersion = Version(tolerant: infoPlist.bundleShortVersion!)!
    }
}

struct Xcode: Codable {
    let version: Version

    init?(name: String) {
        let versionString = name.replacingOccurrences(of: "Xcode ", with: "").split(separator: " ").map(String.init).first ?? ""
        guard let version = Version(tolerant: versionString) else { return nil }
        self.version =  version
    }
}

struct Download: Decodable {
    let name: String
}

struct InfoPlist: Decodable {
    let bundleID: String?
    let bundleShortVersion: String?

    enum CodingKeys: String, CodingKey {
        case bundleID = "CFBundleIdentifier"
        case bundleShortVersion = "CFBundleShortVersionString"
    }
}
