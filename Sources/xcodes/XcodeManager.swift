import Foundation
import Path
import PromiseKit

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
                .compactMap { Xcode(name: $0.name) }

            self.availableXcodes = xcodes
            try? self.cacheAvailableXcodes(xcodes)
            return xcodes
        }
    }
}

extension XcodeManager {
    private static let cacheFilePath = Path.applicationSupport/"ca.brandonevans.xcodes"/"available-xcodes.json"

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