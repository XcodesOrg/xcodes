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
    installer.printInstalledXcodes()
        .done {
            exit(0)
        }
        .catch { error in
            print(error.legibleLocalizedDescription)
            exit(1)
        }

    RunLoop.current.run()
}
app.add(subCommand: installed)

let printFlag = Flag(shortName: "p", longName: "print-path", value: false, description: "Print the path of the selected Xcode")
let select = Command(usage: "select <version or path>",
                     shortMessage: "Change the selected Xcode",
                     longMessage: "Change the selected Xcode. Run without any arguments to interactively select from a list, or provide an absolute path.",
                     flags: [printFlag],
                     example: """
                              xcodes select
                              xcodes select 11.4.0
                              xcodes select /Applications/Xcode-11.4.0.app
                              xcodes select -p
                              """) { flags, args in
    selectXcode(shouldPrint: flags.getBool(name: "print-path") ?? false, pathOrVersion: args.joined(separator: " "))
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

let installPathFlag = Flag(longName: "path", type: String.self, description: "Local path to Xcode .xip")
let installLatestFlag = Flag(longName: "latest", value: false, description: "Update and then install the latest non-prerelease version available.")
let installLatestPrereleaseFlag = Flag(longName: "latest-prerelease", value: false, description: "Update and then install the latest prerelease version available, including GM seeds and GMs.")
let aria2 = Flag(longName: "aria2", type: String.self, description: "The path to an aria2 executable. Defaults to /usr/local/bin/aria2c.")
let noAria2 = Flag(longName: "no-aria2", value: false, description: "Don't use aria2 to download Xcode, even if its available.")

let install = Command(usage: "install <version>",
                      shortMessage: "Download and install a specific version of Xcode",
                      longMessage: """
                      Download and install a specific version of Xcode

                      By default, xcodes will use a URLSession to download the specified version. If aria2 (https://aria2.github.io, available in Homebrew) is installed, either somewhere in PATH or at the path specified by the --aria2 flag, then it will be used instead. aria2 will use up to 16 connections to download Xcode 3-5x faster. If you have aria2 installed and would prefer to not use it, you can use the --no-aria2 flag.
                      """,
                      flags: [installPathFlag, installLatestFlag, installLatestPrereleaseFlag, aria2, noAria2],
                      example: """
                               xcodes install 10.2.1
                               xcodes install 11 Beta 7
                               xcodes install 11.2 GM seed
                               xcodes install 9.0 --path ~/Archive/Xcode_9.xip
                               xcodes install --latest-prerelease
                               """) { flags, args in
    let versionString = args.joined(separator: " ")

    let installation: XcodeInstaller.InstallationType
    if flags.getBool(name: "latest") == true {
        installation = .latest
    } else if flags.getBool(name: "latest-prerelease") == true {
        installation = .latestPrerelease
    } else if let pathString = flags.getString(name: "path"), let path = Path(pathString) {
        installation = .path(versionString, path)
    } else {
        installation = .version(versionString)
    }
    
    var downloader = XcodeInstaller.Downloader.urlSession
    if let aria2Path = flags.getString(name: "aria2").flatMap(Path.init) ?? Current.shell.findExecutable("aria2c"),
       aria2Path.exists, 
       flags.getBool(name: "no-aria2") != true {
        downloader = .aria2(aria2Path)
    }

    installer.install(installation, downloader: downloader)
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

let downloadDirectoryFlag = Flag(longName: "directory", type: String.self, description: "Directory to download .xip to. Defaults to ~/Downloads.")
let downloadLatestFlag = Flag(longName: "latest", value: false, description: "Update and then download the latest non-prerelease version available.")
let downloadLatestPrereleaseFlag = Flag(longName: "latest-prerelease", value: false, description: "Update and then download the latest prerelease version available, including GM seeds and GMs.")
let download = Command(usage: "download <version>",
                       shortMessage: "Download a specific version of Xcode",
                       longMessage: """
                       Download a specific version of Xcode

                       By default, xcodes will use a URLSession to download the specified version. If aria2 (https://aria2.github.io, available in Homebrew) is installed, either somewhere in PATH or at the path specified by the --aria2 flag, then it will be used instead. aria2 will use up to 16 connections to download Xcode 3-5x faster. If you have aria2 installed and would prefer to not use it, you can use the --no-aria2 flag.
                       """,
                       flags: [downloadDirectoryFlag, downloadLatestFlag, downloadLatestPrereleaseFlag, aria2, noAria2],
                       example: """
                                xcodes download 10.2.1
                                xcodes download 11 Beta 7
                                xcodes download 11.2 GM seed
                                xcodes download 9.0 --directory ~/Archive
                                xcodes download --latest-prerelease
                                """) { flags, args in
     let versionString = args.joined(separator: " ")

     let installation: XcodeInstaller.InstallationType
     // Deliberately not using InstallationType.path here as it doesn't make sense to download an Xcode from a .xip that's already on disk
     if flags.getBool(name: "latest") == true {
         installation = .latest
     } else if flags.getBool(name: "latest-prerelease") == true {
         installation = .latestPrerelease
     } else {
         installation = .version(versionString)
     }

     var downloader = XcodeInstaller.Downloader.urlSession
     if let aria2Path = flags.getString(name: "aria2").flatMap(Path.init) ?? Current.shell.findExecutable("aria2c"),
        aria2Path.exists,
        flags.getBool(name: "no-aria2") != true {
         downloader = .aria2(aria2Path)
     }

     let directory = flags.getString(name: "directory").flatMap(Path.init)
     installer.download(installation, downloader: downloader, destinationDirectory: directory ?? Path.home.join("Downloads"))
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
app.add(subCommand: download)

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
