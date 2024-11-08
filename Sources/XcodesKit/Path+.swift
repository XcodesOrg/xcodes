import Path
import Foundation

extension Path {
    // Get Home even if we are running as root
    static let environmentHome = ProcessInfo.processInfo.environment["HOME"].flatMap(Path.init) ?? Path(Path.home)
    static let environmentApplicationSupport = environmentHome/"Library/Application Support"
    static let environmentCaches = environmentHome/"Library/Caches"
    public static let environmentDownloads = environmentHome/"Downloads"

    static let oldXcodesApplicationSupport = environmentApplicationSupport/"ca.brandonevans.xcodes"
    static let xcodesApplicationSupport = environmentApplicationSupport/"com.robotsandpencils.xcodes"
    static let xcodesCaches = environmentCaches/"com.robotsandpencils.xcodes"
    static let cacheFile = xcodesApplicationSupport/"available-xcodes.json"
    static let configurationFile = xcodesApplicationSupport/"configuration.json"

    @discardableResult
    func setCurrentUserAsOwner() -> Path {
        let user = ProcessInfo.processInfo.environment["SUDO_USER"] ?? NSUserName()
        try? FileManager.default.setAttributes([.ownerAccountName: user], ofItemAtPath: string)
        return self
    }
}
