import Foundation
@preconcurrency import Version
@preconcurrency import Path
import Rainbow
import XcodesKit

public final class RuntimeInstaller: Sendable {
    public typealias XcodebuildRuntimeInstall = @Sendable (DownloadableRuntime, String?, @escaping RuntimeXcodebuildInstallService.ProgressChanged) async throws -> Void
    public typealias SelectedXcodeVersion = @Sendable () async throws -> Version?

    public let sessionService: AppleSessionService
    public let runtimeList: RuntimeList
    private let xcodebuildRuntimeInstall: XcodebuildRuntimeInstall
    private let selectedXcodeVersion: SelectedXcodeVersion
    private var runtimeService: RuntimeService {
        runtimeList.runtimeService
    }

    public init(
        runtimeList: RuntimeList,
        sessionService: AppleSessionService,
        xcodebuildRuntimeInstall: @escaping XcodebuildRuntimeInstall = { runtime, architecture, progressChanged in
            try await RuntimeXcodebuildInstallService().downloadAndInstall(
                runtime: runtime,
                architecture: architecture,
                progressChanged: progressChanged
            )
        },
        selectedXcodeVersion: SelectedXcodeVersion? = nil
    ) {
        self.runtimeList = runtimeList
        self.sessionService = sessionService
        self.xcodebuildRuntimeInstall = xcodebuildRuntimeInstall
        self.selectedXcodeVersion = selectedXcodeVersion ?? RuntimeInstaller.selectedXcodeVersionFromXcodebuild
    }

    public func printAvailableRuntimes(includeBetas: Bool, architectures: [ArchitectureFilter] = []) async throws {
        let presentationService = RuntimeListPresentationService()
        let downloadableRuntimeList = try await runtimeList.updateDownloadableRuntimeList()
        let installedRuntimes = try await runtimeList.installedRuntimes()
        let machineArchitecture = Current.shell.machineArchitecture()
        let effectiveArchitectures = architectures.isEmpty
            ? [ArchitectureFilter].defaultForMachine(machineHardwareName: machineArchitecture)
            : architectures

        for (platform, runtimes) in presentationService.rows(
            downloadableRuntimes: downloadableRuntimeList.runtimes,
            installedRuntimes: installedRuntimes,
            includeBetas: includeBetas,
            sdkToSeedMappings: downloadableRuntimeList.sdkToSeedMappings,
            architectures: effectiveArchitectures
        ) {
            Current.logging.log("-- \(platform.shortName) --")
            runtimes.forEach { Current.logging.log(line(for: $0)) }
        }
        Current.logging.log("\nNote: Bundled runtimes are indicated for the currently selected Xcode, more bundled runtimes may exist in other Xcode(s)")
        if architectures.isEmpty {
            let defaultVariant = ArchitectureVariant.defaultForMachine(machineHardwareName: machineArchitecture)
            let machineDescription = machineArchitecture ?? "unknown"
            let betaOption = includeBetas ? "Switch architecture" : "Include beta runtimes with `--include-betas`, or switch architecture"
            Current.logging.log("\nShowing runtimes for this Mac by default: \(defaultVariant.displayString) (\(machineDescription)). \(betaOption) with `--architecture arm64`, `--architecture x86_64`, `--architecture appleSilicon`, or `--architecture universal`.")
        }
    }

    private func line(for row: RuntimeListPresentationService.RuntimeRow) -> String {
        var string = row.visibleIdentifier
        if row.hasDuplicateVersion {
            string += " (\(row.build))"
        }
        if let kind = row.kind {
            switch kind {
            case .bundled:
                string += " (\("Bundled with selected Xcode".green))"
            case .legacyDownload, .diskImage, .cryptexDiskImage, .patchableCryptexDiskImage:
                string += " (\("Installed".blue))"
            }
        }
        return string
    }

    public func downloadRuntime(identifier: String, to destinationDirectory: Path, with downloader: Downloader, architectures: [ArchitectureFilter] = []) async throws {
        let matchedRuntime = try await getMatchingRuntime(identifier: identifier, architectures: architectures)
        guard matchedRuntime.url != nil else {
            throw Error.missingRuntimeSource(matchedRuntime.visibleIdentifier)
        }
        let runtimeName = downloadName(for: matchedRuntime, architectures: architectures)

        _ = try await downloadOrUseExistingArchive(runtime: matchedRuntime, to: destinationDirectory, downloader: downloader, runtimeName: runtimeName)
    }


    public func downloadAndInstallRuntime(identifier: String, to destinationDirectory: Path, with downloader: Downloader, shouldDelete: Bool, architectures: [ArchitectureFilter] = []) async throws {
        let matchedRuntime = try await getMatchingRuntime(identifier: identifier, architectures: architectures)

        let method = try await installMethod(for: matchedRuntime)
        let runtimeName = downloadName(for: matchedRuntime, architectures: architectures)

        switch method {
        case .archive:
            try await downloadAndInstallArchiveRuntime(
                matchedRuntime,
                to: destinationDirectory,
                with: downloader,
                deleteArchive: shouldDelete,
                runtimeName: runtimeName
            )
        case let .xcodebuild(architecture):
            try await downloadAndInstallUsingXcodeBuild(runtime: matchedRuntime, architecture: architecture, runtimeName: runtimeName)
        }
    }

    private func downloadAndInstallArchiveRuntime(
        _ runtime: DownloadableRuntime,
        to destinationDirectory: Path,
        with downloader: Downloader,
        deleteArchive: Bool,
        runtimeName: String
    ) async throws {
        switch runtime.contentType {
        case .package:
            guard Current.shell.isRoot() else {
                throw Error.rootNeeded
            }
            let dmgUrl = try await downloadOrUseExistingArchive(runtime: runtime, to: destinationDirectory, downloader: downloader, runtimeName: runtimeName)
            try await installFromPackage(dmgUrl: dmgUrl, runtime: runtime)
            deleteArchiveIfNeeded(dmgUrl, shouldDelete: deleteArchive)
        case .diskImage:
            let dmgUrl = try await downloadOrUseExistingArchive(runtime: runtime, to: destinationDirectory, downloader: downloader, runtimeName: runtimeName)
            try await runtimeArchiveInstallService.install(
                runtime: runtime,
                archiveURL: dmgUrl,
                deleteArchive: deleteArchive,
                stepChanged: { step in
                    switch step {
                    case .installing:
                        Current.logging.log("Installing Runtime")
                    case .trashingArchive:
                        Current.logging.log("Deleting Archive")
                    case .downloading:
                        break
                    }
                }
            )
        case .cryptexDiskImage, .patchableCryptexDiskImage:
            throw XcodesKitError("Installing via \(runtime.contentType.rawValue) not support. Please install manually.")
        }
    }

    private func getMatchingRuntime(identifier: String, architectures: [ArchitectureFilter] = []) async throws -> DownloadableRuntime {
        let downloadables = try await runtimeList.downloadableRuntimes()
        let matchingRuntimes = downloadables.filter {
            $0.visibleIdentifier == identifier || $0.simulatorVersion.buildUpdate == identifier
        }
        guard let runtime = preferredRuntime(from: matchingRuntimes, architectures: architectures) else {
            throw Error.unavailableRuntime(identifier)
        }
        return runtime
    }

    private func preferredRuntime(from runtimes: [DownloadableRuntime], architectures: [ArchitectureFilter] = []) -> DownloadableRuntime? {
        guard runtimes.count > 1 else { return runtimes.first }

        let machineArchitecture = Current.shell.machineArchitecture()
        let defaultFilters = architectures.isEmpty
            ? [ArchitectureFilter].defaultForMachine(machineHardwareName: machineArchitecture)
            : architectures
        return runtimes.first { runtime in
            guard let architectures = runtime.architectures else { return false }
            return defaultFilters.contains { $0.matches(architectures) }
        } ?? runtimes.matchingArchitectureFilters(defaultFilters).first ?? runtimes.first
    }

    private func downloadName(for runtime: DownloadableRuntime, architectures: [ArchitectureFilter]) -> String {
        guard architectures.isEmpty, let runtimeArchitectures = runtime.architectures, runtimeArchitectures.isEmpty == false else {
            return runtime.visibleIdentifier
        }
        return "\(runtime.visibleIdentifier) - \(architectureDescription(runtimeArchitectures))"
    }

    private func architectureDescription(_ architectures: [Architecture]) -> String {
        if architectures.isUniversal {
            return "\(ArchitectureVariant.universal.displayString) (\(architectures.map(\.rawValue).joined(separator: ", ")))"
        }
        if architectures.isAppleSilicon {
            return "\(ArchitectureVariant.appleSilicon.displayString) (\(Architecture.arm64.rawValue))"
        }
        return architectures.map { "\($0.displayString) (\($0.rawValue))" }.joined(separator: ", ")
    }

    private var runtimeArchiveInstallService: RuntimeArchiveInstallService {
        let runtimeService = self.runtimeService
        return RuntimeArchiveInstallService(
            installDiskImage: { url in
                try await runtimeService.installRuntimeImage(dmgURL: url)
            },
            removeArchive: { url in
                try? Current.files.removeItem(at: url)
            }
        )
    }

    private func deleteArchiveIfNeeded(_ archiveURL: URL, shouldDelete: Bool) {
        guard shouldDelete else { return }
        Current.logging.log("Deleting Archive")
        try? Current.files.removeItem(at: archiveURL)
    }

    private func installFromPackage(dmgUrl: URL, runtime: DownloadableRuntime) async throws {
        Current.logging.log("Mounting DMG")
        try await runtimePackageInstallService.installPackageRuntime(
            from: dmgUrl,
            runtime: runtime,
            cachesDirectory: .xcodesCaches
        )
    }

    private var runtimePackageInstallService: RuntimePackageInstallService {
        let runtimeService = self.runtimeService
        return RuntimePackageInstallService(
            mountDMG: { try await runtimeService.mountDMG(dmgUrl: $0) },
            unmountDMG: { try await runtimeService.unmountDMG(mountedURL: $0) },
            prepareDirectory: { path in try path.mkdir().setCurrentUserAsOwner() },
            expandPkg: { try await Current.shell.expandPkg($0, $1) },
            createPkg: { try await Current.shell.createPkg($0, $1) },
            installPkg: { packageURL, target in
                Current.logging.log("Installing Runtime")
                return try await Current.shell.installPkg(packageURL, target)
            },
            contentsAtPath: { Current.files.contents(atPath: $0) },
            writeData: { try Current.files.write($0, to: $1) },
            removeItem: { try Current.files.removeItem(at: $0) }
        )
    }

    public func downloadOrUseExistingArchive(runtime: DownloadableRuntime, to destinationDirectory: Path, downloader: Downloader, runtimeName: String? = nil) async throws -> URL {
        let runtimeName = runtimeName ?? runtime.visibleIdentifier
        if Current.shell.isatty() {
            // Move to the next line so that the escape codes below can move up a line and overwrite it with download progress
            Current.logging.log("")
        } else {
            Current.logging.log("Downloading Runtime \(runtimeName)")
        }

        let observation = ProgressObservation()
        let result = try await runtimeArchiveService(downloader: downloader).archiveURL(
            for: runtime,
            destinationDirectory: destinationDirectory,
            downloader: XcodeArchiveDownloader(downloader)
        ) { progress in
            observation.observe(progress) { progress in
                guard Current.shell.isatty() else { return }
                // These escape codes move up a line and then clear to the end
                let progressString = NumberFormatter.localizedString(from: NSNumber(value: progress.fractionCompleted), number: .percent)
                Current.logging.log("\u{1B}[1A\u{1B}[KDownloading Runtime \(runtimeName): \(progressString)")
            }
        }
        observation.invalidate()
        Path(url: result)?.setCurrentUserAsOwner()
        return result
    }

    private func runtimeArchiveService(downloader: Downloader) -> RuntimeArchiveService {
        let runtimeArchiveDownloadStrategyService = runtimeArchiveDownloadStrategyService(downloader: downloader)
        return RuntimeArchiveService(
            fileExists: { Current.files.fileExistsAtPath($0.string) },
            download: { runtime, url, destination, _, progressChanged in
                try await runtimeArchiveDownloadStrategyService.download(
                    runtime: runtime,
                    url: url,
                    destination: destination,
                    downloader: XcodeArchiveDownloader(downloader),
                    progressChanged: progressChanged
                )
            }
        )
    }

    private func runtimeArchiveDownloadStrategyService(downloader: Downloader) -> RuntimeArchiveDownloadStrategyService {
        let sessionService = self.sessionService
        return RuntimeArchiveDownloadStrategyService(
            validateDownloadPath: { path in
                try await sessionService.validateADCSession(path: path)
            },
            aria2Path: {
                guard let aria2Path = downloader.aria2Path else {
                    throw XcodesKitError("aria2 path is unavailable.")
                }
                return aria2Path
            },
            cookiesForURL: { Current.network.session.configuration.httpCookieStorage?.cookies(for: $0) ?? [] },
            urlSessionDownload: { url, destination, progressChanged in
                try await downloader.download(url: url, to: destination, progressChanged: progressChanged)
            },
            missingDownloadPathError: { Error.missingRuntimeSource($0.visibleIdentifier) }
        )
    }

    // MARK: Xcode 16.1 Runtime installation helpers
    /// Downloads and installs the runtime using xcodebuild, requires Xcode 16.1+ to download a runtime using a given directory
    /// - Parameters:
    ///   - runtime: The runtime to download and install to identify the platform and version numbers
    private func downloadAndInstallUsingXcodeBuild(runtime: DownloadableRuntime, architecture: String?, runtimeName: String) async throws {
        if Current.shell.isatty() {
            // Reserve the line that the progress renderer rewrites.
            Current.logging.log("")
        }

        do {
            try await xcodebuildRuntimeInstall(runtime, architecture) { progress in
                let formatter = NumberFormatter(numberStyle: .percent)
                guard Current.shell.isatty() else { return }
                // These escape codes move up a line and then clear to the end
                Current.logging.log("\u{1B}[1A\u{1B}[KDownloading Runtime \(runtimeName): \(formatter.string(from: progress.fractionCompleted)!)")
            }
        } catch let error {
            guard try await duplicateRuntimeIsAlreadyInstalled(error, runtime: runtime) else {
                throw error
            }
            Current.logging.log("Runtime \(runtimeName) is already installed")
        }
    }

    private func installMethod(for runtime: DownloadableRuntime) async throws -> RuntimeInstallMethod {
        guard runtime.contentType == .cryptexDiskImage else {
            return try RuntimeInstallPolicy().installMethod(for: runtime, selectedXcodeVersion: nil)
        }

        guard let version = try await selectedXcodeVersion() else {
            throw Error.noXcodeSelectedFound
        }

        return try RuntimeInstallPolicy().installMethod(for: runtime, selectedXcodeVersion: version)
    }

    private func duplicateRuntimeIsAlreadyInstalled(_ error: Swift.Error, runtime: DownloadableRuntime) async throws -> Bool {
        guard isDuplicateRuntimeInstallError(error) else { return false }

        let installedRuntimes = try await runtimeService.localInstalledRuntimes()
        return RuntimeInstallationLookupService().coreSimulatorImage(
            for: runtime,
            in: installedRuntimes
        ) != nil
    }

    private func isDuplicateRuntimeInstallError(_ error: Swift.Error) -> Bool {
        guard let error = error as? ProcessExecutionError else { return false }
        let output = error.standardOutput + "\n" + error.standardError
        return output.contains("SimDiskImageErrorDomain") && output.contains("Duplicate of ")
    }

    private static func selectedXcodeVersionFromXcodebuild() async throws -> Version? {
        let xcodeBuildPath = Path.root.usr.bin.join("xcodebuild")
        let versionString = try await Process.runAsync(xcodeBuildPath, "-version")
        return RuntimeInstallPolicy().selectedXcodeVersion(fromXcodebuildVersionOutput: versionString.out)
    }

}

extension RuntimeInstaller {
    public enum Error: LocalizedError, Equatable {
        case unavailableRuntime(String)
        case failedMountingDMG
        case rootNeeded
        case missingRuntimeSource(String)
        case xcode16_1OrGreaterRequired(Version)
        case noXcodeSelectedFound

        public var errorDescription: String? {
            switch self {
                case let .unavailableRuntime(version):
                    return "Runtime \(version) is invalid or not downloadable. Please include arm64 or x86_64 in the version string if shown."
                case .failedMountingDMG:
                    return "Failed to mount image."
                case .rootNeeded:
                    return "Must be run as root to install the specified runtime"
                case let .missingRuntimeSource(identifier):
                    return "Downloading runtime \(identifier) is not supported at this time. Please use `xcodes runtimes install \"\(identifier)\"` instead."
                case let .xcode16_1OrGreaterRequired(version):
                    return RuntimeInstallPolicyError.xcode16_1OrGreaterRequired(version).localizedDescription
                case .noXcodeSelectedFound:
                    return "No Xcode is currently selected, please make sure that you have one selected and installed before trying to install this runtime"
            }
        }
    }
}
