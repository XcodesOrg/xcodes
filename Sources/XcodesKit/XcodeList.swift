import Foundation
import os
import Path
@preconcurrency import Version
import XcodesKit

/// Provides lists of available and installed Xcodes
public final class XcodeList: Sendable {
    public init() {
        var store = Self.makeStore()
        try? store.loadCachedAvailableXcodes()
        self.store = OSAllocatedUnfairLock(initialState: store)
    }

    private let store: OSAllocatedUnfairLock<XcodesKit.XcodeListStore>

    public var availableXcodes: [Xcode] {
        store.withLock { $0.availableXcodes }
    }

    public var lastUpdated: Date? {
        store.withLock { $0.lastUpdated }
    }

    public var shouldUpdateBeforeListingVersions: Bool {
        store.withLock { $0.shouldUpdateBeforeListingVersions }
    }

    public func shouldUpdateBeforeDownloading(version: Version) -> Bool {
        store.withLock { $0.shouldUpdateBeforeDownloading(version: version) }
    }

    public func updateAvailableXcodes(dataSource: DataSource) async throws -> [Xcode] {
        var updatedStore = store.withLock { $0 }
        let xcodes = try await updatedStore.updateAvailableXcodes(from: dataSource)
        let finishedStore = updatedStore
        store.withLock { $0 = finishedStore }
        return xcodes
    }

}
extension XcodeList {
    private static func makeStore() -> XcodesKit.XcodeListStore {
        let service = XcodesKit.XcodeListService { request in
            let result = try await Current.network.data(for: request)
            return (result.data, result.response)
        }
        let cache = XcodesKit.AvailableXcodeCache(
            cacheFile: .cacheFile,
            contentsAtPath: { path in Current.files.contents(atPath: path) },
            writeData: { data, url in try Current.files.write(data, to: url) },
            attributesOfItem: { path in try Current.files.attributesOfItem(atPath: path) }
        )
        return XcodesKit.XcodeListStore(cache: cache, service: service)
    }
}

extension XcodeList {
    // MARK: - Apple

    func parsePrereleaseXcodes(from data: Data) throws -> [Xcode] {
        try XcodesKit.XcodeListService.parsePrereleaseXcodes(from: data)
            .map(AvailableXcode.init)
    }
}
