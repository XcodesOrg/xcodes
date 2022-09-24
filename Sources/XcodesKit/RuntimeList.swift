import PromiseKit
import Foundation
import Version
import Path

public class RuntimeList {
    public init() {
    }

    public func printAvailableRuntimes() -> Promise<Void> {
        when(fulfilled: downloadableRuntimes(), installedRuntimes())
            .done { downloadables, installed in
                var installed = installed
                for (platform, downloadables) in Dictionary(grouping: downloadables, by: \.platform).sorted(\.key.order) {
                    Current.logging.log("-- \(platform.shortName) --")
                    for downloadable in downloadables.sorted(\.version) {
                        let matchingInstalledRuntimes = installed.remove { $0.build == downloadable.simulatorVersion.buildUpdate }
                        let name = downloadable.platform.shortName + " \(downloadable.simulatorVersion.version)"
                        if !matchingInstalledRuntimes.isEmpty {
                            for matchingInstalledRuntime in matchingInstalledRuntimes {
                                if matchingInstalledRuntime.kind == .legacyDownload {
                                    Current.logging.log(name + " (Downloaded)")
                                } else if matchingInstalledRuntime.kind == .bundled {
                                    Current.logging.log(name + " (Bundled with selected Xcode)")
                                }
                            }
                        } else {
                            Current.logging.log(name)
                        }
                    }
                }
            }
    }

    func downloadableRuntimes() -> Promise<[DownloadableRuntime]> {
        return firstly { () -> Promise<(data: Data, response: URLResponse)> in
            Current.network.dataTask(with: URLRequest.runtimes)
        }
        .map { (data, response) -> [DownloadableRuntime] in
            let response = try PropertyListDecoder().decode(DownloadableRuntimesResponse.self, from: data)
            return response.downloadables.filter { downloadable in
                !downloadable.name.lowercased().contains("beta")
            }
        }
    }

    func installedRuntimes() -> Promise<[InstalledRuntime]> {
        return firstly { () -> Promise<ProcessOutput> in
            Current.shell.installedRuntimes()
        }
        .map { output -> [InstalledRuntime] in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let outputDictionary = try decoder.decode([String: InstalledRuntime].self, from: output.out.data(using: .utf8)!)
            return outputDictionary.values.sorted { first, second in
                return first.identifier.uuidString.compare(second.identifier.uuidString, options: .numeric) == .orderedAscending
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
