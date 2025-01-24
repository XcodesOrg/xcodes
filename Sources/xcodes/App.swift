import Foundation
import ArgumentParser
import Version
import PromiseKit
import XcodesKit
import LegibleError
import Path
import Rainbow

func getDirectory(possibleDirectory: String?, default: Path = Path.root.join("Applications")) -> Path {
    let directory = possibleDirectory.flatMap(Path.init) ??
        ProcessInfo.processInfo.environment["XCODES_DIRECTORY"].flatMap(Path.init) ??
        `default`
    guard directory.isDirectory else {
        Current.logging.log("Directory argument must be a directory, but was provided \(directory.string).".red)
        exit(1)
    }
    return directory
}

struct GlobalDirectoryOption: ParsableArguments {
    @Option(help: "The directory where your Xcodes are installed. Defaults to /Applications.",
            completion: .directory)
    var directory: String?
}

struct GlobalDataSourceOption: ParsableArguments {
    @Option(
        help: ArgumentParser.ArgumentHelp(
            "The data source for available Xcode versions.",
            discussion: """
                The Apple data source ("apple") scrapes the Apple Developer website. It will always show the latest releases that are available, but is more fragile.

                Xcode Releases ("xcodeReleases") is an unofficial list of Xcode releases. It's provided as well-formed data, contains extra information that is not readily available from Apple, and is less likely to break if Apple redesigns their developer website.
                """
        )
    )
    var dataSource: DataSource = .xcodeReleases
}

struct GlobalColorOption: ParsableArguments {
    @Flag(
        inversion: .prefixedNo,
        help: ArgumentHelp(
            "Determines whether output should be colored.",
            discussion: """
                xcodes will also disable colored output if its not running in an interactive terminal, if the NO_COLOR environment variable is set, or if the TERM environment variable is set to "dumb".
                """
        )
    )
    var color: Bool = true
}

@main
struct Xcodes: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Manage the Xcodes installed on your Mac",
        shouldDisplay: true,
        subcommands: [Download.self, Install.self, Installed.self, List.self, Runtimes.self, Select.self, Uninstall.self, Update.self, Version.self, Signout.self]
    )

    static var xcodesConfiguration = Configuration()
    static var sessionService: AppleSessionService!
    static let xcodeList = XcodeList()
    static let runtimeList = RuntimeList()
    static var runtimeInstaller: RuntimeInstaller!
    static var xcodeInstaller: XcodeInstaller!
    static var fastlaneSessionManager: FastlaneSessionManager!

    static func main() async {
        try? xcodesConfiguration.load()
        sessionService = AppleSessionService(configuration: xcodesConfiguration)
        xcodeInstaller = XcodeInstaller(xcodeList: xcodeList, sessionService: sessionService)
        runtimeInstaller = RuntimeInstaller(runtimeList: runtimeList, sessionService: sessionService)
        fastlaneSessionManager = FastlaneSessionManager()
        migrateApplicationSupportFiles()
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            exit(withError: error)
        }
    }

    struct Download: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Download a specific version of Xcode",
            discussion: """
                        By default, xcodes will use a URLSession to download the specified version. If aria2 (https://aria2.github.io, available in Homebrew) is installed, either somewhere in PATH or at the path specified by the --aria2 flag, then it will be used instead. aria2 will use up to 16 connections to download Xcode 3-5x faster. If you have aria2 installed and would prefer to not use it, you can use the --no-aria2 flag.

                        EXAMPLES:
                          xcodes download 10.2.1
                          xcodes download 11 Beta 7
                          xcodes download 11.2 GM seed
                          xcodes download 9.0 --directory ~/Archive
                          xcodes download --latest-prerelease
                        """
        )

        @Argument(help: "The version to download",
                  completion: .custom { args in xcodeList.availableXcodes.sorted { $0.version < $1.version }.map { $0.version.appleDescription } })
        var version: [String] = []

        @Flag(help: "Update and then download the latest release version available.")
        var latest: Bool = false

        @Flag(help: "Update and then download the latest prerelease version available, including GM seeds and GMs.")
        var latestPrerelease = false

        @Option(help: "The path to an aria2 executable. Searches $PATH by default.",
                completion: .file())
        var aria2: String?

        @Flag(help: "Don't use aria2 to download Xcode, even if its available.")
        var noAria2: Bool = false

        @Option(help: "The directory to download Xcode to. Defaults to ~/Downloads.",
                completion: .directory)
        var directory: String?

        @Flag(help: "Use fastlane spaceship session.")
        var useFastlaneAuth: Bool = false

        @Option(help: "The fastlane spaceship user",
                completion: .shellCommand("ls \(FastlaneSessionManager.Constants.fastlaneSpaceshipDir)"))
        var fastlaneUser: String = FastlaneSessionManager.Constants.fastlaneSessionEnvVarName

        @OptionGroup
        var globalDataSource: GlobalDataSourceOption

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color

            let versionString = version.joined(separator: " ")

            let installation: XcodeInstaller.InstallationType
            // Deliberately not using InstallationType.path here as it doesn't make sense to download an Xcode from a .xip that's already on disk
            if latest {
                installation = .latest
            } else if latestPrerelease {
                installation = .latestPrerelease
            } else {
                installation = .version(versionString)
            }
            
            let downloader = noAria2 ? Downloader.urlSession : Downloader(aria2Path: aria2)

            let destination = getDirectory(possibleDirectory: directory, default: .environmentDownloads)

            if useFastlaneAuth {
                fastlaneSessionManager.setupFastlaneAuth(fastlaneUser: fastlaneUser)
            }

            xcodeInstaller.download(installation, dataSource: globalDataSource.dataSource, downloader: downloader, destinationDirectory: destination)
                .catch { error in
                    Install.processDownloadOrInstall(error: error)
                }

            RunLoop.current.run()
        }
    }

    struct Install: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Download and install a specific version of Xcode",
            discussion: """
                        By default, xcodes will use a URLSession to download the specified version. If aria2 (https://aria2.github.io, available in Homebrew) is installed, either somewhere in PATH or at the path specified by the --aria2 flag, then it will be used instead. aria2 will use up to 16 connections to download Xcode 3-5x faster. If you have aria2 installed and would prefer to not use it, you can use the --no-aria2 flag.

                        EXAMPLES:
                          xcodes install 10.2.1
                          xcodes install 11 Beta 7
                          xcodes install 11.2 GM seed
                          xcodes install 9.0 --path ~/Archive/Xcode_9.xip
                          xcodes install --latest-prerelease
                          xcodes install --latest --directory "/Volumes/Bag Of Holding/"
                        """
        )

        @Argument(help: "The version to install",
                  completion: .custom { args in xcodeList.availableXcodes.sorted { $0.version < $1.version }.map { $0.version.appleDescription } })
        var version: [String] = []

        @Option(name: .customLong("path"),
                help: "Local path to Xcode .xip",
                completion: .file(extensions: ["xip"]))
        var pathString: String?

        @Flag(help: "Update and then install the latest release version available.")
        var latest: Bool = false

        @Flag(help: "Update and then install the latest prerelease version available, including GM seeds and GMs.")
        var latestPrerelease = false

        @Option(help: "The path to an aria2 executable. Searches $PATH by default.",
                completion: .file())
        var aria2: String?

        @Flag(help: "Don't use aria2 to download Xcode, even if its available.")
        var noAria2: Bool = false

        @Flag(help: "Select the installed xcode version after installation.")
        var select: Bool = false

        @Flag(help: "Whether to update the list before installing")
        var update: Bool = false

        @ArgumentParser.Flag(name: [.customShort("p"), .customLong("print-path")], help: "Print the path of the selected Xcode")
        var print: Bool = false

        @Flag(help: "Use the experimental unxip functionality. May speed up unarchiving by up to 2-3x.")
        var experimentalUnxip: Bool = false

        @Flag(help: "Don't ask for superuser (root) permission. Some optional steps of the installation will be skipped.")
        var noSuperuser: Bool = false

        @Flag(help: "Completely delete Xcode .xip after installation, instead of keeping it on the user's Trash.")
        var emptyTrash: Bool = false

        @Option(help: "The directory to install Xcode into. Defaults to /Applications.",
                completion: .directory)
        var directory: String?

        @Flag(help: "Use fastlane spaceship session.")
        var useFastlaneAuth: Bool = false

        @Option(help: "The fastlane spaceship user.",
                completion: .shellCommand("ls \(FastlaneSessionManager.Constants.fastlaneSpaceshipDir)"))
        var fastlaneUser: String = FastlaneSessionManager.Constants.fastlaneSessionEnvVarName

        @OptionGroup
        var globalDataSource: GlobalDataSourceOption

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color

            let versionString = version.joined(separator: " ")

            let installation: XcodeInstaller.InstallationType
            if latest {
                installation = .latest
            } else if latestPrerelease {
                installation = .latestPrerelease
            } else if let pathString = pathString, let path = Path(pathString) {
                installation = .path(versionString, path)
            } else {
                installation = .version(versionString)
            }
            
            let downloader = noAria2 ? Downloader.urlSession : Downloader(aria2Path: aria2)

            let destination = getDirectory(possibleDirectory: directory)

            if select, case .version(let version) = installation {
                firstly {
                    selectXcode(shouldPrint: print, pathOrVersion: version, directory: destination, fallbackToInteractive: false)
                }
                .catch { _ in
                    install(installation, using: downloader, to: destination)
                }
            } else {
                install(installation, using: downloader, to: destination)
            }

            RunLoop.current.run()
        }

        private func install(_ installation: XcodeInstaller.InstallationType,
                             using downloader: Downloader,
                             to destination: Path) {
            firstly { () -> Promise<InstalledXcode> in
                if useFastlaneAuth { fastlaneSessionManager.setupFastlaneAuth(fastlaneUser: fastlaneUser) }
                // update the list before installing only for version type because the other types already update internally
                if update, case .version = installation {
                    Current.logging.log("Updating...")
                    return xcodeList.update(dataSource: globalDataSource.dataSource)
                        .then { _ -> Promise<InstalledXcode> in
                            xcodeInstaller.install(installation, dataSource: globalDataSource.dataSource, downloader: downloader, destination: destination, experimentalUnxip: experimentalUnxip, emptyTrash: emptyTrash, noSuperuser: noSuperuser)
                        }
                } else {
                    return xcodeInstaller.install(installation, dataSource: globalDataSource.dataSource, downloader: downloader, destination: destination, experimentalUnxip: experimentalUnxip, emptyTrash: emptyTrash, noSuperuser: noSuperuser)
                }
            }
            .recover { error -> Promise<InstalledXcode> in
                if select, case let XcodeInstaller.Error.versionAlreadyInstalled(installedXcode) = error {
                    Current.logging.log(error.legibleLocalizedDescription.green)
                    return Promise { seal in
                        seal.fulfill(installedXcode)
                    }
                } else {
                    throw error
                }
            }
            .then { xcode -> Promise<Void> in
                if select {
                    return selectXcode(shouldPrint: print, pathOrVersion: xcode.path.string, directory: destination, fallbackToInteractive: false)
                } else {
                    return .init()
                }
            }
            .done {
                Install.exit()
            }
            .catch { error in
                Install.processDownloadOrInstall(error: error)
            }
        }
    }

    struct Installed: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "List the versions of Xcode that are installed"
        )

        @Argument(help: "The version installed to which to print the path for",
                  completion: .custom { _ in Current.files.installedXcodes(getDirectory(possibleDirectory: nil)).sorted { $0.version < $1.version }.map { $0.version.appleDescription } })
        var version: [String] = []

        @OptionGroup
        var globalDirectory: GlobalDirectoryOption

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color

            let directory = getDirectory(possibleDirectory: globalDirectory.directory)

            xcodeInstaller.printXcodePath(ofVersion: version.joined(separator: " "), searchingIn: directory)
                .recover { error -> Promise<Void> in
                    switch error {
                    case XcodeInstaller.Error.invalidVersion:
                        return xcodeInstaller.printInstalledXcodes(directory: directory)
                    default:
                        throw error
                    }
                }
                .done { Installed.exit() }
                .catch { error in Installed.exit(withLegibleError: error) }

            RunLoop.current.run()
        }
    }

    struct List: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "List all versions of Xcode that are available to install"
        )

        @OptionGroup
        var globalDirectory: GlobalDirectoryOption

        @OptionGroup
        var globalDataSource: GlobalDataSourceOption

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color

            let directory = getDirectory(possibleDirectory: globalDirectory.directory)

            firstly { () -> Promise<Void> in
                if xcodeList.shouldUpdateBeforeListingVersions {
                    return xcodeInstaller.updateAndPrint(dataSource: globalDataSource.dataSource, directory: directory)
                }
                else {
                    return xcodeInstaller.printAvailableXcodes(xcodeList.availableXcodes, installed: Current.files.installedXcodes(directory))
                }
            }
            .done { List.exit() }
            .catch { error in List.exit(withLegibleError: error) }

            RunLoop.current.run()
        }
    }

    struct Runtimes: AsyncParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "List all simulator runtimes that are available to install",
            subcommands: [Download.self, Install.self]
        )

        @Flag(help: "Include beta runtimes available to install")
        var includeBetas: Bool = false

        func run() async throws {
            try await runtimeInstaller.printAvailableRuntimes(includeBetas: includeBetas)
        }

        struct Install: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Download and install a specific simulator runtime"
            )

            @Argument(help: "The runtime to install")
            var version: String

            @Option(help: "The path to an aria2 executable. Searches $PATH by default.",
                    completion: .file())
            var aria2: String?

            @Flag(help: "Don't use aria2 to download the runtime, even if its available.")
            var noAria2: Bool = false

            @Option(help: "The directory to download the runtime archive to. Defaults to ~/Downloads.",
                    completion: .directory)
            var directory: String?

            @Flag(help: "Do not delete the runtime archive after the installation is finished.")
            var keepArchive = false

            @OptionGroup
            var globalColor: GlobalColorOption

            func run() async throws {
                Rainbow.enabled = Rainbow.enabled && globalColor.color

                let downloader = noAria2 ? Downloader.urlSession : Downloader(aria2Path: aria2)

                let destination = getDirectory(possibleDirectory: directory, default: .environmentDownloads)

                try await runtimeInstaller.downloadAndInstallRuntime(identifier: version, to: destination, with: downloader, shouldDelete: !keepArchive)
                Current.logging.log("Finished")
            }
        }

        struct Download: AsyncParsableCommand {
            static var configuration = CommandConfiguration(
                abstract: "Download a specific simulator runtime"
            )

            @Argument(help: "The runtime to download")
            var version: String

            @Option(help: "The path to an aria2 executable. Searches $PATH by default.",
                    completion: .file())
            var aria2: String?

            @Flag(help: "Don't use aria2 to download the runtime, even if its available.")
            var noAria2: Bool = false

            @Option(help: "The directory to download the runtime archive to. Defaults to ~/Downloads.",
                    completion: .directory)
            var directory: String?

            @OptionGroup
            var globalColor: GlobalColorOption

            func run() async throws {
                Rainbow.enabled = Rainbow.enabled && globalColor.color

                let downloader = noAria2 ? Downloader.urlSession : Downloader(aria2Path: aria2)

                let destination = getDirectory(possibleDirectory: directory, default: .environmentDownloads)

                try await runtimeInstaller.downloadRuntime(identifier: version, to: destination, with: downloader)
                Current.logging.log("Finished")
            }
        }

    }

    struct Select: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Change the selected Xcode",
            discussion: """
                        Select a version of Xcode by specifying a version number or an absolute path. Run without arguments to select the version specified in your .xcode-version file. If no version file is found, you will be prompted to interactively select from a list.

                        EXAMPLES:
                          xcodes select
                          xcodes select 11.4.0
                          xcodes select /Applications/Xcode-11.4.0.app
                          xcodes select -p
                        """
        )

        @ArgumentParser.Flag(name: [.customShort("p"), .customLong("print-path")], help: "Print the path of the selected Xcode")
        var print: Bool = false

        @Argument(help: "Version or path",
                  completion: .custom { _ in Current.files.installedXcodes(getDirectory(possibleDirectory: nil)).sorted { $0.version < $1.version }.map { $0.version.appleDescription } })
        var versionOrPath: [String] = []

        @Flag(help: "Select the latest installed version of Xcode, excluding prerelease versions")
        var latest = false

        @Flag(help: "Select the latest installed version of Xcode, including prerelease versions")
        var latestPrerelease = false

        @OptionGroup
        var globalDirectory: GlobalDirectoryOption

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color

            let directory = getDirectory(possibleDirectory: globalDirectory.directory)

            var versionOrPath = versionOrPath.joined(separator: " ")
            if latest || latestPrerelease {
                guard let latest = latestInstalledXcode else {
                    Current.logging.log("No versions of Xcode are installed")
                    return
                }

                versionOrPath = latest.path.string
            }

            selectXcode(shouldPrint: print, pathOrVersion: versionOrPath, directory: directory)
                .done { Select.exit() }
                .catch { error in Select.exit(withLegibleError: error) }

            RunLoop.current.run()
        }

        var latestInstalledXcode: InstalledXcode? {
            var installedXcodes = Current.files.installedXcodes(getDirectory(possibleDirectory: nil))
                .sorted { $0.version < $1.version }

            if !latestPrerelease {
                installedXcodes.removeAll { $0.version.isPrerelease }
            }

            return installedXcodes.last
        }
    }

    struct Uninstall: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Uninstall a version of Xcode",
            discussion: """
                        Run without any arguments to interactively select from a list.

                        EXAMPLES:
                          xcodes uninstall
                          xcodes uninstall 11.4.0
                        """
        )

        @Argument(help: "The version to uninstall",
                  completion: .custom { _ in Current.files.installedXcodes(getDirectory(possibleDirectory: nil)).sorted { $0.version < $1.version }.map { $0.version.appleDescription } })
        var version: [String] = []

        @Flag(help: "Completely delete Xcode, instead of keeping it on the user's Trash.")
        var emptyTrash: Bool = false

        @OptionGroup
        var globalDirectory: GlobalDirectoryOption

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color

            let directory = getDirectory(possibleDirectory: globalDirectory.directory)

            xcodeInstaller.uninstallXcode(version.joined(separator: " "), directory: directory, emptyTrash: emptyTrash)
                .done { Uninstall.exit() }
                .catch { error in Uninstall.exit(withLegibleError: error) }

            RunLoop.current.run()
        }
    }

    struct Update: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Update the list of available versions of Xcode"
        )

        @OptionGroup
        var globalDirectory: GlobalDirectoryOption

        @OptionGroup
        var globalDataSource: GlobalDataSourceOption

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color

            let directory = getDirectory(possibleDirectory: globalDirectory.directory)

            xcodeInstaller.updateAndPrint(dataSource: globalDataSource.dataSource, directory: directory)
                .done { Update.exit() }
                .catch { error in Update.exit(withLegibleError: error) }

            RunLoop.current.run()
        }
    }

    struct Version: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Print the version number of xcodes itself"
        )

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color

            Current.logging.log(XcodesKit.version.description)
        }
    }

    struct Signout: ParsableCommand {
        static var configuration = CommandConfiguration(
            abstract: "Clears the stored username and password"
        )

        @OptionGroup
        var globalColor: GlobalColorOption

        func run() {
            Rainbow.enabled = Rainbow.enabled && globalColor.color
            
            sessionService.logout()
                .done {
                    Current.logging.log("Successfully signed out".green)
                    Signout.exit()
                }
                .recover { error in
                    Current.logging.log(error.legibleLocalizedDescription)
                    Signout.exit()
                }

            RunLoop.current.run()
        }
    }
}
