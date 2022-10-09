import PromiseKit

extension Promise {
    func async() async throws -> T {
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
    func async() async -> T {
        return await withCheckedContinuation { continuation in
            done { value in
                continuation.resume(returning: value)
            }
        }
    }
}
