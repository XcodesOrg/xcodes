import Foundation
import Path
import XcodesKit

public struct Configuration: Codable, Sendable {
    public var defaultUsername: String?

    public init() {
        self.defaultUsername = nil
    }

    public mutating func load() throws {
        guard let configuration = try configurationStore.load(from: Path.configurationFile) else { return }
        self = configuration
    }

    public func save() throws {
        try configurationStore.save(self, to: Path.configurationFile)
    }

    private var configurationStore: CodableFileStore<Configuration> {
        CodableFileStore(
            contentsAtPath: { path in Current.files.contents(atPath: path) },
            createDirectory: { url, createIntermediates, attributes in
                try Current.files.createDirectory(
                    at: url,
                    withIntermediateDirectories: createIntermediates,
                    attributes: attributes
                )
            },
            createFile: { path, data, attributes in
                Current.files.createFile(atPath: path, contents: data, attributes: attributes)
            }
        )
    }
}
