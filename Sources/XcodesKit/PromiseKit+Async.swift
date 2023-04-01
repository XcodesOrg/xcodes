import PromiseKit

extension Promise {
    public func async() async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            done { value in
                continuation.resume(returning: value)
            }.catch { error in
                continuation.resume(throwing: error)
            }
        }
    }
}

extension Guarantee {
    public func async() async -> T {
        return await withCheckedContinuation { continuation in
            done { value in
                continuation.resume(returning: value)
            }
        }
    }
}
