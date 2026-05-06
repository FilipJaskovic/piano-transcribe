import Foundation

extension NSLock {
    func withLocking<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ text: String) {
        lock.withLocking {
            storage += text
        }
    }

    var value: String {
        lock.withLocking { storage }
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    func setTrue() {
        lock.withLocking {
            storage = true
        }
    }

    var value: Bool {
        lock.withLocking { storage }
    }
}
