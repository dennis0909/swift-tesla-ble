import Foundation

/// Long-lived per-domain session state. One instance per BLE domain (VCSEC,
/// INFOTAINMENT), held for as long as the BLE connection is alive, and the
/// single owner of all mutable crypto state. `OutboundSigner` and
/// `InboundVerifier` are deliberately stateless so that this actor is the
/// only place counter/epoch updates can happen — which is what lets the
/// replay window and counter monotonicity be reasoned about locally.
///
/// Concurrency: `actor` so multiple in-flight commands cannot race on the
/// counter (two concurrent signs must produce two distinct counter values).
actor VehicleSession {
    enum Error: Swift.Error, Equatable {
        case counterRollover
        case signFailed(String)
        case verifyFailed(String)
        case replayRejected
    }

    /// The BLE domain this session belongs to (VCSEC or INFOTAINMENT).
    let domain: UniversalMessage_Domain
    /// Personalization bytes — VIN for infotainment, VCSEC id for vehicle
    /// security — bound into every AAD so a signature for one vehicle
    /// cannot be replayed against another.
    let verifierName: Data
    /// Local public key, copied verbatim into `signerIdentity` on every
    /// outbound message so the vehicle can identify the signing party.
    let localPublicKey: Data
    /// 16-byte AES-GCM key derived from the ECDH handshake. Immutable for
    /// the lifetime of the session; a new session is required to rotate it.
    let sessionKey: SessionKey

    /// Vehicle-advertised 16-byte epoch. Rotates when the vehicle requests
    /// a resync; refreshed via `resync(epoch:counter:)`.
    private var epoch: Data
    /// Monotonically-increasing outbound counter. Incremented before each
    /// `sign` call and rolled back if sealing fails.
    private var counter: UInt32
    /// Sliding replay window over inbound counters. Reset on `resync`.
    private var window: CounterWindow

    init(
        domain: UniversalMessage_Domain,
        verifierName: Data,
        localPublicKey: Data,
        sessionKey: SessionKey,
        epoch: Data,
        initialCounter: UInt32 = 0,
    ) {
        self.domain = domain
        self.verifierName = verifierName
        self.localPublicKey = localPublicKey
        self.sessionKey = sessionKey
        self.epoch = epoch
        counter = initialCounter
        window = CounterWindow()
    }

    /// Outbound sign: increments counter, seals plaintext into message.
    func sign(
        plaintext: Data,
        into message: inout UniversalMessage_RoutableMessage,
        expiresAt: UInt32,
    ) throws {
        if counter == UInt32.max {
            throw Error.counterRollover
        }
        counter &+= 1
        do {
            try OutboundSigner.signGCM(
                plaintext: plaintext,
                message: &message,
                sessionKey: sessionKey,
                localPublicKey: localPublicKey,
                verifierName: verifierName,
                epoch: epoch,
                counter: counter,
                expiresAt: expiresAt,
            )
        } catch {
            // Rollback counter so the next attempt reuses the same value.
            counter &-= 1
            throw Error.signFailed(String(describing: error))
        }
    }

    /// Inbound verify: extracts plaintext + counter, runs counter through the
    /// replay window, returns plaintext on success.
    func verify(
        response: UniversalMessage_RoutableMessage,
        requestID: Data,
    ) throws -> Data {
        let result: (counter: UInt32, plaintext: Data)
        do {
            result = try InboundVerifier.openGCMResponse(
                message: response,
                sessionKey: sessionKey,
                verifierName: verifierName,
                requestID: requestID,
            )
        } catch {
            throw Error.verifyFailed(String(describing: error))
        }

        // Counter=0 responses bypass the replay window (see verifier.go
        // verifySessionInfo — some responses intentionally allow out-of-order
        // delivery). We treat 0 as "do not track".
        if result.counter > 0 {
            guard window.accept(result.counter) else {
                throw Error.replayRejected
            }
        }
        return result.plaintext
    }

    /// Update the session's epoch and counter to match a fresh SessionInfo
    /// received from the vehicle (e.g. after an error-triggered resync).
    func resync(epoch: Data, counter: UInt32) {
        self.epoch = epoch
        self.counter = counter
        window = CounterWindow()
    }

// Test-only accessors.
#if DEBUG
    var currentCounter: UInt32 {
        counter
    }

    var currentEpoch: Data {
        epoch
    }
#endif
}
