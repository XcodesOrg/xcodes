import Foundation
import Path

public struct Configuration: Codable {
    public var defaultUsername: String?

    public init() {
        self.defaultUsername = nil
    }

    public mutating func load() throws {
        let data = try Data(contentsOf: Path.configurationFile.url)
        self = try JSONDecoder().decode(Configuration.self, from: data)
    }

    public func save() throws {
        let data = try JSONEncoder().encode(self)
        try FileManager.default.createDirectory(at: Path.configurationFile.url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: Path.configurationFile.url)
    }
}

