import Foundation
import Path
import Version
import PromiseKit
import PMKFoundation

class XcodeManager {
    let client = Client()

    init() {
        try? loadCachedAvailableXcodes()
    }

    var installedXcodes: [InstalledXcode] {
        let results = try! Path.root.join("Applications").ls().filter { entry in
            guard entry.kind == .directory && entry.path.extension == "app" && !entry.path.isSymlink else { return false }
            let infoPlistPath = entry.path.join("Contents").join("Info.plist")
            let infoPlist = try! PropertyListDecoder().decode(InfoPlist.self, from: try! Data(contentsOf: infoPlistPath.url))
            return infoPlist.bundleID == "com.apple.dt.Xcode"
        }
        let installedXcodes = results.map { $0.path }.map(InstalledXcode.init)
        return installedXcodes
    }

    private(set) var availableXcodes: [Xcode] = []

    var shouldUpdate: Bool {
        return availableXcodes.isEmpty
    }

    func update() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            URLSession.shared.dataTask(.promise, with: URLRequest.downloads)
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
                        let url = URL(string: urlPrefix + xcodeFile.remotePath)
                    else { return nil }

                    return Xcode(name: download.name, url: url, filename: String(xcodeFile.remotePath.suffix(fromLast: "/")))
                }

            self.availableXcodes = xcodes
            try? self.cacheAvailableXcodes(xcodes)
            return xcodes
        }
    }

    func downloadVersion(_ version: Version) -> (Progress, Promise<Void>) {
        guard let xcode = availableXcodes.first(where: { $0.version == version }) else { exit(1) }
        return downloadXcode(xcode)
    }

    func downloadXcode(_ xcode: Xcode) -> (Progress, Promise<Void>) {
        let destination = XcodeManager.applicationSupportPath/"Xcode-\(xcode.version).\(xcode.filename.suffix(fromLast: ".")))"
        let (progress, promise) = URLSession.shared.downloadTask(.promise, with: xcode.url, to: destination.url)
        return (progress, promise.asVoid())
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

extension URLSession {
    public func downloadTask(_: PMKNamespacer, with convertible: URLRequestConvertible, to saveLocation: URL) -> (progress: Progress, promise: Promise<(saveLocation: URL, response: URLResponse)>) {
        var progress: Progress!

        let promise = Promise<(saveLocation: URL, response: URLResponse)> { seal in
            let task = URLSession.shared.downloadTask(with: convertible.pmkRequest, completionHandler: { temporaryURL, response, error in
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