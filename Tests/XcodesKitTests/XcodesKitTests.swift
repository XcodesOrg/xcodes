import XCTest
import Version
import PromiseKit
import PMKFoundation
import Path
import AppleAPI
import Rainbow
@testable import XcodesKit

final class XcodesKitTests: XCTestCase {
    var installer: XcodeInstaller!

    override class func setUp() {
        super.setUp()
        PromiseKit.conf.Q.map = nil
        PromiseKit.conf.Q.return = nil
    }

    override func setUp() {
        Current = .mock
        Rainbow.outputTarget = .unknown
        Rainbow.enabled = false
        installer = XcodeInstaller(configuration: Configuration(), xcodeList: XcodeList())
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
        let info = installer.parseCertificateInfo(sampleRawInfo)

        XCTAssertEqual(info.authority, ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"])
        XCTAssertEqual(info.teamIdentifier, "59GAB85EFG")
        XCTAssertEqual(info.bundleIdentifier, "com.apple.dt.Xcode")
    }

    func test_DownloadOrUseExistingArchive_ReturnsExistingArchive() {
        Current.files.fileExistsAtPath = { _ in return true }
        var xcodeDownloadURL: URL?
        Current.network.downloadTask = { url, _, _ in
            xcodeDownloadURL = url.pmkRequest.url
            return (Progress(), Promise(error: PMKError.invalidCallingConvention))
        }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
        installer.downloadOrUseExistingArchive(for: xcode, downloader: .urlSession, willInstall: true, progressChanged: { _ in })
            .tap { result in
                guard case .fulfilled(let value) = result else { XCTFail("downloadOrUseExistingArchive rejected."); return }
                XCTAssertEqual(value, Path.applicationSupport.join("com.robotsandpencils.xcodes").join("Xcode-0.0.0.xip").url)
                XCTAssertNil(xcodeDownloadURL)
            }
            .cauterize()
    }

    func test_DownloadOrUseExistingArchive_DownloadsArchive() {
        Current.files.fileExistsAtPath = { _ in return false }
        var xcodeDownloadURL: URL?
        Current.network.downloadTask = { url, destination, _ in
            xcodeDownloadURL = url.pmkRequest.url
            return (Progress(), Promise.value((destination, HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)))
        }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(string: "https://apple.com/xcode.xip")!, filename: "mock.xip", releaseDate: nil)
        installer.downloadOrUseExistingArchive(for: xcode, downloader: .urlSession, willInstall: true, progressChanged: { _ in })
            .tap { result in
                guard case .fulfilled(let value) = result else { XCTFail("downloadOrUseExistingArchive rejected."); return }
                XCTAssertEqual(value, Path.applicationSupport.join("com.robotsandpencils.xcodes").join("Xcode-0.0.0.xip").url)
                XCTAssertEqual(xcodeDownloadURL, URL(string: "https://apple.com/xcode.xip")!)
            }
            .cauterize()
    }

    func test_InstallArchivedXcode_SecurityAssessmentFails_Throws() {
        Current.shell.spctlAssess = { _ in return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil)) }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock", releaseDate: nil)
        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), to: Path.root.join("Applications"))
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.failedSecurityAssessment(xcode: installedXcode, output: "")) }
    }

    func test_InstallArchivedXcode_VerifySigningCertificateFails_Throws() {
        Current.shell.codesignVerify = { _ in return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil)) }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock", releaseDate: nil)
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), to: Path.root.join("Applications"))
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.codesignVerifyFailed(output: "")) }
    }

    func test_InstallArchivedXcode_VerifySigningCertificateDoesntMatch_Throws() {
        Current.shell.codesignVerify = { _ in return Promise.value((0, "", "")) }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock", releaseDate: nil)
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), to: Path.root.join("Applications"))
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.unexpectedCodeSigningIdentity(identifier: "", certificateAuthority: [])) }
    }

    func test_InstallArchivedXcode_TrashesXIPWhenFinished() {
        var trashedItemAtURL: URL?
        Current.files.trashItem = { itemURL in
            trashedItemAtURL = itemURL
            return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash/\(itemURL.lastPathComponent)")
        }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock", releaseDate: nil)
        let xipURL = URL(fileURLWithPath: "/Xcode-0.0.0.xip")
        installer.installArchivedXcode(xcode, at: xipURL, to: Path.root.join("Applications"))
            .ensure { XCTAssertEqual(trashedItemAtURL, xipURL) }
            .cauterize()
    }

    func test_InstallLogging_FullHappyPath() {
        Rainbow.outputTarget = .console
        Rainbow.enabled = true

        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { Promise(error: AppleAPI.Client.Error.invalidSession) }
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
        XcodesKit.Current.network.dataTask = { url in
            if url.pmkRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return Promise.value((data: downloadsData, response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
            }

            return Promise.value((data: Data(), response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Promise { resolver in
                        // Need this to run after the Promise has returned to the caller. This makes the test async, requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for i in 0...100 {
                                progress.completedUnitCount = Int64(i)
                            }
                            resolver.fulfill((saveLocation: saveLocation,
                                              response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                        }
                    })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            return Promise.value(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                        """))
        }
        // Don't have superuser privileges the first time
        var validateSudoAuthenticationCallCount = 0
        XcodesKit.Current.shell.validateSudoAuthentication = {
            validateSudoAuthenticationCallCount += 1

            if validateSudoAuthenticationCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil))
            }
            else {
                return Promise.value(Shell.processOutputMock)
            }
        }
        // User enters password
        XcodesKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesKit.Current.shell.readLine = { prompt in
            XcodesKit.Current.logging.log(prompt)
            return "asdf"
        }

        let expectation = self.expectation(description: "Finished")

        installer.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"))
            .ensure {
                let url = Bundle.module.url(forResource: "LogOutput-FullHappyPath", withExtension: "txt", subdirectory: "Fixtures")!
                XCTAssertEqual(log, try! String(contentsOf: url))
                expectation.fulfill()
            }
            .catch {
                XCTFail($0.localizedDescription)
            }

        waitForExpectations(timeout: 1.0)
    }
    
    func test_InstallLogging_FullHappyPath_NoColor() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { Promise(error: AppleAPI.Client.Error.invalidSession) }
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
        XcodesKit.Current.network.dataTask = { url in
            if url.pmkRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return Promise.value((data: downloadsData, response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
            }

            return Promise.value((data: Data(), response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Promise { resolver in
                        // Need this to run after the Promise has returned to the caller. This makes the test async, requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for i in 0...100 {
                                progress.completedUnitCount = Int64(i)
                            }
                            resolver.fulfill((saveLocation: saveLocation,
                                              response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                        }
                    })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            return Promise.value(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                        """))
        }
        // Don't have superuser privileges the first time
        var validateSudoAuthenticationCallCount = 0
        XcodesKit.Current.shell.validateSudoAuthentication = {
            validateSudoAuthenticationCallCount += 1

            if validateSudoAuthenticationCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil))
            }
            else {
                return Promise.value(Shell.processOutputMock)
            }
        }
        // User enters password
        XcodesKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesKit.Current.shell.readLine = { prompt in
            XcodesKit.Current.logging.log(prompt)
            return "asdf"
        }

        let expectation = self.expectation(description: "Finished")

        installer.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"))
            .ensure {
                let url = Bundle.module.url(forResource: "LogOutput-FullHappyPath-NoColor", withExtension: "txt", subdirectory: "Fixtures")!
                XCTAssertEqual(log, try! String(contentsOf: url))
                expectation.fulfill()
            }
            .catch {
                XCTFail($0.localizedDescription)
            }

        waitForExpectations(timeout: 1.0)
    }
    
    func test_InstallLogging_FullHappyPath_NonInteractiveTerminal() {
        Rainbow.outputTarget = .unknown
        Rainbow.enabled = false
        XcodesKit.Current.shell.isatty = { false }

        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { Promise(error: AppleAPI.Client.Error.invalidSession) }
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
        XcodesKit.Current.network.dataTask = { url in
            if url.pmkRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return Promise.value((data: downloadsData, response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
            }

            return Promise.value((data: Data(), response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Promise { resolver in
                        // Need this to run after the Promise has returned to the caller. This makes the test async, requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for i in 0...100 {
                                progress.completedUnitCount = Int64(i)
                            }
                            resolver.fulfill((saveLocation: saveLocation,
                                              response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                        }
                    })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            return Promise.value(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                        """))
        }
        // Don't have superuser privileges the first time
        var validateSudoAuthenticationCallCount = 0
        XcodesKit.Current.shell.validateSudoAuthentication = {
            validateSudoAuthenticationCallCount += 1

            if validateSudoAuthenticationCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil))
            }
            else {
                return Promise.value(Shell.processOutputMock)
            }
        }
        // User enters password
        XcodesKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesKit.Current.shell.readLine = { prompt in
            XcodesKit.Current.logging.log(prompt)
            return "asdf"
        }

        let expectation = self.expectation(description: "Finished")

        installer.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"))
            .ensure {
                let url = Bundle.module.url(forResource: "LogOutput-FullHappyPath-NonInteractiveTerminal", withExtension: "txt", subdirectory: "Fixtures")!
                XCTAssertEqual(log, try! String(contentsOf: url))
                expectation.fulfill()
            }
            .catch {
                XCTFail($0.localizedDescription)
            }

        waitForExpectations(timeout: 1.0)
    }
    
    func test_InstallLogging_AlternativeDirectory() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { Promise(error: AppleAPI.Client.Error.invalidSession) }
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
        XcodesKit.Current.network.dataTask = { url in
            if url.pmkRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return Promise.value((data: downloadsData, response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
            }

            return Promise.value((data: Data(), response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Promise { resolver in
                        // Need this to run after the Promise has returned to the caller. This makes the test async, requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for i in 0...100 {
                                progress.completedUnitCount = Int64(i)
                            }
                            resolver.fulfill((saveLocation: saveLocation,
                                              response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                        }
                    })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            return Promise.value(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                        """))
        }
        // Don't have superuser privileges the first time
        var validateSudoAuthenticationCallCount = 0
        XcodesKit.Current.shell.validateSudoAuthentication = {
            validateSudoAuthenticationCallCount += 1

            if validateSudoAuthenticationCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil))
            }
            else {
                return Promise.value(Shell.processOutputMock)
            }
        }
        // User enters password
        XcodesKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesKit.Current.shell.readLine = { prompt in
            XcodesKit.Current.logging.log(prompt)
            return "asdf"
        }

        let expectation = self.expectation(description: "Finished")

        installer.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.home.join("Xcode"))
            .ensure {
                let url = Bundle.module.url(forResource: "LogOutput-AlternativeDirectory", withExtension: "txt", subdirectory: "Fixtures")!
                let expectedText = try! String(contentsOf: url).replacingOccurrences(of: "/Users/brandon", with: Path.home.string)
                XCTAssertEqual(log, expectedText)
                expectation.fulfill()
            }
            .catch {
                XCTFail($0.localizedDescription)
            }

        waitForExpectations(timeout: 1.0)
    }
    
    func test_InstallLogging_IncorrectSavedPassword() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        Current.network.validateSession = { Promise(error: AppleAPI.Client.Error.invalidSession) }
        // XCODES_PASSWORD has incorrect password
        var passwordEnvCallCount = 0
        XcodesKit.Current.shell.env = { key in
            if key == "XCODES_PASSWORD" {
                passwordEnvCallCount += 1
                return "old_password" 
            } else {
                return nil 
            }
        }
        var loginCallCount = 0
        XcodesKit.Current.network.login = { _, _ in
            defer { loginCallCount += 1 }
            if loginCallCount == 0 {
                return Promise(error: Client.Error.invalidUsernameOrPassword(username: "test@example.com"))
            }
            return Promise.value(())
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
        XcodesKit.Current.network.dataTask = { url in
            if url.pmkRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return Promise.value((data: downloadsData, response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
            }

            return Promise.value((data: Data(), response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Promise { resolver in
                        // Need this to run after the Promise has returned to the caller. This makes the test async, requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for i in 0...100 {
                                progress.completedUnitCount = Int64(i)
                            }
                            resolver.fulfill((saveLocation: saveLocation,
                                              response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                        }
                    })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            return Promise.value(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                        """))
        }
        // Don't have superuser privileges the first time
        var validateSudoAuthenticationCallCount = 0
        XcodesKit.Current.shell.validateSudoAuthentication = {
            validateSudoAuthenticationCallCount += 1

            if validateSudoAuthenticationCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil))
            }
            else {
                return Promise.value(Shell.processOutputMock)
            }
        }
        // User enters password
        var readSecureLineCallCount = 0
        XcodesKit.Current.shell.readSecureLine = { prompt, _ in
            XcodesKit.Current.logging.log(prompt)
            readSecureLineCallCount += 1
            return "password"
        }
        // User enters something
        XcodesKit.Current.shell.readLine = { prompt in
            XcodesKit.Current.logging.log(prompt)
            return "test@example.com"
        }

        let expectation = self.expectation(description: "Finished")

        installer.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"))
            .ensure {
                let url = Bundle.module.url(forResource: "LogOutput-IncorrectSavedPassword", withExtension: "txt", subdirectory: "Fixtures")!
                XCTAssertEqual(log, try! String(contentsOf: url))
                expectation.fulfill()

                XCTAssertEqual(passwordEnvCallCount, 2)
                XCTAssertEqual(readSecureLineCallCount, 2)
            }
            .catch {
                XCTFail($0.localizedDescription)
            }

        waitForExpectations(timeout: 1.0)
    }
    
    func test_InstallLogging_DamagedXIP() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

        // Don't have a valid session
        var validateSessionCallCount = 0
        Current.network.validateSession = {
            validateSessionCallCount += 1
            
            if validateSessionCallCount == 1 {
                return Promise(error: AppleAPI.Client.Error.invalidSession)
            } else {
                return Promise.value(())
            }
        }
        // It has been downloaded
        var unxipCallCount = 0
        Current.files.fileExistsAtPath = { path in
            if path == (Path.xcodesApplicationSupport/"Xcode-0.0.0.xip").string {
                if unxipCallCount == 1 {
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
        XcodesKit.Current.network.dataTask = { url in
            if url.pmkRequest.url! == URLRequest.downloads.url! {
                let downloads = Downloads(downloads: [Download(name: "Xcode 0.0.0", files: [Download.File(remotePath: "https://apple.com/xcode.xip")], dateModified: Date())])
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .formatted(.downloadsDateModified)
                let downloadsData = try! encoder.encode(downloads)
                return Promise.value((data: downloadsData, response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
            }

            return Promise.value((data: Data(), response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
        }
        // It downloads and updates progress
        Current.network.downloadTask = { (url, saveLocation, _) -> (Progress, Promise<(saveLocation: URL, response: URLResponse)>) in
            let progress = Progress(totalUnitCount: 100)
            return (progress,
                    Promise { resolver in
                        // Need this to run after the Promise has returned to the caller. This makes the test async, requiring waiting for an expectation.
                        DispatchQueue.main.async {
                            for i in 0...100 {
                                progress.completedUnitCount = Int64(i)
                            }
                            resolver.fulfill((saveLocation: saveLocation,
                                              response: HTTPURLResponse(url: url.pmkRequest.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!))
                        }
                    })
        }
        // It's a valid .app
        Current.shell.codesignVerify = { _ in
            return Promise.value(
                ProcessOutput(
                    status: 0,
                    out: "",
                    err: """
                        TeamIdentifier=\(XcodeInstaller.XcodeTeamIdentifier)
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[0])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[1])
                        Authority=\(XcodeInstaller.XcodeCertificateAuthority[2])
                        """))
        }
        // Don't have superuser privileges the first time
        var validateSudoAuthenticationCallCount = 0
        Current.shell.validateSudoAuthentication = {
            validateSudoAuthenticationCallCount += 1

            if validateSudoAuthenticationCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil))
            }
            else {
                return Promise.value(Shell.processOutputMock)
            }
        }
        // User enters password
        Current.shell.readSecureLine = { prompt, _ in
            XcodesKit.Current.logging.log(prompt)
            return "password"
        }
        // User enters something
        XcodesKit.Current.shell.readLine = { prompt in
            XcodesKit.Current.logging.log(prompt)
            return "asdf"
        }
        Current.shell.unxip = { _ in 
            unxipCallCount += 1
            if unxipCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: "The file \"Xcode-0.0.0.xip\" is damaged and can’t be expanded."))
            } else {
                return Promise.value(Shell.processOutputMock)
            }
        }

        let expectation = self.expectation(description: "Finished")

        installer.install(.version("0.0.0"), dataSource: .apple, downloader: .urlSession, destination: Path.root.join("Applications"))
            .ensure {
                let url = Bundle.module.url(forResource: "LogOutput-DamagedXIP", withExtension: "txt", subdirectory: "Fixtures")!
                let expectedText = try! String(contentsOf: url).replacingOccurrences(of: "/Users/brandon", with: Path.home.string)
                XCTAssertEqual(log, expectedText)
                expectation.fulfill()
            }
            .catch {
                XCTFail($0.localizedDescription)
            }

        waitForExpectations(timeout: 1.0)
    }
    
    func test_UninstallXcode() {
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
            Promise.value((status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: ""))
        }
        // Trashing succeeds
        var trashedItemAtURL: URL?
        Current.files.trashItem = { itemURL in
            trashedItemAtURL = itemURL
            return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash/\(itemURL.lastPathComponent)")
        }
        // Switching succeeds
        var selectedPaths: [String] = []
        Current.shell.xcodeSelectSwitch = { password, path in
            selectedPaths.append(path)
            return Promise.value((status: 0, out: "", err: ""))
        }

        installer.uninstallXcode("0.0.0", directory: Path.root.join("Applications"))
            .ensure {
                XCTAssertEqual(selectedPaths, ["/Applications/Xcode-2.0.1.app"])
                XCTAssertEqual(trashedItemAtURL, installedXcodes[0].path.url)
            }
            .cauterize()
    }
    
    func test_UninstallInteractively() {
        
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }
        
        // There are installed Xcodes
        let installedXcodes = [
            InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!, version: Version(0, 0, 0)),
            InstalledXcode(path: Path("/Applications/Xcode-2.0.1.app")!, version: Version(2, 0, 1)),
        ]
        Current.files.installedXcodes = { _ in installedXcodes }
        
        // It prints the expected paths
        var xcodeSelectPrintPathCallCount = 0
        Current.shell.xcodeSelectPrintPath = {
            xcodeSelectPrintPathCallCount += 1
            if xcodeSelectPrintPathCallCount == 1 {
                return Promise.value((status: 0, out: "/Applications/Xcode-2.0.1.app/Contents/Developer", err: ""))
            }
            else {
                return Promise.value((status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: ""))
            }
        }

        // User enters an index
        XcodesKit.Current.shell.readLine = { prompt in
            XcodesKit.Current.logging.log(prompt)
            return "1"
        }
        
        // Trashing succeeds
        var trashedItemAtURL: URL?
        Current.files.trashItem = { itemURL in
            trashedItemAtURL = itemURL
            return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash/\(itemURL.lastPathComponent)")
        }

        installer.uninstallXcode("999", directory: Path.root.join("Applications"))
            .ensure {
                XCTAssertEqual(trashedItemAtURL, installedXcodes[0].path.url)
            }
            .cauterize()
        
        XCTAssertEqual(log, """
        999.0 is not installed.
        Available Xcode versions:
        1) 0.0
        2) 2.0.1
        Enter the number of the Xcode to select: 
        Xcode 0.0 moved to Trash: \(NSHomeDirectory())/.Trash/Xcode-0.0.0.app

        """)
    }

    func test_VerifySecurityAssessment_Fails() {
        Current.shell.spctlAssess = { _ in return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil)) }

        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        installer.verifySecurityAssessment(of: installedXcode)
            .tap { result in XCTAssertFalse(result.isFulfilled) }
            .cauterize()
    }

    func test_VerifySecurityAssessment_Succeeds() {
        Current.shell.spctlAssess = { _ in return Promise.value((0, "", "")) }

        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        installer.verifySecurityAssessment(of: installedXcode)
            .tap { result in XCTAssertTrue(result.isFulfilled) }
            .cauterize()
    }

    func test_MigrateApplicationSupport_NoSupportFiles() {
        Current.files.fileExistsAtPath = { _ in return false }
        var source: URL?
        var destination: URL?
        Current.files.moveItem = { source = $0; destination = $1 } 
        var removedItemAtURL: URL?
        Current.files.removeItem = { removedItemAtURL = $0 } 

        migrateApplicationSupportFiles()

        XCTAssertNil(source)
        XCTAssertNil(destination)
        XCTAssertNil(removedItemAtURL)
    }

    func test_MigrateApplicationSupport_OnlyOldSupportFiles() {
        Current.files.fileExistsAtPath = { return $0.contains("ca.brandonevans") }
        var source: URL?
        var destination: URL?
        Current.files.moveItem = { source = $0; destination = $1 } 
        var removedItemAtURL: URL?
        Current.files.removeItem = { removedItemAtURL = $0 } 

        migrateApplicationSupportFiles()

        XCTAssertEqual(source, Path.applicationSupport.join("ca.brandonevans.xcodes").url)
        XCTAssertEqual(destination, Path.applicationSupport.join("com.robotsandpencils.xcodes").url)
        XCTAssertNil(removedItemAtURL)
    }

    func test_MigrateApplicationSupport_OldAndNewSupportFiles() {
        Current.files.fileExistsAtPath = { _ in return true }
        var source: URL?
        var destination: URL?
        Current.files.moveItem = { source = $0; destination = $1 } 
        var removedItemAtURL: URL?
        Current.files.removeItem = { removedItemAtURL = $0 } 

        migrateApplicationSupportFiles()

        XCTAssertNil(source)
        XCTAssertNil(destination)
        XCTAssertEqual(removedItemAtURL, Path.applicationSupport.join("ca.brandonevans.xcodes").url)
    }

    func test_MigrateApplicationSupport_OnlyNewSupportFiles() {
        Current.files.fileExistsAtPath = { return $0.contains("com.robotsandpencils") }
        var source: URL?
        var destination: URL?
        Current.files.moveItem = { source = $0; destination = $1 } 
        var removedItemAtURL: URL?
        Current.files.removeItem = { removedItemAtURL = $0 } 

        migrateApplicationSupportFiles()

        XCTAssertNil(source)
        XCTAssertNil(destination)
        XCTAssertNil(removedItemAtURL)
    }

    func test_ParsePrereleaseXcodes() {
        let url = Bundle.module.url(forResource: "developer.apple.com-download-19-6-9", withExtension: "html", subdirectory: "Fixtures")!
        let data = try! Data(contentsOf: url)

        let xcodes = try! XcodeList().parsePrereleaseXcodes(from: data)

        XCTAssertEqual(xcodes.count, 1)
        XCTAssertEqual(xcodes[0].version, Version("11.0.0-beta+11M336W"))
    }

    func test_SelectPrint() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

        Current.files.installedXcodes = { _ in
            [InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!,
             InstalledXcode(path: Path("/Applications/Xcode-2.0.0.app")!)!] 
        }

        Current.shell.xcodeSelectPrintPath = { Promise.value((status: 0, out: "/Applications/Xcode-2.0.0.app/Contents/Developer", err: "")) }

        selectXcode(shouldPrint: true, pathOrVersion: "", directory: Path.root.join("Applications"))
            .cauterize()

        XCTAssertEqual(log, """
        /Applications/Xcode-2.0.0.app/Contents/Developer

        """)
    }

    func test_SelectPath() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

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
        var xcodeSelectPrintPathCallCount = 0
        Current.shell.xcodeSelectPrintPath = {
            xcodeSelectPrintPathCallCount += 1
            if xcodeSelectPrintPathCallCount == 1 {
                return Promise.value((status: 0, out: "/Applications/Xcode-2.0.1.app/Contents/Developer", err: ""))
            }
            else {
                return Promise.value((status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: ""))
            }
        }
        // Don't have superuser privileges the first time
        var validateSudoAuthenticationCallCount = 0
        Current.shell.validateSudoAuthentication = {
            validateSudoAuthenticationCallCount += 1

            if validateSudoAuthenticationCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil))
            }
            else {
                return Promise.value(Shell.processOutputMock)
            }
        }
        // User enters password
        Current.shell.readSecureLine = { prompt, _ in
            XcodesKit.Current.logging.log(prompt)
            return "password"
        }
        // It successfully switches
        Current.shell.xcodeSelectSwitch = { _, _ in
            Promise.value((status: 0, out: "", err: ""))
        }

        selectXcode(shouldPrint: false, pathOrVersion: "/Applications/Xcode-0.0.0.app", directory: Path.root.join("Applications"))
            .cauterize()

        XCTAssertEqual(log, """
        xcodes requires superuser privileges to select an Xcode
        macOS User Password: 
        Selected /Applications/Xcode-0.0.0.app/Contents/Developer

        """)
    }

    func test_SelectInteractively() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

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
        var xcodeSelectPrintPathCallCount = 0
        Current.shell.xcodeSelectPrintPath = {
            xcodeSelectPrintPathCallCount += 1
            if xcodeSelectPrintPathCallCount == 1 {
                return Promise.value((status: 0, out: "/Applications/Xcode-2.0.1.app/Contents/Developer", err: ""))
            }
            else {
                return Promise.value((status: 0, out: "/Applications/Xcode-0.0.0.app/Contents/Developer", err: ""))
            }
        }
        // User enters an index
        XcodesKit.Current.shell.readLine = { prompt in
            XcodesKit.Current.logging.log(prompt)
            return "1"
        }
        // Don't have superuser privileges the first time
        var validateSudoAuthenticationCallCount = 0
        Current.shell.validateSudoAuthentication = {
            validateSudoAuthenticationCallCount += 1

            if validateSudoAuthenticationCallCount == 1 {
                return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil))
            }
            else {
                return Promise.value(Shell.processOutputMock)
            }
        }
        // User enters password
        Current.shell.readSecureLine = { prompt, _ in
            XcodesKit.Current.logging.log(prompt)
            return "password"
        }
        // It successfully switches
        Current.shell.xcodeSelectSwitch = { _, _ in
            Promise.value((status: 0, out: "", err: ""))
        }

        selectXcode(shouldPrint: false, pathOrVersion: "", directory: Path.root.join("Applications"))
            .cauterize()

        XCTAssertEqual(log, """
        Available Xcode versions:
        1) 0.0 (ABC123)
        2) 2.0.1 (ABC123) (Selected)
        Enter the number of the Xcode to select: 
        xcodes requires superuser privileges to select an Xcode
        macOS User Password: 
        Selected /Applications/Xcode-0.0.0.app/Contents/Developer

        """)
    }
    
    func test_Installed_InteractiveTerminal() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

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
            Promise.value((status: 0, out: "/Applications/Xcode-2.0.1-Release.Candidate.app/Contents/Developer", err: ""))
        }
        
        // Standard output is an interactive terminal
        Current.shell.isatty = { true }

        installer.printInstalledXcodes(directory: Path.root/"Applications")
            .cauterize()
        
        XCTAssertEqual(
            log,
            """
            0.0 (ABC123)                                /Applications/Xcode-0.0.0.app
            2.0 (ABC123)                                /Applications/Xcode-2.0.0.app
            2.0.1 Release Candidate (ABC123) (Selected) /Applications/Xcode-2.0.1-Release.Candidate.app

            """
        )
    }
    
    func test_Installed_NonInteractiveTerminal() {
        var log = ""
        XcodesKit.Current.logging.log = { log.append($0 + "\n") }

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
            Promise.value((status: 0, out: "/Applications/Xcode-2.0.0.app/Contents/Developer", err: ""))
        }
        
        // Standard output is not an interactive terminal
        Current.shell.isatty = { false }

        installer.printInstalledXcodes(directory: Path.root/"Applications")
            .cauterize()
        
        XCTAssertEqual(
            log,
            """
            0.0 (ABC123)\t/Applications/Xcode-0.0.0.app
            2.0 (ABC123) (Selected)\t/Applications/Xcode-2.0.0.app
            2.0.1 Release Candidate (ABC123)\t/Applications/Xcode-2.0.1-Release.Candidate.app

            """
        )
    }

}
