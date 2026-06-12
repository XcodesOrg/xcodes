import Foundation
import os

final class LockedBox<Value: Sendable>: Sendable {
    private let storedValue: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        self.storedValue = OSAllocatedUnfairLock(initialState: value)
    }

    var value: Value {
        storedValue.withLock { $0 }
    }

    func set(_ value: Value) {
        storedValue.withLock { $0 = value }
    }

    func update(_ body: @Sendable (inout Value) -> Void) {
        storedValue.withLock {
            body(&$0)
        }
    }
}

extension LockedBox where Value == String {
    func append(_ string: String) {
        update { $0.append(string) }
    }
}

extension LockedBox where Value == Int {
    @discardableResult
    func increment() -> Int {
        storedValue.withLock {
            $0 += 1
            return $0
        }
    }

    @discardableResult
    func incrementAfterRead() -> Int {
        storedValue.withLock { value in
            defer { value += 1 }
            return value
        }
    }
}

extension LockedBox where Value == [String] {
    func append(_ string: String) {
        update { $0.append(string) }
    }
}
