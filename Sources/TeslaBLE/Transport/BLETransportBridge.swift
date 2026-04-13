#if canImport(TeslaCommand)

import Foundation
import TeslaCommand

/// Bridges the async-based `BLETransport` to the synchronous
/// `MobileBLETransportProtocol` that the Go-generated `TeslaCommand` framework
/// expects.
///
/// Go's `bleConnectorAdapter` calls `recv(5000)` in a tight polling loop. A
/// naive implementation that creates a new async task per call leaks
/// continuations on timeout — stale continuations consume real messages
/// before the current call can see them, causing data loss.
///
/// Instead, we run a single persistent receive loop that buffers complete
/// messages. `recv()` simply dequeues from the buffer with a timeout.
final nonisolated class BLETransportBridge: NSObject, MobileBLETransportProtocol, @unchecked Sendable {
    let transport: BLETransport

    private let lock = NSLock()
    private var messageQueue: [Data] = []
    private let dataAvailable = DispatchSemaphore(value: 0)
    private var receiveTask: Task<Void, Never>?
    private var stopped = false
    private let logger: (any TeslaBLELogger)?

    init(transport: BLETransport, logger: (any TeslaBLELogger)? = nil) {
        self.transport = transport
        self.logger = logger
        super.init()
        startReceiveLoop()
    }

    private func startReceiveLoop() {
        logger?.log(.debug, category: "bridge", "Starting receive loop")
        receiveTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let data = try await transport.receive()
                    let (wasStopped, depth) = lock.withLock { () -> (Bool, Int) in
                        if self.stopped { return (true, 0) }
                        self.messageQueue.append(data)
                        return (false, self.messageQueue.count)
                    }
                    if wasStopped {
                        logger?.log(.debug, category: "bridge", "Receive loop stopped (bridge closed)")
                        return
                    }
                    dataAvailable.signal()
                    logger?.log(.debug, category: "bridge", "RX enqueued \(data.count) bytes (depth: \(depth))")
                } catch {
                    logger?.log(.debug, category: "bridge", "Receive loop ended: \(error)")
                    return
                }
            }
        }
    }

    func send(_ data: Data?) throws {
        guard let data else { return }
        logger?.log(.debug, category: "bridge", "TX \(data.count) bytes")
        try transport.send(data)
    }

    func recv(_ timeoutMs: Int64) throws -> Data {
        let timeout = DispatchTime.now() + .milliseconds(Int(timeoutMs))
        if dataAvailable.wait(timeout: timeout) == .timedOut {
            throw BLEError.timeout
        }
        lock.lock()
        let data = messageQueue.removeFirst()
        let remaining = messageQueue.count
        lock.unlock()
        logger?.log(.debug, category: "bridge", "RX dequeued \(data.count) bytes (remaining: \(remaining))")
        return data
    }

    func close() {
        logger?.log(.debug, category: "bridge", "Closing")
        lock.lock()
        stopped = true
        lock.unlock()
        receiveTask?.cancel()
        receiveTask = nil
        transport.disconnect()
    }
}

#endif
