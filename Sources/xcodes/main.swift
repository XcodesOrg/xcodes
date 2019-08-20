import Foundation
import Guaka
import Version
import PromiseKit
import XcodesKit
import LegibleError
import Path
import KeychainAccess
import AppleAPI

let client = AppleAPI.Client()
let installer = XcodeInstaller(client: client)
let xcodeList = XcodeList(client: client)
let keychain = Keychain(service: "com.robotsandpencils.xcodes")
var configuration = Configuration()
try? configuration.load()

let xcodesUsername = "XCODES_USERNAME"
let xcodesPassword = "XCODES_PASSWORD"

enum XcodesError: Swift.Error, LocalizedError {
    case missingUsernameOrPassword
    case missingSudoerPassword
    case invalidVersion(String)
    case unavailableVersion(Version)

    var errorDescription: String? {
        switch self {
        case .missingUsernameOrPassword:
            return "Missing username or a password. Please try again."
        case .missingSudoerPassword:
            return "Missing password. Please try again."
        case let .invalidVersion(version):
            return "\(version) is not a valid version number."
        case let .unavailableVersion(version):
            return "Could not find version \(version.xcodeDescription)."
        }
    }
}

func loginIfNeeded(withUsername existingUsername: String? = nil) -> Promise<Void> {
    return firstly { () -> Promise<Void> in
        return client.validateSession()
    }
    .recover { error -> Promise<Void> in
        guard
            let username = existingUsername ?? findUsername() ?? readLine(prompt: "Apple ID: "),
            let password = findPassword(withUsername: username) ?? readSecureLine(prompt: "Apple ID Password: ")
        else { throw XcodesError.missingUsernameOrPassword }

        return firstly { () -> Promise<Void> in
            login(username, password: password)
        }
        .recover { error -> Promise<Void> in
            print(error.legibleLocalizedDescription)

            if case Client.Error.invalidUsernameOrPassword = error {
                print("Try entering your password again")
                return loginIfNeeded(withUsername: username)
            }
            else {
                return Promise(error: error)
            }
        }
    }
}

func findUsername() -> String? {
    if let username = env(xcodesUsername) {
        return username
    }
    else if let username = configuration.defaultUsername {
        return username
    }
    return nil
}

func findPassword(withUsername username: String) -> String? {
    if let password = env(xcodesPassword) {
        return password
    }
    else if let password = try? keychain.getString(username){
        return password
    }
    return nil
}

func login(_ username: String, password: String) -> Promise<Void> {
    return firstly { () -> Promise<Void> in
        client.login(accountName: username, password: password)
    }
    .recover { error -> Promise<Void> in

        if let error = error as? Client.Error {
          switch error  {
          case .invalidUsernameOrPassword(_):
              // remove any keychain password if we fail to log with an invalid username or password so it doesn't try again.
              keychain[username] = nil
          default:
              break
          }
        }

        return Promise(error: error)
    }
    .done { _ in
        keychain[username] = password

        if configuration.defaultUsername != username {
            configuration.defaultUsername = username
            try? configuration.save()
        }
    }
}

func printAvailableXcodes(_ xcodes: [Xcode], installed: [InstalledXcode]) {
    var allXcodeVersions = xcodes.map { $0.version }
    for xcode in installed where !allXcodeVersions.contains(where: { $0.isEquivalentForDeterminingIfInstalled(to: xcode.version) }) {
        allXcodeVersions.append(xcode.version)
    }

    allXcodeVersions
        .sorted { $0 < $1 }
        .forEach { xcodeVersion in
            if installed.contains(where: { $0.version.isEquivalentForDeterminingIfInstalled(to: xcodeVersion) }) {
                print("\(xcodeVersion.xcodeDescription) (Installed)")
            }
            else {
                print(xcodeVersion.xcodeDescription)
            }
        }
}

func updateAndPrint() {
    firstly { () -> Promise<Void> in
        loginIfNeeded()
    }
    .then { () -> Promise<[Xcode]> in
        xcodeList.update()
    }
    .done { xcodes in
        printAvailableXcodes(xcodes, installed: xcodeList.installedXcodes)
        exit(0)
    }
    .catch { error in
        print(error.legibleLocalizedDescription)
        exit(1)
    }

    RunLoop.current.run()
}

let installed = Command(usage: "installed") { _, _ in
    xcodeList
        .installedXcodes
        .map { $0.version }
        .sorted()
        .forEach { print($0) }
}

let list = Command(usage: "list") { _, _ in
    if xcodeList.shouldUpdate {
        updateAndPrint()
    }
    else {
        printAvailableXcodes(xcodeList.availableXcodes, installed: xcodeList.installedXcodes)
    }
}

let update = Command(usage: "update") { _, _ in
    updateAndPrint()
}

func downloadXcode(version: Version) -> Promise<(Xcode, URL)> {
    return firstly { () -> Promise<Version> in
        loginIfNeeded().map { version }
    }
    .then { version -> Promise<Version> in
        if xcodeList.shouldUpdate {
            return xcodeList.update().map { _ in version }
        }
        else {
            return Promise.value(version)
        }
    }
    .then { version -> Promise<(Xcode, URL)> in
        guard let xcode = xcodeList.availableXcodes.first(where: { version.isEqualWithoutBuildMetadataIdentifiers(to: $0.version) }) else {
            throw XcodesError.unavailableVersion(version)
        }

        // Move to the next line
        print("")
        let formatter = NumberFormatter(numberStyle: .percent)
        var observation: NSKeyValueObservation?

        let promise = installer.downloadOrUseExistingArchive(for: xcode, progressChanged: { progress in
            observation?.invalidate()
            observation = progress.observe(\.fractionCompleted) { progress, _ in
                // These escape codes move up a line and then clear to the end
                print("\u{1B}[1A\u{1B}[K" + "Downloading Xcode \(xcode.version): " + formatter.string(from: progress.fractionCompleted)!)
            }
        })

        return promise
            .get { _ in observation?.invalidate() }
            .map { return (xcode, $0) }
    }
}

func versionFromXcodeVersionFile() -> Version? {
    let xcodeVersionFilePath = Path.cwd.join(".xcode-version")
    let version = (try? Data(contentsOf: xcodeVersionFilePath.url))
        .flatMap { String(data: $0, encoding: .utf8) }
        .flatMap(Version.init(gemVersion:))
    return version
}

let urlFlag = Flag(longName: "url", type: String.self, description: "Local path or HTTP(S) URL (currently unsupported) of Xcode .dmg or .xip.")
let install = Command(usage: "install <version>", flags: [urlFlag]) { flags, args in
    firstly { () -> Promise<(Xcode, URL)> in
        let versionString = args.joined(separator: " ")
        guard let version = Version(xcodeVersion: versionString) ?? versionFromXcodeVersionFile() else {
            throw XcodesError.invalidVersion(versionString)
        }

        if let urlString = flags.getString(name: "url") {
            let url = URL(fileURLWithPath: urlString, relativeTo: nil)
            let xcode = Xcode(version: version, url: url, filename: String(url.path.suffix(fromLast: "/")))
            return Promise.value((xcode, url))
        }
        else {
            return downloadXcode(version: version)
        }
    }
    .then { xcode, url -> Promise<Void> in
        return installer.installArchivedXcode(xcode, at: url, archiveTrashed: { archiveURL in
            print("Xcode archive \(url.lastPathComponent) has been moved to the Trash.")
        }, passwordInput: { () -> Promise<String> in
            return Promise { seal in
                print("xcodes requires superuser privileges in order to setup some parts of Xcode.")
                guard let password = readSecureLine(prompt: "Password: ") else { seal.reject(XcodesError.missingSudoerPassword); return }
                seal.fulfill(password + "\n")
            }
        })
    }
    .done {
        exit(0)
    }
    .catch { error in
        switch error {
        case XcodeInstaller.Error.failedSecurityAssessment(let xcode, let output):
            print("""
                  Xcode \(xcode.version) failed its security assessment with the following output:
                  \(output)
                  It remains installed at \(xcode.path) if you wish to use it anyways.
                  """)
        default:
            print(error.legibleLocalizedDescription)
        }

        exit(1)
    }

    RunLoop.current.run()
}

let version = Command(usage: "version") { _, _ in
    print(XcodesKit.version)
    exit(0)
}

XcodeList.migrateApplicationSupportFiles()

// This is awkward, but Guaka wants a root command in order to add subcommands,
// but then seems to want it to behave like a normal command even though it'll only ever print the help.
// But it doesn't even print the help without the user providing the --help flag,
// so we need to tell it to do this explicitly
var app: Command!
app = Command(usage: "xcodes") { _, _ in print(GuakaConfig.helpGenerator.init(command: app).helpMessage) }
app.add(subCommand: installed)
app.add(subCommand: list)
app.add(subCommand: update)
app.add(subCommand: install)
app.add(subCommand: version)
app.execute()
