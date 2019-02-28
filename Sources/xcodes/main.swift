import Foundation
import Guaka
import Version
import PromiseKit
import XcodesKit

let manager = XcodeManager()

enum Error: Swift.Error {
    case invalidVersion(String)
}

func loginIfNeeded() -> Promise<Void> {
    return firstly { () -> Promise<Void> in
        return manager.client.validateSession()
    }
    .recover { error -> Promise<Void> in
        print("Username: ", terminator: "")
        let username = readLine() ?? ""
        let password = readSecureLine(prompt: "Password: ") ?? ""

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

let install = Command(usage: "install <version>") { _, args in
    firstly { () -> Promise<Xcode> in
        guard 
            let versionString = args.first,
            let version = Version(tolerant: versionString),
            let xcode = manager.availableXcodes.first(where: { $0.version == version })
        else { 
            throw Error.invalidVersion(args.first ?? "")
        }

        return loginIfNeeded().map { xcode }
    }
    .then { xcode -> Promise<(Xcode, URL)> in
        let (progress, promise) = manager.downloadXcode(xcode)

        let formatter = NumberFormatter(numberStyle: .percent)
        let observation = progress.observe(\.fractionCompleted) { progress, _ in
            print("Downloaded " + formatter.string(from: progress.fractionCompleted)!)
        }

        return promise
            .get { _ in observation.invalidate() }
            .map { return (xcode, $0) }
    }
    .then { xcode, url -> Promise<Void> in
        return manager.installer.installArchivedXcode(xcode, at: url)
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
