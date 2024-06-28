import PromiseKit
import Foundation
import Version
import Path
import AppleAPI

public class RuntimeInstaller {

    public let sessionService: AppleSessionService
    public let runtimeList: RuntimeList

    public init(runtimeList: RuntimeList, sessionService: AppleSessionService) {
        self.runtimeList = runtimeList
        self.sessionService = sessionService
    }

    public func printAvailableRuntimes(includeBetas: Bool) async throws {
        let downloadablesResponse = try await runtimeList.downloadableRuntimes()
        var installed = try await runtimeList.installedRuntimes()

        var mappedRuntimes: [PrintableRuntime] = []

        downloadablesResponse.downloadables.forEach { downloadable in
            let matchingInstalledRuntimes = installed.removeAll { $0.build == downloadable.simulatorVersion.buildUpdate }
            if !matchingInstalledRuntimes.isEmpty {
                matchingInstalledRuntimes.forEach {
                    mappedRuntimes.append(PrintableRuntime(platform: downloadable.platform,
                                                           betaNumber: downloadable.betaNumber,
                                                           version: downloadable.simulatorVersion.version,
                                                           build: downloadable.simulatorVersion.buildUpdate,
                                                           state: $0.kind))
                }
            } else {
                mappedRuntimes.append(PrintableRuntime(platform: downloadable.platform,
                                                       betaNumber: downloadable.betaNumber,
                                                       version: downloadable.simulatorVersion.version,
                                                       build: downloadable.simulatorVersion.buildUpdate))
            }
        }




        installed.forEach { runtime in
            let resolvedBetaNumber = downloadablesResponse.sdkToSeedMappings.first {
                $0.buildUpdate == runtime.build
            }?.seedNumber

            var result = PrintableRuntime(platform: runtime.platformIdentifier.asPlatformOS,
                                          betaNumber: resolvedBetaNumber,
                                          version: runtime.version,
                                          build: runtime.build,
                                          state: runtime.kind)

            mappedRuntimes.indices {
                result.visibleIdentifier == $0.visibleIdentifier
            }.forEach { index in
                result.hasDuplicateVersion = true
                mappedRuntimes[index].hasDuplicateVersion = true
            }

            mappedRuntimes.append(result)
        }

        for (platform, runtimes) in Dictionary(grouping: mappedRuntimes, by: \.platform).sorted(\.key.order) {
            Current.logging.log("-- \(platform.shortName) --")
            let sortedRuntimes = runtimes.sorted { first, second in
                let firstVersion = Version(tolerant: first.completeVersion)!
                let secondVersion = Version(tolerant: second.completeVersion)!
                if firstVersion == secondVersion {
                    return first.build.compare(second.build, options: .numeric) == .orderedAscending
                }
                return firstVersion < secondVersion
            }

            for runtime in sortedRuntimes {
                if !includeBetas && runtime.betaNumber != nil && runtime.state == nil {
                    continue
                }
                var str = runtime.visibleIdentifier
                if runtime.hasDuplicateVersion {
                    str += " (\(runtime.build))"
                }
                if runtime.state == .legacyDownload || runtime.state == .diskImage {
                    str += " (Installed)"
                } else if runtime.state == .bundled {
                    str += " (Bundled with selected Xcode)"
                }
                Current.logging.log(str)
            }
        }
        Current.logging.log("\nNote: Bundled runtimes are indicated for the currently selected Xcode, more bundled runtimes may exist in other Xcode(s)")
    }

    public func downloadRuntime(identifier: String, to destinationDirectory: Path, with downloader: Downloader) async throws {
        let matchedRuntime = try await getMatchingRuntime(identifier: identifier)

        _ = try await downloadOrUseExistingArchive(runtime: matchedRuntime, to: destinationDirectory, downloader: downloader)
    }


    public func downloadAndInstallRuntime(identifier: String, to destinationDirectory: Path, with downloader: Downloader, shouldDelete: Bool) async throws {
        let matchedRuntime = try await getMatchingRuntime(identifier: identifier)

        if matchedRuntime.contentType == .package && !Current.shell.isRoot() {
            throw Error.rootNeeded
        }

        let dmgUrl = try await downloadOrUseExistingArchive(runtime: matchedRuntime, to: destinationDirectory, downloader: downloader)
        switch matchedRuntime.contentType {
            case .package:
                try await installFromPackage(dmgUrl: dmgUrl, runtime: matchedRuntime)
            case .diskImage:
                try await installFromImage(dmgUrl: dmgUrl)
            case .cryptexDiskImage:
                throw Error.unsupportedCryptexDiskImage
        }
        if shouldDelete {
            Current.logging.log("Deleting Archive")
            try? Current.files.removeItem(at: dmgUrl)
        }
    }

    private func getMatchingRuntime(identifier: String) async throws -> DownloadableRuntime {
        let downloadables = try await runtimeList.downloadableRuntimes().downloadables
        guard let runtime = downloadables.first(where: { $0.visibleIdentifier == identifier || $0.simulatorVersion.buildUpdate == identifier }) else {
            throw Error.unavailableRuntime(identifier)
        }
        return runtime
    }

    private func installFromImage(dmgUrl: URL)  async throws {
        Current.logging.log("Installing Runtime")
        try await Current.shell.installRuntimeImage(dmgUrl).asVoid().async()
    }

    private func installFromPackage(dmgUrl: URL, runtime: DownloadableRuntime) async throws {
        Current.logging.log("Mounting DMG")
        // 1-Mount DMG and get the mounted path
        let mountedUrl = try await mountDMG(dmgUrl: dmgUrl)
        // 2-Get the first path under the mounted path, should be a .pkg
        let pkgPath = try! Path(url: mountedUrl)!.ls().first!.path
        // 3-Create a caches directory (if it doesn't exist), and
        // 4-Set its ownership to the current user (important because under sudo it would be owned by root)
        try Path.xcodesCaches.mkdir().setCurrentUserAsOwner()
        let expandedPkgPath = Path.xcodesCaches/runtime.identifier
        try? Current.files.removeItem(at: expandedPkgPath.url)
        // 5-Expand (not install) the pkg to temporary path
        try await Current.shell.expandPkg(pkgPath.url, expandedPkgPath.url).asVoid().async()
        try await unmountDMG(mountedURL: mountedUrl)
        let packageInfoPath = expandedPkgPath/"PackageInfo"
        // 6-Get the `PackageInfo` file contents from the expanded pkg
        let packageInfoContentsData = Current.files.contents(atPath: packageInfoPath.string)!
        var packageInfoContents = String(data: packageInfoContentsData, encoding: .utf8)!
        let runtimeFileName = "\(runtime.visibleIdentifier).simruntime"
        let runtimeDestination = Path("/Library/Developer/CoreSimulator/Profiles/Runtimes/\(runtimeFileName)")!
        packageInfoContents = packageInfoContents.replacingOccurrences(of: "<pkg-info", with: "<pkg-info install-location=\"\(runtimeDestination)\"")
        // 7-Modify the `PackageInfo` file with a new `install-location`
        try Current.files.write(packageInfoContents.data(using: .utf8)!, to: packageInfoPath.url)
        let newPkgPath = Path.xcodesCaches/(runtime.identifier + ".pkg")
        try? Current.files.removeItem(at: newPkgPath.url)
        // 8-Re-create the expanded pkg with the new modified `PackageInfo` file
        try await Current.shell.createPkg(expandedPkgPath.url, newPkgPath.url).asVoid().async()
        try Current.files.removeItem(at: expandedPkgPath.url)
        Current.logging.log("Installing Runtime")
        // TODO: Report progress
        // 9-Install the newly created pkg (must be root to run)
        try await Current.shell.installPkg(newPkgPath.url, "/").asVoid().async()
        try Current.files.removeItem(at: newPkgPath.url)
    }

    private func mountDMG(dmgUrl: URL) async throws -> URL {
        let resultPlist = try await Current.shell.mountDmg(dmgUrl).async()
        let dict = try? (PropertyListSerialization.propertyList(from: resultPlist.out.data(using: .utf8)!, format: nil) as? NSDictionary)
        let systemEntities = dict?["system-entities"] as? NSArray
        guard let path = systemEntities?.compactMap ({ ($0 as? NSDictionary)?["mount-point"] as? String }).first else {
            throw Error.failedMountingDMG
        }
        return URL(fileURLWithPath: path)
    }

    private func unmountDMG(mountedURL: URL) async throws {
        try await Current.shell.unmountDmg(mountedURL).asVoid().async()
    }

    @MainActor
    public func downloadOrUseExistingArchive(runtime: DownloadableRuntime, to destinationDirectory: Path, downloader: Downloader) async throws -> URL {
        guard let source = runtime.source else {
            throw Error.missingRuntimeSource(runtime.identifier)
        }
        let url = URL(string: source)!
        let destination = destinationDirectory/url.lastPathComponent
        let aria2DownloadMetadataPath = destination.parent/(destination.basename() + ".aria2")
        var aria2DownloadIsIncomplete = false
        if case .aria2 = downloader, aria2DownloadMetadataPath.exists {
            aria2DownloadIsIncomplete = true
        }

        if Current.shell.isatty() {
            // Move to the next line so that the escape codes below can move up a line and overwrite it with download progress
            Current.logging.log("")
        } else {
            Current.logging.log("Downloading Runtime \(runtime.visibleIdentifier)")
        }

        if Current.files.fileExistsAtPath(destination.string), aria2DownloadIsIncomplete == false {
            Current.logging.log("Found existing Runtime that will be used, at \(destination).")
            return destination.url
        }
        if runtime.authentication == .virtual {
            try await sessionService.validateADCSession(path: url.path).async()
        }
        let formatter = NumberFormatter(numberStyle: .percent)
        var observation: NSKeyValueObservation?
        let result = try await downloader.download(url: url, to: destination, progressChanged: { progress in
            observation?.invalidate()
            observation = progress.observe(\.fractionCompleted) { progress, _ in
                guard Current.shell.isatty() else { return }
                // These escape codes move up a line and then clear to the end
                Current.logging.log("\u{1B}[1A\u{1B}[KDownloading Runtime \(runtime.visibleIdentifier): \(formatter.string(from: progress.fractionCompleted)!)")
            }
        }).async()
        observation?.invalidate()
        destination.setCurrentUserAsOwner()
        return result
    }
}

extension RuntimeInstaller {
    public enum Error: LocalizedError, Equatable {
        case unavailableRuntime(String)
        case failedMountingDMG
        case rootNeeded
        case missingRuntimeSource(String)
        case unsupportedCryptexDiskImage

        public var errorDescription: String? {
            switch self {
                case let .unavailableRuntime(version):
                    return "Runtime \(version) is invalid or not downloadable"
                case .failedMountingDMG:
                    return "Failed to mount image."
                case .rootNeeded:
                    return "Must be run as root to install the specified runtime"
                case let .missingRuntimeSource(identifier):
                    return "Runtime \(identifier) is missing source url. Downloading of iOS 18 runtimes are not supported. Please install manually see https://developer.apple.com/documentation/xcode/installing-additional-simulator-runtimes"
                case .unsupportedCryptexDiskImage:
                    return "Cryptex Disk Image is not yet supported."
            }
        }
    }
}

fileprivate struct PrintableRuntime {
    let platform: DownloadableRuntime.Platform
    let betaNumber: Int?
    let version: String
    let build: String
    var state: InstalledRuntime.Kind? = nil
    var hasDuplicateVersion = false

    var completeVersion: String {
        makeVersion(for: version, betaNumber: betaNumber)
    }

    var visibleIdentifier: String {
        return platform.shortName + " " + completeVersion
    }
}

extension Array {
    fileprivate mutating func removeAll(where predicate: ((Element) -> Bool)) -> [Element] {
        guard !isEmpty else { return [] }
        var removed: [Element] = []
        self = filter { current in
            let satisfy = predicate(current)
            if satisfy {
                removed.append(current)
            }
            return !satisfy
        }
        return removed
    }

    fileprivate func indices(where predicate: ((Element) -> Bool)) -> [Index] {
        var result: [Index] = []

        for index in indices {
            if predicate(self[index]) {
                result.append(index)
            }
        }

        return result
    }
}
