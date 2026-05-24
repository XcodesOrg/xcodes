import Foundation
@preconcurrency import Version
@preconcurrency import Path
import XcodesKit

public final class RuntimeInstaller: Sendable {

    public let sessionService: AppleSessionService
    public let runtimeList: RuntimeList
    private var runtimeService: RuntimeService {
        runtimeList.runtimeService
    }

    public init(runtimeList: RuntimeList, sessionService: AppleSessionService) {
        self.runtimeList = runtimeList
        self.sessionService = sessionService
    }

    public func printAvailableRuntimes(includeBetas: Bool, architectures: [Architecture] = []) async throws {
        let presentationService = RuntimeListPresentationService()
        let downloadableRuntimeList = try await runtimeList.updateDownloadableRuntimeList()
        let installedRuntimes = try await runtimeList.installedRuntimes()

        for (platform, runtimes) in presentationService.rows(
            downloadableRuntimes: downloadableRuntimeList.runtimes,
            installedRuntimes: installedRuntimes,
            includeBetas: includeBetas,
            sdkToSeedMappings: downloadableRuntimeList.sdkToSeedMappings,
            architectures: architectures
        ) {
            Current.logging.log("-- \(platform.shortName) --")
            runtimes.forEach { Current.logging.log(presentationService.line(for: $0)) }
        }
        Current.logging.log("\nNote: Bundled runtimes are indicated for the currently selected Xcode, more bundled runtimes may exist in other Xcode(s)")
    }

    public func downloadRuntime(identifier: String, to destinationDirectory: Path, with downloader: Downloader) async throws {
        let matchedRuntime = try await getMatchingRuntime(identifier: identifier)

        _ = try await downloadOrUseExistingArchive(runtime: matchedRuntime, to: destinationDirectory, downloader: downloader)
    }


    public func downloadAndInstallRuntime(identifier: String, to destinationDirectory: Path, with downloader: Downloader, shouldDelete: Bool) async throws {
        let matchedRuntime = try await getMatchingRuntime(identifier: identifier)

        let method = try await installMethod(for: matchedRuntime)

        switch method {
        case .archive:
            try await downloadAndInstallArchiveRuntime(
                matchedRuntime,
                to: destinationDirectory,
                with: downloader,
                deleteArchive: shouldDelete
            )
        case let .xcodebuild(architecture):
            try await downloadAndInstallUsingXcodeBuild(runtime: matchedRuntime, architecture: architecture)
        }
    }

    private func downloadAndInstallArchiveRuntime(
        _ runtime: DownloadableRuntime,
        to destinationDirectory: Path,
        with downloader: Downloader,
        deleteArchive: Bool
    ) async throws {
        switch runtime.contentType {
        case .package:
            guard Current.shell.isRoot() else {
                throw Error.rootNeeded
            }
            let dmgUrl = try await downloadOrUseExistingArchive(runtime: runtime, to: destinationDirectory, downloader: downloader)
            try await installFromPackage(dmgUrl: dmgUrl, runtime: runtime)
            deleteArchiveIfNeeded(dmgUrl, shouldDelete: deleteArchive)
        case .diskImage:
            let dmgUrl = try await downloadOrUseExistingArchive(runtime: runtime, to: destinationDirectory, downloader: downloader)
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

    private func getMatchingRuntime(identifier: String) async throws -> DownloadableRuntime {
        let downloadables = try await runtimeList.downloadableRuntimes()
        guard let runtime = downloadables.first(where: { $0.visibleIdentifier == identifier || $0.simulatorVersion.buildUpdate == identifier }) else {
            throw Error.unavailableRuntime(identifier)
        }
        return runtime
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

    public func downloadOrUseExistingArchive(runtime: DownloadableRuntime, to destinationDirectory: Path, downloader: Downloader) async throws -> URL {
        if Current.shell.isatty() {
            // Move to the next line so that the escape codes below can move up a line and overwrite it with download progress
            Current.logging.log("")
        } else {
            Current.logging.log("Downloading Runtime \(runtime.visibleIdentifier)")
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
                Current.logging.log("\u{1B}[1A\u{1B}[KDownloading Runtime \(runtime.visibleIdentifier): \(progressString)")
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
    private func downloadAndInstallUsingXcodeBuild(runtime: DownloadableRuntime, architecture: String?) async throws {
        try await RuntimeXcodebuildInstallService().downloadAndInstall(
            runtime: runtime,
            architecture: architecture
        ) { progress in
            let formatter = NumberFormatter(numberStyle: .percent)
            guard Current.shell.isatty() else { return }
            // These escape codes move up a line and then clear to the end
            Current.logging.log("\u{1B}[1A\u{1B}[KDownloading Runtime \(runtime.visibleIdentifier): \(formatter.string(from: progress.fractionCompleted)!)")
        }
    }

    private func installMethod(for runtime: DownloadableRuntime) async throws -> RuntimeInstallMethod {
        guard runtime.contentType == .cryptexDiskImage else {
            return try RuntimeInstallPolicy().installMethod(for: runtime, selectedXcodeVersion: nil)
        }

        let xcodeBuildPath = Path.root.usr.bin.join("xcodebuild")
        let versionString = try await Process.runAsync(xcodeBuildPath, "-version")
        guard let version = RuntimeInstallPolicy().selectedXcodeVersion(fromXcodebuildVersionOutput: versionString.out) else {
            throw Error.noXcodeSelectedFound
        }

        return try RuntimeInstallPolicy().installMethod(for: runtime, selectedXcodeVersion: version)
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
