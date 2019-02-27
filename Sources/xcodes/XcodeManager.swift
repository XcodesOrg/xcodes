import Foundation
import Path
import PromiseKit

class XcodeManager {
    let client = Client()

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

    func update() -> Promise<[Xcode]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            URLSession.shared.dataTask(.promise, with: URLRequest.downloads)
        }
        .map { (data, response) -> [Xcode] in
            struct Downloads: Decodable {
                let downloads: [Download]
            }

            let downloads = try JSONDecoder().decode(Downloads.self, from: data)
            return downloads
                .downloads
                .filter { $0.name.range(of: "^Xcode [0-9]", options: .regularExpression) != nil }
                .compactMap { Xcode(name: $0.name) }
        }
    }
}