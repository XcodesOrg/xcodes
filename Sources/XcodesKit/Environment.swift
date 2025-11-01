import Foundation
import PromiseKit
import PMKFoundation
import Path
import AppleAPI
import KeychainAccess

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
    public var logging = Logging()
    public var keychain = Keychain()
    public var fastlaneCookieParser = FastlaneCookieParser()
}

public var Current = Environment()

public struct Shell {
    public var unxip: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.xip, workingDirectory: $0.deletingLastPathComponent(), "--expand", "\($0.path)") }
    public var unxipExperimental: (URL) -> Promise<ProcessOutput> = { url in
        let workingDir = url.deletingLastPathComponent()

        // 1) Try bundled unxip first
        if let bundledURL = Bundle.module.url(forResource: "unxip", withExtension: nil) {
            guard let bundledPath = Path(url: bundledURL) else {
                return Process.run(Path.root.usr.bin.xip, workingDirectory: workingDir, "--expand", "\(url.path)")
            }
            return Process.run(bundledPath, workingDirectory: workingDir, "\(url.path)")
        }
        
        Current.logging.log("Can't find unxip bundle path".black.onYellow)
        // 2) Fallback to system xip --expand
        return Process.run(Path.root.usr.bin.xip, workingDirectory: workingDir, "--expand", "\(url.path)")
    }
    public var mountDmg: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.join("hdiutil"), "attach", "-nobrowse", "-plist", $0.path) }
    public var unmountDmg: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.join("hdiutil"), "detach", $0.path) }
    public var expandPkg: (URL, URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.sbin.join("pkgutil"), "--expand", $0.path, $1.path) }
    public var createPkg: (URL, URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.sbin.join("pkgutil"), "--flatten", $0.path, $1.path) }
    public var installPkg: (URL, String) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.sbin.join("installer"), "-pkg", $0.path, "-target", $1) }
    public var installRuntimeImage: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "add", $0.path) }
    public var spctlAssess: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.sbin.spctl, "--assess", "--verbose", "--type", "execute", "\($0.path)") }
    public var codesignVerify: (URL) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.codesign, "-vv", "-d", "\($0.path)") }
    public var devToolsSecurityEnable: (String?) -> Promise<ProcessOutput> = { Process.sudo(password: $0, Path.root.usr.sbin.DevToolsSecurity, "-enable") }
    public var addStaffToDevelopersGroup: (String?) -> Promise<ProcessOutput> = { Process.sudo(password: $0, Path.root.usr.sbin.dseditgroup, "-o", "edit", "-t", "group", "-a", "staff", "_developer") }
    public var acceptXcodeLicense: (InstalledXcode, String?) -> Promise<ProcessOutput> = { Process.sudo(password: $1, $0.path.join("/Contents/Developer/usr/bin/xcodebuild"), "-license", "accept") }
    public var runFirstLaunch: (InstalledXcode, String?) -> Promise<ProcessOutput> = { Process.sudo(password: $1, $0.path.join("/Contents/Developer/usr/bin/xcodebuild"),"-runFirstLaunch") }
    public var buildVersion: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sw_vers, "-buildVersion") }
    public var xcodeBuildVersion: (InstalledXcode) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.libexec.PlistBuddy, "-c", "Print :ProductBuildVersion", "\($0.path.string)/Contents/version.plist") }
    public var getUserCacheDir: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.getconf, "DARWIN_USER_CACHE_DIR") }
    public var touchInstallCheck: (String, String, String) -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin/"touch", "\($0)com.apple.dt.Xcode.InstallCheckCache_\($1)_\($2)") }
    public var installedRuntimes: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.join("xcrun"), "simctl", "runtime", "list", "-j") }

    public var validateSudoAuthentication: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.sudo, "-nv") }
    public var authenticateSudoerIfNecessary: (@escaping () -> Promise<String>) -> Promise<String?> = { passwordInput in
        firstly { () -> Promise<String?> in
            Current.shell.validateSudoAuthentication().map { _ in return nil }
        }
        .recover { _ -> Promise<String?> in
            return passwordInput().map(Optional.init)
        }
    }
    public func authenticateSudoerIfNecessary(passwordInput: @escaping () -> Promise<String>) -> Promise<String?> {
        authenticateSudoerIfNecessary(passwordInput)
    }

    public var xcodeSelectPrintPath: () -> Promise<ProcessOutput> = { Process.run(Path.root.usr.bin.join("xcode-select"), "-p") }
    public var xcodeSelectSwitch: (String?, String) -> Promise<ProcessOutput> = { Process.sudo(password: $0, Path.root.usr.bin.join("xcode-select"), "-s", $1) }
    public func xcodeSelectSwitch(password: String?, path: String) -> Promise<ProcessOutput> {
        xcodeSelectSwitch(password, path)
    }
    public var isRoot: () -> Bool = { NSUserName() == "root" }

    /// Returns the path of an executable within the directories in the PATH environment variable.
    public var findExecutable: (_ executableName: String) -> Path? = { executableName in
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }

        for directory in path.components(separatedBy: ":") {
            if let executable = Path(directory)?.join(executableName), executable.isExecutable {
                return executable
            }
        }

        return nil
    }

    public var downloadWithAria2: (Path, URL, Path, [HTTPCookie]) -> (Progress, Promise<Void>) = { aria2Path, url, destination, cookies in
        precondition(Thread.isMainThread, "Aria must be called on the main queue")
        let process = Process()
        process.executableURL = aria2Path.url
        process.arguments = [
            "--header=Cookie: \(cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; "))",
            "--max-connection-per-server=16",
            "--split=16",
            "--summary-interval=1",
            "--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)",
            "--dir=\(destination.parent.string)",
            "--out=\(destination.basename())",
            url.absoluteString,
        ]
        let stdOutPipe = Pipe()
        process.standardOutput = stdOutPipe
        let stdErrPipe = Pipe()
        process.standardError = stdErrPipe

        var progress = Progress(totalUnitCount: 100)
        
        // We hold on to the unauthorized status
        // So that we can properly throw error from inside the promise
        var unauthorized = false

        let observer = NotificationCenter.default.addObserver(
            forName: .NSFileHandleDataAvailable,
            object: nil,
            queue: OperationQueue.main
        ) { note in
            guard
                // This should always be the case for Notification.Name.NSFileHandleDataAvailable
                let handle = note.object as? FileHandle,
                handle === stdOutPipe.fileHandleForReading || handle === stdErrPipe.fileHandleForReading
            else { return }

            defer { handle.waitForDataInBackgroundAndNotify() }

            let string = String(decoding: handle.availableData, as: UTF8.self)
            
            /// If the operation is unauthorized, the download page redirects to https://developer.apple.com/unauthorized/
            /// with 200 status. After that the html page is downloaded as a xip and subsequent unxipping fails
            if !unauthorized && string.contains("Redirecting to https://developer.apple.com/unauthorized/") {
                unauthorized = true
            }
            
            let regex = try! NSRegularExpression(pattern: #"((?<percent>\d+)%\))"#)
            let range = NSRange(location: 0, length: string.utf16.count)

            guard
                let match = regex.firstMatch(in: string, options: [], range: range),
                let matchRange = Range(match.range(withName: "percent"), in: string),
                let percentCompleted = Int64(string[matchRange])
            else { return }

            progress.completedUnitCount = percentCompleted
        }

        stdOutPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        stdErrPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()

        do {
            try process.run()
        } catch {
            return (progress, Promise(error: error))
        }

        let promise = Promise<Void> { seal in
            DispatchQueue.global(qos: .default).async {
                process.waitUntilExit()

                NotificationCenter.default.removeObserver(observer, name: .NSFileHandleDataAvailable, object: nil)

                guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                    if let aria2cError = Aria2CError(exitStatus: process.terminationStatus) {
                        return seal.reject(aria2cError)
                    } else {
                        return seal.reject(Process.PMKError.execution(process: process, standardOutput: "", standardError: ""))
                    }
                }
                guard !unauthorized else {
                    return seal.reject(XcodeInstaller.Error.unauthorized)
                }
                seal.fulfill(())
            }
        }

        return (progress, promise)
    }

    public var readLine: (String) -> String? = { prompt in
        print(prompt, terminator: "")
        return Swift.readLine()
    }
    public func readLine(prompt: String) -> String? {
        readLine(prompt)
    }

    public var readSecureLine: (String, Int) -> String? = { prompt, maximumLength in
        let buffer = UnsafeMutablePointer<Int8>.allocate(capacity: maximumLength)
        buffer.initialize(repeating: 0, count: maximumLength)
        defer {
            buffer.deinitialize(count: maximumLength)
            buffer.initialize(repeating: 0, count: maximumLength)
            buffer.deinitialize(count: maximumLength)
            buffer.deallocate()
        }

        guard let passwordData = readpassphrase(prompt, buffer, maximumLength, 0) else {
            return nil
        }

        return String(validatingUTF8: passwordData)
    }
    /**
     Like `readLine()`, but doesn't echo the user's input to the screen.

     - Parameter prompt: Prompt printed on the line preceding user input
     - Parameter maximumLength: The maximum length to read, in bytes

     - Returns: The entered password, or nil if an error occurred.

     Buffer is zeroed after use.

     - SeeAlso: [readpassphrase man page](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/readpassphrase.3.html)
     */
    public func readSecureLine(prompt: String, maximumLength: Int = 8192) -> String? {
        readSecureLine(prompt, maximumLength)
    }

    public var env: (String) -> String? = { key in
        ProcessInfo.processInfo.environment[key]
    }
    public func env(_ key: String) -> String? {
        env(key)
    }

    public var exit: (Int32) -> Void = { Darwin.exit($0) }

    public var isatty: () -> Bool = { Foundation.isatty(fileno(stdout)) != 0 }
}

public struct Files {
    public var fileExistsAtPath: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    public func fileExists(atPath path: String) -> Bool {
        return fileExistsAtPath(path)
    }

    public var attributesOfItemAtPath: (String) throws -> [FileAttributeKey: Any] = { try FileManager.default.attributesOfItem(atPath: $0) }

    public func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        return try attributesOfItemAtPath(path)
    }

    public var moveItem: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try moveItem(srcURL, dstURL)
    }

    public var contentsAtPath: (String) -> Data? = { FileManager.default.contents(atPath: $0) }

    public func contents(atPath path: String) -> Data? {
        return contentsAtPath(path)
    }

    public var write: (Data, URL) throws -> Void = { try $0.write(to: $1) }

    public func write(_ data: Data, to url: URL) throws {
        try write(data, url)
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

    public var createDirectory: (URL, Bool, [FileAttributeKey : Any]?) throws -> Void = FileManager.default.createDirectory(at:withIntermediateDirectories:attributes:)
    public func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        try createDirectory(url, createIntermediates, attributes)
    }

    public var contentsOfDirectory: (URL) throws -> [URL] = { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: []) }

    public var installedXcodes: (Path) -> [InstalledXcode] = { directory in
        return ((try? directory.ls()) ?? [])
            .filter { $0.isAppBundle && $0.infoPlist?.bundleID == "com.apple.dt.Xcode" }
            .map { $0.path }
            .compactMap(InstalledXcode.init)
    }
}

public struct Network {
    private static let client = AppleAPI.Client()

    public var dataTask: (URLRequestConvertible) -> Promise<(data: Data, response: URLResponse)> = { AppleAPI.Current.network.session.dataTask(.promise, with: $0) }
    public func dataTask(with convertible: URLRequestConvertible) -> Promise<(data: Data, response: URLResponse)> {
        dataTask(convertible)
    }

    public var downloadTask: (URLRequestConvertible, URL, Data?) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) = { AppleAPI.Current.network.session.downloadTask(with: $0, to: $1, resumingWith: $2) }

    public func downloadTask(with convertible: URLRequestConvertible, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, promise: Promise<(saveLocation: URL, response: URLResponse)>) {
        return downloadTask(convertible, saveLocation, resumeData)
    }

    public var validateSession: () -> Promise<Void> = client.validateSession

    public var login: (String, String) -> Promise<Void> = { client.srpLogin(accountName: $0, password: $1) }
    public func login(accountName: String, password: String) -> Promise<Void> {
        login(accountName, password)
    }
}

public struct Logging {
    public var log: (String) -> Void = { print($0) }
}

public struct Keychain {
    private static let keychain = KeychainAccess.Keychain(service: "com.robotsandpencils.xcodes")

    public var getString: (String) throws -> String? = keychain.getString(_:)
    public func getString(_ key: String) throws -> String? {
        try getString(key)
    }

    public var set: (String, String) throws -> Void = keychain.set(_:key:)
    public func set(_ value: String, key: String) throws {
        try set(value, key)
    }

    public var remove: (String) throws -> Void = keychain.remove(_:)
    public func remove(_ key: String) throws -> Void {
        try remove(key)
    }
}

