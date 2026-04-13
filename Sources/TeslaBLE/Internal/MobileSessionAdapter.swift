#if canImport(TeslaCommand)

import Foundation
import SwiftProtobuf
@preconcurrency import TeslaCommand

/// Wraps `MobileSession` from the Go-built `TeslaCommand` xcframework,
/// translating its synchronous `Int64`/`NSError` API into Swift-native
/// `async throws`/`Duration`/`TeslaBLEError` calls.
///
/// The adapter is an `actor` so that the internal `MobileSession` instance is
/// mutated under serial access. Every blocking call is dispatched off the
/// actor's executor via `Task.detached` so the Go code never stalls the
/// actor's cooperative thread.
actor MobileSessionAdapter {
    private let vin: String
    private let privateKeyBytes: Data
    private let bridge: BLETransportBridge
    private let logger: (any TeslaBLELogger)?
    private var session: MobileSession?

    init(
        vin: String,
        privateKeyBytes: Data,
        bridge: BLETransportBridge,
        logger: (any TeslaBLELogger)? = nil,
    ) {
        self.vin = vin
        self.privateKeyBytes = privateKeyBytes
        self.bridge = bridge
        self.logger = logger
    }

    /// Creates `MobileSession` and performs the full session handshake.
    func start(timeout: Duration) async throws {
        logger?.log(.info, category: "session", "Starting session for VIN=\(vin)")
        let vin = vin
        let privateKeyBytes = privateKeyBytes
        let bridge = bridge
        let timeoutMs = Self.clampMilliseconds(timeout)
        let newSession: MobileSession
        do {
            newSession = try await Task.detached(priority: .userInitiated) {
                () -> MobileSession in
                guard let s = MobileSession(vin, privateKeyBytes: privateKeyBytes, transport: bridge) else {
                    throw TeslaBLEError.handshakeFailed(underlying: "MobileSession init returned nil")
                }
                try s.start(timeoutMs)
                return s
            }.value
        } catch let error as TeslaBLEError {
            throw error
        } catch {
            logger?.log(.error, category: "session", "Handshake failed: \(error)")
            throw TeslaBLEError.handshakeFailed(underlying: (error as NSError).localizedDescription)
        }
        session = newSession
        logger?.log(.info, category: "session", "Session established")
    }

    /// Starts only the dispatcher (no handshake) — required before
    /// `sendAddKeyRequest` on an unpaired vehicle.
    func connectDispatcher(timeout: Duration) async throws {
        logger?.log(.info, category: "session", "Starting dispatcher-only connection")
        let vin = vin
        let privateKeyBytes = privateKeyBytes
        let bridge = bridge
        let timeoutMs = Self.clampMilliseconds(timeout)
        do {
            let newSession = try await Task.detached(priority: .userInitiated) {
                () -> MobileSession in
                guard let s = MobileSession(vin, privateKeyBytes: privateKeyBytes, transport: bridge) else {
                    throw TeslaBLEError.handshakeFailed(underlying: "MobileSession init returned nil")
                }
                try s.connect(timeoutMs)
                return s
            }.value
            session = newSession
        } catch let error as TeslaBLEError {
            throw error
        } catch {
            throw TeslaBLEError.handshakeFailed(underlying: (error as NSError).localizedDescription)
        }
    }

    func fetchVehicleData(timeout: Duration) async throws -> CarServer_VehicleData {
        guard let session else { throw TeslaBLEError.notConnected }
        let timeoutMs = Self.clampMilliseconds(timeout)
        let bytes: Data
        do {
            bytes = try await Task.detached(priority: .userInitiated) {
                try session.getVehicleState(timeoutMs)
            }.value
        } catch {
            logger?.log(.error, category: "session", "fetchVehicleData failed: \(error)")
            throw TeslaBLEError.fetchFailed(underlying: (error as NSError).localizedDescription)
        }
        return try CarServer_VehicleData(serializedBytes: bytes)
    }

    func fetchDriveState(timeout: Duration) async throws -> CarServer_VehicleData {
        guard let session else { throw TeslaBLEError.notConnected }
        let timeoutMs = Self.clampMilliseconds(timeout)
        let bytes: Data
        do {
            bytes = try await Task.detached(priority: .userInitiated) {
                try session.getDriveState(timeoutMs)
            }.value
        } catch {
            logger?.log(.error, category: "session", "fetchDriveState failed: \(error)")
            throw TeslaBLEError.fetchFailed(underlying: (error as NSError).localizedDescription)
        }
        return try CarServer_VehicleData(serializedBytes: bytes)
    }

    func sendAddKeyRequest(
        publicKeyBytes: Data,
        isOwner: Bool,
        timeout: Duration,
    ) async throws {
        guard let session else { throw TeslaBLEError.notConnected }
        let timeoutMs = Self.clampMilliseconds(timeout)
        do {
            try await Task.detached(priority: .userInitiated) {
                try session.sendAddKeyRequest(publicKeyBytes, isOwner: isOwner, timeoutMs: timeoutMs)
            }.value
        } catch {
            logger?.log(.error, category: "addkey", "sendAddKeyRequest failed: \(error)")
            throw TeslaBLEError.addKeyFailed(underlying: (error as NSError).localizedDescription)
        }
    }

    func stop() {
        session?.stop()
        session = nil
    }

    private static func clampMilliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        let totalMs = components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000
        if totalMs < 0 { return 0 }
        return totalMs
    }
}

#endif
