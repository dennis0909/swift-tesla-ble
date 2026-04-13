import Foundation

// Request-id-keyed map of pending continuations used by `Dispatcher` to match
// inbound responses, drive timeouts, and wake waiters on shutdown. Not an
// actor: all access happens inside `Dispatcher`'s actor isolation, so the
// caller provides the serialization.
struct RequestTable {
    enum Error: Swift.Error, Equatable {
        case duplicateRequestID
        case noSuchRequest
    }

    typealias Continuation = CheckedContinuation<UniversalMessage_RoutableMessage, Swift.Error>

    private var entries: [Data: Continuation] = [:]

    mutating func register(uuid: Data, continuation: Continuation) throws {
        if entries[uuid] != nil {
            throw Error.duplicateRequestID
        }
        entries[uuid] = continuation
    }

    /// Returns true if a matching continuation was resumed, false if the uuid
    /// was unknown (e.g. already timed out or never registered).
    @discardableResult
    mutating func complete(uuid: Data, with message: UniversalMessage_RoutableMessage) -> Bool {
        guard let continuation = entries.removeValue(forKey: uuid) else {
            return false
        }
        continuation.resume(returning: message)
        return true
    }

    @discardableResult
    mutating func fail(uuid: Data, error: Swift.Error) -> Bool {
        guard let continuation = entries.removeValue(forKey: uuid) else {
            return false
        }
        continuation.resume(throwing: error)
        return true
    }

    /// Wakes every pending continuation with `error`. Called from
    /// `Dispatcher.stop()` to guarantee no caller is left suspended.
    mutating func cancelAll(error: Swift.Error) {
        let snapshot = entries
        entries.removeAll()
        for (_, cont) in snapshot {
            cont.resume(throwing: error)
        }
    }

    var count: Int {
        entries.count
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    func contains(uuid: Data) -> Bool {
        entries[uuid] != nil
    }
}
