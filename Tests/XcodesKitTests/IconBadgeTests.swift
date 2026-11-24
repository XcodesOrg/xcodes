import Path
import Version
import XCTest
import XcodesKit
@testable import XcodesCLIKit

#if canImport(AppKit)
import AppKit
#endif

final class IconBadgeTests: XCTestCase {
    private func badge(_ version: Version) -> IconBadge { IconBadge(version: version) }

    private let beta2 = Version(27, 0, 0, prereleaseIdentifiers: ["Beta", "2"])

    func test_release() {
        XCTAssertEqual(badge(Version("27.0.0+25A100")!).label, "27.0")
        XCTAssertEqual(badge(Version("26.0.1")!).label, "26.0.1")
        XCTAssertEqual(badge(Version("26.0.1")!).suffix, "")
        XCTAssertFalse(badge(Version("26.0.1")!).isPrerelease)
    }

    func test_prerelease() {
        XCTAssertEqual(badge(beta2).label, "27.0")
        XCTAssertEqual(badge(beta2).suffix, "b2")
        XCTAssertTrue(badge(beta2).isPrerelease)
    }

    func test_prereleaseSuffix_abbreviatesKnownNames() {
        let expected: [(Version, String)] = [
            (Version("26.4.0-Beta")!, "b"),
            (Version("26.4.0-Beta.2")!, "b2"),
            (Version(xcodeVersion: "26.4 Beta 3")!, "b3"),
            (Version(26, 4, 0, prereleaseIdentifiers: ["beta"]), "b"),
            (Version("27.2.0-Release.Candidate")!, "rc"),
            (Version("27.2.0-Release.Candidate.2")!, "rc2"),
            (Version(xcodeVersion: "27.1 Release Candidate")!, "rc"),
            (Version("27.0.0-Gold.Master")!, "gm"),
            (Version("27.0.0-Developer.Preview.2")!, "dp2"),
        ]
        for (version, suffix) in expected {
            XCTAssertEqual(badge(version).suffix, suffix, "\(version)")
            XCTAssertTrue(badge(version).isPrerelease, "\(version)")
        }
    }

    func test_prereleaseSuffix_keepsUnknownNames() {
        XCTAssertEqual(badge(Version("27.0.0-2")!).suffix, "2")
        XCTAssertEqual(badge(Version("27.0.0-Nightly")!).suffix, "Nightly")
    }

    #if canImport(AppKit)
    private func baseIcon(size: CGFloat, color: NSColor? = nil) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if let color {
                color.setFill()
                rect.fill()
            }
            return true
        }
    }

    func test_render_producesBitmapAtEverySize() throws {
        let image = try badge(beta2).makeImage(base: baseIcon(size: 256, color: .systemBlue))
        let reps = image.representations.map { (points: Int($0.size.width), pixels: $0.pixelsWide) }
        XCTAssertEqual(reps.count, IconBadge.representations.count)
        for (rep, expected) in zip(reps, IconBadge.representations) {
            XCTAssertEqual(rep.points, expected.points)
            XCTAssertEqual(rep.pixels, expected.pixels)
        }
        // Every point size has a 1x and a 2x bitmap
        for points in Set(reps.map(\.points)) {
            XCTAssertEqual(reps.filter { $0.points == points }.map(\.pixels).sorted(), [points, points * 2])
        }
    }
    #endif
}

final class UpdateIconsTests: XCTestCase {
    var installer: XcodeInstaller!
    let applied = LockedBox<[(String, String)]>([])
    let removed = LockedBox<[String]>([])
    let logged = LockedBox<[String]>([])

    let rc = InstalledXcode(path: Path("/Applications/Xcode-27.2.0-Release.Candidate.app")!, version: Version("27.2.0-Release.Candidate")!)
    let release = InstalledXcode(path: Path("/Applications/Xcode-27.0.0.app")!, version: Version("27.0.0")!)

    override func setUp() {
        Current = .mock
        syncXcodesKitMocks()
        let installed = [rc, release]
        Current.files.installedXcodes = { _ in installed }
        Current.logging.log = { [logged] line in logged.update { $0.append(line) } }
        Current.icons.applyBadge = { [applied] badge, path in applied.update { $0.append((badge.label, path.string)) } }
        Current.icons.removeBadge = { [removed] path in removed.update { $0.append(path.string) } }
        installer = XcodeInstaller(xcodeList: XcodeList(), sessionService: AppleSessionService(configuration: Configuration()))
    }

    func test_noVersion_badgesEveryXcode() throws {
        try installer.addIconBadges(ofVersion: nil, directory: Path("/Applications")!)
        XCTAssertEqual(applied.value.map(\.0), ["27.0", "27.2"])
        XCTAssertEqual(applied.value.map(\.1), [release.path.string, rc.path.string])
    }

    func test_version_badgesOnlyThatXcode() throws {
        try installer.addIconBadges(ofVersion: "27.2 Release Candidate", directory: Path("/Applications")!)
        XCTAssertEqual(applied.value.map(\.0), ["27.2"])
    }

    func test_remove_restoresIcons() throws {
        try installer.removeIconBadges(ofVersion: "27.0", directory: Path("/Applications")!)
        XCTAssertEqual(removed.value, [release.path.string])
        XCTAssertTrue(applied.value.isEmpty)
    }

    func test_unknownVersion_throws() {
        XCTAssertThrowsError(try installer.addIconBadges(ofVersion: "1.0", directory: Path("/Applications")!)) {
            XCTAssertEqual($0 as? XcodeInstaller.Error, .versionNotInstalled(Version("1.0.0")!))
        }
        XCTAssertThrowsError(try installer.addIconBadges(ofVersion: "nope", directory: Path("/Applications")!)) {
            XCTAssertEqual($0 as? XcodeInstaller.Error, .invalidVersion("nope"))
        }
    }

    func test_betaLogLineIncludesTheSuffix() throws {
        let beta = InstalledXcode(path: Path("/Applications/Xcode-27.0.0-Beta.2.app")!, version: Version("27.0.0-Beta.2")!)
        Current.files.installedXcodes = { _ in [beta] }
        try installer.addIconBadges(ofVersion: nil, directory: Path("/Applications")!)
        XCTAssertTrue(logged.value.contains { $0.contains("\"27.0b2\"") }, "\(logged.value)")
    }

    func test_failures_areReportedAfterTryingEveryXcode() {
        struct Boom: Error {}
        Current.icons.applyBadge = { [applied] badge, path in
            if badge.label == "27.0" { throw Boom() }
            applied.update { $0.append((badge.label, path.string)) }
        }
        XCTAssertThrowsError(try installer.addIconBadges(ofVersion: nil, directory: Path("/Applications")!)) {
            XCTAssertEqual($0 as? XcodeInstaller.Error, .failedToUpdateIcons(count: 1))
        }
        XCTAssertEqual(applied.value.map(\.0), ["27.2"])
    }
}
