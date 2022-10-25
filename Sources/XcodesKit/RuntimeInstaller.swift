import PromiseKit
import Foundation
import Version
import Path
import AppleAPI

public class RuntimeInstaller {

    private var sessionService: AppleSessionService
    private var runtimeList: RuntimeList

    public init(runtimeList: RuntimeList, sessionService: AppleSessionService) {
        self.runtimeList = runtimeList
        self.sessionService = sessionService
    }

    public func printAvailableRuntimes(includeBetas: Bool) async throws {
        let downloadables = try await runtimeList.downloadableRuntimes(includeBetas: includeBetas)
        var installed = try await runtimeList.installedRuntimes()
        for (platform, downloadables) in Dictionary(grouping: downloadables, by: \.platform).sorted(\.key.order) {
            Current.logging.log("-- \(platform.shortName) --")
            for downloadable in downloadables {
                let matchingInstalledRuntimes = installed.remove { $0.build == downloadable.simulatorVersion.buildUpdate }
                let name = downloadable.visibleIdentifier
                if !matchingInstalledRuntimes.isEmpty {
                    for matchingInstalledRuntime in matchingInstalledRuntimes {
                        switch matchingInstalledRuntime.kind {
                            case .bundled:
                                Current.logging.log(name + " (Bundled with selected Xcode)")
                            case .diskImage, .legacyDownload:
                                Current.logging.log(name + " (Downloaded)")
                        }
                    }
                } else {
                    Current.logging.log(name)
                }
            }
        }
        Current.logging.log("\nNote: Bundled runtimes are indicated for the currently selected Xcode, more bundled runtimes may exist in other Xcode(s)")
    }

    public func downloadAndInstallRuntime(identifier: String, downloader: Downloader) async throws {
        let downloadables = try await runtimeList.downloadableRuntimes(includeBetas: true)
        guard let matchedRuntime = downloadables.first(where: { $0.visibleIdentifier == identifier }) else {
            throw Error.unavailableRuntime(identifier)
        }
        let dmgUrl = try await download(runtime: matchedRuntime, downloader: downloader)
        switch matchedRuntime.contentType {
            case .package:
                try await installFromPackage(dmgUrl: dmgUrl, runtime: matchedRuntime)
            case .diskImage:
                try await installFromImage(dmgUrl: dmgUrl)
        }
    }

    private func installFromImage(dmgUrl: URL)  async throws {
        Current.logging.log("Installing Runtime")
        try await Current.shell.installRuntimeImage(dmgUrl).asVoid().async()
    }

    private func installFromPackage(dmgUrl: URL, runtime: DownloadableRuntime) async throws {
        Current.logging.log("Mounting DMG")
        let mountedUrl = try await mountDMG(dmgUrl: dmgUrl)
        let pkgPath = try! Path(url: mountedUrl)!.ls().first!.path
        try Path.xcodesCaches.mkdir()
        let expandedPkgPath = Path.xcodesCaches/runtime.identifier
        try expandedPkgPath.delete()
        _ = try await Current.shell.expandPkg(pkgPath.url, expandedPkgPath.url).async()
        try await unmountDMG(mountedURL: mountedUrl)
        let packageInfoPath = expandedPkgPath/"PackageInfo"
        var packageInfoContents = try String(contentsOf: packageInfoPath)
        let runtimeFileName = "\(runtime.platform.shortName) \(runtime.simulatorVersion.version).simruntime"
        let runtimeDestination = Path("/Library/Developer/CoreSimulator/Profiles/Runtimes/\(runtimeFileName)")!
        packageInfoContents = packageInfoContents.replacingOccurrences(of: "<pkg-info", with: "<pkg-info install-location=\"\(runtimeDestination)\"")
        try packageInfoContents.write(to: packageInfoPath)
        let newPkgPath = Path.xcodesCaches/(runtime.identifier + ".pkg")
        try await Current.shell.createPkg(expandedPkgPath.url, newPkgPath.url).asVoid().async()
        try expandedPkgPath.delete()
        Current.logging.log("Installing Runtime")
        let passwordInput = {
            Promise<String> { seal in
                Current.logging.log("xcodes requires superuser privileges in order to finish installation.")
                guard let password = Current.shell.readSecureLine(prompt: "macOS User Password: ") else { seal.reject(XcodeInstaller.Error.missingSudoerPassword); return }
                seal.fulfill(password + "\n")
            }
        }
        let possiblePassword = try await Current.shell.authenticateSudoerIfNecessary(passwordInput: passwordInput).async()
        _ = try await Current.shell.installPkg(newPkgPath.url, "/", possiblePassword).async()
        try newPkgPath.delete()
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
        _ = try await Current.shell.unmountDmg(mountedURL).async()
    }

    @MainActor
    private func download(runtime: DownloadableRuntime, downloader: Downloader) async throws -> URL {
        let url = URL(string: runtime.source)!
        let destination = Path.xcodesApplicationSupport/url.lastPathComponent
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
            Current.logging.log("Found existing Runtime that will be used for installation at \(destination).")
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
        return result
    }
}

extension RuntimeInstaller {
    public enum Error: LocalizedError, Equatable {
        case unavailableRuntime(String)
        case failedMountingDMG

        public var errorDescription: String? {
            switch self {
                case let .unavailableRuntime(version):
                    return "Could not find runtime \(version)."
                case .failedMountingDMG:
                    return "Failed to mount image."
            }
        }
    }
}

extension Array {
    fileprivate mutating func remove(where predicate: ((Element) -> Bool)) -> [Element] {
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
}
