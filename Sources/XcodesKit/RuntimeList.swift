import Foundation
import os
import XcodesKit

public final class RuntimeList: Sendable {
    private let store: OSAllocatedUnfairLock<RuntimeListStore>

    public init() {
        var store = Self.makeStore()
        try? store.loadCachedDownloadableRuntimes()
        self.store = OSAllocatedUnfairLock(initialState: store)
    }

    var runtimeService: RuntimeService {
        Self.makeRuntimeService()
    }

    private static func makeRuntimeService() -> RuntimeService {
        return RuntimeService(
            loadData: { request in
                let (data, response) = try await Current.network.data(for: request)
                return (data, response)
            },
            installedRuntimesOutput: Current.shell.installedRuntimes,
            installRuntimeImageOutput: Current.shell.installRuntimeImage,
            mountDMGOutput: Current.shell.mountDmg,
            unmountDMGOutput: Current.shell.unmountDmg
        )
    }

    private static func makeStore() -> RuntimeListStore {
        RuntimeListStore(
            cache: DownloadableRuntimeCache(
                cacheFile: .runtimeCacheFile,
                contentsAtPath: { path in Current.files.contents(atPath: path) },
                writeData: { data, url in try Current.files.write(data, to: url) },
                createDirectory: { url, createIntermediates, attributes in
                    try Current.files.createDirectory(
                        at: url,
                        withIntermediateDirectories: createIntermediates,
                        attributes: attributes
                    )
                }
            ),
            service: makeRuntimeService()
        )
    }

    func downloadableRuntimes() async throws -> [DownloadableRuntime] {
        try await updateDownloadableRuntimeList().runtimes
    }

    func updateDownloadableRuntimeList() async throws -> RuntimeListStore.UpdateResult {
        var updatedStore = store.withLock { $0 }
        let result = try await updatedStore.updateDownloadableRuntimeList()
        let finishedStore = updatedStore
        store.withLock { $0 = finishedStore }
        return result
    }

    func installedRuntimes() async throws -> [InstalledRuntime] {
        try await runtimeService.installedRuntimes()
    }
}
