import Path
import Foundation
import XcodesKit

extension Path {
    // Get Home even if we are running as root
    static let environmentHome = XcodesPathResolver.cliHome()
    static let environmentApplicationSupport = environmentHome/"Library/Application Support"
    static let environmentCaches = environmentHome/"Library/Caches"
    public static let environmentDownloads = XcodesPathResolver.cliDownloads(home: environmentHome)

    static let oldXcodesApplicationSupport = XcodesPathResolver.cliOldApplicationSupport(home: environmentHome)
    static let xcodesApplicationSupport = XcodesPathResolver.cliApplicationSupport(home: environmentHome)
    static let xcodesCaches = XcodesPathResolver.cliCaches(home: environmentHome)
    static let cacheFile = XcodesPathResolver.cliAvailableXcodesCacheFile(applicationSupport: xcodesApplicationSupport)
    static let runtimeCacheFile = XcodesPathResolver.downloadableRuntimesCacheFile(in: xcodesApplicationSupport)
    static let configurationFile = XcodesPathResolver.cliConfigurationFile(applicationSupport: xcodesApplicationSupport)
}
