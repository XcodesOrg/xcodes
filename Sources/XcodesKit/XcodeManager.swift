import Foundation
import Path
import Version
import PromiseKit
import PMKFoundation
import SwiftSoup
import AppleAPI

public final class XcodeManager {
    public let client = AppleAPI.Client()
    public let installer = XcodeInstaller()

    public init() {
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
            .map { availableXcodes, prereleaseXcodes in
                let xcodes = availableXcodes + prereleaseXcodes
                self.availableXcodes = xcodes
                try? self.cacheAvailableXcodes(xcodes)
                return xcodes
            }
    }

    public func downloadXcode(_ xcode: Xcode) -> (Progress, Promise<URL>) {
        let destination = XcodeManager.applicationSupportPath/"Xcode-\(xcode.version).\(xcode.filename.suffix(fromLast: "."))"
        let (progress, promise) = client.session.downloadTask(.promise, with: xcode.url, to: destination.url)
        return (progress, promise.map { $0.saveLocation })
    }
}

extension XcodeManager {
    private static let applicationSupportPath = Path.applicationSupport/"ca.brandonevans.xcodes"
    private static let cacheFilePath = applicationSupportPath/"available-xcodes.json"

    private func loadCachedAvailableXcodes() throws {
        let data = try Data(contentsOf: XcodeManager.cacheFilePath.url)
        let xcodes = try JSONDecoder().decode([Xcode].self, from: data)
        self.availableXcodes = xcodes
    }

    private func cacheAvailableXcodes(_ xcodes: [Xcode]) throws {
        let data = try JSONEncoder().encode(xcodes)
        try FileManager.default.createDirectory(at: XcodeManager.cacheFilePath.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: XcodeManager.cacheFilePath.url)
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
        .map { (data, response) -> [Xcode] in
            let body = String(data: data, encoding: .utf8)!
            let document = try SwiftSoup.parse(body)

            guard 
                let versionString = try document.select("span.platform-title:containsOwn(Xcode)").first()?.parent()?.text(),
                let version = Version(xcodeVersion: versionString),
                let path = try document.select("button.direct-download[value*=xip]").first()?.val(),
                let url = URL(string: "https://developer.apple.com" + path)
            else { return [] }

            let filename = String(path.suffix(fromLast: "/"))

            return [Xcode(version: version, url: url, filename: filename)]
        }
    }
}

extension URLSession {
    public func downloadTask(_: PMKNamespacer, with convertible: URLRequestConvertible, to saveLocation: URL) -> (progress: Progress, promise: Promise<(saveLocation: URL, response: URLResponse)>) {
        var progress: Progress!

        let promise = Promise<(saveLocation: URL, response: URLResponse)> { seal in
            let task = downloadTask(with: convertible.pmkRequest, completionHandler: { temporaryURL, response, error in
                if let error = error {
                    dump(error)
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
            })
            progress = task.progress
            task.resume()
        }

        return (progress, promise)
    }
}
