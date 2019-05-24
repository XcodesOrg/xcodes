import Foundation
import Path
import Version
import PromiseKit
import PMKFoundation
import SwiftSoup
import AppleAPI

/// Provides lists of available and installed Xcodes
public final class XcodeManager {
    private let client: AppleAPI.Client

    public init(client: AppleAPI.Client) {
        self.client = client
        try? loadCachedAvailableXcodes()
        try? loadConfiguration()
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

    public private(set) var configuration = Configuration(defaultUsername: nil)

    public var shouldUpdate: Bool {
        return availableXcodes.isEmpty
    }

    public func update() -> Promise<[Xcode]> {
        return when(fulfilled: releasedXcodes(), prereleaseXcodes())
            .map { availableXcodes, prereleaseXcodes in
                let xcodes = availableXcodes + prereleaseXcodes
                self.availableXcodes = xcodes
                try? self.cacheAvailableXcodes(xcodes)
                return xcodes
            }
    }

    public func saveUsername(_ username: String) {
        self.configuration = Configuration(defaultUsername: username)
        try? saveConfiguration(self.configuration)
    }
}

extension XcodeManager {
    /// Migrates any application support files from Xcodes < v0.4 if application support files from >= v0.4 don't exist
    public static func migrateApplicationSupportFiles() {
        if Current.files.fileExistsAtPath(Path.oldXcodesApplicationSupport.string) {
            if Current.files.fileExistsAtPath(Path.xcodesApplicationSupport.string) {
                print("Removing old support files...")
                try? Current.files.removeItem(Path.oldXcodesApplicationSupport.url)
                print("Done")
            }
            else {
                print("Migrating old support files...")
                try? Current.files.moveItem(Path.oldXcodesApplicationSupport.url, Path.xcodesApplicationSupport.url)
                print("Done")
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

    private func loadConfiguration() throws {
        let data = try Data(contentsOf: Path.configurationFile.url)
        self.configuration = try JSONDecoder().decode(Configuration.self, from: data)
    }

    private func saveConfiguration(_ configuration: Configuration) throws {
        let data = try JSONEncoder().encode(configuration)
        try FileManager.default.createDirectory(at: Path.configurationFile.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: Path.configurationFile.url)
    }
}

extension XcodeManager {
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
                        let versionString = download.name.replacingOccurrences(of: "Xcode ", with: "").split(separator: " ").map(String.init).first,
                        let version = Version(tolerant: versionString)
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
            let versionString = try document.select("h2:containsOwn(Xcode)").first()?.text(),
            let version = Version(xcodeVersion: versionString),
            let path = try document.select(".direct-download[href*=xip]").first()?.attr("href"),
            let url = URL(string: "https://developer.apple.com" + path)
        else { return [] }

        let filename = String(path.suffix(fromLast: "/"))

        return [Xcode(version: version, url: url, filename: filename)]
    }
}

extension URLSession {
    public func downloadTask(_: PMKNamespacer, with convertible: URLRequestConvertible, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, promise: Promise<(saveLocation: URL, response: URLResponse)>) {
        var progress: Progress!

        let promise = Promise<(saveLocation: URL, response: URLResponse)> { seal in
            let completionHandler = { (temporaryURL: URL?, response: URLResponse?, error: Error?) in
                if let error = error {
                    seal.reject(error)
                } else if let response = response, let temporaryURL = temporaryURL {
                    do {
                        try FileManager.default.moveItem(at: temporaryURL, to: saveLocation)
                        seal.fulfill((saveLocation, response))
                    } catch {
                        seal.reject(error)
                    }
                } else {
                    seal.reject(PMKError.invalidCallingConvention)
                }
            }
            
            let task: URLSessionDownloadTask
            if let resumeData = resumeData {
                task = downloadTask(withResumeData: resumeData, completionHandler: completionHandler)
            }
            else {
                task = downloadTask(with: convertible.pmkRequest, completionHandler: completionHandler)
            }
            progress = task.progress
            task.resume()
        }

        return (progress, promise)
    }
}
