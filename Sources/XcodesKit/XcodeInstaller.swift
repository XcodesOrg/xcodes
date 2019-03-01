import Foundation
import PromiseKit
import Path

public final class XcodeInstaller {
    static let XcodeTeamIdentifier = "59GAB85EFG"
    static let XcodeCertificateAuthority = "Apple Mac OS Application Signing"

    enum Error: Swift.Error {
        case failedSecurityAssessment
    }

    public init() {}

    public func installArchivedXcode(_ xcode: Xcode, at url: URL) -> Promise<Void> {
        return firstly { () -> Promise<InstalledXcode> in
            let destinationURL = Path.root.join("Applications").join("Xcode.app").url
            switch url.pathExtension {
            case "xip":
                return try unarchiveAndMoveXIP(at: url, to: destinationURL)
                    .map { InstalledXcode(path: Path(url: $0)!) }
            case "dmg":
                fatalError()
            default:
                fatalError()
            }
        }
        .then { xcode -> Promise<InstalledXcode> in
            return when(fulfilled: self.verifySecurityAssessment(of: xcode.path.url),
                                   self.verifySigningCertificate(of: xcode.path.url))
                .map { validAssessment, validCert -> InstalledXcode in
                    guard validAssessment && validCert else { throw Error.failedSecurityAssessment }
                    return xcode
                }
        }
        .then { xcode -> Promise<InstalledXcode> in
            self.enableDeveloperMode().map { xcode }
        }
        .then { xcode -> Promise<InstalledXcode> in
            self.approveLicense(for: xcode).map { xcode }
        }
        .then { xcode -> Promise<Void> in
            self.installComponents(for: xcode)
        }
    }

    func unarchiveAndMoveXIP(at source: URL, to destination: URL) throws -> Promise<URL> {
        return firstly { () -> Promise<ProcessOutput> in
            return Current.shell.unxip(source)
        }
        .map { output -> URL in
            let xcodeURL = source.deletingLastPathComponent().appendingPathComponent("Xcode.app")
            let xcodeBetaURL = source.deletingLastPathComponent().appendingPathComponent("Xcode-Beta.app")
            if Current.files.fileExists(atPath: xcodeURL.path) {
                try Current.files.moveItem(at: xcodeURL, to: destination)
            }
            else if Current.files.fileExists(atPath: xcodeBetaURL.path) {
                try Current.files.moveItem(at: xcodeBetaURL, to: destination)
            }

            return destination
        }
    }

    func verifySecurityAssessment(of url: URL) -> Promise<Bool> {
        return Current.shell.spctlAssess(url).map { $0.status == 0 }
    }

    func verifySigningCertificate(of url: URL) -> Promise<Bool> {
        return gatherCertificateInfo(for: url)
            .map { return $0.teamIdentifier == XcodeInstaller.XcodeTeamIdentifier &&
                          $0.authority.contains(XcodeInstaller.XcodeCertificateAuthority) }
    }

    public struct CertificateInfo {
        public var authority: [String]
        public var teamIdentifier: String
        public var bundleIdentifier: String
    }

    func gatherCertificateInfo(for url: URL) -> Promise<CertificateInfo> {
        return Current.shell.codesignVerify(url)
            .map { output in
                guard output.status == 0 else { exit(output.status) }
                return self.parseCertificateInfo(output.out)
            }
    }

    public func parseCertificateInfo(_ rawInfo: String) -> CertificateInfo {
        var info = CertificateInfo(authority: [], teamIdentifier: "", bundleIdentifier: "")

        for part in rawInfo.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines) {
            if part.hasPrefix("Authority") {
                info.authority.append(part.components(separatedBy: "=")[1])
            }
            if part.hasPrefix("TeamIdentifier") {
                info.teamIdentifier = part.components(separatedBy: "=")[1]
            }
            if part.hasPrefix("Identifier") {
                info.bundleIdentifier = part.components(separatedBy: "=")[1]
            }
        }

        return info
    }

    func enableDeveloperMode() -> Promise<Void> {
        return Current.shell.devToolsSecurityEnable()
            .then { _ in
                return Current.shell.addStaffToDevelopersGroup().asVoid()
            }
    }

    func approveLicense(for xcode: InstalledXcode) -> Promise<Void> {
        return Current.shell.acceptXcodeLicense(xcode).asVoid()
    }

    func installComponents(for xcode: InstalledXcode) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            Current.shell.runFirstLaunch(xcode).asVoid()
        }
        .then { () -> Promise<(String, String, String)> in
            return when(fulfilled:
                Current.shell.getUserCacheDir().map { $0.out },
                Current.shell.buildVersion().map { $0.out },
                Current.shell.xcodeBuildVersion(xcode).map { $0.out }
            )
        }
        .then { cacheDirectory, macOSBuildVersion, toolsVersion -> Promise<Void> in
            return Current.shell.touchInstallCheck(cacheDirectory, macOSBuildVersion, toolsVersion).asVoid()
        }
    }
}
