import XCTest
import PromiseKit
@testable import XcodesKit

final class XcodesKitTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        Current = .mock
        PromiseKit.conf.Q.map = nil
        PromiseKit.conf.Q.return = nil
    }

    let installer = XcodeInstaller()

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

    func test_InstallArchivedXcode_SecurityAssessmentFails_Throws() {
        Current.shell.spctlAssess = { _ in return Promise.value((1, "", "")) }

        let xcode = Xcode(name: "Xcode 0.0.0", url: URL(fileURLWithPath: "/"), filename: "mock")!
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), passwordInput: { Promise.value("") })
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.failedSecurityAssessment) }
    }

    func test_InstallArchivedXcode_VerifySigningCertificateFails_Throws() {
        Current.shell.codesignVerify = { _ in return Promise.value((1, "", "")) }

        let xcode = Xcode(name: "Xcode 0.0.0", url: URL(fileURLWithPath: "/"), filename: "mock")!
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), passwordInput: { Promise.value("") })
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.codesignVerifyFailed) }
    }

    func test_InstallArchivedXcode_VerifySigningCertificateDoesntMatch_Throws() {
        Current.shell.codesignVerify = { _ in return Promise.value((0, "", "")) }

        let xcode = Xcode(name: "Xcode 0.0.0", url: URL(fileURLWithPath: "/"), filename: "mock")!
        installer.installArchivedXcode(xcode, at: URL(fileURLWithPath: "/Xcode-0.0.0.xip"), passwordInput: { Promise.value("") })
            .catch { error in XCTAssertEqual(error as! XcodeInstaller.Error, XcodeInstaller.Error.failedSecurityAssessment) }
    }

    func test_VerifySecurityAssessment_Fails() {
        Current.shell.spctlAssess = { _ in return Promise.value((1, "", "")) }

        installer.verifySecurityAssessment(of: URL(fileURLWithPath: "/"))
            .done { success in XCTAssertFalse(success) }
    }

    func test_VerifySecurityAssessment_Succeeds() {
        Current.shell.spctlAssess = { _ in return Promise.value((0, "", "")) }

        installer.verifySecurityAssessment(of: URL(fileURLWithPath: "/"))
            .done { success in XCTAssertTrue(success) }
    }
}
