import PromiseKit
import Foundation
import Version
import Path

public class RuntimeList {
    public init() {
    }

    public func printAvailableRuntimes(includeBetas: Bool) async throws {
        let downloadables = try await downloadableRuntimes(includeBetas: includeBetas)
        var installed = try await installedRuntimes()
        for (platform, downloadables) in Dictionary(grouping: downloadables, by: \.platform).sorted(\.key.order) {
            Current.logging.log("-- \(platform.shortName) --")
            for downloadable in downloadables {
                let matchingInstalledRuntimes = installed.remove { $0.build == downloadable.simulatorVersion.buildUpdate }
                let name = downloadable.visibleName
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
