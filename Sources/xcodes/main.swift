import Foundation
import Guaka
import Version
import PromiseKit
import XcodesKit

let manager = XcodeManager()

enum Error: Swift.Error {
    case missingUsernameOrPassword
    case missingSudoerPassword
    case invalidVersion(String)
}

func loginIfNeeded() -> Promise<Void> {
    return firstly { () -> Promise<Void> in
        return manager.client.validateSession()
    }
    .recover { error -> Promise<Void> in
        guard
            let username = env("XCODES_USERNAME") ?? readLine(prompt: "Apple ID: "),
            let password = readSecureLine(prompt: "Apple ID Password: ")
        else { throw Error.missingUsernameOrPassword }

        return manager.client.login(accountName: username, password: password)
    }
}

func printAvailableXcodes(_ xcodes: [Xcode], installed: [InstalledXcode]) {
    xcodes
        .sorted { $0.version < $1.version }
        .forEach { xcode in
            if installed.contains(where: { $0.bundleVersion == xcode.version }) {
                print("\(xcode.version) (Installed)")
            }
            else {
                print(xcode.version)
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
        print(String(describing: error))
        exit(1)
    }
}

let installed = Command(usage: "installed") { _, _ in
    manager
        .installedXcodes
        .map { $0.bundleVersion }
        .sorted()
        .forEach { print($0) }
    exit(0)
}

let list = Command(usage: "list") { _, _ in
    if manager.shouldUpdate {
        updateAndPrint()
    }
    else {
        printAvailableXcodes(manager.availableXcodes, installed: manager.installedXcodes)
        exit(0)
    }
}

let update = Command(usage: "update") { _, _ in
    updateAndPrint()
}

func downloadXcode(_ xcode: Xcode) -> Promise<(Xcode, URL)> {
    return firstly { () -> Promise<Xcode> in
        loginIfNeeded().map { xcode }
    }
    .then { xcode -> Promise<(Xcode, URL)> in
        let (progress, promise) = manager.downloadXcode(xcode)

        // Move to the next line
        print("")
        let formatter = NumberFormatter(numberStyle: .percent)
        let observation = progress.observe(\.fractionCompleted) { progress, _ in
            // These escape codes move up a line and then clear to the end
            print("\u{1B}[1A\u{1B}[K" + "Downloading Xcode \(xcode.version): " + formatter.string(from: progress.fractionCompleted)!)
        }

        return promise
            .get { _ in observation.invalidate() }
            .map { return (xcode, $0) }
    }
}

let urlFlag = Flag(longName: "url", type: String.self, description: "Local path or HTTP(S) URL (currently unsupported) of Xcode .dmg or .xip.")
let install = Command(usage: "install <version>", flags: [urlFlag]) { flags, args in
    firstly { () -> Promise<(Xcode, URL)> in
        guard 
            let versionString = args.first,
            let version = Version(tolerant: versionString),
            let xcode = manager.availableXcodes.first(where: { $0.version == version })
        else { 
            throw Error.invalidVersion(args.first ?? "")
        }

        if let urlString = flags.getString(name: "url") {
            let url = URL(fileURLWithPath: urlString, relativeTo: nil)
            return Promise.value((xcode, url))
        }
        else {
            return downloadXcode(xcode)
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
        print(String(describing: error))
        exit(1)
    }
}

let app = Command(usage: "xcodes")
app.add(subCommand: installed)
app.add(subCommand: list)
app.add(subCommand: update)
app.add(subCommand: install)
app.execute()

RunLoop.current.run()
