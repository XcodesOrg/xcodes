import Foundation

public class RuntimeList {

    public init() {}

    func downloadableRuntimes() async throws -> DownloadableRuntimesResponse {
        let (data, _) = try await Current.network.dataTask(with: URLRequest.runtimes).async()
        let decodedResponse = try PropertyListDecoder().decode(DownloadableRuntimesResponse.self, from: data)
        return decodedResponse
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
