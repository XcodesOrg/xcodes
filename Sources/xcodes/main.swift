import Foundation
import Guaka
import Version
import PromiseKit
import XcodesKit
import LegibleError
import Path
import KeychainAccess

let manager = XcodeManager()
let keychain = Keychain(service: "ca.brandonevans.xcodes")

let xcodesUsername = "XCODES_USERNAME"
let xcodesPassword = "XCODES_PASSWORD"

enum Error: Swift.Error {
    case missingUsernameOrPassword
    case missingSudoerPassword
    case invalidVersion(String)
    case unavailableVersion(Version)
}

func loginIfNeeded() -> Promise<Void> {
    return firstly { () -> Promise<Void> in
        return manager.client.validateSession()
    }
    .recover { error -> Promise<Void> in
        guard
            let username = findUsername() ?? readLine(prompt: "Apple ID: "),
            let password = findPassword() ?? readSecureLine(prompt: "Apple ID Password: ")
        else { throw Error.missingUsernameOrPassword }

        return login(username, password: password)
    }
}

func findUsername() -> String? {
    if let username = env(xcodesUsername) {
        return username
    }
    else if let username = try? keychain.getString(xcodesUsername){
        return username
    }
    return nil
}

func findPassword() -> String? {
    if let password = env(xcodesPassword) {
        return password
    }
    else if let password = try? keychain.getString(xcodesPassword){
        return password
    }
    return nil
}

func login(_ username: String, password: String) -> Promise<Void> {
    return firstly { () -> Promise<Void> in
        manager.client.login(accountName: username, password: password)
    }
    .done { _ in
        keychain[xcodesUsername] = username
        keychain[xcodesPassword] = password
    }
}

func printAvailableXcodes(_ xcodes: [Xcode], installed: [InstalledXcode]) {
    xcodes
        .sorted { $0.version < $1.version }
        .forEach { xcode in
            // Not sure of a good way to determine which pre-release version is installed
            // For now, compare versions without pre-release identifiers
            // This should match xcode-install's behaviour
            if installed.contains(where: { $0.bundleVersion.isEqualWithoutPrerelease(xcode.version) }) {
                print("\(xcode.version) (Installed)")
            }
            else {
                print(xcode.version.xcodeDescription)
            }
        }
}

func updateAndPrint() {
    firstly { () -> Promise<Void> in
        loginIfNeeded()
    }
    .then { () -> Promise<[Xcode]> in
        manager.update()
    }
    .done { xcodes in
        printAvailableXcodes(xcodes, installed: manager.installedXcodes)
        exit(0)
    }
    .catch { error in
        print(error.legibleLocalizedDescription)
        exit(1)
    }

    RunLoop.current.run()
}

let installed = Command(usage: "installed") { _, _ in
    manager
        .installedXcodes
        .map { $0.bundleVersion }
        .sorted()
        .forEach { print($0) }
}

let list = Command(usage: "list") { _, _ in
    if manager.shouldUpdate {
        updateAndPrint()
    }
    else {
        printAvailableXcodes(manager.availableXcodes, installed: manager.installedXcodes)
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
        if manager.shouldUpdate {
            return manager.update().map { _ in version }
        }
        else {
            return Promise.value(version)
        }
    }
    .then { version -> Promise<(Xcode, URL)> in
        guard let xcode = manager.availableXcodes.first(where: { $0.version == version }) else {
            throw Error.unavailableVersion(version)
        }

        // Move to the next line
        print("")
        let formatter = NumberFormatter(numberStyle: .percent)
        var observation: NSKeyValueObservation?

        let promise = manager.downloadXcode(xcode, progressChanged: { progress in
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
            throw Error.invalidVersion(versionString)
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
        return manager.installer.installArchivedXcode(xcode, at: url, passwordInput: { () -> Promise<String> in
            return Promise { seal in
                print("xcodes requires superuser privileges in order to setup some parts of Xcode.")
                guard let password = readSecureLine(prompt: "Password: ") else { seal.reject(Error.missingSudoerPassword); return }
                seal.fulfill(password + "\n")
            }
        })
    }
    .done {
        exit(0)
    }
    .catch { error in
        print(error.legibleLocalizedDescription)
        exit(1)
    }

    RunLoop.current.run()
}

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
app.execute()
