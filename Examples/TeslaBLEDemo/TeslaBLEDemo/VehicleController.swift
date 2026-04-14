//
//  VehicleController.swift
//  TeslaBLEDemo
//
//  Created by Jiaxin Shou on 2026/4/14.
//

import CryptoKit
import Foundation
import OSLog
import Security
import SwiftUI
import TeslaBLE

/// Single source of truth wrapping `TeslaVehicleClient` for the demo UI.
///
/// All mutations happen on the main actor so SwiftUI bindings fire on the
/// main thread. Every throwing call to the client funnels through a catch
/// block that assigns `lastError` — the UI shows a single global alert.
@Observable
final class VehicleController {
    // Pairing state
    var pairedVIN: String?
    var isPairing: Bool = false

    // Session state
    var connectionState: ConnectionState = .disconnected
    var drive: DriveState?
    var isLive: Bool = false
    var lastError: String?

    private let keyStore: KeychainTeslaKeyStore
    private let store: PairedVehicleStore
    private let logger = Logger(subsystem: Constants.bundleIdentifier, category: "controller")

    private var client: TeslaVehicleClient?
    private var stateObserverTask: Task<Void, Never>?
    private var livePollTask: Task<Void, Never>?

    convenience init() {
        self.init(
            keyStore: KeychainTeslaKeyStore(service: Constants.bundleIdentifier),
            store: PairedVehicleStore(),
        )
    }

    init(
        keyStore: KeychainTeslaKeyStore,
        store: PairedVehicleStore,
    ) {
        self.keyStore = keyStore
        self.store = store
        pairedVIN = store.pairedVIN
    }

    // MARK: - Pairing (Task 6)

    func startPairing(vin: String) async {
        guard vin.count == 17 else {
            lastError = "VIN must be exactly 17 characters."
            return
        }
        guard !isPairing else { return }
        lastError = nil
        isPairing = true
        defer { isPairing = false }

        do {
            let privateKey: P256.KeyAgreement.PrivateKey
            if let existing = try keyStore.loadPrivateKey(forVIN: vin) {
                privateKey = existing
            } else {
                privateKey = KeyPairFactory.generateKeyPair()
                try keyStore.savePrivateKey(privateKey, forVIN: vin)
            }
            let publicKey = KeyPairFactory.publicKeyBytes(of: privateKey)

            let pairingClient = TeslaVehicleClient(vin: vin, keyStore: keyStore)
            do {
                try await pairingClient.connect(mode: .pairing)
                try await pairingClient.send(
                    .security(.addKey(publicKey: publicKey, role: .owner, formFactor: .iosDevice)),
                )
                await pairingClient.disconnect()
            } catch {
                await pairingClient.disconnect()
                throw error
            }

            store.setPairedVIN(vin)
            pairedVIN = vin
        } catch {
            logger.error("pairing failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
        }
    }

    func clearPairing() {
        guard client == nil else {
            lastError = "Disconnect before forgetting the vehicle."
            return
        }
        if let vin = pairedVIN {
            do {
                try keyStore.deletePrivateKey(forVIN: vin)
            } catch {
                logger.error("delete key failed: \(String(describing: error), privacy: .public)")
                lastError = String(describing: error)
                return
            }
        }
        store.clearPairedVIN()
        pairedVIN = nil
        drive = nil
        connectionState = .disconnected
    }

    /// Nuclear option for the pairing screen: wipes every Keychain item under
    /// this app's service (including orphans from previously-paired VINs) and
    /// clears the persisted VIN. Safe to call only while no session is active.
    func wipeAllPersistedData() {
        guard client == nil else {
            lastError = "Disconnect before wiping data."
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.bundleIdentifier,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            logger.error("wipe keychain failed: \(status, privacy: .public)")
            lastError = "Keychain wipe failed (OSStatus \(status))."
            return
        }
        store.clearPairedVIN()
        pairedVIN = nil
        drive = nil
        connectionState = .disconnected
    }

    // MARK: - Session (Task 5)

    /// Number of `connect(mode: .normal)` attempts before giving up. One
    /// transient retry is enough to absorb CoreBluetooth's back-to-back
    /// reconnect race right after pairing's disconnect, and occasional scan
    /// misses during scene-phase transitions.
    private static let maxConnectAttempts = 2
    private static let connectRetryDelay: Duration = .seconds(1)

    func connect() async {
        guard let vin = pairedVIN else {
            lastError = "No paired vehicle."
            return
        }
        guard client == nil else { return }

        let newClient = TeslaVehicleClient(vin: vin, keyStore: keyStore)
        client = newClient

        // Subscribe to state transitions. This stream never finishes for the
        // lifetime of the client, so we MUST cancel this task in disconnect().
        stateObserverTask = Task { [weak self] in
            for await state in newClient.stateStream {
                guard let self else { return }
                await MainActor.run { self.connectionState = state }
                if Task.isCancelled { return }
            }
        }

        for attempt in 1 ... Self.maxConnectAttempts {
            do {
                try await newClient.connect(mode: .normal)
                setLive(true)
                return
            } catch let error as TeslaBLEError where Self.isRetryable(error) && attempt < Self.maxConnectAttempts {
                logger.debug(
                    "connect attempt \(attempt, privacy: .public) failed: \(String(describing: error), privacy: .public); retrying",
                )
                try? await Task.sleep(for: Self.connectRetryDelay)
                continue
            } catch {
                logger.error("connect failed: \(String(describing: error), privacy: .public)")
                lastError = String(describing: error)
                await disconnect()
                return
            }
        }
    }

    /// Errors worth retrying once: transient BLE transport failures where a
    /// brief delay typically clears the race. Handshake, auth, and keystore
    /// errors are intentionally excluded — they represent configuration
    /// problems that retrying won't fix.
    private static func isRetryable(_ error: TeslaBLEError) -> Bool {
        switch error {
        case .scanTimeout, .connectionFailed:
            true
        default:
            false
        }
    }

    func disconnect() async {
        livePollTask?.cancel()
        livePollTask = nil
        isLive = false

        stateObserverTask?.cancel()
        stateObserverTask = nil

        if let client {
            await client.disconnect()
        }
        client = nil

        // The stream task is cancelled; force-publish .disconnected so the UI
        // doesn't sit on the last observed value.
        connectionState = .disconnected
        drive = nil
    }

    // MARK: - Reads & commands (Task 7)

    func refreshDrive() async {
        guard let client else { return }
        do {
            let drive = try await client.fetchDrive()
            self.drive = drive
        } catch is CancellationError {
            return
        } catch {
            logger.error("fetchDrive failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
        }
    }

    func setLive(_ on: Bool) {
        guard on != isLive else { return }
        isLive = on
        livePollTask?.cancel()
        livePollTask = nil
        guard on else { return }

        livePollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if await MainActor.run(body: { self.connectionState }) == .connected {
                    await pollOnce()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Live-loop variant of `refreshDrive` that never writes to `lastError`.
    /// Transient misses while Live is on must not spam the global alert.
    private func pollOnce() async {
        guard let client else { return }
        do {
            let drive = try await client.fetchDrive()
            self.drive = drive
        } catch {
            logger.debug("live poll miss: \(String(describing: error), privacy: .public)")
        }
    }

    func unlock() async {
        guard let client else { return }
        do {
            try await client.send(.security(.unlock))
        } catch is CancellationError {
            return
        } catch {
            logger.error("unlock failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
        }
    }

    func honk() async {
        guard let client else { return }
        do {
            try await client.send(.actions(.honk))
        } catch is CancellationError {
            return
        } catch {
            logger.error("honk failed: \(String(describing: error), privacy: .public)")
            lastError = String(describing: error)
        }
    }
}
