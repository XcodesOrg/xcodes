import Foundation
@preconcurrency import Path
@preconcurrency import Version
import LegibleError
import Rainbow
import Unxip
import XcodesKit

/// Downloads and installs Xcodes
public final class XcodeInstaller: Sendable {
    static let XcodeTeamIdentifier = XcodesKit.XcodeSignatureVerifier.expectedTeamIdentifier
    static let XcodeCertificateAuthority = XcodesKit.XcodeSignatureVerifier.expectedCertificateAuthority

    public enum Error: LocalizedError, Equatable {
        case damagedXIP(url: URL)
        case notEnoughFreeSpaceToExpandArchive(url: URL)
        case failedToMoveXcodeToDestination(Path)
        case failedSecurityAssessment(xcode: InstalledXcode, output: String)
        case codesignVerifyFailed(output: String)
        case unexpectedCodeSigningIdentity(identifier: String, certificateAuthority: [String])
        case unsupportedFileFormat(extension: String)
        case missingSudoerPassword
        case unavailableVersion(Version)
        case noReleaseVersionAvailable
        case noPrereleaseVersionAvailable
        case versionAlreadyInstalled(InstalledXcode)
        case invalidVersion(String)
        case versionNotInstalled(Version)
        case unauthorized

        public var errorDescription: String? {
            switch self {
            case .damagedXIP(let url):
                return "The archive \"\(url.lastPathComponent)\" is damaged and can't be expanded."
            case .notEnoughFreeSpaceToExpandArchive(let url):
                return "The archive \"\(url.lastPathComponent)\" couldn't be expanded because the selected volume doesn't have enough free space."
            case .failedToMoveXcodeToDestination(let destination):
                return "Failed to move Xcode to the \(destination.string) directory."
            case .failedSecurityAssessment(let xcode, let output):
                return """
                       Xcode \(xcode.version) failed its security assessment with the following output:
                       \(output)
                       It remains installed at \(xcode.path) if you wish to use it anyways.
                       """
            case .codesignVerifyFailed(let output):
                return """
                       The downloaded Xcode failed code signing verification with the following output:
                       \(output)
                       """
            case .unexpectedCodeSigningIdentity(let identity, let certificateAuthority):
                return """
                       The downloaded Xcode doesn't have the expected code signing identity.
                       Got:
                         \(identity)
                         \(certificateAuthority)
                       Expected:
                         \(XcodeInstaller.XcodeTeamIdentifier)
                         \(XcodeInstaller.XcodeCertificateAuthority)
                       """
            case .unsupportedFileFormat(let fileExtension):
                return "xcodes doesn't (yet) support installing Xcode from the \(fileExtension) file format."
            case .missingSudoerPassword:
                return "Missing password. Please try again."
            case let .unavailableVersion(version):
                return "Could not find version \(version.appleDescription)."
            case .noReleaseVersionAvailable:
                return "No release versions available."
            case .noPrereleaseVersionAvailable:
                return "No prerelease versions available."
            case let .versionAlreadyInstalled(installedXcode):
                return "\(installedXcode.version.appleDescription) is already installed at \(installedXcode.path)"
            case let .invalidVersion(version):
                return "\(version) is not a valid version number."
            case let .versionNotInstalled(version):
                return "\(version.appleDescription) is not installed."
            case .unauthorized:
                return """
                        Received 403: Unauthorized. This can happen when either:
                        1. Apple Developer Terms and Conditions were not accepted at https://developer.apple.com/
                        2. Apple ID authorization was revoked for some other reason
                       """
            }
        }
    }

    /// A numbered step
    enum InstallationStep: CustomStringConvertible {
        case downloading(version: String, progress: String?, willInstall: Bool)
        case unarchiving(experimentalUnxip: Bool)
        case moving(destination: String)
        case cleaningArchive(archiveName: String, shouldDelete: Bool)
        case checkingSecurity
        case finishing

        var description: String {
            switch self {
            case .downloading(_, _, let willInstall) where !willInstall:
                return "(\(stepNumber)/\(InstallationStep.downloadStepCount)) \(message)"
            default:
                return "(\(stepNumber)/\(InstallationStep.installStepCount)) \(message)"
            }
        }

        var message: String {
            switch self {
            case .downloading(let version, let progress, _):
                if let progress = progress {
                    return "Downloading Xcode \(version): \(progress)"
                } else {
                    return "Downloading Xcode \(version)"
                }
            case .unarchiving(let experimentalUnxip):
                let hint = experimentalUnxip ?
                    "Using experimental unxip. If you encounter any issues, remove the flag and try again" :
                    "Using regular unxip. Try passing `--experimental-unxip` for a faster unxip process"
                return
                    """
                    Unarchiving Xcode (This can take a while)
                    \(hint)
                    """
            case .moving(let destination):
                return "Moving Xcode to \(destination)"
            case .cleaningArchive(let archiveName, let shouldDelete):
                if shouldDelete {
                    return "Deleting Xcode archive \(archiveName)"
                }
                return "Moving Xcode archive \(archiveName) to the Trash"
            case .checkingSecurity:
                return "Checking security assessment and code signing"
            case .finishing:
                return "Finishing installation"
            }
        }

        var stepNumber: Int {
            switch self {
            case .downloading:      return 1
            case .unarchiving:      return 2
            case .moving:           return 3
            case .cleaningArchive:  return 4
            case .checkingSecurity: return 5
            case .finishing:        return 6
            }
        }

        static var downloadStepCount: Int {
            return 1
        }

        static var installStepCount: Int {
            return 6
        }
    }

    private let sessionService: AppleSessionService
    private let xcodeList: XcodeList
    private let currentOSVersion: @Sendable () -> OperatingSystemVersion

    public init(
        xcodeList: XcodeList,
        sessionService: AppleSessionService,
        currentOSVersion: @escaping @Sendable () -> OperatingSystemVersion = { ProcessInfo.processInfo.operatingSystemVersion }
    ) {
        self.xcodeList = xcodeList
        self.sessionService = sessionService
        self.currentOSVersion = currentOSVersion
    }

    public enum InstallationType: Sendable {
        case version(String)
        case path(String, Path)
        case latest
        case latestPrerelease

        var shouldRetryAfterDamagedArchive: Bool {
            switch self {
            case .path:
                return false
            case .version, .latest, .latestPrerelease:
                return true
            }
        }
    }

    public func install(_ installationType: InstallationType, dataSource: DataSource, downloader: Downloader, destination: Path, experimentalUnxip: Bool = false, emptyTrash: Bool, noSuperuser: Bool) async throws -> InstalledXcode {
        let xcode = try await xcodeInstallRetryService.install(
            shouldRetryAfterDamagedArchive: installationType.shouldRetryAfterDamagedArchive,
            attempt: { _ in
                let (xcode, url) = try await getXcodeArchive(installationType, dataSource: dataSource, downloader: downloader, destination: destination, willInstall: true)
                return try await installArchivedXcode(xcode, at: url, to: destination, experimentalUnxip: experimentalUnxip, emptyTrash: emptyTrash, noSuperuser: noSuperuser)
            },
            onRetryDamagedArchive: { error, _ in
                Current.logging.log(error.legibleLocalizedDescription.red)
                Current.logging.log("Removing damaged XIP and re-attempting installation.\n")
            }
        )
        Current.logging.log("\nXcode \(xcode.version.descriptionWithoutBuildMetadata) has been installed to \(xcode.path.string)".green)
        return xcode
    }

    private var xcodeInstallRetryService: XcodeInstallRetryService {
        XcodeInstallRetryService(
            damagedArchiveURL: { error in
                guard case XcodeInstaller.Error.damagedXIP(let url) = error else { return nil }
                return url
            },
            removeDamagedArchive: { url in
                try Current.files.removeItem(at: url)
            }
        )
    }

    public func download(_ installation: InstallationType, dataSource: DataSource, downloader: Downloader, destinationDirectory: Path) async throws {
        let (xcode, url) = try await getXcodeArchive(installation, dataSource: dataSource, downloader: downloader, destination: destinationDirectory, willInstall: false)
        let destination = destinationDirectory.url.appendingPathComponent(url.lastPathComponent)
        try Current.files.moveItem(at: url, to: destination)
        Current.logging.log("\nXcode \(xcode.version.descriptionWithoutBuildMetadata) has been downloaded to \(destination.path)".green)
        Current.shell.exit(0)
    }

    private func getXcodeArchive(_ installationType: InstallationType, dataSource: DataSource, downloader: Downloader, destination: Path, willInstall: Bool) async throws -> (Xcode, URL) {
        let resolutionService = XcodeInstallResolutionService(versionFile: XcodeVersionFileService(
            fileExists: { path in Current.files.fileExists(atPath: path) },
            contentsAtPath: { path in Current.files.contents(atPath: path) }
        ))

        switch installationType {
        case .latest:
            Current.logging.log("Updating...")
            let availableXcodes = try await update(dataSource: dataSource)

            let resolution = try mapInstallResolutionError {
                try resolutionService.resolve(
                    .latest,
                    availableXcodes: availableXcodes,
                    installedXcodes: Current.files.installedXcodes(destination),
                    willInstall: willInstall
                )
            }
            return try await archive(for: resolution, dataSource: dataSource, downloader: downloader, willInstall: willInstall)
        case .latestPrerelease:
            Current.logging.log("Updating...")
            let availableXcodes = try await update(dataSource: dataSource)

            let resolution = try mapInstallResolutionError {
                try resolutionService.resolve(
                    .latestPrerelease,
                    availableXcodes: availableXcodes,
                    installedXcodes: Current.files.installedXcodes(destination),
                    willInstall: willInstall
                )
            }
            return try await archive(for: resolution, dataSource: dataSource, downloader: downloader, willInstall: willInstall)
        case .path(let versionString, let path):
            let resolution = try mapInstallResolutionError {
                try resolutionService.resolve(
                    .path(versionString: versionString, path: path),
                    availableXcodes: [],
                    installedXcodes: [],
                    willInstall: willInstall
                )
            }
            return try await archive(for: resolution, dataSource: dataSource, downloader: downloader, willInstall: willInstall)
        case .version(let versionString):
            let resolution = try mapInstallResolutionError {
                try resolutionService.resolve(
                    .version(versionString),
                    availableXcodes: [],
                    installedXcodes: Current.files.installedXcodes(destination),
                    willInstall: willInstall
                )
            }
            return try await archive(for: resolution, dataSource: dataSource, downloader: downloader, willInstall: willInstall)
        }
    }

    private func archive(for resolution: XcodeInstallResolution, dataSource: DataSource, downloader: Downloader, willInstall: Bool) async throws -> (Xcode, URL) {
        switch resolution {
        case let .download(version, resolvedXcode):
            if let resolvedXcode {
                let releaseType = resolvedXcode.version.isPrerelease ? "prerelease" : "release"
                Current.logging.log("Latest \(releaseType) version available is \(resolvedXcode.version.appleDescription)")
            }
            return try await downloadXcode(version: version, dataSource: dataSource, downloader: downloader, willInstall: willInstall)
        case let .localArchive(xcode, url):
            return (xcode, url)
        }
    }

    private func mapInstallResolutionError<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as XcodeInstallResolutionError {
            switch error {
            case let .invalidVersion(version):
                throw Error.invalidVersion(version)
            case .noReleaseVersionAvailable:
                throw Error.noReleaseVersionAvailable
            case .noPrereleaseVersionAvailable:
                throw Error.noPrereleaseVersionAvailable
            case let .versionAlreadyInstalled(installedXcode):
                throw Error.versionAlreadyInstalled(installedXcode)
            }
        }
    }

    private func downloadXcode(version: Version, dataSource: DataSource, downloader: Downloader, willInstall: Bool) async throws -> (Xcode, URL) {
        switch dataSource {
        case .apple:
            // When using the Apple data source, an authenticated session is required for both
            // downloading the list of Xcodes as well as to actually download Xcode, so we'll
            // establish our session right at the start.
            try await sessionService.loginIfNeeded()

        case .xcodeReleases:
            // When using the Xcode Releases data source, we only need to establish an anonymous
            // session once we're ready to download Xcode. Doing that requires us to know the
            // URL we want to download though (and we may not know that yet), so we don't need
            // to do anything session-related quite yet.
            try await sessionService.loginIfNeeded()
        }

        if xcodeList.shouldUpdateBeforeDownloading(version: version) {
            _ = try await xcodeList.updateAvailableXcodes(dataSource: dataSource)
        }

        guard let xcode = xcodeList.availableXcodes.first(withVersion: version) else {
            throw Error.unavailableVersion(version)
        }

        if willInstall {
            let currentOSVersion = currentOSVersion()
            switch XcodeCompatibilityService().status(for: xcode, currentOSVersion: currentOSVersion) {
            case .supported:
                break
            case let .unsupported(requiredMacOSVersion, currentMacOSVersion):
                Current.logging.log("Warning: Xcode \(xcode.version.appleDescription) requires macOS \(requiredMacOSVersion) or later. This Mac is running macOS \(currentMacOSVersion).".yellow)
            }
        }

        switch dataSource {
        case .apple:
            /// We already established a session for the Apple data source at the beginning of
            /// this download, so we don't need to do anything session-related at this point.
            break

        case .xcodeReleases:
            /// Now that we've used Xcode Releases to determine what URL we should use to
            /// download Xcode, we can use that to establish an anonymous session with Apple.
            // As of Nov 2022, the `validateADCSession` return 403 forbidden for Xcode versions (works with runtimes)
            // try await sessionService.validateADCSession(path: xcode.downloadPath)
            // -------
            // We need the cookies from its response in order to download Xcodes though,
            // so perform it here first just to be sure.
            _ = try await Current.network.data(for: URLRequest.developerDownloads)
        }

        if Current.shell.isatty() {
            // Move to the next line so that the escape codes below can move up a line and overwrite it with download progress
            Current.logging.log("")
        } else {
            Current.logging.log("\(InstallationStep.downloading(version: xcode.version.description, progress: nil, willInstall: willInstall))")
        }
        let versionDescription = xcode.version.description
        let observation = ProgressObservation()
        defer { observation.invalidate() }

        let url = try await downloadOrUseExistingArchive(for: xcode, downloader: downloader, willInstall: willInstall) { progress in
            observation.observe(progress) { progress in
                guard Current.shell.isatty() else { return }

                // These escape codes move up a line and then clear to the end
                let progressString = NumberFormatter.localizedString(from: NSNumber(value: progress.fractionCompleted), number: .percent)
                Current.logging.log("\u{1B}[1A\u{1B}[K\(InstallationStep.downloading(version: versionDescription, progress: progressString, willInstall: willInstall))")
            }
        }
        return (xcode, url)
    }

    public func downloadOrUseExistingArchive(for xcode: Xcode, downloader: Downloader, willInstall: Bool, progressChanged: @escaping @Sendable (Progress) -> Void) async throws -> URL {
        let archive = XcodeArchive(xcode)
        let archiveDownloader = XcodeArchiveDownloader(downloader)
        let service = archiveService(downloader: downloader)

        if let existingArchiveURL = service.existingArchiveURL(for: archive, downloader: archiveDownloader) {
            if willInstall {
                Current.logging.log("(1/\(InstallationStep.installStepCount)) Found existing archive that will be used for installation at \(Path(url: existingArchiveURL)!).")
            } else {
                Current.logging.log("(1/\(InstallationStep.downloadStepCount)) Found existing archive at \(Path(url: existingArchiveURL)!).")
            }
            return existingArchiveURL
        }

        return try await service.archiveURL(for: archive, downloader: archiveDownloader, progressChanged: progressChanged)
    }

    private func archiveService(downloader: Downloader) -> XcodeArchiveService {
        XcodeArchiveService(
            applicationSupportPath: .xcodesApplicationSupport,
            fileExists: { Current.files.fileExistsAtPath($0.string) },
            download: { archive, destination, _, progressChanged in
                try await downloader.download(url: archive.downloadURL, to: destination, progressChanged: progressChanged)
            }
        )
    }

    public func installArchivedXcode(_ xcode: Xcode, at archiveURL: URL, to destination: Path, experimentalUnxip: Bool = false, emptyTrash: Bool, noSuperuser: Bool) async throws -> InstalledXcode {
        let installedXcode: InstalledXcode
        do {
            installedXcode = try await xcodeArchiveInstallService(experimentalUnxip: experimentalUnxip, destination: destination)
                .installArchivedXcode(
                    xcode,
                    at: archiveURL,
                    cleanArchive: { archiveURL in
                        if emptyTrash {
                            try Current.files.removeItem(at: archiveURL)
                        } else {
                            try Current.files.trashItem(at: archiveURL)
                        }
                    }
                ) { step in
                    switch step {
                    case .unarchive(.unarchiving):
                        Current.logging.log(InstallationStep.unarchiving(experimentalUnxip: experimentalUnxip).description)
                    case let .unarchive(.moving(destination)):
                        Current.logging.log(InstallationStep.moving(destination: destination).description)
                    case let .cleaningArchive(archiveName):
                        Current.logging.log(InstallationStep.cleaningArchive(archiveName: archiveName, shouldDelete: emptyTrash).description)
                    case .checkingSecurity:
                        Current.logging.log(InstallationStep.checkingSecurity.description)
                    }
                }
        } catch {
            throw mapXcodeArchiveInstallError(error, destination: destination)
        }

        if noSuperuser {
            Current.logging.log(InstallationStep.finishing.description)
            Current.logging.log("Skipping asking for superuser privileges.")
            return installedXcode
        }
        return try await postInstallXcode(installedXcode)
    }

    public func postInstallXcode(_ xcode: InstalledXcode) async throws -> InstalledXcode {
        try await postInstallXcode(xcode, passwordInput: {
            Current.logging.log("xcodes requires superuser privileges in order to finish installation.")
            guard let password = Current.shell.readSecureLine(prompt: "macOS User Password: ") else { throw Error.missingSudoerPassword }
            return password + "\n"
        })
    }

    public func postInstallXcode(_ xcode: InstalledXcode, passwordInput: @escaping @Sendable () async throws -> String) async throws -> InstalledXcode {
        Current.logging.log(InstallationStep.finishing.description)
        try await xcodePostInstallWorkflowService(passwordInput: passwordInput)
            .performPostInstallSteps(for: xcode)
        return xcode
    }

    public func uninstallXcode(_ versionString: String, directory: Path, emptyTrash: Bool) async throws {
        let installedXcode: InstalledXcode
        if let version = Version(xcodeVersion: versionString),
           let matchingXcode = Current.files.installedXcodes(directory).first(withVersion: version) {
            installedXcode = matchingXcode
        } else {
            if let version = Version(xcodeVersion: versionString) {
                Current.logging.log(Error.versionNotInstalled(version).legibleLocalizedDescription)
            } else {
                Current.logging.log(Error.invalidVersion(versionString).legibleLocalizedDescription)
            }
            installedXcode = try await chooseFromInstalledXcodesInteractivelyAsync(currentPath: "", directory: directory)
        }

        let result = try XcodesKit.XcodeUninstallService(
            removeItem: { url in try Current.files.removeItem(at: url) },
            trashItem: { url in try Current.files.trashItem(at: url) }
        ).uninstall(installedXcode, emptyTrash: emptyTrash)

        if let trashURL = result.trashURL {
            Current.logging.log("Xcode \(installedXcode.version.appleDescription) moved to Trash: \(trashURL.path)".green)
        } else {
            Current.logging.log("Xcode \(installedXcode.version.appleDescription) deleted".green)
        }
        Current.shell.exit(0)
    }

    func update(dataSource: DataSource) async throws -> [Xcode] {
        if dataSource == .apple {
            try await sessionService.loginIfNeeded()
        }
        return try await xcodeList.updateAvailableXcodes(dataSource: dataSource)
    }

    public func updateAndPrint(dataSource: DataSource, directory: Path) async throws {
        let xcodes = try await update(dataSource: dataSource)
        try await printAvailableXcodes(xcodes, installed: Current.files.installedXcodes(directory), dataSource: dataSource)
        Current.shell.exit(0)
    }

    public func printAvailableXcodes(_ xcodes: [Xcode], installed installedXcodes: [InstalledXcode], dataSource: DataSource = .xcodeReleases) async throws {
        let output = try await Current.shell.xcodeSelectPrintPath()

        XcodeListPresentationService()
            .availableRows(
                availableXcodes: xcodes,
                installedXcodes: installedXcodes,
                selectedXcodePath: output.out,
                dataSource: dataSource
            )
            .forEach { row in
                var output = row.versionDescription
                if row.isInstalled {
                    output += row.isSelected
                        ? " (\("Installed".blue), \("Selected".green))"
                        : " (\("Installed".blue))"
                }
                Current.logging.log(output)
            }
    }

    public func printInstalledXcodes(directory: Path) async throws {
        let pathOutput = try await Current.shell.xcodeSelectPrintPath()
        let selectedString = "(Selected)"
        let presentationService = XcodeListPresentationService()
        let rows = presentationService.installedRows(
            installedXcodes: Current.files.installedXcodes(directory),
            selectedXcodePath: pathOutput.out
        )

        for line in presentationService.installedLines(rows: rows, interactive: Current.shell.isatty(), selectedMarker: selectedString) {
            Current.logging.log(line.replacingOccurrences(of: selectedString, with: selectedString.green))
        }
    }

    private func xcodeArchiveInstallService(experimentalUnxip: Bool, destination: Path) -> XcodesKit.XcodeArchiveInstallService {
        XcodesKit.XcodeArchiveInstallService(
            destinationDirectory: destination,
            unarchiveService: xcodeUnarchiveService(experimentalUnxip: experimentalUnxip),
            validationService: xcodeValidationService,
            fileExists: { path in Current.files.fileExists(atPath: path) },
            makeInstalledXcode: { path in
                InstalledXcode(
                    path: path,
                    contentsAtPath: { path in Current.files.contents(atPath: path) },
                    loadArchitectures: Current.shell.archs
                )
            }
        )
    }

    private func mapXcodeArchiveInstallError(_ error: Swift.Error, destination: Path) -> Swift.Error {
        switch error {
        case let error as XcodesKit.XcodeArchiveInstallError:
            switch error {
            case let .failedToMoveXcodeToDestination(destination):
                return Error.failedToMoveXcodeToDestination(destination)
            case let .unsupportedFileFormat(fileExtension):
                return Error.unsupportedFileFormat(extension: fileExtension)
            }
        case let error as XcodesKit.XcodeUnarchiveError:
            switch error {
            case let .damagedXIP(url):
                return Error.damagedXIP(url: url)
            case let .notEnoughFreeSpaceToExpandArchive(url):
                return Error.notEnoughFreeSpaceToExpandArchive(url: url)
            }
        case let error as XcodesKit.XcodeValidationError:
            switch error {
            case let .failedSecurityAssessment(xcode, output):
                return Error.failedSecurityAssessment(xcode: xcode, output: output)
            case let .codesignVerifyFailed(output):
                return Error.codesignVerifyFailed(output: output)
            case let .unexpectedCodeSigningIdentity(identifier, certificateAuthority):
                return Error.unexpectedCodeSigningIdentity(
                    identifier: identifier,
                    certificateAuthority: certificateAuthority
                )
            }
        default:
            return error
        }
    }

    public func printXcodePath(ofVersion versionString: String, searchingIn directory: Path) async throws {
            guard let version = Version(xcodeVersion: versionString) else {
                throw Error.invalidVersion(versionString)
            }
            let installedXcodes = Current.files.installedXcodes(directory)
                .sorted { $0.version < $1.version }
            guard let installedXcode = installedXcodes.first(withVersion: version) else {
                throw Error.versionNotInstalled(version)
            }
            Current.logging.log(installedXcode.path.string)
    }

    private func xcodeUnarchiveService(experimentalUnxip: Bool) -> XcodesKit.XcodeUnarchiveService {
        XcodesKit.XcodeUnarchiveService(
            unarchive: { source in
                if experimentalUnxip, #available(macOS 11, *) {
                    let output = source.deletingLastPathComponent()
                    let options = UnxipOptions(input: source, output: output)
                    try await Unxip(options: options).run()
                } else {
                    _ = try await Current.shell.unxip(source)
                }
            },
            fileExists: { path in Current.files.fileExists(atPath: path) },
            moveItem: { source, destination in try Current.files.moveItem(at: source, to: destination) },
            removeItem: { url in try Current.files.removeItem(at: url) }
        )
    }

    public func verifySecurityAssessment(of xcode: InstalledXcode) async throws {
        do {
            try await xcodeValidationService.verifySecurityAssessment(of: xcode)
        } catch let error as XcodesKit.XcodeValidationError {
            switch error {
            case let .failedSecurityAssessment(xcode, output):
                throw Error.failedSecurityAssessment(xcode: xcode, output: output)
            case let .codesignVerifyFailed(output):
                throw Error.codesignVerifyFailed(output: output)
            case let .unexpectedCodeSigningIdentity(identifier, certificateAuthority):
                throw Error.unexpectedCodeSigningIdentity(
                    identifier: identifier,
                    certificateAuthority: certificateAuthority
                )
            }
        }
    }

    func verifySigningCertificate(of url: URL) async throws {
        do {
            try await xcodeValidationService.verifySigningCertificate(of: url)
        } catch let error as XcodesKit.XcodeValidationError {
            switch error {
            case let .failedSecurityAssessment(xcode, output):
                throw Error.failedSecurityAssessment(xcode: xcode, output: output)
            case let .codesignVerifyFailed(output):
                throw Error.codesignVerifyFailed(output: output)
            case let .unexpectedCodeSigningIdentity(identifier, certificateAuthority):
                throw Error.unexpectedCodeSigningIdentity(
                    identifier: identifier,
                    certificateAuthority: certificateAuthority
                )
            }
        }
    }

    public func parseCertificateInfo(_ rawInfo: String) -> XcodesKit.XcodeSignature {
        XcodesKit.XcodeSignatureVerifier().parse(rawInfo)
    }

    private var xcodeValidationService: XcodesKit.XcodeValidationService {
        XcodesKit.XcodeValidationService(
            assessSecurity: { url in try await Current.shell.spctlAssess(url) },
            verifyCodesign: { url in try await Current.shell.codesignVerify(url) }
        )
    }

    private func xcodePostInstallWorkflowService(passwordInput: @escaping @Sendable () async throws -> String) -> XcodesKit.XcodePostInstallWorkflowService {
        return XcodesKit.XcodePostInstallWorkflowService(
            enableDeveloperMode: { try await Self.enableDeveloperMode(passwordInput: passwordInput) },
            approveLicense: { try await Self.approveLicense(for: $0, passwordInput: passwordInput) },
            installComponents: { try await Self.installComponents(for: $0, passwordInput: passwordInput) }
        )
    }

    private static func enableDeveloperMode(passwordInput: @escaping @Sendable () async throws -> String) async throws {
        let possiblePassword = try await Current.shell.authenticateSudoerIfNecessaryAsync(passwordInput: passwordInput)
        try await xcodePostInstallPreparationService(password: possiblePassword).enableDeveloperMode()
    }

    private static func approveLicense(for xcode: InstalledXcode, passwordInput: @escaping @Sendable () async throws -> String) async throws {
        let possiblePassword = try await Current.shell.authenticateSudoerIfNecessaryAsync(passwordInput: passwordInput)
        try await xcodePostInstallPreparationService(password: possiblePassword).approveLicense(for: xcode)
    }

    private static func installComponents(for xcode: InstalledXcode, passwordInput: @escaping @Sendable () async throws -> String) async throws {
        let possiblePassword = try await Current.shell.authenticateSudoerIfNecessaryAsync(passwordInput: passwordInput)
        try await xcodePostInstallService(password: possiblePassword).installComponents(for: xcode)
    }

    private static func xcodePostInstallService(password: String?) -> XcodesKit.XcodePostInstallService {
        XcodesKit.XcodePostInstallService(
            runFirstLaunch: { xcode in _ = try await Current.shell.runFirstLaunch(xcode, password) },
            getUserCacheDirectory: { try await Current.shell.getUserCacheDir() },
            getMacOSBuildVersion: { try await Current.shell.buildVersion() },
            getXcodeBuildVersion: { xcode in try await Current.shell.xcodeBuildVersion(xcode) },
            touchInstallCheck: { cacheDirectory, macOSBuildVersion, toolsVersion in
                try await Current.shell.touchInstallCheck(cacheDirectory, macOSBuildVersion, toolsVersion)
            }
        )
    }

    private static func xcodePostInstallPreparationService(password: String?) -> XcodesKit.XcodePostInstallPreparationService {
        XcodesKit.XcodePostInstallPreparationService(
            enableDeveloperTools: { _ = try await Current.shell.devToolsSecurityEnable(password) },
            addStaffToDevelopersGroup: { _ = try await Current.shell.addStaffToDevelopersGroup(password) },
            acceptLicense: { xcode in _ = try await Current.shell.acceptXcodeLicense(xcode, password) }
        )
    }
}
