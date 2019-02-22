import Foundation
import Path

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
}