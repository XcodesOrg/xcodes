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
    return firstly {
        manager.client.validateSession()
    }
    .recover { error -> Promise<Void> in
        print("Username: ")
        let username = readLine() ?? ""
        print("Password: ")
        let password = readLine() ?? ""

        return manager.client.login(accountName: username, password: password)
    }
    .then { () -> Promise<(data: Data, response: URLResponse)> in
        return URLSession.shared.dataTask(.promise, with: URLRequest.downloads)
    }
    .map { (data, response) -> [Download] in
        struct Downloads: Decodable {
            let downloads: [Download]
        }

        let downloads = try JSONDecoder().decode(Downloads.self, from: data)
        return downloads.downloads
    }
    .done { downloads in
        downloads
            .filter { $0.name.range(of: "^Xcode [0-9]", options: .regularExpression) != nil }
            .compactMap { Xcode(name: $0.name) }
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
