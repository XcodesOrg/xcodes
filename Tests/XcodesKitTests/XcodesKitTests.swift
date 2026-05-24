import XCTest
import Version
import Path
@preconcurrency import Rainbow
import XcodesLoginKit
import XcodesKit
import struct XcodesKit.Downloads
import struct XcodesKit.Download
@testable import XcodesCLIKit

private func configureRainbowForTest(outputTarget: OutputTarget, enabled: Bool) {
    Rainbow.outputTarget = outputTarget
    Rainbow.enabled = enabled
}

final class XcodesKitTests: XCTestCase {
    static let mockXcode = Xcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)

    var xcodeList: XcodeList!
    var xcodeInstaller: XcodeInstaller!
    var sessionService: AppleSessionService!

    override func setUp() {
        Current = .mock
        syncXcodesKitMocks()
        configureRainbowForTest(outputTarget: .unknown, enabled: false)
        sessionService = AppleSessionService(configuration: Configuration())
        xcodeList = XcodeList()
        xcodeInstaller = XcodeInstaller(xcodeList: xcodeList, sessionService: sessionService)
    }

    func test_ParseCertificateInfo_Succeeds() throws {
        let sampleRawInfo = """
        Executable=/Applications/Xcode-10.1.app/Contents/MacOS/Xcode
        Identifier=com.apple.dt.Xcode
        Format=app bundle with Mach-O thin (x86_64)
        CodeDirectory v=20200 size=434 flags=0x2000(library-validation) hashes=6+5 location=embedded
        Signature size=4485
        Authority=Software Signing
        Authority=Apple Code Signing Certification Authority
        Authority=Apple Root CA
        Info.plist entries=39
        TeamIdentifier=59GAB85EFG
        Sealed Resources version=2 rules=13 files=253327
        Internal requirements count=1 size=68
        """
        let info = xcodeInstaller.parseCertificateInfo(sampleRawInfo)

        XCTAssertEqual(info.authority, ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"])
        XCTAssertEqual(info.teamIdentifier, "59GAB85EFG")
        XCTAssertEqual(info.bundleIdentifier, "com.apple.dt.Xcode")
    }

    func test_DownloadOrUseExistingArchive_ReturnsExistingArchive() async throws {
        Current.files.fileExistsAtPath = { _ in return true }
        let xcodeDownloadURL = LockedBox<URL?>(nil)
        Current.network.downloadTask = { url, _, _ in
            xcodeDownloadURL.set(url.url)
            return (Progress(), Task { throw URLError(.unknown) })
        }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
        let value = try await xcodeInstaller.downloadOrUseExistingArchive(for: xcode, downloader: .urlSession, willInstall: true, progressChanged: { _ in })
        XCTAssertEqual(value, Path.environmentApplicationSupport.join("com.robotsandpencils.xcodes").join("Xcode-0.0.0.xip").url)
        XCTAssertNil(xcodeDownloadURL.value)
    }

    func test_DownloadOrUseExistingArchive_DownloadsArchive() async throws {
        Current.files.fileExistsAtPath = { _ in return false }
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

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
        let value = try await xcodeInstaller.downloadOrUseExistingArchive(for: xcode, downloader: .urlSession, willInstall: true, progressChanged: { _ in })
        XCTAssertEqual(value, Path.environmentApplicationSupport.join("com.robotsandpencils.xcodes").join("Xcode-0.0.0.xip").url)
        XCTAssertEqual(xcodeDownloadURL.value, URL(string: "https://apple.com/xcode.xip")!)
    }

    func test_InstallLatestPrerelease_WithoutPrereleases_ThrowsNoPrereleaseVersionAvailable() async throws {
        Current.files.contentsAtPath = { _ in nil }
        Current.network.loadData = { request in
            let releases = """
            [
              {
                "name": "Xcode",
                "version": {
                  "number": "1.0",
                  "release": { "release": true }
                },
                "date": { "year": 2020, "month": 1, "day": 1 },
                "requires": "10.15",
                "links": {
                  "download": { "url": "https://apple.com/Xcode.xip" }
                }
              }
            ]
            """
            return (
                data: Data(releases.utf8),
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        do {
            _ = try await xcodeInstaller.install(
                .latestPrerelease,
                dataSource: .xcodeReleases,
                downloader: .urlSession,
                destination: Path.root.join("Applications"),
                emptyTrash: false,
                noSuperuser: true
            )
            XCTFail("Expected latest prerelease install to fail without prereleases")
        } catch {
            XCTAssertEqual(error as? XcodeInstaller.Error, .noPrereleaseVersionAvailable)
        }
    }

    func test_InstallLatest_WithUnsupportedMacOSVersion_WarnsAndContinues() async throws {
        let log = LockedBox("")
        Current.logging.log = { log.append($0 + "\n") }
        Current.shell.codesignVerify = { _ in
            (
                0,
                "",
                """
                TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                """
            )
        }
        Current.network.loadData = { request in
            let releases = """
            [
              {
                "name": "Xcode",
                "version": {
                  "number": "16.0",
                  "release": { "release": true }
                },
                "date": { "year": 2024, "month": 9, "day": 16 },
                "requires": "15.0",
                "links": {
                  "download": { "url": "https://apple.com/Xcode.xip" }
                }
              }
            ]
            """
            return (
                data: Data(releases.utf8),
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        xcodeInstaller = XcodeInstaller(
            xcodeList: xcodeList,
            sessionService: sessionService,
            currentOSVersion: { OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0) }
        )

        _ = try await xcodeInstaller.install(
            .latest,
            dataSource: .xcodeReleases,
            downloader: .urlSession,
            destination: Path.root.join("Applications"),
            emptyTrash: false,
            noSuperuser: true
        )

        XCTAssertTrue(log.value.contains("Warning: Xcode 16.0 requires macOS 15.0 or later. This Mac is running macOS 14.6.0."))
    }

    func test_DownloadLatest_WithUnsupportedMacOSVersion_DoesNotThrow() async throws {
        Current.files.contentsAtPath = { _ in nil }
        Current.files.fileExistsAtPath = { _ in false }
        let downloadedURL = LockedBox<URL?>(nil)
        Current.network.loadData = { request in
            let releases = """
            [
              {
                "name": "Xcode",
                "version": {
                  "number": "16.0",
                  "release": { "release": true }
                },
                "date": { "year": 2024, "month": 9, "day": 16 },
                "requires": "15.0",
                "links": {
                  "download": { "url": "https://apple.com/Xcode.xip" }
                }
              }
            ]
            """
            return (
                data: Data(releases.utf8),
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }
        Current.network.downloadTask = { request, destination, _ in
            downloadedURL.set(request.url)
            return (
                Progress(),
                Task {
                    (destination, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
                }
            )
        }
        xcodeInstaller = XcodeInstaller(
            xcodeList: xcodeList,
            sessionService: sessionService,
            currentOSVersion: { OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0) }
        )

        try await xcodeInstaller.download(
            .latest,
            dataSource: .xcodeReleases,
            downloader: .urlSession,
            destinationDirectory: Path.root.join("Downloads")
        )

        XCTAssertEqual(downloadedURL.value, URL(string: "https://apple.com/Xcode.xip"))
    }

    func test_InstallArchivedXcode_SecurityAssessmentFails_Throws() async {
        Current.shell.spctlAssess = { _ in throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil) }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock", releaseDate: nil)
        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        do {
            _ = try await xcodeInstaller.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), to: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
            XCTFail("Expected install to fail security assessment")
        } catch {
            XCTAssertEqual(error as? XcodeInstaller.Error, XcodeInstaller.Error.failedSecurityAssessment(xcode: installedXcode, output: ""))
        }
    }

    func test_InstallArchivedXcode_VerifySigningCertificateFails_Throws() async {
        Current.shell.codesignVerify = { _ in throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil) }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock", releaseDate: nil)
        do {
            _ = try await xcodeInstaller.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), to: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
            XCTFail("Expected install to fail code signing verification")
        } catch {
            XCTAssertEqual(error as? XcodeInstaller.Error, XcodeInstaller.Error.codesignVerifyFailed(output: ""))
        }
    }

    func test_InstallArchivedXcode_VerifySigningCertificateDoesntMatch_Throws() async {
        Current.shell.codesignVerify = { _ in (0, "", "") }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock", releaseDate: nil)
        do {
            _ = try await xcodeInstaller.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), to: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
            XCTFail("Expected install to fail signing identity check")
        } catch {
            XCTAssertEqual(error as? XcodeInstaller.Error, XcodeInstaller.Error.unexpectedCodeSigningIdentity(identifier: "", certificateAuthority: []))
        }
    }

    func test_InstallArchivedXcode_TrashesXIPWhenFinished() async throws {
        let trashedItemAtURL = LockedBox<URL?>(nil)
        Current.files.trashItem = { itemURL in
            trashedItemAtURL.set(itemURL)
            return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash/\(itemURL.lastPathComponent)")
        }
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                    """)
        }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock", releaseDate: nil)
        let xipURL = URL(fileURLWithPath: "/Xcode-0.0.0.xip")
        _ = try await xcodeInstaller.installArchivedXcode(xcode, at: xipURL, to: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
        XCTAssertEqual(trashedItemAtURL.value, xipURL)
    }

    func test_InstallLogging_FullHappyPath() async throws {
        configureRainbowForTest(outputTarget: .console, enabled: true)

        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { throw AuthenticationError.invalidSession }
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        // It's an available release version
        XcodesCLIKit.Current.network.loadData = { urlRequest in
            if urlRequest.url! == URLRequest.developerDownloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return (data: downloadsData, response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

            return (data: Data(), response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Task {
                // Need this to run after the Task has returned to the caller. This makes the test async, requiring waiting for an expectation.
                await MainActor.run {
                    for i in 0...100 {
                        progress.completedUnitCount = Int64(i)
                    }
                }
                return (saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                    """)
        }
        // Don't have superuser privileges the first time
        let validateSudoAuthenticationCallCount = LockedBox(0)
        XcodesCLIKit.Current.shell.validateSudoAuthentication = {
            if validateSudoAuthenticationCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil)
            }
            else {
                return Shell.processOutputMock
            }
        }
        // User enters password
        XcodesCLIKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesCLIKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesCLIKit.Current.shell.readLine = { prompt in
            XcodesCLIKit.Current.logging.log(prompt)
            return "asdf"
        }

        _ = try await xcodeInstaller.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
        let url = Bundle.module.url(forResource: "LogOutput-FullHappyPath", withExtension: "txt", subdirectory: "Fixtures")!
        XCTAssertEqual(log.value, try String(contentsOf: url))
    }

    func test_InstallLogging_FullHappyPath_NoColor() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { throw AuthenticationError.invalidSession }
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        // It's an available release version
        XcodesCLIKit.Current.network.loadData = { urlRequest in
            if urlRequest.url! == URLRequest.developerDownloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return (data: downloadsData, response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

            return (data: Data(), response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Task {
                // Need this to run after the Task has returned to the caller. This makes the test async, requiring waiting for an expectation.
                await MainActor.run {
                    for i in 0...100 {
                        progress.completedUnitCount = Int64(i)
                    }
                }
                return (saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                    """)
        }
        // Don't have superuser privileges the first time
        let validateSudoAuthenticationCallCount = LockedBox(0)
        XcodesCLIKit.Current.shell.validateSudoAuthentication = {
            if validateSudoAuthenticationCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil)
            }
            else {
                return Shell.processOutputMock
            }
        }
        // User enters password
        XcodesCLIKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesCLIKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesCLIKit.Current.shell.readLine = { prompt in
            XcodesCLIKit.Current.logging.log(prompt)
            return "asdf"
        }

        _ = try await xcodeInstaller.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
        let url = Bundle.module.url(forResource: "LogOutput-FullHappyPath-NoColor", withExtension: "txt", subdirectory: "Fixtures")!
        XCTAssertEqual(log.value, try String(contentsOf: url))
    }

    func test_InstallLogging_FullHappyPath_NonInteractiveTerminal() async throws {
        configureRainbowForTest(outputTarget: .unknown, enabled: false)
        XcodesCLIKit.Current.shell.isatty = { false }

        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { throw AuthenticationError.invalidSession }
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        // It's an available release version
        XcodesCLIKit.Current.network.loadData = { urlRequest in
            if urlRequest.url! == URLRequest.developerDownloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return (data: downloadsData, response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

            return (data: Data(), response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Task {
                // Need this to run after the Task has returned to the caller. This makes the test async, requiring waiting for an expectation.
                await MainActor.run {
                    for i in 0...100 {
                        progress.completedUnitCount = Int64(i)
                    }
                }
                return (saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                    """)
        }
        // Don't have superuser privileges the first time
        let validateSudoAuthenticationCallCount = LockedBox(0)
        XcodesCLIKit.Current.shell.validateSudoAuthentication = {
            if validateSudoAuthenticationCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil)
            }
            else {
                return Shell.processOutputMock
            }
        }
        // User enters password
        XcodesCLIKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesCLIKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesCLIKit.Current.shell.readLine = { prompt in
            XcodesCLIKit.Current.logging.log(prompt)
            return "asdf"
        }

        _ = try await xcodeInstaller.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
        let url = Bundle.module.url(forResource: "LogOutput-FullHappyPath-NonInteractiveTerminal", withExtension: "txt", subdirectory: "Fixtures")!
        XCTAssertEqual(log.value, try String(contentsOf: url))
    }

    func test_InstallLogging_AlternativeDirectory() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { throw AuthenticationError.invalidSession }
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        // It's an available release version
        XcodesCLIKit.Current.network.loadData = { urlRequest in
            if urlRequest.url! == URLRequest.developerDownloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return (data: downloadsData, response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

            return (data: Data(), response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Task {
                // Need this to run after the Task has returned to the caller. This makes the test async, requiring waiting for an expectation.
                await MainActor.run {
                    for i in 0...100 {
                        progress.completedUnitCount = Int64(i)
                    }
                }
                return (saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                    """)
        }
        // Don't have superuser privileges the first time
        let validateSudoAuthenticationCallCount = LockedBox(0)
        XcodesCLIKit.Current.shell.validateSudoAuthentication = {
            if validateSudoAuthenticationCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil)
            }
            else {
                return Shell.processOutputMock
            }
        }
        // User enters password
        XcodesCLIKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesCLIKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesCLIKit.Current.shell.readLine = { prompt in
            XcodesCLIKit.Current.logging.log(prompt)
            return "asdf"
        }

        _ = try await xcodeInstaller.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.home.join("Xcode"), emptyTrash: false, noSuperuser: false)
        let url = Bundle.module.url(forResource: "LogOutput-AlternativeDirectory", withExtension: "txt", subdirectory: "Fixtures")!
        let expectedText = try String(contentsOf: url).replacingOccurrences(of: "/Users/brandon", with: Path.home.string)
        XCTAssertEqual(log.value, expectedText)
    }

    func test_InstallLogging_IncorrectSavedPassword() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { throw AuthenticationError.invalidSession }
        // XCODES_PASSWORD has incorrect password
        let passwordEnvCallCount = LockedBox(0)
        XcodesCLIKit.Current.shell.env = { key in
            if key == "XCODES_PASSWORD" {
                passwordEnvCallCount.increment()
                return "old_password"
            } else {
                return nil
            }
        }
        let loginCallCount = LockedBox(0)
        XcodesCLIKit.Current.network.login = { _, _ in
            if loginCallCount.incrementAfterRead() == 0 {
                throw AuthenticationError.invalidUsernameOrPassword(username: "test@example.com")
            }
        }
        // It hasn't been downloaded
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                return false
            }
            else {
                return true
            }
        }
        // It's an available release version
        XcodesCLIKit.Current.network.loadData = { urlRequest in
            if urlRequest.url! == URLRequest.developerDownloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return (data: downloadsData, response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

            return (data: Data(), response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Task {
                // Need this to run after the Task has returned to the caller. This makes the test async, requiring waiting for an expectation.
                await MainActor.run {
                    for i in 0...100 {
                        progress.completedUnitCount = Int64(i)
                    }
                }
                return (saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                    """)
        }
        // Don't have superuser privileges the first time
        let validateSudoAuthenticationCallCount = LockedBox(0)
        XcodesCLIKit.Current.shell.validateSudoAuthentication = {
            if validateSudoAuthenticationCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil)
            }
            else {
                return Shell.processOutputMock
            }
        }
        // User enters password
        let readSecureLineCallCount = LockedBox(0)
        XcodesCLIKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesCLIKit.Current.logging.log(prompt)
            readSecureLineCallCount.increment()
            return "password"
        }
        // User enters something
        XcodesCLIKit.Current.shell.readLine = { prompt in
            XcodesCLIKit.Current.logging.log(prompt)
            return "test@example.com"
        }

        _ = try await xcodeInstaller.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
        let url = Bundle.module.url(forResource: "LogOutput-IncorrectSavedPassword", withExtension: "txt", subdirectory: "Fixtures")!
        XCTAssertEqual(log.value, try String(contentsOf: url))
        XCTAssertEqual(passwordEnvCallCount.value, 2)
        XCTAssertEqual(readSecureLineCallCount.value, 2)
    }

    func test_InstallLogging_DamagedXIP() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        let validateSessionCallCount = LockedBox(0)
        Current.network.validateSession = {
            if validateSessionCallCount.increment() == 1 {
                throw AuthenticationError.invalidSession
            }
        }
        // It has been downloaded
        let unxipCallCount = LockedBox(0)
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                if unxipCallCount.value == 1 {
                    return false
                } else {
                    return true
                }
            }
            else {
                return true
            }
        }
        // It's an available release version
        XcodesCLIKit.Current.network.loadData = { urlRequest in
            if urlRequest.url! == URLRequest.developerDownloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return (data: downloadsData, response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

            return (data: Data(), response: HTTPURLResponse(url: urlRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Task<(saveLocation: URL, response: URLResponse), Error>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Task {
                // Need this to run after the Task has returned to the caller. This makes the test async, requiring waiting for an expectation.
                await MainActor.run {
                    for i in 0...100 {
                        progress.completedUnitCount = Int64(i)
                    }
                }
                return (saveLocation: saveLocation,
                        response: HTTPURLResponse(url: url.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            ProcessOutput(
                status: 0,
                out: "",
                err: """
                    TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                    Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                    """)
        }
        // Don't have superuser privileges the first time
        let validateSudoAuthenticationCallCount = LockedBox(0)
        Current.shell.validateSudoAuthentication = {
            if validateSudoAuthenticationCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil)
            }
            else {
                return Shell.processOutputMock
            }
        }
        // User enters password
        Current.shell.readSecureLine = { prompt, _ in
            XcodesCLIKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesCLIKit.Current.shell.readLine = { prompt in
            XcodesCLIKit.Current.logging.log(prompt)
            return "asdf"
        }
        Current.shell.unxip = { _ in
            if unxipCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: "The file \"Xcode-0.0.0.xip\" is damaged and can’t be expanded.")
            } else {
                return Shell.processOutputMock
            }
        }

        _ = try await xcodeInstaller.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"), emptyTrash: false, noSuperuser: false)
        let url = Bundle.module.url(forResource: "LogOutput-DamagedXIP", withExtension: "txt", subdirectory: "Fixtures")!
        let expectedText = try String(contentsOf: url).replacingOccurrences(of: "/Users/brandon", with: Path.home.string)
        XCTAssertEqual(log.value, expectedText)
    }

    func test_UninstallXcode() async throws {
        // There are installed Xcodes
        let installedXcodes = [
            InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!,
            InstalledXcode(path: Path("/Applications/Xcode-2.0.0.app")!)!,
            InstalledXcode(path: Path("/Applications/Xcode-2.0.1.app")!)!
        ]
        Current.files.installedXcodes = { _ in installedXcodes }
        Current.files.contentsAtPath = { path in
            if path == "/Applications/Xcode-0.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-0.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.1.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.1.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else {
                return nil
            }
        }
        // The one that's going to be deleted is selected
        Current.shell.xcodeSelectPrintPath = {
            (status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: "")
        }
        // Trashing succeeds
        let trashedItemAtURL = LockedBox<URL?>(nil)
        Current.files.trashItem = { itemURL in
            trashedItemAtURL.set(itemURL)
            return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash/\(itemURL.lastPathComponent)")
        }
        // Switching succeeds
        let selectedPaths = LockedBox<[String]>([])
        Current.shell.xcodeSelectSwitch = { password, path in
            selectedPaths.append(path)
            return (status: 0, out: "", err: "")
        }

        try await xcodeInstaller.uninstallXcode("0.0.0", directory: Path.root.join("Applications"), emptyTrash: false)
        XCTAssertEqual(selectedPaths.value, [])
        XCTAssertEqual(trashedItemAtURL.value, installedXcodes[0].path.url)
    }

    func test_UninstallInteractively() async throws {

        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // There are installed Xcodes
        let installedXcodes = [
            InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!, version: Version(0, 0, 0)),
            InstalledXcode(path: Path("/Applications/Xcode-2.0.1.app")!, version: Version(2, 0, 1)),
        ]
        Current.files.installedXcodes = { _ in installedXcodes }

        // It prints the expected paths
        let xcodeSelectPrintPathCallCount = LockedBox(0)
        Current.shell.xcodeSelectPrintPath = {
            if xcodeSelectPrintPathCallCount.increment() == 1 {
                return (status: 0, out: "/Applications/Xcode-2.0.1.app/Contents/Developer", err: "")
            }
            else {
                return (status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: "")
            }
        }

        // User enters an index
        XcodesCLIKit.Current.shell.readLine = { prompt in
            XcodesCLIKit.Current.logging.log(prompt)
            return "1"
        }

        // Trashing succeeds
        let trashedItemAtURL = LockedBox<URL?>(nil)
        Current.files.trashItem = { itemURL in
            trashedItemAtURL.set(itemURL)
            return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash/\(itemURL.lastPathComponent)")
        }

        try await xcodeInstaller.uninstallXcode("999", directory: Path.root.join("Applications"), emptyTrash: false)
        XCTAssertEqual(trashedItemAtURL.value, installedXcodes[0].path.url)

        XCTAssertEqual(log.value, """
        999.0 is not installed.
        Available Xcode versions:
        1) 0.0
        2) 2.0.1
        Enter the number of the Xcode to select: 
        Xcode 0.0 moved to Trash: \(NSHomeDirectory())/.Trash/Xcode-0.0.0.app

        """)
    }

    func test_VerifySecurityAssessment_Fails() async {
        Current.shell.spctlAssess = { _ in throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil) }

        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        do {
            try await xcodeInstaller.verifySecurityAssessment(of: installedXcode)
            XCTFail("Expected security assessment to fail")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func test_VerifySecurityAssessment_Succeeds() async throws {
        Current.shell.spctlAssess = { _ in (0, "", "") }

        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        try await xcodeInstaller.verifySecurityAssessment(of: installedXcode)
    }

    func test_MigrateApplicationSupport_NoSupportFiles() {
        Current.files.fileExistsAtPath = { _ in return false }
        let source = LockedBox<URL?>(nil)
        let destination = LockedBox<URL?>(nil)
        Current.files.moveItem = { source.set($0); destination.set($1) }
        let removedItemAtURL = LockedBox<URL?>(nil)
        Current.files.removeItem = { removedItemAtURL.set($0) }

        migrateApplicationSupportFiles()

        XCTAssertNil(source.value)
        XCTAssertNil(destination.value)
        XCTAssertNil(removedItemAtURL.value)
    }

    func test_MigrateApplicationSupport_OnlyOldSupportFiles() {
        Current.files.fileExistsAtPath = { return $0.contains("ca.brandonevans") }
        let source = LockedBox<URL?>(nil)
        let destination = LockedBox<URL?>(nil)
        Current.files.moveItem = { source.set($0); destination.set($1) }
        let removedItemAtURL = LockedBox<URL?>(nil)
        Current.files.removeItem = { removedItemAtURL.set($0) }

        migrateApplicationSupportFiles()

        XCTAssertEqual(source.value, Path.environmentApplicationSupport.join("ca.brandonevans.xcodes").url)
        XCTAssertEqual(destination.value, Path.environmentApplicationSupport.join("com.robotsandpencils.xcodes").url)
        XCTAssertNil(removedItemAtURL.value)
    }

    func test_MigrateApplicationSupport_OldAndNewSupportFiles() {
        Current.files.fileExistsAtPath = { _ in return true }
        let source = LockedBox<URL?>(nil)
        let destination = LockedBox<URL?>(nil)
        Current.files.moveItem = { source.set($0); destination.set($1) }
        let removedItemAtURL = LockedBox<URL?>(nil)
        Current.files.removeItem = { removedItemAtURL.set($0) }

        migrateApplicationSupportFiles()

        XCTAssertNil(source.value)
        XCTAssertNil(destination.value)
        XCTAssertEqual(removedItemAtURL.value, Path.environmentApplicationSupport.join("ca.brandonevans.xcodes").url)
    }

    func test_MigrateApplicationSupport_OnlyNewSupportFiles() {
        Current.files.fileExistsAtPath = { return $0.contains("com.robotsandpencils") }
        let source = LockedBox<URL?>(nil)
        let destination = LockedBox<URL?>(nil)
        Current.files.moveItem = { source.set($0); destination.set($1) }
        let removedItemAtURL = LockedBox<URL?>(nil)
        Current.files.removeItem = { removedItemAtURL.set($0) }

        migrateApplicationSupportFiles()

        XCTAssertNil(source.value)
        XCTAssertNil(destination.value)
        XCTAssertNil(removedItemAtURL.value)
    }

    func test_ParsePrereleaseXcodes() {
        let url = Bundle.module.url(forResource: "developer.apple.com-download-19-6-9", withExtension: "html", subdirectory: "Fixtures")!
        let data = try! Data(contentsOf: url)

        let xcodes = try! XcodeList().parsePrereleaseXcodes(from: data)

        XCTAssertEqual(xcodes.count, 1)
        XCTAssertEqual(xcodes[0].version, Version("11.0.0-beta+11M336W"))
    }

    func test_SelectPrint() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        Current.files.installedXcodes = { _ in
            [InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!,
             InstalledXcode(path: Path("/Applications/Xcode-2.0.0.app")!)!]
        }

        Current.shell.xcodeSelectPrintPath = { (status: 0, out: "/Applications/Xcode-2.0.0.app/Contents/Developer", err: "") }

        try await selectXcodeAsync(shouldPrint: true, pathOrVersion: "", directory: Path.root.join("Applications"))

        XCTAssertEqual(log.value, """
        /Applications/Xcode-2.0.0.app/Contents/Developer

        """)
    }

    func test_SelectPath() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // There are installed Xcodes
        Current.files.installedXcodes = { _ in
            [InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!,
             InstalledXcode(path: Path("/Applications/Xcode-2.0.1.app")!)!]
        }
        Current.files.contentsAtPath = { path in
            if path == "/Applications/Xcode-0.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-0.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.1.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.1.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else {
                return nil
            }
        }
        // It prints the expected paths
        let xcodeSelectPrintPathCallCount = LockedBox(0)
        Current.shell.xcodeSelectPrintPath = {
            if xcodeSelectPrintPathCallCount.increment() == 1 {
                return (status: 0, out: "/Applications/Xcode-2.0.1.app/Contents/Developer", err: "")
            }
            else {
                return (status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: "")
            }
        }
        // Don't have superuser privileges the first time
        let validateSudoAuthenticationCallCount = LockedBox(0)
        Current.shell.validateSudoAuthentication = {
            if validateSudoAuthenticationCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil)
            }
            else {
                return Shell.processOutputMock
            }
        }
        // User enters password
        Current.shell.readSecureLine = { prompt, _ in
            XcodesCLIKit.Current.logging.log(prompt)
            return "password"
        }
        // It successfully switches
        Current.shell.xcodeSelectSwitch = { _, _ in
            (status: 0, out: "", err: "")
        }

        try await selectXcodeAsync(shouldPrint: false, pathOrVersion: "/Applications/Xcode-0.0.0.app", directory: Path.root.join("Applications"))

        XCTAssertEqual(log.value, """
        xcodes requires superuser privileges to select an Xcode
        macOS User Password: 
        Selected /Applications/Xcode-0.0.0.app/Contents/Developer

        """)
    }

    func test_SelectInteractively() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // There are installed Xcodes
        Current.files.installedXcodes = { _ in
            [InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!,
             InstalledXcode(path: Path("/Applications/Xcode-2.0.1.app")!)!]
        }
        Current.files.contentsAtPath = { path in
            if path == "/Applications/Xcode-0.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-0.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.1.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.1.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else {
                return nil
            }
        }
        Current.files.fileExistsAtPath = { path in
            if path == "" {
                return false
            }
            return true
        }
        // It prints the expected paths
        let xcodeSelectPrintPathCallCount = LockedBox(0)
        Current.shell.xcodeSelectPrintPath = {
            if xcodeSelectPrintPathCallCount.increment() == 1 {
                return (status: 0, out: "/Applications/Xcode-2.0.1.app/Contents/Developer", err: "")
            }
            else {
                return (status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: "")
            }
        }
        // User enters an index
        XcodesCLIKit.Current.shell.readLine = { prompt in
            XcodesCLIKit.Current.logging.log(prompt)
            return "1"
        }
        // Don't have superuser privileges the first time
        let validateSudoAuthenticationCallCount = LockedBox(0)
        Current.shell.validateSudoAuthentication = {
            if validateSudoAuthenticationCallCount.increment() == 1 {
                throw ProcessExecutionError(process: Process(), standardOutput: nil, standardError: nil)
            }
            else {
                return Shell.processOutputMock
            }
        }
        // User enters password
        Current.shell.readSecureLine = { prompt, _ in
            XcodesCLIKit.Current.logging.log(prompt)
            return "password"
        }
        // It successfully switches
        Current.shell.xcodeSelectSwitch = { _, _ in
            (status: 0, out: "", err: "")
        }

        try await selectXcodeAsync(shouldPrint: false, pathOrVersion: "", directory: Path.root.join("Applications"))

        XCTAssertEqual(log.value, """
        Available Xcode versions:
        1) 0.0 (ABC123)
        2) 2.0.1 (ABC123) (Selected)
        Enter the number of the Xcode to select: 
        xcodes requires superuser privileges to select an Xcode
        macOS User Password: 
        Selected /Applications/Xcode-0.0.0.app/Contents/Developer

        """)
    }

    func test_SelectUsingXcodeVersionFile() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // There are installed Xcodes
        Current.files.installedXcodes = { _ in
            [InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!,
             InstalledXcode(path: Path("/Applications/Xcode-2.0.1.app")!)!]
        }
        Current.files.contentsAtPath = { path in
            if path == "/Applications/Xcode-0.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-0.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.1.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.1.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.hasSuffix(".xcode-version") {
                return "2.0.1\n".data(using: .utf8)
            }
            else {
                return nil
            }
        }
        Current.files.fileExistsAtPath = { path in
            if path == "" {
                return false
            }
            return true
        }
        // It prints the expected paths
        let xcodeSelectPrintPathCallCount = LockedBox(0)
        Current.shell.xcodeSelectPrintPath = {
            switch xcodeSelectPrintPathCallCount.incrementAfterRead() {
            case 0:
                return (status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: "")
            case 1:
                return (status: 0, out: "/Applications/Xcode-2.0.1.app/Contents/Developer", err: "")
            default:
                fatalError("Unexpected third invocation of xcode select")
            }
        }
        // It successfully switches
        Current.shell.xcodeSelectSwitch = { _, _ in
            (status: 0, out: "", err: "")
        }

        try await selectXcodeAsync(shouldPrint: false, pathOrVersion: "", directory: Path.root.join("Applications"))

        XCTAssertEqual(log.value, """
        Selected /Applications/Xcode-2.0.1.app/Contents/Developer

        """)
    }
    
    func test_Installed_InteractiveTerminal() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // There are installed Xcodes
        Current.files.contentsAtPath = { path in
            if path == "/Applications/Xcode-0.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-0.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.1-Release.Candidate.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.1.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else {
                return nil
            }
        }
        let installedXcodes = [
            InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!,
            InstalledXcode(path: Path("/Applications/Xcode-2.0.0.app")!)!,
            InstalledXcode(path: Path("/Applications/Xcode-2.0.1-Release.Candidate.app")!)!
        ]
        Current.files.installedXcodes = { _ in installedXcodes }

        // One is selected
        Current.shell.xcodeSelectPrintPath = {
            (status: 0, out: "/Applications/Xcode-2.0.1-Release.Candidate.app/Contents/Developer", err: "")
        }

        // Standard output is an interactive terminal
        Current.shell.isatty = { true }

        try await xcodeInstaller.printInstalledXcodes(directory: Path.root/"Applications")

        XCTAssertEqual(
            log.value,
            """
            0.0 (ABC123)                                /Applications/Xcode-0.0.0.app
            2.0 (ABC123)                                /Applications/Xcode-2.0.0.app
            2.0.1 Release Candidate (ABC123) (Selected) /Applications/Xcode-2.0.1-Release.Candidate.app

            """
        )
    }

    func test_Installed_NonInteractiveTerminal() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // There are installed Xcodes
        Current.files.contentsAtPath = { path in
            if path == "/Applications/Xcode-0.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-0.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path == "/Applications/Xcode-2.0.1-Release.Candidate.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.1.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else {
                return nil
            }
        }
        let installedXcodes = [
            InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!,
            InstalledXcode(path: Path("/Applications/Xcode-2.0.0.app")!)!,
            InstalledXcode(path: Path("/Applications/Xcode-2.0.1-Release.Candidate.app")!)!
        ]
        Current.files.installedXcodes = { _ in installedXcodes }

        // One is selected
        Current.shell.xcodeSelectPrintPath = {
            (status: 0, out: "/Applications/Xcode-2.0.0.app/Contents/Developer", err: "")
        }

        // Standard output is not an interactive terminal
        Current.shell.isatty = { false }

        try await xcodeInstaller.printInstalledXcodes(directory: Path.root/"Applications")

        XCTAssertEqual(
            log.value,
            """
            0.0 (ABC123)\t/Applications/Xcode-0.0.0.app
            2.0 (ABC123) (Selected)\t/Applications/Xcode-2.0.0.app
            2.0.1 Release Candidate (ABC123)\t/Applications/Xcode-2.0.1-Release.Candidate.app

            """
        )
    }

    func test_Installed_WithValidVersion_PrintsXcodePath() async throws {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // There are installed Xcodes
        Current.files.contentsAtPath = { path in
            if path == "/Applications/Xcode-2.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else {
                return nil
            }
        }
        let installedXcodes = [
            InstalledXcode(path: Path("/Applications/Xcode-2.0.0.app")!)!,
        ]
        Current.files.installedXcodes = { _ in installedXcodes }

        // One is selected
        Current.shell.xcodeSelectPrintPath = {
            (status: 0, out: "/Applications/Xcode-2.0.0.app/Contents/Developer", err: "")
        }

        // Standard output is not an interactive terminal
        Current.shell.isatty = { false }

        try await xcodeInstaller.printXcodePath(ofVersion: "2", searchingIn: Path.root/"Applications")

        XCTAssertEqual(
            log.value,
            """
            /Applications/Xcode-2.0.0.app

            """
        )
    }

    func test_Installed_WithUninstalledVersion_ThrowsError() async {
        let log = LockedBox("")
        XcodesCLIKit.Current.logging.log = { log.append($0 + "\n") }

        // There are installed Xcodes
        Current.files.contentsAtPath = { path in
            if path == "/Applications/Xcode-2.0.0.app/Contents/Info.plist" {
                let url = Bundle.module.url(forResource: "Stub-2.0.0.Info", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else if path.contains("version.plist") {
                let url = Bundle.module.url(forResource: "Stub.version", withExtension: "plist", subdirectory: "Fixtures")!
                return try? Data(contentsOf: url)
            }
            else {
                return nil
            }
        }
        let installedXcodes = [
            InstalledXcode(path: Path("/Applications/Xcode-2.0.0.app")!)!,
        ]
        Current.files.installedXcodes = { _ in installedXcodes }

        // One is selected
        Current.shell.xcodeSelectPrintPath = {
            (status: 0, out: "/Applications/Xcode-2.0.0.app/Contents/Developer", err: "")
        }

        // Standard output is not an interactive terminal
        Current.shell.isatty = { false }

        do {
            try await xcodeInstaller.printXcodePath(ofVersion: "3", searchingIn: Path.root/"Applications")
            XCTFail("Expected uninstalled version to throw")
        } catch {
            XCTAssertEqual(error as? XcodeInstaller.Error, XcodeInstaller.Error.versionNotInstalled(Version(xcodeVersion: "3")!))
        }
    }

    func test_Signout_WithExistingSession() async throws {
        let keychainDidRemove = LockedBox(false)
        Current.keychain.remove = { _ in
            keychainDidRemove.set(true)
        }

        var customConfig = Configuration()
        customConfig.defaultUsername = "test@example.com"
        let customService = AppleSessionService(configuration: customConfig)

        try await customService.logout()

        XCTAssertTrue(keychainDidRemove.value)
    }

    func test_Signout_WithoutExistingSession() async {
        var customConfig = Configuration()
        customConfig.defaultUsername = nil
        let customService = AppleSessionService(configuration: customConfig)

        do {
            try await customService.logout()
            XCTFail("Expected signout to fail without an existing session")
        } catch {
            XCTAssertEqual(error as? AppleSessionService.Error, AppleSessionService.Error.notAuthenticated)
        }
    }

    func test_Signout_RemovesCookiesFromDownloadSession() async throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "developer.apple.com",
            .path: "/",
            .name: "ADCDownloadAuth",
            .value: "test",
            .secure: "TRUE"
        ]))
        Current.network.session.configuration.httpCookieStorage?.setCookie(cookie)

        XCTAssertEqual(Current.network.session.configuration.httpCookieStorage?.cookies?.contains(cookie), true)

        await Current.network.signout()

        XCTAssertEqual(Current.network.session.configuration.httpCookieStorage?.cookies?.contains(cookie), false)
    }

    func test_Signout_RemovesCookiesAfterDownloadSessionIsReplaced() async throws {
        Current.network.session = URLSession(configuration: .ephemeral)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "developer.apple.com",
            .path: "/",
            .name: "FASTLANE_SESSION",
            .value: "test",
            .secure: "TRUE"
        ]))
        Current.network.session.configuration.httpCookieStorage?.setCookie(cookie)

        XCTAssertEqual(Current.network.session.configuration.httpCookieStorage?.cookies?.contains(cookie), true)

        await Current.network.signout()

        XCTAssertEqual(Current.network.session.configuration.httpCookieStorage?.cookies?.contains(cookie), false)
    }

    func test_XcodeList_ShouldUpdate_NotWhenCacheFileIsRecent() {
        Current.files.contentsAtPath = { _ in try! JSONEncoder().encode([Self.mockXcode]) }
        Current.files.attributesOfItemAtPath = { _ in [.modificationDate: Date(timeIntervalSinceNow: -3600)] }

        let xcodesList = XcodeList()

        XCTAssertFalse(xcodesList.shouldUpdateBeforeListingVersions)
    }

    func test_XcodeList_ShouldUpdate_WhenCacheFileIsOld() {
        Current.files.contentsAtPath = { _ in try! JSONEncoder().encode([Self.mockXcode]) }
        Current.files.attributesOfItemAtPath = { _ in [.modificationDate: Date(timeIntervalSinceNow: -3600*6)] }

        let xcodesList = XcodeList()

        XCTAssertTrue(xcodesList.shouldUpdateBeforeListingVersions)
    }

    func test_XcodeList_ShouldUpdate_WhenCacheFileIsMissing() {
        Current.files.contentsAtPath = { _ in nil }

        let xcodesList = XcodeList()

        XCTAssertTrue(xcodesList.shouldUpdateBeforeListingVersions)
    }

    func test_XcodeList_ShouldUpdate_WhenCacheFileIsEmpty() {
        Current.files.contentsAtPath = { _ in "[]".data(using: .utf8) }

        let xcodesList = XcodeList()

        XCTAssertTrue(xcodesList.shouldUpdateBeforeListingVersions)
    }

    func test_XcodeList_ShouldUpdate_WhenCacheFileIsCorrupt() {
        Current.files.contentsAtPath = { _ in "[".data(using: .utf8) }

        let xcodesList = XcodeList()

        XCTAssertTrue(xcodesList.shouldUpdateBeforeListingVersions)
    }

    func test_XcodeList_LoadsCacheEvenIfAttributesFailToLoad() {
        Current.files.contentsAtPath = { _ in try! JSONEncoder().encode([Self.mockXcode]) }
        Current.files.attributesOfItemAtPath = { _ in throw NSError(domain: "com.robotsandpencils.xcodes", code: 0) }

        let xcodesList = XcodeList()

        XCTAssert(xcodesList.availableXcodes == [Self.mockXcode])
    }

}
