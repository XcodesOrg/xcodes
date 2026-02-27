import XCTest
import Version
import Path
@testable import XcodesKit

final class XcodeArchitectureSelectionTests: XCTestCase {
    func test_selectXcodeCandidate_prefersAppleSiliconVariant() throws {
        let version = Version("16.0.0+16A100")!
        let universal = Xcode(version: version,
                              url: URL(string: "https://example.com/Xcode-16-universal.xip")!,
                              filename: "Xcode-16-universal.xip",
                              releaseDate: nil)
        let appleSilicon = Xcode(version: version,
                                 url: URL(string: "https://example.com/Xcode-16-arm64.xip")!,
                                 filename: "Xcode-16-arm64.xip",
                                 releaseDate: nil)

        let selected = XcodeInstaller.selectXcodeCandidate(
            version: version,
            requiredArchitectures: [.arm64],
            availableXcodes: [universal, appleSilicon],
            architecturesByDownloadPath: [
                universal.downloadPath: [.arm64, .x86_64],
                appleSilicon.downloadPath: [.arm64]
            ]
        )

        XCTAssertEqual(selected?.url, appleSilicon.url)
    }

    func test_selectXcodeCandidate_matchesUniversalWithNormalizedArchitectures() throws {
        let version = Version("16.0.0+16A100")!
        let universal = Xcode(version: version,
                              url: URL(string: "https://example.com/Xcode-16-universal.xip")!,
                              filename: "Xcode-16-universal.xip",
                              releaseDate: nil)
        let appleSilicon = Xcode(version: version,
                                 url: URL(string: "https://example.com/Xcode-16-arm64.xip")!,
                                 filename: "Xcode-16-arm64.xip",
                                 releaseDate: nil)

        let selected = XcodeInstaller.selectXcodeCandidate(
            version: version,
            requiredArchitectures: [.x86_64, .arm64],
            availableXcodes: [appleSilicon, universal],
            architecturesByDownloadPath: [
                universal.downloadPath: [.x86_64, .arm64],
                appleSilicon.downloadPath: [.arm64]
            ]
        )

        XCTAssertEqual(selected?.url, universal.url)
    }

    func test_selectXcodeCandidate_returnsNilWhenArchitectureVariantMissing() throws {
        let version = Version("16.0.0+16A100")!
        let universal = Xcode(version: version,
                              url: URL(string: "https://example.com/Xcode-16-universal.xip")!,
                              filename: "Xcode-16-universal.xip",
                              releaseDate: nil)

        let selected = XcodeInstaller.selectXcodeCandidate(
            version: version,
            requiredArchitectures: [.arm64],
            availableXcodes: [universal],
            architecturesByDownloadPath: [
                universal.downloadPath: [.arm64, .x86_64]
            ]
        )

        XCTAssertNil(selected)
    }

    func test_parseXcodeReleasesPayload_normalizesAndFiltersUnsupportedArchitectures() throws {
        let data = """
        [
          {
            "name": "Xcode 16.0",
            "version": {
              "number": "16.0",
              "build": "16A100",
              "release": { "release": true }
            },
            "date": { "year": 2024, "month": 9, "day": 16 },
            "requires": "macOS 14.5",
            "links": {
              "download": {
                "url": "https://example.com/Xcode-16-arm64.xip",
                "architectures": ["arm64"]
              }
            }
          },
          {
            "name": "Xcode 16.0",
            "version": {
              "number": "16.0",
              "build": "16A100",
              "release": { "release": true }
            },
            "date": { "year": 2024, "month": 9, "day": 16 },
            "requires": "macOS 14.5",
            "links": {
              "download": {
                "url": "https://example.com/Xcode-16-universal.xip",
                "architectures": ["x86_64", "arm64", "x86_64"]
              }
            }
          },
          {
            "name": "Xcode 15.4",
            "version": {
              "number": "15.4",
              "build": "15F31",
              "release": { "release": true }
            },
            "date": { "year": 2024, "month": 5, "day": 13 },
            "requires": "macOS 14.0",
            "links": {
              "download": {
                "url": "https://example.com/Xcode-legacy.xip",
                "architectures": ["i386"]
              }
            }
          }
        ]
        """.data(using: .utf8)!

        let xcodeList = XcodeList()
        let payload = try xcodeList.parseXcodeReleasesPayload(from: data)
        let architecturesByPath = payload.architecturesByDownloadPath

        XCTAssertEqual(payload.xcodes.count, 3)
        XCTAssertEqual(architecturesByPath["/Xcode-16-arm64.xip"], [.arm64])
        XCTAssertEqual(architecturesByPath["/Xcode-16-universal.xip"], [.arm64, .x86_64])
        XCTAssertNil(architecturesByPath["/Xcode-legacy.xip"])
    }

    func test_installedVersionConflict_requiresForceForArchitectureInstall() throws {
        let version = Version("16.0.0+16A100")!
        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-16.0.0.app")!, version: version)

        let error = XcodeInstaller.installedVersionConflict(
            installedXcode: installedXcode,
            requiredArchitectures: [.arm64],
            forceReinstall: false
        )

        XCTAssertEqual(
            error,
            .architectureInstallationRequiresForceReinstall(
                installedXcode: installedXcode,
                requiredArchitectures: [.arm64]
            )
        )
    }

    func test_installedVersionConflict_allowsReinstallWithForce() throws {
        let version = Version("16.0.0+16A100")!
        let installedXcode = InstalledXcode(path: Path("/Applications/Xcode-16.0.0.app")!, version: version)

        let error = XcodeInstaller.installedVersionConflict(
            installedXcode: installedXcode,
            requiredArchitectures: [.arm64],
            forceReinstall: true
        )

        XCTAssertNil(error)
    }

    func test_unavailableXcodeError_returnsArchitectureSpecificError() throws {
        let version = Version("16.0.0+16A100")!

        let error = XcodeInstaller.unavailableXcodeError(
            version: version,
            requiredArchitectures: [.arm64]
        )

        XCTAssertEqual(
            error,
            .unavailableVersionForArchitectures(
                version: version,
                requiredArchitectures: [.arm64]
            )
        )
    }
}
