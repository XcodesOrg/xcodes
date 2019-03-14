import Foundation
import PromiseKit
import Path

public final class XcodeInstaller {
    static let XcodeTeamIdentifier = "59GAB85EFG"
    static let XcodeCertificateAuthority = ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"]

    enum Error: Swift.Error, Equatable {
        case failedToMoveXcodeToApplications
        case failedSecurityAssessment
        case codesignVerifyFailed
        case unsupportedFileFormat(extension: String)
    }

    public init() {}

    public func installArchivedXcode(_ xcode: Xcode, at url: URL, passwordInput: @escaping () -> Promise<String>) -> Promise<Void> {
        return firstly { () -> Promise<InstalledXcode> in
            let destinationURL = Path.root.join("Applications").join("Xcode-\(xcode.version).app").url
            switch url.pathExtension {
            case "xip":
                return try unarchiveAndMoveXIP(at: url, to: destinationURL).map { xcodeURL in
                    guard 
                        let path = Path(url: xcodeURL),
                        Current.files.fileExists(atPath: path.string),
                        let installedXcode = InstalledXcode(path: path)
                    else { throw Error.failedToMoveXcodeToApplications }
                    return installedXcode
                }
            case "dmg":
                throw Error.unsupportedFileFormat(extension: "dmg")
            default:
                throw Error.unsupportedFileFormat(extension: url.pathExtension)
            }
        }
        .then { xcode -> Promise<InstalledXcode> in
            try Current.files.removeItem(at: url)

            return when(fulfilled: self.verifySecurityAssessment(of: xcode.path.url),
                                   self.verifySigningCertificate(of: xcode.path.url))
                .map { xcode }
        }
        .then { xcode -> Promise<InstalledXcode> in
            self.enableDeveloperMode(passwordInput: passwordInput).map { xcode }
        }
        .then { xcode -> Promise<InstalledXcode> in
            self.approveLicense(for: xcode, passwordInput: passwordInput).map { xcode }
        }
        .then { xcode -> Promise<Void> in
            self.installComponents(for: xcode, passwordInput: passwordInput)
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

    func verifySecurityAssessment(of url: URL) -> Promise<Void> {
        return Current.shell.spctlAssess(url).asVoid()
            .recover { _ in throw Error.failedSecurityAssessment }
    }

    func verifySigningCertificate(of url: URL) -> Promise<Void> {
        return Current.shell.codesignVerify(url)
            .recover { _ -> Promise<ProcessOutput> in throw Error.codesignVerifyFailed }
            .map { output -> CertificateInfo in
                // codesign prints to stderr
                return self.parseCertificateInfo(output.err)
            }
            .done { cert in
                guard
                    cert.teamIdentifier == XcodeInstaller.XcodeTeamIdentifier,
                    cert.authority == XcodeInstaller.XcodeCertificateAuthority
                else { throw Error.codesignVerifyFailed }
            }
    }

    public struct CertificateInfo {
        public var authority: [String]
        public var teamIdentifier: String
        public var bundleIdentifier: String
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

    func authenticateSudoerIfNecessary(passwordInput: @escaping () -> Promise<String>) -> Promise<String?> {
        return firstly { () -> Promise<String?> in
            Current.shell.validateSudoAuthentication().map { _ in return nil }
        }
        .recover { _ -> Promise<String?> in
            return passwordInput().map(Optional.init)
        }
    }

    func enableDeveloperMode(passwordInput: @escaping () -> Promise<String>) -> Promise<Void> {
        return firstly { () -> Promise<String?> in
            authenticateSudoerIfNecessary(passwordInput: passwordInput)
        }
        .then { possiblePassword -> Promise<String?> in
            return Current.shell.devToolsSecurityEnable(possiblePassword).map { _ in possiblePassword }
        }
        .then { possiblePassword in
            return Current.shell.addStaffToDevelopersGroup(possiblePassword).asVoid()
        }
    }

    func approveLicense(for xcode: InstalledXcode, passwordInput: @escaping () -> Promise<String>) -> Promise<Void> {
        return firstly { () -> Promise<String?> in
            authenticateSudoerIfNecessary(passwordInput: passwordInput)
        }
        .then { possiblePassword in
            return Current.shell.acceptXcodeLicense(xcode, possiblePassword).asVoid()
        }
    }

    func installComponents(for xcode: InstalledXcode, passwordInput: @escaping () -> Promise<String>) -> Promise<Void> {
        return firstly { () -> Promise<String?> in
            authenticateSudoerIfNecessary(passwordInput: passwordInput)
        }
        .then { possiblePassword -> Promise<Void> in
            Current.shell.runFirstLaunch(xcode, possiblePassword).asVoid()
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
