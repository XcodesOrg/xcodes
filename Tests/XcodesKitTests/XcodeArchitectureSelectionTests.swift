import XCTest
import Version
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
            requiredArchitectures: ["arm64"],
            availableXcodes: [universal, appleSilicon],
            architecturesByDownloadPath: [
                universal.downloadPath: ["arm64", "x86_64"],
                appleSilicon.downloadPath: ["arm64"]
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
            requiredArchitectures: ["x86_64", "arm64", "arm64"],
            availableXcodes: [appleSilicon, universal],
            architecturesByDownloadPath: [
                universal.downloadPath: ["x86_64", "arm64"],
                appleSilicon.downloadPath: ["arm64"]
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
            requiredArchitectures: ["arm64"],
            availableXcodes: [universal],
            architecturesByDownloadPath: [
                universal.downloadPath: ["arm64", "x86_64"]
            ]
        )

        XCTAssertNil(selected)
    }

    func test_parseArchitecturesByDownloadPath_normalizesAndFiltersUnsupportedArchitectures() throws {
        let data = """
        [
          {
            "links": {
              "download": {
                "url": "https://example.com/Xcode-16-arm64.xip",
                "architectures": ["arm64"]
              }
            }
          },
          {
            "links": {
              "download": {
                "url": "https://example.com/Xcode-16-universal.xip",
                "architectures": ["x86_64", "arm64", "x86_64"]
              }
            }
          },
          {
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
        let architecturesByPath = try xcodeList.parseArchitecturesByDownloadPath(from: data)

        XCTAssertEqual(architecturesByPath["/Xcode-16-arm64.xip"], ["arm64"])
        XCTAssertEqual(architecturesByPath["/Xcode-16-universal.xip"], ["arm64", "x86_64"])
        XCTAssertNil(architecturesByPath["/Xcode-legacy.xip"])
    }
}
