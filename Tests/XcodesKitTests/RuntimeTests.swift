import XCTest
import Version
import PromiseKit
import PMKFoundation
import Path
import AppleAPI
import Rainbow
@testable import XcodesKit

final class RuntimeTests: XCTestCase {

    var runtimeList: RuntimeList!
    var runtimeInstaller: RuntimeInstaller!

    override class func setUp() {
        super.setUp()
        PromiseKit.conf.Q.map = nil
        PromiseKit.conf.Q.return = nil
    }

    override func setUp() {
        Current = .mock
        let sessionService = AppleSessionService(configuration: Configuration())
        runtimeList = RuntimeList()
        runtimeInstaller = RuntimeInstaller(runtimeList: runtimeList, sessionService: sessionService)
    }

    func mockDownloadables() {
        XcodesKit.Current.network.dataTask = { url in
            if url.pmkRequest.url! == .downloadableRuntimes {
                let url = Bundle.module.url(forResource: "DownloadableRuntimes", withExtension: "plist", subdirectory: "Fixtures")!
                let downloadsData = try! Data(contentsOf: url)
                return Promise.value((data: downloadsData, response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
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
            return Promise.value((0, plist, ""))
        }
    }

    func test_installedRuntimes() async throws {
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return Promise.value((0, try! String(contentsOf: url), ""))
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
        let values = try await runtimeList.downloadableRuntimes().downloadables
        XCTAssertEqual(values.count, 60)
    }

    func test_downloadableRuntimesNoBetas() async throws {
        mockDownloadables()
        let values = try await runtimeList.downloadableRuntimes().downloadables.filter { $0.betaNumber == nil }
        XCTAssertFalse(values.contains { $0.name.lowercased().contains("beta") })
        XCTAssertEqual(values.count, 52)
    }

    func test_printAvailableRuntimes() async throws {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }
        mockDownloadables()
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return Promise.value((0, try! String(contentsOf: url), ""))
        }
        try await runtimeInstaller.printAvailableRuntimes(includeBetas: true)
        let outputUrl = Bundle.module.url(forResource: "LogOutput-Runtimes", withExtension: "txt", subdirectory: "Fixtures")!
        XCTAssertEqual(log, try String(contentsOf: outputUrl))
    }

    func test_printAvailableRuntimes_NoBetas() async throws {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }
        mockDownloadables()
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return Promise.value((0, try! String(contentsOf: url), ""))
        }
        try await runtimeInstaller.printAvailableRuntimes(includeBetas: false)
        let outputUrl = Bundle.module.url(forResource: "LogOutput-Runtime_NoBetas", withExtension: "txt", subdirectory: "Fixtures")!
        XCTAssertEqual(log, try String(contentsOf: outputUrl))
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

    func test_rootNeededIfPackage() async throws {
        mockDownloadables()
        XcodesKit.Current.shell.isRoot = { false }
        let identifier = "iOS 15.5"
        let runtime = try await runtimeList.downloadableRuntimes().downloadables.first { $0.visibleIdentifier == identifier }!
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
        XcodesKit.Current.shell.isRoot = { false }
        let identifier = "iOS 16.0"
        let runtime = try await runtimeList.downloadableRuntimes().downloadables.first { $0.visibleIdentifier == identifier }!
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
        let runtime = try await runtimeList.downloadableRuntimes().downloadables.first { $0.visibleIdentifier == "iOS 15.5" }!
        var xcodeDownloadURL: URL?
        Current.network.downloadTask = { url, _, _ in
            xcodeDownloadURL = url.pmkRequest.url
            return (Progress(), Promise(error: PMKError.invalidCallingConvention))
        }

        let url = try await runtimeInstaller.downloadOrUseExistingArchive(runtime: runtime, to: .xcodesCaches, downloader: .urlSession)
        let fileName = URL(string: runtime.source!)!.lastPathComponent
        XCTAssertEqual(url, Path.xcodesCaches.join(fileName).url)
        XCTAssertNil(xcodeDownloadURL)
    }

    func test_downloadOrUseExistingArchive_DownloadsArchive() async throws {
        Current.files.fileExistsAtPath = { _ in return false }
        mockDownloadables()
        var xcodeDownloadURL: URL?
        Current.network.downloadTask = { url, destination, _ in
            xcodeDownloadURL = url.pmkRequest.url
            return (Progress(), Promise.value((destination, HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)))
        }
        let runtime = try await runtimeList.downloadableRuntimes().downloadables.first { $0.visibleIdentifier == "iOS 15.5" }!
        let fileName = URL(string: runtime.source!)!.lastPathComponent
        let url = try await runtimeInstaller.downloadOrUseExistingArchive(runtime: runtime, to: .xcodesCaches, downloader: .urlSession)
        XCTAssertEqual(url, Path.xcodesCaches.join(fileName).url)
        XCTAssertEqual(xcodeDownloadURL, URL(string: runtime.source!)!)
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
        var doneSteps: [String] = []
        Current.shell.mountDmg = { _ in doneSteps.append("mounting"); return .value((0, mockDMGPathPlist(), "")) }
        Current.shell.expandPkg = { _, _ in doneSteps.append("expanding_pkg"); return .value(Shell.processOutputMock) }
        Current.shell.unmountDmg = { _ in doneSteps.append("unmounting"); return .value(Shell.processOutputMock) }
        Current.files.contentsAtPath = { path in
            guard path.contains("PackageInfo") else { return nil }
            doneSteps.append("gettingInfo")
            let url = Bundle.module.url(forResource: "PackageInfo_before", withExtension: nil, subdirectory: "Fixtures")!
            return try? Data(contentsOf: url)
        }
        Current.files.write = { data, path in
            guard path.path.contains("PackageInfo") else { fatalError() }
            doneSteps.append("wrtitingInfo")
            let url = Bundle.module.url(forResource: "PackageInfo_after", withExtension: nil, subdirectory: "Fixtures")!
            let newString = String(data: data, encoding: .utf8)
            XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), String(data: data, encoding: .utf8))
            XCTAssertTrue(newString?.contains("/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 15.5.simruntime") == true)
        }
        Current.shell.createPkg = { _, _ in doneSteps.append("creating_pkg"); return .value(Shell.processOutputMock) }
        Current.shell.installPkg = { _, _ in doneSteps.append("installing_pkg"); return .value(Shell.processOutputMock) }
        try await runtimeInstaller.downloadAndInstallRuntime(identifier: "iOS 15.5", to: .xcodesCaches, with: .urlSession, shouldDelete: true)

        XCTAssertEqual(expectedSteps, doneSteps)
    }

    func test_installStepsForImage() async throws {
        mockDownloadables()
        var didInstall = false
        Current.shell.installRuntimeImage = { _ in
            didInstall = true
            return .value(Shell.processOutputMock)
        }
        try await runtimeInstaller.downloadAndInstallRuntime(identifier: "iOS 16.0", to: .xcodesCaches, with: .urlSession, shouldDelete: true)
        XCTAssertTrue(didInstall)
    }


    func test_deletesArchiveWhenFinished() async throws {
        mockDownloadables()
        var removed = false
        Current.files.removeItem = { itemURL in
            removed = true
        }
        try await runtimeInstaller.downloadAndInstallRuntime(identifier: "iOS 16.0", to: .xcodesCaches, with: .urlSession, shouldDelete: true)
        XCTAssertTrue(removed)
    }

    func test_KeepArchiveWhenFinished() async throws {
        mockDownloadables()
        var removed = false
        Current.files.removeItem = { itemURL in
            removed = true
        }
        try await runtimeInstaller.downloadAndInstallRuntime(identifier: "iOS 16.0", to: .xcodesCaches, with: .urlSession, shouldDelete: false)
        XCTAssertFalse(removed)
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
