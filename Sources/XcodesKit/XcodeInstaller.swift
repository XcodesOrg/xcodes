import Foundation
import PromiseKit
import Path
import AppleAPI

/// Downloads and installs Xcodes
public final class XcodeInstaller {
    static let XcodeTeamIdentifier = "59GAB85EFG"
    static let XcodeCertificateAuthority = ["Software Signing", "Apple Code Signing Certification Authority", "Apple Root CA"]

    public enum Error: Swift.Error, Equatable {
        case failedToMoveXcodeToApplications
        case failedSecurityAssessment(xcode: InstalledXcode, output: String)
        case codesignVerifyFailed
        case unsupportedFileFormat(extension: String)
    }

    public init() {}

    public func downloadOrUseExistingArchive(for xcode: Xcode, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        // Check to see if the archive is in the expected path in case it was downloaded but failed to install
        let expectedArchivePath = Path.xcodesApplicationSupport/"Xcode-\(xcode.version).\(xcode.filename.suffix(fromLast: "."))"
        if Current.files.fileExistsAtPath(expectedArchivePath.string) {
            print("Found existing archive that will be used for installation at \(expectedArchivePath).")
            return Promise.value(expectedArchivePath.url)
        }
        else {
            return downloadXcode(xcode, progressChanged: progressChanged)
        }
    }

    public func downloadXcode(_ xcode: Xcode, progressChanged: @escaping (Progress) -> Void) -> Promise<URL> {
        let destination = Path.xcodesApplicationSupport/"Xcode-\(xcode.version).\(xcode.filename.suffix(fromLast: "."))"
        let resumeDataPath = Path.xcodesApplicationSupport/"Xcode-\(xcode.version).resumedata"
        let persistedResumeData = Current.files.contents(atPath: resumeDataPath.string)
        
        return attemptResumableTask(maximumRetryCount: 3) { resumeData in
            let (progress, promise) = Current.network.downloadTask(with: xcode.url,
                                                                   to: destination.url,
                                                                   resumingWith: resumeData ?? persistedResumeData)
            progressChanged(progress)
            return promise.map { $0.saveLocation }
        }
        .tap { result in
            self.persistOrCleanUpResumeData(at: resumeDataPath, for: result)
        }
    }

    public func installArchivedXcode(_ xcode: Xcode, at archiveURL: URL, archiveTrashed: @escaping (URL) -> Void, passwordInput: @escaping () -> Promise<String>) -> Promise<Void> {
        return firstly { () -> Promise<InstalledXcode> in
            let destinationURL = Path.root.join("Applications").join("Xcode-\(xcode.version.descriptionWithoutBuildMetadata).app").url
            switch archiveURL.pathExtension {
            case "xip":
                return try unarchiveAndMoveXIP(at: archiveURL, to: destinationURL).map { xcodeURL in
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
                throw Error.unsupportedFileFormat(extension: archiveURL.pathExtension)
            }
        }
        .then { xcode -> Promise<InstalledXcode> in
            try Current.files.trashItem(at: archiveURL)
            archiveTrashed(archiveURL)

            return when(fulfilled: self.verifySecurityAssessment(of: xcode),
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

    public func verifySecurityAssessment(of xcode: InstalledXcode) -> Promise<Void> {
        return Current.shell.spctlAssess(xcode.path.url)
            .recover { (error: Swift.Error) throws -> Promise<ProcessOutput> in
                var output = ""
                if case let Process.PMKError.execution(_, possibleOutput, possibleError) = error {
                    output = [possibleOutput, possibleError].compactMap { $0 }.joined(separator: "\n")
                }
                throw Error.failedSecurityAssessment(xcode: xcode, output: output)
            }
            .asVoid()
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

private extension XcodeInstaller {
    func persistOrCleanUpResumeData<T>(at path: Path, for result: Result<T>) {
        switch result {
        case .fulfilled:
            try? Current.files.removeItem(at: path.url)
        case .rejected(let error):
            guard let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data else { return }
            Current.files.createFile(atPath: path.string, contents: resumeData)
        }
    }
}

/// Attempt and retry a task that fails with resume data up to `maximumRetryCount` times
private func attemptResumableTask<T>(maximumRetryCount: Int = 3, delayBeforeRetry: DispatchTimeInterval = .seconds(2), _ body: @escaping (Data?) -> Promise<T>) -> Promise<T> {
    var attempts = 0
    func attempt(with resumeData: Data? = nil) -> Promise<T> {
        attempts += 1
        return body(resumeData).recover { error -> Promise<T> in
            guard
                attempts < maximumRetryCount,
                let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            else { throw error }

            return after(delayBeforeRetry).then(on: nil) { attempt(with: resumeData) }
        }
    }
    return attempt()
}
