#if canImport(TeslaCommand)

import CryptoKit
import Foundation

/// Primary entry point for TeslaBLE.
///
/// One `TeslaVehicleClient` represents a session with a single Tesla vehicle
/// identified by its VIN. The client manages the BLE connection lifecycle,
/// the `MobileSession` handshake, and command/fetch dispatch. Consumers
/// subscribe to `stateStream` to observe `ConnectionState` transitions.
///
/// Thread-safe by virtue of being an `actor` — every public method serializes
/// against every other. Discard and recreate to switch vehicles.
public actor TeslaVehicleClient {
    // MARK: - Stored

    public let vin: String
    private let keyStore: any TeslaKeyStore
    private let logger: (any TeslaBLELogger)?

    private var transport: BLETransport?
    private var bridge: BLETransportBridge?
    private var adapter: MobileSessionAdapter?

    private var _state: ConnectionState = .disconnected
    private let stream: AsyncStream<ConnectionState>
    private let streamContinuation: AsyncStream<ConnectionState>.Continuation

    // MARK: - Init

    public init(
        vin: String,
        keyStore: any TeslaKeyStore,
        logger: (any TeslaBLELogger)? = nil,
    ) {
        self.vin = vin
        self.keyStore = keyStore
        self.logger = logger
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectionState.self)
        self.stream = stream
        streamContinuation = continuation
    }

    // MARK: - Public API

    public var state: ConnectionState {
        _state
    }

    public nonisolated var stateStream: AsyncStream<ConnectionState> {
        stream
    }

    /// Scans for the vehicle, connects over BLE, and performs the full
    /// `MobileSession` handshake. Observable via `stateStream`.
    public func connect(timeout: Duration = .seconds(30)) async throws {
        guard _state == .disconnected else {
            logger?.log(.warning, category: "client", "connect() called while in state \(_state); ignoring")
            return
        }

        let privateKey = try loadOrFailPrivateKey()

        let transport = BLETransport(logger: logger)
        self.transport = transport
        transport.onStateChange = { [weak self] bleState in
            Task { [weak self] in
                await self?.handleTransportStateChange(bleState)
            }
        }

        do {
            updateState(.scanning)
            try await transport.connect(vin: vin, timeout: Self.seconds(timeout))
        } catch {
            logger?.log(.error, category: "client", "BLE connect failed: \(error)")
            await tearDown()
            throw Self.mapTransportError(error)
        }

        updateState(.handshaking)

        let bridge = BLETransportBridge(transport: transport, logger: logger)
        self.bridge = bridge

        let adapter = MobileSessionAdapter(
            vin: vin,
            privateKeyBytes: privateKey.rawRepresentation,
            bridge: bridge,
            logger: logger,
        )
        self.adapter = adapter

        do {
            try await adapter.start(timeout: timeout)
        } catch {
            await tearDown()
            throw error
        }

        updateState(.connected)
    }

    public func disconnect() async {
        await tearDown()
    }

    public func fetchVehicleData(
        timeout: Duration = .seconds(10),
    ) async throws -> TeslaVehicleSnapshot {
        guard let adapter else { throw TeslaBLEError.notConnected }
        let raw = try await adapter.fetchVehicleData(timeout: timeout)
        return VehicleSnapshotMapper.map(raw)
    }

    public func fetchDriveState(
        timeout: Duration = .seconds(3),
    ) async throws -> DriveStateDTO {
        guard let adapter else { throw TeslaBLEError.notConnected }
        let raw = try await adapter.fetchDriveState(timeout: timeout)
        return VehicleSnapshotMapper.mapDrive(raw)
    }

    /// Initiates the AddKey flow. Self-contained: does its own BLE connect +
    /// dispatcher start. After calling this, the user must tap their key
    /// card on the vehicle's NFC reader within `timeout`.
    public func registerKey(
        isOwner: Bool = true,
        timeout: Duration = .seconds(60),
    ) async throws {
        let key: P256.KeyAgreement.PrivateKey
        if let existing = try keyStore.loadPrivateKey(forVIN: vin) {
            key = existing
        } else {
            let generated = KeyPairFactory.generateKeyPair()
            try keyStore.savePrivateKey(generated, forVIN: vin)
            key = generated
        }
        let publicKeyBytes = KeyPairFactory.publicKeyBytes(of: key)

        let transport = BLETransport(logger: logger)
        self.transport = transport
        transport.onStateChange = { [weak self] bleState in
            Task { [weak self] in
                await self?.handleTransportStateChange(bleState)
            }
        }

        do {
            updateState(.scanning)
            try await transport.connect(vin: vin, timeout: Self.seconds(.seconds(30)))
        } catch {
            await tearDown()
            throw Self.mapTransportError(error)
        }

        updateState(.handshaking)
        let bridge = BLETransportBridge(transport: transport, logger: logger)
        self.bridge = bridge
        let adapter = MobileSessionAdapter(
            vin: vin,
            privateKeyBytes: key.rawRepresentation,
            bridge: bridge,
            logger: logger,
        )
        self.adapter = adapter

        do {
            try await adapter.connectDispatcher(timeout: .seconds(10))
            try await adapter.sendAddKeyRequest(
                publicKeyBytes: publicKeyBytes,
                isOwner: isOwner,
                timeout: timeout,
            )
        } catch {
            await tearDown()
            throw error
        }

        // After AddKey, always tear down — a real session still needs
        // re-establishing via connect() afterwards.
        await tearDown()
    }

    // MARK: - Private

    private func loadOrFailPrivateKey() throws -> P256.KeyAgreement.PrivateKey {
        do {
            if let key = try keyStore.loadPrivateKey(forVIN: vin) {
                return key
            }
        } catch let error as TeslaBLEError {
            throw error
        } catch {
            throw TeslaBLEError.handshakeFailed(underlying: "key load failed: \(error)")
        }
        throw TeslaBLEError.handshakeFailed(underlying: "no private key for VIN \(vin); call registerKey() first")
    }

    private func handleTransportStateChange(_ bleState: BLETransport.ConnectionState) {
        switch bleState {
        case .disconnected:
            if _state != .disconnected { updateState(.disconnected) }
        case .scanning:
            if _state == .disconnected { updateState(.scanning) }
        case .connecting:
            updateState(.connecting)
        case .connected:
            // Client elevates to .handshaking or .connected itself.
            break
        }
    }

    private func updateState(_ newState: ConnectionState) {
        _state = newState
        streamContinuation.yield(newState)
        logger?.log(.debug, category: "client", "state → \(newState)")
    }

    private func tearDown() async {
        await adapter?.stop()
        adapter = nil
        bridge?.close()
        bridge = nil
        transport?.disconnect()
        transport = nil
        if _state != .disconnected {
            updateState(.disconnected)
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1e18
    }

    private static func mapTransportError(_ error: Error) -> TeslaBLEError {
        if let bleError = error as? BLEError {
            switch bleError {
            case .bluetoothUnavailable: return .bluetoothUnavailable
            case .notConnected: return .notConnected
            case .connectionFailed: return .connectionFailed(underlying: "connect failed")
            case .disconnected: return .connectionFailed(underlying: "peer disconnected")
            case .serviceNotFound: return .serviceNotFound
            case .characteristicsNotFound: return .characteristicsNotFound
            case .messageTooLarge: return .messageTooLarge
            case .timeout: return .scanTimeout
            }
        }
        return .connectionFailed(underlying: (error as NSError).localizedDescription)
    }
}

#endif
