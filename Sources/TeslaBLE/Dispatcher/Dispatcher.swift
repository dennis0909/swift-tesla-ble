import CryptoKit
import Foundation
import Security

/// Actor that owns per-domain `VehicleSession` state on top of a `MessageTransport`,
/// serializing in-flight requests through `RequestTable` for sign/verify + timeout.
/// Framing and BLE connection lifecycle are the transport's concern, not ours.
@available(macOS 13.0, iOS 16.0, *)
actor Dispatcher {
    enum Error: Swift.Error, Equatable {
        case notStarted
        case alreadyStarted
        case notConnected
        case noSessionForDomain(UniversalMessage_Domain)
        case timeout
        case shutdown
        case encodingFailed(String)
        case decodingFailed(String)
        case unexpectedResponse(String)
    }

    private let transport: MessageTransport
    private let logger: (any TeslaBLELogger)?

    private var vcsecSession: VehicleSession?
    private var infotainmentSession: VehicleSession?
    private var requestTable = RequestTable()
    private var inboundTask: Task<Void, Never>?
    private var started = false

    init(transport: MessageTransport, logger: (any TeslaBLELogger)? = nil) {
        self.transport = transport
        self.logger = logger
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !started else { throw Error.alreadyStarted }
        started = true
        inboundTask = Task { [weak self] in
            await self?.inboundLoop()
        }
    }

    func stop() async {
        started = false
        inboundTask?.cancel()
        inboundTask = nil
        requestTable.cancelAll(error: Error.shutdown)
    }

    /// Installs or replaces a `VehicleSession` for the given domain. Typically
    /// called after a successful `negotiate(domain:...)`.
    func installSession(_ session: VehicleSession, forDomain domain: UniversalMessage_Domain) {
        switch domain {
        case .vehicleSecurity: vcsecSession = session
        case .infotainment: infotainmentSession = session
        default: break
        }
    }

    // MARK: - Outbound

    /// Signed send: wraps `plaintext` in the domain's `VehicleSession` envelope,
    /// awaits the matching response, and returns the verified response plaintext.
    /// Requires an installed session; throws `.noSessionForDomain` otherwise.
    /// For the unsigned bootstrap path used by `addKey`, see `sendUnsigned(_:domain:)`.
    func send(
        _ plaintext: Data,
        domain: UniversalMessage_Domain,
        timeout: Duration = .seconds(10),
    ) async throws -> Data {
        guard started else { throw Error.notStarted }
        let session = try requireSession(for: domain)

        // Build an outbound routable message with a fresh uuid.
        var request = UniversalMessage_RoutableMessage()
        var dst = UniversalMessage_Destination()
        dst.domain = domain
        request.toDestination = dst
        let requestUUID = Self.newUUIDBytes()
        request.uuid = requestUUID

        // Sign (actor hop into VehicleSession).
        try await session.sign(plaintext: plaintext, into: &request, expiresAt: Self.defaultExpiresAt)

        // Compute requestID for response matching.
        guard let responseMatchID = InboundVerifier.requestID(forSignedRequest: request) else {
            throw Error.encodingFailed("failed to compute requestID from signed message")
        }

        // Freeze the request before capturing in the Sendable closure.
        let frozenRequest = request

        // Register and transmit.
        let response: UniversalMessage_RoutableMessage
        do {
            response = try await withRegisteredRequest(uuid: requestUUID, timeout: timeout) { [self] in
                try await transmit(message: frozenRequest)
            }
        } catch let e as Error where e == .timeout {
            logger?.log(.error, category: "dispatcher", "send timeout on domain \(domain)")
            throw Error.timeout
        }

        // Verify response.
        do {
            return try await session.verify(response: response, requestID: responseMatchID)
        } catch {
            throw Error.decodingFailed(String(describing: error))
        }
    }

    /// Unsigned send: used ONLY for the `addKey` pairing bootstrap, where the
    /// vehicle accepts a plaintext request without an established session.
    /// Returns the raw `protobufMessageAsBytes` payload from the response
    /// (typically a `VCSEC_FromVCSECMessage`); no session verify is performed.
    func sendUnsigned(
        _ plaintext: Data,
        domain: UniversalMessage_Domain,
        timeout: Duration = .seconds(60),
    ) async throws -> Data {
        guard started else { throw Error.notStarted }

        var request = UniversalMessage_RoutableMessage()
        var dst = UniversalMessage_Destination()
        dst.domain = domain
        request.toDestination = dst
        let requestUUID = Self.newUUIDBytes()
        request.uuid = requestUUID
        request.payload = .protobufMessageAsBytes(plaintext)
        // No subSigData — unsigned.

        let frozenRequest = request

        let response: UniversalMessage_RoutableMessage
        do {
            response = try await withRegisteredRequest(uuid: requestUUID, timeout: timeout) { [self] in
                try await transmit(message: frozenRequest)
            }
        } catch let e as Error where e == .timeout {
            logger?.log(.error, category: "dispatcher", "sendUnsigned timeout on domain \(domain)")
            throw Error.timeout
        }

        // Return the raw response payload bytes. No session verify since
        // the request wasn't signed.
        guard case let .protobufMessageAsBytes(payload)? = response.payload else {
            throw Error.decodingFailed("unsigned response missing protobufMessageAsBytes payload")
        }
        return payload
    }

    // MARK: - Handshake

    /// Runs a SessionInfoRequest/SessionInfo handshake and returns the decoded
    /// `SessionInfo` together with the derived `SessionKey`.
    ///
    /// ECDH is performed inline here — not by the caller — because the response's
    /// HMAC tag is keyed by the session key, which in turn is derived from the
    /// vehicle public key embedded inside that same response. That circular
    /// dependency can only be resolved by decoding the response, doing ECDH
    /// against `info.publicKey` on the spot, and then verifying the HMAC with
    /// the freshly-derived key.
    func negotiate(
        domain: UniversalMessage_Domain,
        localPrivateKey: P256.KeyAgreement.PrivateKey,
        verifierName: Data,
        timeout: Duration = .seconds(10),
    ) async throws -> (sessionInfo: Signatures_SessionInfo, sessionKey: SessionKey) {
        guard started else { throw Error.notStarted }

        // Challenge: 8 random bytes (matches Go test helper).
        var challenge = Data(count: 8)
        let challengeCount = challenge.count
        challenge.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, challengeCount, buffer.baseAddress!)
        }

        // Local public key in uncompressed SEC1 form (0x04 || X || Y, 65 bytes).
        let localPublicKey = localPrivateKey.publicKey.x963Representation

        let request = SessionNegotiator.buildRequest(
            domain: domain,
            publicKey: localPublicKey,
            challenge: challenge,
            uuid: Self.newUUIDBytes(),
        )

        let response: UniversalMessage_RoutableMessage = try await withRegisteredRequest(
            uuid: request.uuid,
            timeout: timeout,
        ) { [self] in
            try await transmit(message: request)
        }

        // Extract encodedInfo and tag from response.
        guard case let .sessionInfo(encodedInfo)? = response.payload else {
            throw Error.unexpectedResponse("negotiate response missing sessionInfo payload")
        }
        guard case let .signatureData(sigData)? = response.subSigData else {
            throw Error.unexpectedResponse("negotiate response missing signature data")
        }
        guard case let .sessionInfoTag(hmacSig)? = sigData.sigType else {
            throw Error.unexpectedResponse("negotiate response has wrong signature type")
        }
        let expectedTag = hmacSig.tag

        // Decode SessionInfo to get vehicle public key.
        let info: Signatures_SessionInfo
        do {
            info = try Signatures_SessionInfo(serializedBytes: encodedInfo)
        } catch {
            throw Error.decodingFailed("SessionInfo: \(error)")
        }

        // ECDH: localPrivateKey × info.publicKey → sharedSecret → SessionKey
        let sharedSecret: Data
        do {
            sharedSecret = try P256ECDH.sharedSecret(
                localScalar: localPrivateKey.rawRepresentation,
                peerPublicUncompressed: info.publicKey,
            )
        } catch {
            throw Error.decodingFailed("ECDH: \(error)")
        }
        let sessionKey = SessionKey.derive(fromSharedSecret: sharedSecret)

        // Verify the HMAC tag using the newly-derived session key.
        let computedTag = try SessionNegotiator.computeSessionInfoTag(
            sessionKey: sessionKey,
            verifierName: verifierName,
            challenge: challenge,
            encodedInfo: encodedInfo,
        )
        guard Self.constantTimeEqual(computedTag, expectedTag) else {
            throw Error.unexpectedResponse("SessionInfo HMAC tag mismatch")
        }

        return (info, sessionKey)
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0 ..< a.count {
            diff |= a[a.index(a.startIndex, offsetBy: i)] ^ b[b.index(b.startIndex, offsetBy: i)]
        }
        return diff == 0
    }

    // MARK: - Internals

    private func requireSession(for domain: UniversalMessage_Domain) throws -> VehicleSession {
        switch domain {
        case .vehicleSecurity:
            guard let s = vcsecSession else { throw Error.noSessionForDomain(domain) }
            return s
        case .infotainment:
            guard let s = infotainmentSession else { throw Error.noSessionForDomain(domain) }
            return s
        default:
            throw Error.noSessionForDomain(domain)
        }
    }

    private func transmit(message: UniversalMessage_RoutableMessage) async throws {
        let bytes: Data
        do {
            bytes = try message.serializedData()
        } catch {
            throw Error.encodingFailed(String(describing: error))
        }
        try await transport.sendMessage(bytes)
    }

    /// Registers a continuation before firing `transmit` so that an early
    /// response cannot arrive at an unregistered uuid. Completion races the
    /// inbound loop, the timeout task, and `stop()` / `cancelAll`.
    private func withRegisteredRequest(
        uuid: Data,
        timeout: Duration,
        transmit: @Sendable @escaping () async throws -> Void,
    ) async throws -> UniversalMessage_RoutableMessage {
        try await withCheckedThrowingContinuation { (cont: RequestTable.Continuation) in
            do {
                try requestTable.register(uuid: uuid, continuation: cont)
            } catch {
                cont.resume(throwing: error)
                return
            }

            Task { [weak self] in
                // Transmit outside the register-or-throw critical section so
                // an early response finds a registered continuation.
                do {
                    try await transmit()
                } catch {
                    await self?.failRequest(uuid: uuid, error: error)
                    return
                }

                do {
                    try await Task.sleep(nanoseconds: Self.durationToNanoseconds(timeout))
                    await self?.failRequest(uuid: uuid, error: Error.timeout)
                } catch {
                    // Task cancelled — the continuation may already have been
                    // completed by the inbound loop; attempt to fail is a
                    // no-op if the uuid is already unregistered.
                    await self?.failRequest(uuid: uuid, error: CancellationError())
                }
            }
        }
    }

    private func failRequest(uuid: Data, error: Swift.Error) {
        _ = requestTable.fail(uuid: uuid, error: error)
    }

    // MARK: - Inbound loop

    private func inboundLoop() async {
        while !Task.isCancelled {
            let bytes: Data
            do {
                bytes = try await transport.receiveMessage()
            } catch {
                logger?.log(.warning, category: "dispatcher", "inbound loop exit: \(error)")
                requestTable.cancelAll(error: Error.shutdown)
                return
            }

            let message: UniversalMessage_RoutableMessage
            do {
                message = try UniversalMessage_RoutableMessage(serializedBytes: bytes)
            } catch {
                logger?.log(.warning, category: "dispatcher", "dropping undecodable inbound frame: \(error)")
                continue
            }

            let matchUUID = message.requestUuid
            if !matchUUID.isEmpty {
                let routed = requestTable.complete(uuid: matchUUID, with: message)
                if !routed {
                    logger?.log(.warning, category: "dispatcher", "no pending request for uuid \(matchUUID.map { String(format: "%02x", $0) }.joined()); dropping")
                }
            } else {
                logger?.log(.debug, category: "dispatcher", "unsolicited inbound message (no requestUuid); dropping")
            }
        }
    }

    // MARK: - Constants & helpers

    private static let defaultExpiresAt: UInt32 = 60

    private static func newUUIDBytes() -> Data {
        var uuid = UUID().uuid
        return withUnsafeBytes(of: &uuid) { Data($0) }
    }

    /// Uses the `nanoseconds:` form of `Task.sleep` because `sleep(for:)`
    /// requires macOS 13+ / iOS 16+ but this package's macOS floor is 11.
    private static func durationToNanoseconds(_ duration: Duration) -> UInt64 {
        let components = duration.components
        let seconds = UInt64(max(0, components.seconds))
        // `attoseconds` range is 0..<1e18; 1 nano = 1e9 atto.
        let fractionalNanos = UInt64(max(0, components.attoseconds)) / 1_000_000_000
        return seconds * 1_000_000_000 + fractionalNanos
    }
}
