import Foundation

/// A minimal thread-safe cancellation flag, safe to read from a background
/// operation while being set from the main actor.
final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock(); _cancelled = true; lock.unlock()
    }

    func reset() {
        lock.lock(); _cancelled = false; lock.unlock()
    }
}
