import Foundation
import Path

extension Path {
    var isAppBundle: Bool {
        type == .directory &&
        `extension` == "app" &&
        !isSymlink
    }

    var infoPlist: InfoPlist? {
        let infoPlistPath = join("Contents").join("Info.plist")
        guard
            let infoPlistData = try? Data(contentsOf: infoPlistPath.url),
            let infoPlist = try? PropertyListDecoder().decode(InfoPlist.self, from: infoPlistData)
        else { return nil }

        return infoPlist
    }
}
