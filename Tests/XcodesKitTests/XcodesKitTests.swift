import XCTest
import XcodesKit

final class XcodesKitTests: XCTestCase {
    let installer = XcodeInstaller()

    func testParseCertificateInfo() throws {
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
}
