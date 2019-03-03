import Foundation
import PromiseKit
import Path

/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
struct Environment {
    var shell = Shell()
    var files = Files()
}

var Current = Environment()

struct Shell {
    var spctlAssess: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.sbin.spctl, "--assess", "--verbose", "--type", "execute", "\"\($0.path)\"") }
    var codesignVerify: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.codesign, "-vv", "-d", "\"\($0.path)\"") }
    var unxip: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.xip, workingDirectory: $0.deletingLastPathComponent(), "--expand", "\"\($0.path)\"") }
    var devToolsSecurityEnable: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sudo, "/usr/sbin/DevToolsSecurity", "-enable") }
    var addStaffToDevelopersGroup: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sudo, "/usr/sbin/dseditgroup", "-o", "edit", "-t", "group", "-a", "staff", "_developer") }
    var acceptXcodeLicense: (InstalledXcode) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sudo, $0.path.join("/Contents/Developer/usr/bin/xcodebuild").string, "-license", "accept") }
    var runFirstLaunch: (InstalledXcode) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sudo, $0.path.join("/Contents/Developer/usr/bin/xcodebuild").string, "-runFirstLaunch") }
    var buildVersion: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sw_vers, "-buildVersion") }
    var xcodeBuildVersion: (InstalledXcode) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.libexec.PlistBuddy, "-c", "\"Print :ProductBuildVersion\"", "\"\($0.path.string)/Contents/version.plist\"") }
    var getUserCacheDir: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.getconf, "DARWIN_USER_CACHE_DIR") }
    var touchInstallCheck: (String, String, String) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin/"touch", "\($0)com.apple.dt.Xcode.InstallCheckCache_\($1)_\($2)") }
}

struct Files {
    var fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    func fileExists(atPath path: String) -> Bool {
        return fileExistsAtPath(path)
    }

    var moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try moveItem(srcURL, dstURL)
    }
}