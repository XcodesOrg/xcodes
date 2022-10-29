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
//        Rainbow.outputTarget = .unknown
//        Rainbow.enabled = false
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

    func test_installedRuntimes() async throws {
        Current.shell.installedRuntimes = {
            let url = Bundle.module.url(forResource: "ShellOutput-InstalledRuntimes", withExtension: "json", subdirectory: "Fixtures")!
            return Promise.value((0, try! String(contentsOf: url), ""))
        }
        let values = try await runtimeList.installedRuntimes()
        let givenIDs = [
            UUID(uuidString: "2A6068A0-7FCF-4DB9-964D-21145EB98498")!,
            UUID(uuidString: "6DE6B631-9439-4737-A65B-73F675EB77D1")!,
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
        XCTAssertEqual(values.count, 57)
    }

    func test_downloadableRuntimesNoBetas() async throws {
        mockDownloadables()
        let values = try await runtimeList.downloadableRuntimes(includeBetas: false)
        XCTAssertFalse(values.contains { $0.name.lowercased().contains("beta") })
        XCTAssertEqual(values.count, 45)
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

    func test_DownloadOrUseExistingArchive_ReturnsExistingArchive() async throws {
        Current.files.fileExistsAtPath = { _ in return true }
        mockDownloadables()
        let runtime = try await runtimeList.downloadableRuntimes().first { $0.visibleIdentifier == "iOS 14.5" }!
        var xcodeDownloadURL: URL?
        Current.network.downloadTask = { url, _, _ in
            xcodeDownloadURL = url.pmkRequest.url
            return (Progress(), Promise(error: PMKError.invalidCallingConvention))
        }

        let url = try await runtimeInstaller.downloadOrUseExistingArchive(runtime: runtime, to: .xcodesApplicationSupport, downloader: .urlSession)
        let fileName = URL(string: runtime.source)!.lastPathComponent
        XCTAssertEqual(url, Path.xcodesApplicationSupport.join(fileName).url)
        XCTAssertNil(xcodeDownloadURL)
    }

    func test_DownloadOrUseExistingArchive_DownloadsArchive() async throws {
        Current.files.fileExistsAtPath = { _ in return false }
        mockDownloadables()
        var xcodeDownloadURL: URL?
        Current.network.downloadTask = { url, destination, _ in
            xcodeDownloadURL = url.pmkRequest.url
            return (Progress(), Promise.value((destination, HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)))
        }
        let runtime = try await runtimeList.downloadableRuntimes().first { $0.visibleIdentifier == "iOS 14.5" }!
        let fileName = URL(string: runtime.source)!.lastPathComponent
        let url = try await runtimeInstaller.downloadOrUseExistingArchive(runtime: runtime, to: .xcodesApplicationSupport, downloader: .urlSession)
        XCTAssertEqual(url, Path.xcodesApplicationSupport.join(fileName).url)
        XCTAssertEqual(xcodeDownloadURL, URL(string: runtime.source)!)
    }
}
