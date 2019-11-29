import Foundation
import Path
import Version
import PromiseKit
import SwiftSoup
import AppleAPI

/// Provides lists of available and installed Xcodes
public final class XcodeList {
    private let client: AppleAPI.Client

    public init(client: AppleAPI.Client) {
        self.client = client
        try? loadCachedAvailableXcodes()
    }

    public var installedXcodes: [InstalledXcode] {
        let results = try! Path.root.join("Applications").ls().filter { entry in
            guard entry.kind == .directory && entry.path.extension == "app" && !entry.path.isSymlink else { return false }
            let infoPlistPath = entry.path.join("Contents").join("Info.plist")
            let infoPlist = try! PropertyListDecoder().decode(InfoPlist.self, from: try! Data(contentsOf: infoPlistPath.url))
            return infoPlist.bundleID == "com.apple.dt.Xcode"
        }
        let installedXcodes = results.map { $0.path }.compactMap(InstalledXcode.init)
        return installedXcodes
    }

    public private(set) var availableXcodes: [Xcode] = []

    public var shouldUpdate: Bool {
        return availableXcodes.isEmpty
    }

    public func update() -> Promise<[Xcode]> {
        return when(fulfilled: releasedXcodes(), prereleaseXcodes())
            .map { releasedXcodes, prereleaseXcodes in
                // Starting with Xcode 11 beta 6, developer.apple.com/download and developer.apple.com/download/more both list some pre-release versions of Xcode.
                // Previously pre-release versions only appeared on developer.apple.com/download.
                // /download/more doesn't include build numbers, so we trust that if the version number and prerelease identifiers are the same that they're the same build.
                // If an Xcode version is listed on both sites then prefer the one on /download because the build metadata is used to compare against installed Xcodes.
                let xcodes = releasedXcodes.filter { releasedXcode in
                    prereleaseXcodes.contains { $0.version.isEqualWithoutBuildMetadataIdentifiers(to: releasedXcode.version) } == false
                } + prereleaseXcodes
                self.availableXcodes = xcodes
                try? self.cacheAvailableXcodes(xcodes)
                return xcodes
            }
    }
}

extension XcodeList {
    /// Migrates any application support files from Xcodes < v0.4 if application support files from >= v0.4 don't exist
    public static func migrateApplicationSupportFiles() {
        if Current.files.fileExistsAtPath(Path.oldXcodesApplicationSupport.string) {
            if Current.files.fileExistsAtPath(Path.xcodesApplicationSupport.string) {
                Current.logging.log("Removing old support files...")
                try? Current.files.removeItem(Path.oldXcodesApplicationSupport.url)
                Current.logging.log("Done")
            }
            else {
                Current.logging.log("Migrating old support files...")
                try? Current.files.moveItem(Path.oldXcodesApplicationSupport.url, Path.xcodesApplicationSupport.url)
                Current.logging.log("Done")
            }
        }
    }

    private func loadCachedAvailableXcodes() throws {
        let data = try Data(contentsOf: Path.cacheFile.url)
        let xcodes = try JSONDecoder().decode([Xcode].self, from: data)
        self.availableXcodes = xcodes
    }

    private func cacheAvailableXcodes(_ xcodes: [Xcode]) throws {
        let data = try JSONEncoder().encode(xcodes)
        try FileManager.default.createDirectory(at: Path.cacheFile.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: Path.cacheFile.url)
    }
}

extension XcodeList {
    private func releasedXcodes() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            client.session.dataTask(.promise, with: URLRequest.downloads)
        }
        .map { (data, response) -> [Xcode] in
            struct Downloads: Decodable {
                let downloads: [Download]
            }

            let downloads = try JSONDecoder().decode(Downloads.self, from: data)
            let xcodes = downloads
                .downloads
                .filter { $0.name.range(of: "^Xcode [0-9]", options: .regularExpression) != nil }
                .compactMap { download -> Xcode? in
                    let urlPrefix = "https://developer.apple.com/devcenter/download.action?path="
                    guard 
                        let xcodeFile = download.files.first(where: { $0.remotePath.hasSuffix("dmg") || $0.remotePath.hasSuffix("xip") }),
                        let url = URL(string: urlPrefix + xcodeFile.remotePath),
                        let version = Version(xcodeVersion: download.name)
                    else { return nil }

                    return Xcode(version: version, url: url, filename: String(xcodeFile.remotePath.suffix(fromLast: "/")))
                }
            return xcodes
        }
    }

    private func prereleaseXcodes() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            client.session.dataTask(.promise, with: URLRequest.download)
        }
        .map { (data, _) -> [Xcode] in
            try self.parsePrereleaseXcodes(from: data)
        }
    }

    func parsePrereleaseXcodes(from data: Data) throws -> [Xcode] {
        let body = String(data: data, encoding: .utf8)!
        let document = try SwiftSoup.parse(body)

        guard 
            let xcodeHeader = try document.select("h2:containsOwn(Xcode)").first(),
            let productBuildVersion = try xcodeHeader.parent()?.select("li:contains(Build)").text().replacingOccurrences(of: "Build", with: ""),
            let version = Version(xcodeVersion: try xcodeHeader.text(), buildMetadataIdentifier: productBuildVersion),
            let path = try document.select(".direct-download[href*=xip]").first()?.attr("href"),
            let url = URL(string: "https://developer.apple.com" + path)
        else { return [] }

        let filename = String(path.suffix(fromLast: "/"))

        return [Xcode(version: version, url: url, filename: filename)]
    }
}
