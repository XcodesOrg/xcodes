import Foundation
@preconcurrency import Path
@preconcurrency import KeychainAccess
import XcodesKit
import XcodesLoginKit
import os

/**
 Lightweight dependency injection using global mutable state :P

 - SeeAlso: https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
 - SeeAlso: https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
 - SeeAlso: https://vimeo.com/291588126
 */
public struct Environment: Sendable {
    public var shell = Shell()
    public var files = Files()
    public var network = Network()
    public var logging = Logging()
    public var keychain = Keychain()

    public init() {
        self.shell = Shell()
        self.files = Files()
        self.network = Network()
        self.logging = Logging()
        self.keychain = Keychain()
    }

    public init(shell: Shell, files: Files, network: Network, logging: Logging, keychain: Keychain) {
        self.shell = shell
        self.files = files
        self.network = network
        self.logging = logging
        self.keychain = keychain
    }
}

private let currentEnvironment = CurrentEnvironmentStorage(Environment())

public var Current: Environment {
    get { currentEnvironment.value }
    set { currentEnvironment.value = newValue }
}

private final class CurrentEnvironmentStorage: Sendable {
    private let environment: OSAllocatedUnfairLock<Environment>

    var value: Environment {
        get {
            environment.withLock { $0 }
        }
        set {
            environment.withLock { $0 = newValue }
        }
    }

    init(_ environment: Environment) {
        self.environment = OSAllocatedUnfairLock(initialState: environment)
    }
}

public struct Shell: Sendable {
    private static let shared = XcodesShell()

    public var unxip = Shell.shared.unxip
    public var mountDmg = Shell.shared.mountDmg
    public var unmountDmg = Shell.shared.unmountDmg
    public var expandPkg = Shell.shared.expandPkg
    public var createPkg = Shell.shared.createPkg
    public var installPkg = Shell.shared.installPkg
    public var installRuntimeImage = Shell.shared.installRuntimeImage
    public var spctlAssess = Shell.shared.spctlAssess
    public var codesignVerify = Shell.shared.codesignVerify
    public var devToolsSecurityEnable: @Sendable (String?) async throws -> ProcessOutput = { try await Process.sudoAsync(password: $0, Path.root.usr.sbin.DevToolsSecurity, "-enable") }
    public var addStaffToDevelopersGroup: @Sendable (String?) async throws -> ProcessOutput = { try await Process.sudoAsync(password: $0, Path.root.usr.sbin.dseditgroup, "-o", "edit", "-t", "group", "-a", "staff", "_developer") }
    public var acceptXcodeLicense: @Sendable (InstalledXcode, String?) async throws -> ProcessOutput = { try await Process.sudoAsync(password: $1, $0.path.join("/Contents/Developer/usr/bin/xcodebuild"), "-license", "accept") }
    public var runFirstLaunch: @Sendable (InstalledXcode, String?) async throws -> ProcessOutput = { try await Process.sudoAsync(password: $1, $0.path.join("/Contents/Developer/usr/bin/xcodebuild"),"-runFirstLaunch") }
    public var buildVersion = Shell.shared.buildVersion
    public var xcodeBuildVersion = Shell.shared.xcodeBuildVersion
    public var archs = Shell.shared.archs
    public var getUserCacheDir = Shell.shared.getUserCacheDir
    public var touchInstallCheck = Shell.shared.touchInstallCheck
    public var installedRuntimes = Shell.shared.installedRuntimes

    public var validateSudoAuthentication: @Sendable () async throws -> ProcessOutput = { try await Process.runAsync(Path.root.usr.bin.sudo, "-nv") }
    public func authenticateSudoerIfNecessaryAsync(passwordInput: @escaping @Sendable () async throws -> String) async throws -> String? {
        do {
            _ = try await validateSudoAuthentication()
            return nil
        } catch {
            return try await passwordInput()
        }
    }

    public var xcodeSelectPrintPath = Shell.shared.xcodeSelectPrintPath

    public var xcodeSelectSwitch = Shell.shared.xcodeSelectSwitch
    public var isRoot: @Sendable () -> Bool = { NSUserName() == "root" }
    public var machineArchitecture: @Sendable () -> String? = { HostHardware.currentMachineHardwareName() }

    /// Returns the path of an executable within the directories in the PATH environment variable.
    public var findExecutable: @Sendable (_ executableName: String) -> Path? = { executableName in
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }

        for directory in path.components(separatedBy: ":") {
            if let executable = Path(directory)?.join(executableName), executable.isExecutable {
                return executable
            }
        }

        return nil
    }

    public var downloadWithAria2: @Sendable (Path, URL, Path, [HTTPCookie]) -> AsyncThrowingStream<Progress, Error> = { aria2Path, url, destination, cookies in
        Aria2DownloadService().download(
            aria2Path: aria2Path,
            url: url,
            destination: destination,
            cookies: cookies,
            unauthorizedError: { XcodeInstaller.Error.unauthorized }
        )
    }

    public var readLine: @Sendable (String) -> String? = { prompt in
        print(prompt, terminator: "")
        return Swift.readLine()
    }
    public func readLine(prompt: String) -> String? {
        readLine(prompt)
    }

    public var readLongLine: @Sendable (String) -> String? = { prompt in
        print(prompt, terminator: "")
        fflush(stdout)
        return withRawTerminalMode(echo: true) {
            var result = Data()
            var byte: UInt8 = 0
            let fd = fileno(stdin)
            while read(fd, &byte, 1) == 1 {
                if byte == 0x0A || byte == 0x0D { break }
                result.append(byte)
            }
            print("")
            return String(data: result, encoding: .utf8)
        }
    }
    public func readLongLine(prompt: String) -> String? {
        readLongLine(prompt)
    }

    public var readSecureLine: @Sendable (String, Int) -> String? = { prompt, maximumLength in
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

        return String(validatingCString: passwordData)
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

    public var env: @Sendable (String) -> String? = { key in
        ProcessInfo.processInfo.environment[key]
    }
    public func env(_ key: String) -> String? {
        env(key)
    }

    public var exit: @Sendable (Int32) -> Void = { Darwin.exit($0) }

    public var isatty: @Sendable () -> Bool = { Foundation.isatty(fileno(stdout)) != 0 }
}

private func withRawTerminalMode<T>(echo: Bool, _ body: () -> T) -> T {
    let fd = fileno(stdin)
    var original = termios()
    tcgetattr(fd, &original)

    var raw = original
    raw.c_lflag &= ~UInt(ICANON)
    if echo {
        raw.c_lflag |= UInt(ECHO)
    } else {
        raw.c_lflag &= ~UInt(ECHO)
    }
    raw.c_cc.4 = 1
    raw.c_cc.5 = 0
    tcsetattr(fd, TCSANOW, &raw)
    defer { tcsetattr(fd, TCSANOW, &original) }

    return body()
}

public struct Files: Sendable {
    private static let sharedShell = XcodesShell()

    public var fileExistsAtPath: @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    public func fileExists(atPath path: String) -> Bool {
        return fileExistsAtPath(path)
    }

    public var attributesOfItemAtPath: @Sendable (String) throws -> [FileAttributeKey: Any] = { try FileManager.default.attributesOfItem(atPath: $0) }

    public func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        return try attributesOfItemAtPath(path)
    }

    public var moveItem: @Sendable (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try moveItem(srcURL, dstURL)
    }

    public var contentsAtPath: @Sendable (String) -> Data? = { FileManager.default.contents(atPath: $0) }

    public func contents(atPath path: String) -> Data? {
        return contentsAtPath(path)
    }

    public var write: @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1) }

    public func write(_ data: Data, to url: URL) throws {
        try write(data, url)
    }

    public var removeItem: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }

    public func removeItem(at URL: URL) throws {
        try removeItem(URL)
    }

    public var trashItem: @Sendable (URL) throws -> URL = { try FileManager.default.xcodesTrashItem(at: $0) }

    @discardableResult
    public func trashItem(at URL: URL) throws -> URL {
        return try trashItem(URL)
    }

    public var createFile: @Sendable (String, Data?, [FileAttributeKey: Any]?) -> Bool = { FileManager.default.createFile(atPath: $0, contents: $1, attributes: $2) }

    @discardableResult
    public func createFile(atPath path: String, contents data: Data?, attributes attr: [FileAttributeKey : Any]? = nil) -> Bool {
        return createFile(path, data, attr)
    }

    public var createDirectory: @Sendable (URL, Bool, [FileAttributeKey : Any]?) throws -> Void = { url, createIntermediates, attributes in
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
    public func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]? = nil) throws {
        try createDirectory(url, createIntermediates, attributes)
    }

    public var contentsOfDirectory: @Sendable (URL) throws -> [URL] = { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil, options: []) }

    public var installedXcodes: @Sendable (Path) -> [InstalledXcode] = { directory in
        InstalledXcodeDiscoveryService(
            listDirectory: { $0.ls() },
            contentsAtPath: { path in FileManager.default.contents(atPath: path) },
            loadArchitectures: Files.sharedShell.archs
        ).installedXcodes(in: directory)
    }
}

public struct Network: Sendable {
    public private(set) var loginClient: XcodesLoginKit.Client

    public var session: URLSession {
        get { loginClient.urlSession }
        set {
            let loginClient = XcodesLoginKit.Client(urlSession: newValue)
            self.loginClient = loginClient
            loadData = { try await loginClient.urlSession.data(for: $0) }
            downloadTask = { loginClient.urlSession.downloadTask(with: $0, to: $1, resumingWith: $2) }
            validateSession = { _ = try await loginClient.validateSession() }
            login = { accountName, password in
                _ = try await loginClient.srpLogin(accountName: accountName, password: password)
            }
            checkIsFederated = { accountName in
                try await loginClient.checkIsFederated(accountName: accountName)
            }
            validateFederatedCallbackURL = { callbackURLString in
                _ = try await loginClient.validateFederatedCallbackURLString(callbackURLString)
            }
            signoutAction = { loginClient.signout() }
        }
    }

    public var loadData: @Sendable (URLRequest) async throws -> (data: Data, response: URLResponse)

    public func data(for request: URLRequest) async throws -> (data: Data, response: URLResponse) {
        try await loadData(request)
    }

    public var downloadTask: @Sendable (URLRequest, URL, Data?) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>)

    public func downloadTask(with request: URLRequest, to saveLocation: URL, resumingWith resumeData: Data?) -> (progress: Progress, task: Task<(saveLocation: URL, response: URLResponse), Error>) {
        return downloadTask(request, saveLocation, resumeData)
    }

    public var validateSession: @Sendable () async throws -> Void

    public func validateSessionAsync() async throws {
        try await validateSession()
    }

    public var login: @Sendable (String, String) async throws -> Void

    public func loginAsync(accountName: String, password: String) async throws {
        try await login(accountName, password)
    }

    public var checkIsFederated: @Sendable (String) async throws -> FederationResponse

    public func checkIsFederatedAsync(accountName: String) async throws -> FederationResponse {
        try await checkIsFederated(accountName)
    }

    public var validateFederatedCallbackURL: @Sendable (String) async throws -> Void

    public func validateFederatedCallbackURLAsync(_ callbackURLString: String) async throws {
        try await validateFederatedCallbackURL(callbackURLString)
    }

    public var signoutAction: @Sendable () -> Void

    public func signout() async {
        signoutAction()
    }

    public init(
        session: URLSession? = nil,
        loadData: (@Sendable (URLRequest) async throws -> (data: Data, response: URLResponse))? = nil,
        downloadTask: (@Sendable (URLRequest, URL, Data?) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>))? = nil,
        validateSession: (@Sendable () async throws -> Void)? = nil,
        login: (@Sendable (String, String) async throws -> Void)? = nil,
        checkIsFederated: (@Sendable (String) async throws -> FederationResponse)? = nil,
        validateFederatedCallbackURL: (@Sendable (String) async throws -> Void)? = nil,
        signoutAction: (@Sendable () -> Void)? = nil
    ) {
        let loginClient: XcodesLoginKit.Client
        if let session {
            loginClient = XcodesLoginKit.Client(urlSession: session)
        } else {
            loginClient = XcodesLoginKit.Client()
        }
        self.loginClient = loginClient
        self.loadData = loadData ?? { try await loginClient.urlSession.data(for: $0) }
        self.downloadTask = downloadTask ?? { loginClient.urlSession.downloadTask(with: $0, to: $1, resumingWith: $2) }
        self.validateSession = validateSession ?? { _ = try await loginClient.validateSession() }
        self.login = login ?? { accountName, password in
            _ = try await loginClient.srpLogin(accountName: accountName, password: password)
        }
        self.checkIsFederated = checkIsFederated ?? { accountName in
            try await loginClient.checkIsFederated(accountName: accountName)
        }
        self.validateFederatedCallbackURL = validateFederatedCallbackURL ?? { callbackURLString in
            _ = try await loginClient.validateFederatedCallbackURLString(callbackURLString)
        }
        self.signoutAction = signoutAction ?? { loginClient.signout() }
    }
}

public struct Logging: Sendable {
    public var log: @Sendable (String) -> Void = { print($0) }
}

public struct Keychain: Sendable {
    private static let keychain = KeychainAccess.Keychain(service: "com.robotsandpencils.xcodes")

    public var getString: @Sendable (String) throws -> String? = { try keychain.getString($0) }
    public func getString(_ key: String) throws -> String? {
        try getString(key)
    }

    public var set: @Sendable (String, String) throws -> Void = { try keychain.set($0, key: $1) }
    public func set(_ value: String, key: String) throws {
        try set(value, key)
    }

    public var remove: @Sendable (String) throws -> Void = { try keychain.remove($0) }
    public func remove(_ key: String) throws -> Void {
        try remove(key)
    }
}
