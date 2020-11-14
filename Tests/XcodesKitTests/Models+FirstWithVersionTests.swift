import Path
import XCTest
import Version
@testable import XcodesKit

final class ModelsFirstWithVersionTests: XCTestCase {
    let xcodes = [
        Xcode(version: Version(xcodeVersion: "1.2.3")!,        url: URL(fileURLWithPath: "https://developer.apple.com/Xcode1.2.3.app"),      filename: "Xcode1.2.3.app",      releaseDate: nil),
        Xcode(version: Version(xcodeVersion: "1.2.3 Beta 1")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode1.2.3Beta1.app"), filename: "Xcode1.2.3Beta1.app", releaseDate: nil),
        Xcode(version: Version(xcodeVersion: "1.2.3 Beta 2")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode1.2.3Beta2.app"), filename: "Xcode1.2.3Beta2.app", releaseDate: nil),
        
        Xcode(version: Version(xcodeVersion: "4.5.6 Beta 1")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode4.5.6Beta1.app"), filename: "Xcode4.5.6Beta1app",  releaseDate: nil),
        Xcode(version: Version(xcodeVersion: "4.5.6 Beta 2")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode4.5.6Beta2.app"), filename: "Xcode4.5.6Beta2.app", releaseDate: nil),
        
        Xcode(version: Version(xcodeVersion: "7.8.9")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode7.8.9.app"), filename: "Xcode7.8.9.app", releaseDate: nil),
        
        Xcode(version: Version(xcodeVersion: "10.11.12 Release Candidate")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode10.11.12ReleaseCandidate.app"), filename: "Xcode10.11.12ReleaseCandidate.app", releaseDate: nil),
    ]
    
    let installedXcodes = [
        InstalledXcode(path: Path("/Applications/Xcode-1.2.3.app")!,        version: Version(xcodeVersion: "1.2.3")!),
        InstalledXcode(path: Path("/Applications/Xcode-1.2.3-beta.1.app")!, version: Version(xcodeVersion: "1.2.3 Beta 1")!),
        InstalledXcode(path: Path("/Applications/Xcode-1.2.3-beta.2.app")!, version: Version(xcodeVersion: "1.2.3 Beta 2")!),
        
        InstalledXcode(path: Path("/Applications/Xcode-4.5.6-beta.1.app")!, version: Version(xcodeVersion: "4.5.6 Beta 1")!),
        InstalledXcode(path: Path("/Applications/Xcode-4.5.6-beta.2.app")!, version: Version(xcodeVersion: "4.5.6 Beta 2")!),
        
        InstalledXcode(path: Path("/Applications/Xcode-7.8.9.app")!, version: Version(xcodeVersion: "7.8.9")!),
        
        InstalledXcode(path: Path("/Applications/Xcode-10.11.12-release.candidate.app")!, version: Version(xcodeVersion: "10.11.12 Release Candidate")!),
    ]
    
    func test_xcodes_exactMatch() {
        XCTAssertEqual(
            xcodes.first(withVersion: Version(xcodeVersion: "1.2.3")!),
            Xcode(version: Version(xcodeVersion: "1.2.3")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode1.2.3.app"), filename: "Xcode1.2.3.app", releaseDate: nil)
        )
        XCTAssertEqual(
            xcodes.first(withVersion: Version(xcodeVersion: "1.2.3 Beta 2")!),
            Xcode(version: Version(xcodeVersion: "1.2.3 Beta 2")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode1.2.3Beta2.app"), filename: "Xcode1.2.3Beta2.app", releaseDate: nil)
        )
        XCTAssertEqual(
            xcodes.first(withVersion: Version(xcodeVersion: "7.8.9")!),
            Xcode(version: Version(xcodeVersion: "7.8.9")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode7.8.9.app"), filename: "Xcode7.8.9.app", releaseDate: nil)
        )
    }
    
    func test_xcodes_fuzzyMatch() {
        XCTAssertEqual(
            xcodes.first(withVersion: Version(xcodeVersion: "10.11.12")!),
            Xcode(version: Version(xcodeVersion: "10.11.12 Release Candidate")!, url: URL(fileURLWithPath: "https://developer.apple.com/Xcode10.11.12ReleaseCandidate.app"), filename: "Xcode10.11.12ReleaseCandidate.app", releaseDate: nil)
        )
    }
    
    func test_xcodes_noMatch() {
        XCTAssertEqual(
            xcodes.first(withVersion: Version(xcodeVersion: "3.4.5")!),
            nil
        )
    }
    
    func test_xcodes_multipleMatches() {
        XCTAssertEqual(
            xcodes.first(withVersion: Version(xcodeVersion: "4.5.6")!),
            nil
        )
    }
    
    func test_installedXcodes_exactMatch() {
        XCTAssertEqual(
            installedXcodes.first(withVersion: Version(xcodeVersion: "1.2.3")!),
            InstalledXcode(path: Path("/Applications/Xcode-1.2.3.app")!, version: Version(xcodeVersion: "1.2.3")!)
        )
        XCTAssertEqual(
            installedXcodes.first(withVersion: Version(xcodeVersion: "1.2.3 Beta 2")!),
            InstalledXcode(path: Path("/Applications/Xcode-1.2.3-beta.2.app")!, version: Version(xcodeVersion: "1.2.3 Beta 2")!)
        )
        XCTAssertEqual(
            installedXcodes.first(withVersion: Version(xcodeVersion: "7.8.9")!),
            InstalledXcode(path: Path("/Applications/Xcode-7.8.9.app")!, version: Version(xcodeVersion: "7.8.9")!)
        )
    }
    
    func test_installedXcodes_fuzzyMatch() {
        XCTAssertEqual(
            installedXcodes.first(withVersion: Version(xcodeVersion: "10.11.12")!),
            InstalledXcode(path: Path("/Applications/Xcode-10.11.12-release.candidate.app")!, version: Version(xcodeVersion: "10.11.12 Release Candidate")!)
        )
    }
    
    func test_installedXcodes_noMatch() {
        XCTAssertEqual(
            installedXcodes.first(withVersion: Version(xcodeVersion: "3.4.5")!),
            nil
        )
    }
    
    func test_installedXcodes_multipleMatches() {
        XCTAssertEqual(
            installedXcodes.first(withVersion: Version(xcodeVersion: "4.5.6")!),
            nil
        )
    }
}
