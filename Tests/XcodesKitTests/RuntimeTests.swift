import XCTest
import Version
import Path
@preconcurrency import Rainbow
@testable import XcodesCLIKit

final class RuntimeTests: XCTestCase {

    var runtimeList: RuntimeList!
    var runtimeInstaller: RuntimeInstaller!

    override func setUp() {
        Current = .mock
        syncXcodesKitMocks()
        let sessionService = AppleSessionService(configuration: Configuration())
        runtimeList = RuntimeList()
        runtimeInstaller = RuntimeInstaller(runtimeList: runtimeList, sessionService: sessionService)
    }

    func mockDownloadables() {
        let url = Bundle.module.url(forResource: "DownloadableRuntimes", withExtension: "plist", subdirectory: "Fixtures")!
        let downloadsData = try! Data(contentsOf: url)
        mockDownloadables(data: downloadsData)
    }

    func mockDownloadables(data downloadsData: Data) {
        XcodesCLIKit.Current.network.loadData = { urlRequest in
            if urlRequest.url! == .downloadableRuntimes {
                return (data: downloadsData, response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if urlRequest.url?.absoluteString.hasPrefix("https://developerservices2.apple.com/services/download") == true {
                return (data: Data(), response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            fatalError("wrong url")
        }
    }

    func mockMountedDMG() {
        Current.shell.mountDmg = { _ in
            let plist = """
            <dict>
                <key>system-entities</key>
                <array>
                    <dict>
                    </dict>
                    <dict>
                        <key>mount-point</key>
                        <string>\(NSHomeDirectory())</string>
                    </dict>
                    <dict>
                    </dict>
                </array>
            </dict>
            """
            return (0, plist, "")
        }
    }

    func test_installedRuntimes() async throws {
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return (0, try! String(contentsOf: url), "")
        }
        let values = try await runtimeList.installedRuntimes()
        let givenIDs = [
            UUID(uuidString: "2A6068A0-7FCF-4DB9-964D-21145EB98498")!,
            UUID(uuidString: "6DE6B631-9439-4737-A65B-73F675EB77D1")!,
            UUID(uuidString: "6DE6B631-9439-4737-A65B-73F675EB77D2")!,
            UUID(uuidString: "7A032D54-0D93-4E04-80B9-4CB207136C3F")!,
            UUID(uuidString: "91B92361-CD02-4AF7-8DFE-DE8764AA949F")!,
            UUID(uuidString: "630146EA-A027-42B1-AC25-BE4EA018DE90")!,
            UUID(uuidString: "AAD753FE-A798-479C-B6D6-41259B063DD6")!,
            UUID(uuidString: "BE68168B-7AC8-4A1F-A344-15DFCC375457")!,
            UUID(uuidString: "F8D81829-354C-4EB0-828D-83DC765B27E1")!,
        ]
        XCTAssertEqual(givenIDs, values.map(\.identifier))
    }

    func test_downloadableRuntimes() async throws {
        mockDownloadables()
        let values = try await runtimeList.downloadableRuntimes()
        XCTAssertEqual(values.count, 60)
    }

    func test_downloadableRuntimesNoBetas() async throws {
        mockDownloadables()
        let values = try await runtimeList.downloadableRuntimes().filter { $0.betaNumber == nil }
        XCTAssertFalse(values.contains { $0.name.lowercased().contains("beta") })
        XCTAssertEqual(values.count, 52)
    }

    func test_printAvailableRuntimes() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }
        mockDownloadables()
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return (0, try! String(contentsOf: url), "")
        }
        try await runtimeInstaller.printAvailableRuntimes(includeBetas: true)
        let outputUrl = Bundle.module.url(forResource: "LogOutput-Runtimes", withExtension: "txt", subdirectory: "Fixtures")!
        XCTAssertEqual(log.value, try String(contentsOf: outputUrl))
    }

    func test_printAvailableRuntimes_NoBetas() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }
        mockDownloadables()
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return (0, try! String(contentsOf: url), "")
        }
        try await runtimeInstaller.printAvailableRuntimes(includeBetas: false)
        let outputUrl = Bundle.module.url(forResource: "LogOutput-Runtime_NoBetas", withExtension: "txt", subdirectory: "Fixtures")!
        XCTAssertEqual(log.value, try String(contentsOf: outputUrl))
    }

    func test_printAvailableRuntimes_WithArchitectureFilter_DoesNotPrintOptions() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }
        mockDownloadables()
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return (0, try! String(contentsOf: url), "")
        }

        try await runtimeInstaller.printAvailableRuntimes(includeBetas: false, architectures: [.variant(.universal)])

        XCTAssertFalse(log.value.contains("Options:"))
    }

    func test_printAvailableRuntimes_ColorsInstalledStatus() async throws {
        let originalOutputTarget = Rainbow.outputTarget
        let originalEnabled = Rainbow.enabled
        Rainbow.outputTarget = .console
        Rainbow.enabled = true
        defer {
            Rainbow.outputTarget = originalOutputTarget
            Rainbow.enabled = originalEnabled
        }

        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }
        mockDownloadables()
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return (0, try! String(contentsOf: url), "")
        }

        try await runtimeInstaller.printAvailableRuntimes(includeBetas: false)

        XCTAssertTrue(log.value.contains("(\("Installed".blue))"))
        XCTAssertTrue(log.value.contains("(\("Bundled with selected Xcode".green))"))
    }

    func test_wrongIdentifier() async throws {
        mockDownloadables()
        var resultError: RuntimeInstaller.Error? = nil
        let identifier = "iOS 99.0"
        do {
            try await runtimeInstaller.downloadAndInstallRuntime(identifier: identifier, to: .xcodesCaches, with: .urlSession, shouldDelete: true)
        } catch {
            resultError = error as? RuntimeInstaller.Error
        }
        XCTAssertEqual(resultError, .unavailableRuntime(identifier))
    }

    func test_downloadRuntimeWithNoSourceSuggestsInstall() async throws {
        mockDownloadables()
        let identifier = "iOS 18.0-beta1"
        var resultError: RuntimeInstaller.Error? = nil

        do {
            try await runtimeInstaller.downloadRuntime(identifier: identifier, to: .xcodesCaches, with: .urlSession)
        } catch {
            resultError = error as? RuntimeInstaller.Error
        }

        XCTAssertEqual(resultError, .missingRuntimeSource(identifier))
    }

    func test_rootNeededIfPackage() async throws {
        mockDownloadables()
        XcodesCLIKit.Current.shell.isRoot = { false }
        let identifier = "iOS 15.5"
        let runtime = try await runtimeList.downloadableRuntimes().first { $0.visibleIdentifier == identifier }!
        var resultError: RuntimeInstaller.Error? = nil
        do {
            try await runtimeInstaller.downloadAndInstallRuntime(identifier: identifier, to: .xcodesCaches, with: .urlSession, shouldDelete: true)
        } catch {
            resultError = error as? RuntimeInstaller.Error
        }
        XCTAssertEqual(runtime.visibleIdentifier, identifier)
        XCTAssertEqual(runtime.contentType, .package)
        XCTAssertEqual(resultError, .rootNeeded)
    }

    func test_rootNotNeededIfDiskImage() async throws {
        mockDownloadables()
        XcodesCLIKit.Current.shell.isRoot = { false }
        let identifier = "iOS 16.0"
        let runtime = try await runtimeList.downloadableRuntimes().first { $0.visibleIdentifier == identifier }!
        var resultError: RuntimeInstaller.Error? = nil
        do {
            try await runtimeInstaller.downloadAndInstallRuntime(identifier: identifier, to: .xcodesCaches, with: .urlSession, shouldDelete: true)
        } catch {
            resultError = error as? RuntimeInstaller.Error
        }
        XCTAssertEqual(runtime.visibleIdentifier, identifier)
        XCTAssertEqual(runtime.contentType, .diskImage)
        XCTAssertEqual(resultError, nil)
    }

    func test_downloadOrUseExistingArchive_ReturnsExistingArchive() async throws {
        Current.files.fileExistsAtPath = { _ in return true }
        mockDownloadables()
        let runtime = try await runtimeList.downloadableRuntimes().first { $0.visibleIdentifier == "iOS 15.5" }!
        let xcodeDownloadURL = LockedBox<URL?>(nil)
        Current.network.downloadTask = { url, _, _ in
            xcodeDownloadURL.set(url.url)
            return (Progress(), Task { throw URLError(.unknown) })
        }

        let url = try await runtimeInstaller.downloadOrUseExistingArchive(runtime: runtime, to: .xcodesCaches, downloader: .urlSession)
        let fileName = URL(string: runtime.source!)!.lastPathComponent
        XCTAssertEqual(url, Path.xcodesCaches.join(fileName).url)
        XCTAssertNil(xcodeDownloadURL.value)
    }

    func test_downloadOrUseExistingArchive_DownloadsArchive() async throws {
        Current.files.fileExistsAtPath = { _ in return false }
        mockDownloadables()
        let xcodeDownloadURL = LockedBox<URL?>(nil)
        Current.network.downloadTask = { url, destination, _ in
            xcodeDownloadURL.set(url.url)
            return (
                Progress(),
                Task {
                    (destination, HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            )
        }
        let runtime = try await runtimeList.downloadableRuntimes().first { $0.visibleIdentifier == "iOS 15.5" }!
        let fileName = URL(string: runtime.source!)!.lastPathComponent
        let url = try await runtimeInstaller.downloadOrUseExistingArchive(runtime: runtime, to: .xcodesCaches, downloader: .urlSession)
        XCTAssertEqual(url, Path.xcodesCaches.join(fileName).url)
        XCTAssertEqual(xcodeDownloadURL.value, URL(string: runtime.source!)!)
    }

    func test_downloadRuntimePrefersMachineDefaultArchitectureWhenIdentifiersMatch() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }
        Current.files.fileExistsAtPath = { _ in false }
        Current.shell.machineArchitecture = { "arm64" }
        Current.shell.isatty = { false }
        mockDownloadables(data: Self.duplicateArchitectureRuntimePlistData())
        let xcodeDownloadURL = LockedBox<URL?>(nil)
        Current.network.downloadTask = { url, destination, _ in
            xcodeDownloadURL.set(url.url)
            return (
                Progress(),
                Task {
                    (destination, HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            )
        }

        try await runtimeInstaller.downloadRuntime(identifier: "iOS 16.0", to: .xcodesCaches, with: .urlSession)

        XCTAssertEqual(xcodeDownloadURL.value, URL(string: "https://example.com/arm64.dmg")!)
        XCTAssertTrue(log.value.contains("Downloading Runtime iOS 16.0 - Apple Silicon (arm64)"))
    }

    func test_downloadRuntimeDoesNotPrintDefaultArchitectureWhenArchitectureIsSpecified() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }
        Current.files.fileExistsAtPath = { _ in false }
        Current.shell.machineArchitecture = { "arm64" }
        Current.shell.isatty = { false }
        mockDownloadables(data: Self.duplicateArchitectureRuntimePlistData())
        Current.network.downloadTask = { url, destination, _ in
            return (
                Progress(),
                Task {
                    (destination, HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            )
        }

        try await runtimeInstaller.downloadRuntime(identifier: "iOS 16.0", to: .xcodesCaches, with: .urlSession, architectures: [.variant(.appleSilicon)])

        XCTAssertTrue(log.value.contains("Downloading Runtime iOS 16.0"))
        XCTAssertFalse(log.value.contains("Apple Silicon (arm64)"))
    }

    func test_downloadAndInstallRuntimeTreatsDuplicateXcodebuildRuntimeAsAlreadyInstalled() async throws {
        let log = LockedBox("")
        let attempts = LockedBox(0)
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }
        Current.shell.isatty = { false }
        Current.files.contentsAtPath = { path in
            guard path == "/Library/Developer/CoreSimulator/images/images.plist" else { return nil }
            return Self.installedRuntimeImagesPlistData()
        }
        mockDownloadables(data: Self.cryptexRuntimePlistData())
        runtimeInstaller = RuntimeInstaller(
            runtimeList: runtimeList,
            sessionService: AppleSessionService(configuration: Configuration()),
            xcodebuildRuntimeInstall: { _, _, _ in
                attempts.increment()
                throw ProcessExecutionError(
                    process: Process(),
                    terminationStatus: 70,
                    standardOutput: """
                    Finding content...
                    Downloading iOS 16.0 Simulator (20A360) (arm64): Error: Error Domain=SimDiskImageErrorDomain Code=5 "Duplicate of B9DF5553-BDD3-49DF-B82B-96CCA8CB8F70"
                    """,
                    standardError: ""
                )
            },
            selectedXcodeVersion: { Version(major: 26, minor: 0, patch: 0) }
        )

        try await runtimeInstaller.downloadAndInstallRuntime(
            identifier: "iOS 16.0",
            to: .xcodesCaches,
            with: .urlSession,
            shouldDelete: true
        )

        XCTAssertEqual(attempts.value, 1)
        XCTAssertTrue(log.value.contains("Runtime iOS 16.0 - Apple Silicon (arm64) is already installed"))
    }

    func test_installStepsForPackage() async throws {
        mockDownloadables()
        let expectedSteps = [
            "mounting",
            "expanding_pkg",
            "unmounting",
            "gettingInfo",
            "wrtitingInfo",
            "creating_pkg",
            "installing_pkg"
        ]
        let doneSteps = LockedBox<[String]>([])
        Current.shell.mountDmg = { _ in doneSteps.append("mounting"); return (0, mockDMGPathPlist(), "") }
        Current.shell.expandPkg = { _, _ in doneSteps.append("expanding_pkg"); return Shell.processOutputMock }
        Current.shell.unmountDmg = { _ in doneSteps.append("unmounting"); return Shell.processOutputMock }
        Current.files.contentsAtPath = { path in
            guard path.contains("PackageInfo") else { return nil }
            doneSteps.append("gettingInfo")
            let url = Bundle.module.url(forResource: "PackageInfo_before", withExtension: nil, subdirectory: "Fixtures")!
            return try? Data(contentsOf: url)
        }
        Current.files.write = { data, path in
            guard path.path.contains("PackageInfo") else { return }
            doneSteps.append("wrtitingInfo")
            let url = Bundle.module.url(forResource: "PackageInfo_after", withExtension: nil, subdirectory: "Fixtures")!
            let newString = String(data: data, encoding: .utf8)
            XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), String(data: data, encoding: .utf8))
            XCTAssertTrue(newString?.contains("/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 15.5.simruntime") == true)
        }
        Current.shell.createPkg = { _, _ in doneSteps.append("creating_pkg"); return Shell.processOutputMock }
        Current.shell.installPkg = { _, _ in doneSteps.append("installing_pkg"); return Shell.processOutputMock }
        try await runtimeInstaller.downloadAndInstallRuntime(identifier: "iOS 15.5", to: .xcodesCaches, with: .urlSession, shouldDelete: true)

        XCTAssertEqual(expectedSteps, doneSteps.value)
    }

    func test_installStepsForImage() async throws {
        mockDownloadables()
        let didInstall = LockedBox(false)
        Current.shell.installRuntimeImage = { _ in
            didInstall.set(true)
            return Shell.processOutputMock
        }
        try await runtimeInstaller.downloadAndInstallRuntime(identifier: "iOS 16.0", to: .xcodesCaches, with: .urlSession, shouldDelete: true)
        XCTAssertTrue(didInstall.value)
    }


    func test_deletesArchiveWhenFinished() async throws {
        mockDownloadables()
        let removed = LockedBox(false)
        Current.files.removeItem = { itemURL in
            removed.set(true)
        }
        try await runtimeInstaller.downloadAndInstallRuntime(identifier: "iOS 16.0", to: .xcodesCaches, with: .urlSession, shouldDelete: true)
        XCTAssertTrue(removed.value)
    }

    func test_KeepArchiveWhenFinished() async throws {
        mockDownloadables()
        let removed = LockedBox(false)
        Current.files.removeItem = { itemURL in
            removed.set(true)
        }
        try await runtimeInstaller.downloadAndInstallRuntime(identifier: "iOS 16.0", to: .xcodesCaches, with: .urlSession, shouldDelete: false)
        XCTAssertFalse(removed.value)
    }
}

private extension RuntimeTests {
    static func cryptexRuntimePlistData() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>sdkToSimulatorMappings</key>
            <array/>
            <key>sdkToSeedMappings</key>
            <array/>
            <key>refreshInterval</key>
            <integer>3600</integer>
            <key>downloadables</key>
            <array>
                <dict>
                    <key>category</key>
                    <string>simulator</string>
                    <key>simulatorVersion</key>
                    <dict>
                        <key>buildUpdate</key>
                        <string>20A360</string>
                        <key>version</key>
                        <string>16.0</string>
                    </dict>
                    <key>architectures</key>
                    <array>
                        <string>arm64</string>
                    </array>
                    <key>dictionaryVersion</key>
                    <integer>1</integer>
                    <key>contentType</key>
                    <string>cryptexDiskImage</string>
                    <key>platform</key>
                    <string>com.apple.platform.iphoneos</string>
                    <key>identifier</key>
                    <string>com.apple.dmg.iPhoneSimulatorSDK16_0_arm64</string>
                    <key>version</key>
                    <string>16.0</string>
                    <key>fileSize</key>
                    <integer>42</integer>
                    <key>name</key>
                    <string>iOS 16.0 Simulator Runtime</string>
                </dict>
            </array>
            <key>version</key>
            <string>2</string>
        </dict>
        </plist>
        """.utf8)
    }

    static func installedRuntimeImagesPlistData() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>images</key>
            <array>
                <dict>
                    <key>uuid</key>
                    <string>B9DF5553-BDD3-49DF-B82B-96CCA8CB8F70</string>
                    <key>path</key>
                    <dict>
                        <key>relative</key>
                        <string>file:///Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 16.simruntime</string>
                    </dict>
                    <key>runtimeInfo</key>
                    <dict>
                        <key>build</key>
                        <string>20A360</string>
                        <key>supportedArchitectures</key>
                        <array>
                            <string>arm64</string>
                        </array>
                    </dict>
                </dict>
            </array>
        </dict>
        </plist>
        """.utf8)
    }

    static func duplicateArchitectureRuntimePlistData() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>sdkToSimulatorMappings</key>
            <array/>
            <key>sdkToSeedMappings</key>
            <array/>
            <key>refreshInterval</key>
            <integer>3600</integer>
            <key>downloadables</key>
            <array>
                <dict>
                    <key>category</key>
                    <string>simulator</string>
                    <key>simulatorVersion</key>
                    <dict>
                        <key>buildUpdate</key>
                        <string>20A360</string>
                        <key>version</key>
                        <string>16.0</string>
                    </dict>
                    <key>source</key>
                    <string>https://example.com/universal.dmg</string>
                    <key>architectures</key>
                    <array>
                        <string>arm64</string>
                        <string>x86_64</string>
                    </array>
                    <key>dictionaryVersion</key>
                    <integer>1</integer>
                    <key>contentType</key>
                    <string>diskImage</string>
                    <key>platform</key>
                    <string>com.apple.platform.iphoneos</string>
                    <key>identifier</key>
                    <string>com.apple.CoreSimulator.SimRuntime.iOS-16-0</string>
                    <key>version</key>
                    <string>16.0</string>
                    <key>fileSize</key>
                    <integer>42</integer>
                    <key>name</key>
                    <string>iOS 16.0</string>
                </dict>
                <dict>
                    <key>category</key>
                    <string>simulator</string>
                    <key>simulatorVersion</key>
                    <dict>
                        <key>buildUpdate</key>
                        <string>20A360</string>
                        <key>version</key>
                        <string>16.0</string>
                    </dict>
                    <key>source</key>
                    <string>https://example.com/arm64.dmg</string>
                    <key>architectures</key>
                    <array>
                        <string>arm64</string>
                    </array>
                    <key>dictionaryVersion</key>
                    <integer>1</integer>
                    <key>contentType</key>
                    <string>diskImage</string>
                    <key>platform</key>
                    <string>com.apple.platform.iphoneos</string>
                    <key>identifier</key>
                    <string>com.apple.CoreSimulator.SimRuntime.iOS-16-0-arm64</string>
                    <key>version</key>
                    <string>16.0</string>
                    <key>fileSize</key>
                    <integer>42</integer>
                    <key>name</key>
                    <string>iOS 16.0</string>
                </dict>
            </array>
            <key>version</key>
            <string>2</string>
        </dict>
        </plist>
        """.utf8)
    }
}

private func mockDMGPathPlist(path: String = NSHomeDirectory()) -> String {
    return """
    <dict>
        <key>system-entities</key>
        <array>
            <dict>
            </dict>
            <dict>
                <key>mount-point</key>
                <string>\(path)</string>
            </dict>
            <dict>
            </dict>
        </array>
    </dict>
    """
}
