import PromiseKit
import Foundation
import Version
import Path

public class RuntimeList {

    private var sessionController: SessionController

    public init(sessionController: SessionController) {
        self.sessionController = sessionController
    }

    public func printAvailableRuntimes(includeBetas: Bool) async throws {
        let downloadables = try await downloadableRuntimes(includeBetas: includeBetas)
        var installed = try await installedRuntimes()
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

    func downloadableRuntimes(includeBetas: Bool) async throws -> [DownloadableRuntime] {
        let (data, _) = try await Current.network.dataTask(with: URLRequest.runtimes).async()
        let decodedResponse = try PropertyListDecoder().decode(DownloadableRuntimesResponse.self, from: data)
        return includeBetas ? decodedResponse.downloadables : decodedResponse.downloadables.filter { $0.betaVersion == nil }
    }

    func installedRuntimes() async throws -> [InstalledRuntime] {
        let output = try await Current.shell.installedRuntimes().async()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let outputDictionary = try decoder.decode([String: InstalledRuntime].self, from: output.out.data(using: .utf8)!)
        return outputDictionary.values.sorted { first, second in
            return first.identifier.uuidString.compare(second.identifier.uuidString, options: .numeric) == .orderedAscending
        }
    }

    public func downloadAndInstallRuntime(identifier: String, downloader: Downloader) async throws {
        let downloadables = try await downloadableRuntimes(includeBetas: true)
        guard let matchedRuntime = downloadables.first(where: { $0.visibleIdentifier == identifier }) else {
            throw Error.unavailableRuntime(identifier)
        }
        _ = try await download(runtime: matchedRuntime, downloader: downloader)
    }

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
            Current.logging.log("\(InstallationStep.downloading(identifier: runtime.visibleIdentifier, progress: nil))")
        }

        if Current.files.fileExistsAtPath(destination.string), aria2DownloadIsIncomplete == false {
            Current.logging.log("(1/1) Found existing Runtime that will be used for installation at \(destination).")
            return destination.url
        }
        if runtime.authentication == .virtual {
            try await sessionController.validateADCSession(path: url.path).async()
        }
        let formatter = NumberFormatter(numberStyle: .percent)
        var observation: NSKeyValueObservation?
        let result = try await downloader.download(url: url, to: destination, progressChanged: { progress in
            observation?.invalidate()
            observation = progress.observe(\.fractionCompleted) { progress, _ in
                guard Current.shell.isatty() else { return }
                // These escape codes move up a line and then clear to the end
                Current.logging.log("\u{1B}[1A\u{1B}[K\(InstallationStep.downloading(identifier: runtime.visibleIdentifier, progress: formatter.string(from: progress.fractionCompleted)!))")
            }
        }).async()
        observation?.invalidate()
        return result
    }
}

extension RuntimeList {
    public enum Error: LocalizedError, Equatable {
        case unavailableRuntime(String)

        public var errorDescription: String? {
            switch self {
                case let .unavailableRuntime(version):
                    return "Could not find runtime \(version)."
            }
        }
    }

    enum InstallationStep: CustomStringConvertible {
        case downloading(identifier: String, progress: String?)

        var description: String {
            return "(\(stepNumber)/\(InstallationStep.installStepCount)) \(message)"
        }

        var message: String {
            switch self {
                case .downloading(let version, let progress):
                    if let progress = progress {
                        return "Downloading Runtime \(version): \(progress)"
                    } else {
                        return "Downloading Runtime \(version)"
                    }
            }
        }

        var stepNumber: Int {
            switch self {
                case .downloading: return 1
            }
        }

        static var installStepCount: Int {
            return 1
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
