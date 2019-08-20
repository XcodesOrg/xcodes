import XCTest
import Version
import PromiseKit
import PMKFoundation
import Path
import AppleAPI
@testable import XcodesKit

final class XcodesKitTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        PromiseKit.conf.Q.map = nil
        PromiseKit.conf.Q.return = nil
    }

    override func setUp() {
        Current = .mock
    }

    var installer = XcodeInstaller(client: AppleAPI.Client())

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
        let client = SpyClient()
        installer = XcodeInstaller(client: client)
        Current.files.fileExistsAtPath = { _ in return true }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock.xip")
        installer.downloadOrUseExistingArchive(for: xcode, progressChanged: { _ in })
            .tap { result in
                guard case .fulfilled(let value) = result else { XCTFail("downloadOrUseExistingArchive rejected."); return }
                XCTAssertEqual(value, Path.applicationSupport.join("com.robotsandpencils.xcodes").join("Xcode-0.0.0.xip").url)
                XCTAssertFalse(client.didAccessSession)
            }
    }

    func test_InstallArchivedXcode_SecurityAssessmentFails_Throws() {
        Current.shell.spctlAssess = { _ in return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil)) }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock")
        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), archiveTrashed: { _ in },  passwordInput: { Promise.value("") })
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.failedSecurityAssessment(xcode: installedXcode, output: "")) }
    }

    func test_InstallArchivedXcode_VerifySigningCertificateFails_Throws() {
        Current.shell.codesignVerify = { _ in return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil)) }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock")
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), archiveTrashed: { _ in }, passwordInput: { Promise.value("") })
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.codesignVerifyFailed) }
    }

    func test_InstallArchivedXcode_VerifySigningCertificateDoesntMatch_Throws() {
        Current.shell.codesignVerify = { _ in return Promise.value((0, "", "")) }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock")
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), archiveTrashed: { _ in }, passwordInput: { Promise.value("") })
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.codesignVerifyFailed) }
    }

    func test_InstallArchivedXcode_TrashesXIPWhenFinished() {
        var trashedItemAtURL: URL?
        Current.files.trashItem = { itemURL in
            trashedItemAtURL = itemURL
            return URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash/\(itemURL.lastPathComponent)")
        }

        let xcode = Xcode(version: Version("0.0.0")!, url: URL(fileURLWithPath: "/"), filename: "mock")
        let xipURL = URL(fileURLWithPath: "/Xcode-0.0.0.xip")
        installer.installArchivedXcode(xcode, at: xipURL, archiveTrashed: { _ in }, passwordInput: { Promise.value("") })
            .ensure { XCTAssertEqual(trashedItemAtURL, xipURL) }
    }

    func test_VerifySecurityAssessment_Fails() {
        Current.shell.spctlAssess = { _ in return Promise(error: Process.PMKError.execution(process: Process(), standardOutput: nil, standardError: nil)) }

        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        installer.verifySecurityAssessment(of: installedXcode)
            .tap { result in XCTAssertFalse(result.isFulfilled) }
    }

    func test_VerifySecurityAssessment_Succeeds() {
        Current.shell.spctlAssess = { _ in return Promise.value((0, "", "")) }

        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-0.0.0.app")!)!
        installer.verifySecurityAssessment(of: installedXcode)
            .tap { result in XCTAssertTrue(result.isFulfilled) }
    }

    func test_MigrateApplicationSupport_NoSupportFiles() {
        Current.files.fileExistsAtPath = { _ in return false }
        var source: URL?
        var destination: URL?
        Current.files.moveItem = { source = $0; destination = $1 } 
        var removedItemAtURL: URL?
        Current.files.removeItem = { removedItemAtURL = $0 } 

        XcodeList.migrateApplicationSupportFiles()

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

        XcodeList.migrateApplicationSupportFiles()

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

        XcodeList.migrateApplicationSupportFiles()

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

        XcodeList.migrateApplicationSupportFiles()

        XCTAssertNil(source)
        XCTAssertNil(destination)
        XCTAssertNil(removedItemAtURL)
    }

    func test_ParsePrereleaseXcodes() {
        let url = URL(fileURLWithPath: "developer.apple.com-download-19-6-9.html", relativeTo: URL(fileURLWithPath: #file).deletingLastPathComponent())
        let data = try! Data(contentsOf: url)

        let xcodes = try! XcodeList(client: AppleAPI.Client()).parsePrereleaseXcodes(from: data)

        XCTAssertEqual(xcodes.count, 1)
        XCTAssertEqual(xcodes[0].version, Version("11.0.0-beta+11M336W"))
    }
}

// TODO: Create a better way to stub responses and spy on XcodeInstaller's interaction with AppleAPI.Client
class SpyClient: AppleAPI.Client {
    private(set) var didAccessSession = false
    override var session: URLSession {
        didAccessSession = true
        return URLSession.shared
    }
}
