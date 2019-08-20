import Foundation
import PromiseKit
import PMKFoundation
import Path

/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
public struct Environment {
    public var shell = Shell()
    public var files = Files()
    public var network = Network()
}

public var Current = Environment()

public struct Shell {
    public var unxip: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.xip, workingDirectory: $0.deletingLastPathComponent(), "--expand", "\($0.path)") }
    public var spctlAssess: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.sbin.spctl, "--assess", "--verbose", "--type", "execute", "\($0.path)") }
    public var codesignVerify: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.codesign, "-vv", "-d", "\($0.path)") }
    public var validateSudoAuthentication: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sudo, "-nv") }
    public var devToolsSecurityEnable: (String?) -> Promise<ProcessOutput> = { Process.sudo(password: $0, Path.root.usr.sbin.DevToolsSecurity, "-enable") }
    public var addStaffToDevelopersGroup: (String?) -> Promise<ProcessOutput> = { Process.sudo(password: $0, Path.root.usr.sbin.dseditgroup, "-o", "edit", "-t", "group", "-a", "staff", "_developer") }
    public var acceptXcodeLicense: (InstalledXcode, String?) -> Promise<ProcessOutput> = { Process.sudo(password: $1, $0.path.join("/Contents/Developer/usr/bin/xcodebuild"), "-license", "accept") }
    public var runFirstLaunch: (InstalledXcode, String?) -> Promise<ProcessOutput> = { Process.sudo(password: $1, $0.path.join("/Contents/Developer/usr/bin/xcodebuild"),"-runFirstLaunch") }
    public var buildVersion: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sw_vers, "-buildVersion") }
    public var xcodeBuildVersion: (InstalledXcode) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.libexec.PlistBuddy, "-c", "Print :ProductBuildVersion", "\($0.path.string)/Contents/version.plist") }
    public var getUserCacheDir: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.getconf, "DARWIN_USER_CACHE_DIR") }
    public var touchInstallCheck: (String, String, String) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin/"touch", "\($0)com.apple.dt.Xcode.InstallCheckCache_\($1)_\($2)") }
}

public struct Files {
    public var fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    public func fileExists(atPath path: String) -> Bool {
        return fileExistsAtPath(path)
    }

    public var moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try moveItem(srcURL, dstURL)
    }

    public var contentsAtPath: (String) -> Data? = { FileManager.default.contents(atPath: $0) }

    public func contents(atPath path: String) -> Data? {
        return contentsAtPath(path)
    }

    public var removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    public func removeItem(at URL: URL) throws {
        try removeItem(URL)
    }

    public var trashItem: (URL) throws -> URL = { try FileManager.default.trashItem(at: $0) }

    @discardableResult
    public func trashItem(at URL: URL) throws -> URL {
        return try trashItem(URL)
    }
    
    public var createFile: (String, Data?, [FileAttributeKey: Any]?) -> Bool = { FileManager.default.createFile(atPath: $0, contents: $1, attributes: $2) }
    
    @discardableResult
    public func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]? = nil) -> Bool {
        return createFile(path, data, attr)
    }
}

public struct Network {
    public var downloadTask: (URLRequestConvertible, URL, Data?) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) = { URLSession.shared.downloadTask(with: $0, to: $1, resumingWith: $2) }

    public func downloadTask(with convertible: URLRequestConvertible, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, promise: Promise<(saveLocation: URL, response: URLResponse)>) {
        return downloadTask(convertible, saveLocation, resumeData)
    }
}
