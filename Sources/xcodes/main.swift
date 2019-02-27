import Foundation
import Guaka
import Path
import Version
import PromiseKit
import PMKFoundation

let manager = XcodeManager()

let installed = Command(usage: "installed") { _, _ in
    manager.installedXcodes.map { $0.bundleVersion }.forEach { print($0) }
    exit(0)
}

let list = Command(usage: "list") { _, _ in
    firstly { () -> Promise<Void> in
        return manager.client.validateSession()
    }
    .recover { error -> Promise<Void> in
        print("Username: ", terminator: "")
        let username = readLine() ?? ""
        let password = readSecureLine(prompt: "Password: ") ?? ""

        return manager.client.login(accountName: username, password: password)
    }
    .then { () -> Promise<[Xcode]> in
        return manager.update()
    }
    .done { xcodes in
        xcodes
            .sorted { $0.version < $1.version }
            .forEach { xcode in
                if manager.installedXcodes.contains(where: { $0.bundleVersion == xcode.version }) {
                    print("\(xcode.version) (Installed)")
                }
                else {
                    print(xcode.version)
                }
            }

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
app.execute()

RunLoop.current.run()
