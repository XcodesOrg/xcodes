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
            return run(Path.root.usr.bin.xip, "--expand", source.path)
        }
        .map { output -> URL in
            let xcodeURL = source.deletingLastPathComponent().appendingPathComponent("Xcode.app")
            let xcodeBetaURL = source.deletingLastPathComponent().appendingPathComponent("Xcode-Beta.app")
            if FileManager.default.fileExists(atPath: xcodeURL.path) {
                try FileManager.default.moveItem(at: xcodeURL, to: destination)
            }
            else if FileManager.default.fileExists(atPath: xcodeBetaURL.path) {
                try FileManager.default.moveItem(at: xcodeBetaURL, to: destination)
            }

            return destination
        }
    }

    func verifySecurityAssessment(of url: URL) -> Promise<Bool> {
        return run(Path.root.usr.sbin.spctl, "--assess", "--verbose", "--type", "execute", url.path)
            .map { $0.status == 0 }
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
        return run(Path.root.usr.bin.codesign, "-vv", "-d", "\"\(url.path)\"")
            .map { output in
                guard output.status == 0 else { exit(output.status) }

                let rawInfo = String(data: output.out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
                return self.parseCertificateInfo(rawInfo)
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
        return run(Path.root.usr.bin.sudo, "/usr/sbin/DevToolsSecurity", "-enable")
            .then { _ in
                return run(Path.root.usr.bin.sudo, "/usr/sbin/dseditgroup", "-o", "edit", "-t", "group", "-a", "staff", "_developer").asVoid()
            }
    }

    func approveLicense(for xcode: InstalledXcode) -> Promise<Void> {
        return run(Path.root.usr.bin.sudo, xcode.path.join("/Contents/Developer/usr/bin/xcodebuild").string, "-license", "accept").asVoid()
    }

    func installComponents(for xcode: InstalledXcode) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            run(Path.root.usr.bin.sudo, xcode.path.join("/Contents/Developer/usr/bin/xcodebuild").string, "-runFirstLaunch").asVoid()
        }
        .then { () -> Promise<(String, String, String)> in
            return when(fulfilled:
                run(Path.root.usr.bin.sw_vers, "-buildVersion")
                    .map { String(data: $0.out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)! },
                run(Path.root.usr.libexec.PlistBuddy, "-c", "\"Print :ProductBuildVersion\"", "\"\(xcode.path.string)/Contents/version.plist\"")
                    .map { String(data: $0.out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)! },
                run(Path.root.usr.bin.getconf, "DARWIN_USER_CACHE_DIR")
                    .map { String(data: $0.out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)! }
            )
        }
        .then { macOSBuildVersion, toolsVersion, cacheDirectory -> Promise<Void> in
            return run(Path.root.usr.bin/"touch", "\(cacheDirectory)com.apple.dt.Xcode.InstallCheckCache_\(macOSBuildVersion)_\(toolsVersion)").asVoid()
        }
    }
}
