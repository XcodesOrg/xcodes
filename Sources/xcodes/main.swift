import Foundation
import Guaka
import Version
import PromiseKit
import XcodesKit
import LegibleError
import Path

var configuration = Configuration()
try? configuration.load()
let xcodeList = XcodeList()
let installer = XcodeInstaller(configuration: configuration, xcodeList: xcodeList)

migrateApplicationSupportFiles()

// This is awkward, but Guaka wants a root command in order to add subcommands,
// but then seems to want it to behave like a normal command even though it'll only ever print the help.
// But it doesn't even print the help without the user providing the --help flag,
// so we need to tell it to do this explicitly
var app: Command!
app = Command(usage: "xcodes") { _, _ in print(GuakaConfig.helpGenerator.init(command: app).helpMessage) }

let installed = Command(usage: "installed",
                        shortMessage: "List the versions of Xcode that are installed") { _, _ in
    Current.files.installedXcodes()
        .map { $0.version }
        .sorted()
        .forEach { print($0) }
}
app.add(subCommand: installed)

let printFlag = Flag(shortName: "p", longName: "print-path", value: false, description: "Print the path of the selected Xcode")
let select = Command(usage: "select",
                     shortMessage: "Change the selected Xcode",
                     longMessage: "Change the selected Xcode. Run without any arguments to interactively select from a list, or provide an absolute path.",
                     flags: [printFlag],
                     example: """
                              xcodes select
                              xcodes select /Applications/Xcode-11.4.0.app
                              xcodes select -p
                              """) { flags, args in

    selectXcode(shouldPrint: flags.getBool(name: "print-path") ?? false, path: args.first)
        .catch { error in
            print(error.legibleLocalizedDescription)
            exit(1)
        }

    RunLoop.current.run()
}
app.add(subCommand: select)

let list = Command(usage: "list",
                   shortMessage: "List all versions of Xcode that are available to install") { _, _ in
    firstly { () -> Promise<Void> in
        if xcodeList.shouldUpdate {
            return installer.updateAndPrint()
        }
        else {
            return installer.printAvailableXcodes(xcodeList.availableXcodes, installed: Current.files.installedXcodes())
        }
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
app.add(subCommand: list)

let update = Command(usage: "update",
                     shortMessage: "Update the list of available versions of Xcode") { _, _ in
    firstly {
        installer.updateAndPrint()
    }
    .catch { error in
        print(error.legibleLocalizedDescription)
        exit(1)
    }

    RunLoop.current.run()
}
app.add(subCommand: update)

let urlFlag = Flag(longName: "url", type: String.self, description: "Local path to Xcode .xip")
let install = Command(usage: "install <version>",
                      shortMessage: "Download and install a specific version of Xcode",
                      flags: [urlFlag],
                      example: """
                               xcodes install 10.2.1
                               xcodes install 11 Beta 7
                               xcodes install 11.2 GM seed
                               xcodes install 9.0 --url ~/Archive/Xcode_9.xip
                               """) { flags, args in
        let versionString = args.joined(separator: " ")
    installer.install(versionString, flags.getString(name: "url"))
        .catch { error in
            switch error {
            case Process.PMKError.execution(let process, let standardOutput, let standardError):
                Current.logging.log("""
                    Failed executing: `\(process)` (\(process.terminationStatus))
                    \([standardOutput, standardError].compactMap { $0 }.joined(separator: "\n"))
                    """)
            default:
                Current.logging.log(error.legibleLocalizedDescription)
            }

            exit(1)
        }

    RunLoop.current.run()
}
app.add(subCommand: install)

let uninstall = Command(usage: "uninstall <version>",
                        shortMessage: "Uninstall a specific version of Xcode",
                        example: "xcodes uninstall 10.2.1") { _, args in
        let versionString = args.joined(separator: " ")
    installer.uninstallXcode(versionString)
        .catch { error in
            print(error.legibleLocalizedDescription)
            exit(1)
        }

    RunLoop.current.run()
}
app.add(subCommand: uninstall)

let version = Command(usage: "version",
                      shortMessage: "Print the version number of xcodes itself") { _, _ in
    print(XcodesKit.version)
    exit(0)
}
app.add(subCommand: version)

app.execute()
