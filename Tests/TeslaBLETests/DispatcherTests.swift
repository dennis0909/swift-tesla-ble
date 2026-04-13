import CryptoKit
import Foundation
@testable import TeslaBLE
import XCTest

final class DispatcherTests: XCTestCase {
    // MARK: - RequestTable

    /// Wraps RequestTable (a value type) in a class so Swift 6 strict-concurrency
    /// lets us capture the same table across multiple async-let closures.
    private final class TableBox: @unchecked Sendable {
        var table = RequestTable()
    }

    func testRequestTableRegisterComplete() async throws {
        let box = TableBox()
        let uuid = Data([0xDE, 0xAD, 0xBE, 0xEF])

        async let received: UniversalMessage_RoutableMessage = withCheckedThrowingContinuation { cont in
            do {
                try box.table.register(uuid: uuid, continuation: cont)
            } catch {
                cont.resume(throwing: error)
            }
        }

        // Give the async let a chance to register before we complete.
        try await Task.sleep(nanoseconds: 10_000_000)

        var response = UniversalMessage_RoutableMessage()
        response.requestUuid = uuid
        let found = box.table.complete(uuid: uuid, with: response)
        XCTAssertTrue(found)

        let got = try await received
        XCTAssertEqual(got.requestUuid, uuid)
        XCTAssertTrue(box.table.isEmpty)
    }

    func testRequestTableFailPropagatesError() async throws {
        enum Canary: Swift.Error, Equatable { case boom }

        let box = TableBox()
        let uuid = Data([0x01, 0x02])

        async let result: UniversalMessage_RoutableMessage = withCheckedThrowingContinuation { cont in
            do {
                try box.table.register(uuid: uuid, continuation: cont)
            } catch {
                cont.resume(throwing: error)
            }
        }

        try await Task.sleep(nanoseconds: 10_000_000)

        let found = box.table.fail(uuid: uuid, error: Canary.boom)
        XCTAssertTrue(found)

        do {
            _ = try await result
            XCTFail("expected error")
        } catch Canary.boom {
            // ok
        }
        XCTAssertTrue(box.table.isEmpty)
    }

    func testRequestTableCancelAllWakesEveryone() async throws {
        enum Canary: Swift.Error, Equatable { case shutdown }

        // Use an actor to serialize all access to the RequestTable, avoiding
        // data races when multiple tasks register continuations concurrently.
        actor TableActor {
            var table = RequestTable()
            func register(uuid: Data, continuation: RequestTable.Continuation) throws {
                try table.register(uuid: uuid, continuation: continuation)
            }

            func count() -> Int {
                table.count
            }

            func cancelAll(error: Swift.Error) {
                table.cancelAll(error: error)
            }

            func isEmpty() -> Bool {
                table.isEmpty
            }
        }

        let actor = TableActor()
        let uuidA = Data([0xA1])
        let uuidB = Data([0xB2])

        // Spawn two tasks, each of which registers a continuation and then
        // suspends. The tasks run concurrently but table access is serialized
        // by the actor.
        let taskA = Task { () -> UniversalMessage_RoutableMessage in
            return try await withCheckedThrowingContinuation { cont in
                Task { try? await actor.register(uuid: uuidA, continuation: cont) }
            }
        }
        let taskB = Task { () -> UniversalMessage_RoutableMessage in
            return try await withCheckedThrowingContinuation { cont in
                Task { try? await actor.register(uuid: uuidB, continuation: cont) }
            }
        }

        // Wait for both registrations to land.
        try await Task.sleep(nanoseconds: 20_000_000)
        let countBeforeCancel = await actor.count()
        XCTAssertEqual(countBeforeCancel, 2)

        await actor.cancelAll(error: Canary.shutdown)
        let emptyAfterCancel = await actor.isEmpty()
        XCTAssertTrue(emptyAfterCancel)

        var failures = 0
        do { _ = try await taskA.value } catch Canary.shutdown { failures += 1 }
        do { _ = try await taskB.value } catch Canary.shutdown { failures += 1 }
        XCTAssertEqual(failures, 2)
    }

    // MARK: - Dispatcher helpers

    @available(macOS 13.0, iOS 16.0, *)
    private func makeSessionKey() -> SessionKey {
        SessionKey(rawBytes: Data(repeating: 0x42, count: 16))
    }

    @available(macOS 13.0, iOS 16.0, *)
    private func makeSession(domain: UniversalMessage_Domain, initialCounter: UInt32 = 0) -> VehicleSession {
        VehicleSession(
            domain: domain,
            verifierName: Data("test_verifier".utf8),
            localPublicKey: Data(repeating: 0x04, count: 65),
            sessionKey: makeSessionKey(),
            epoch: Data(repeating: 0xAB, count: 16),
            initialCounter: initialCounter,
        )
    }

    /// Seal a canned response plaintext with the supplied session parameters
    /// and return the serialized `UniversalMessage_RoutableMessage` bytes
    /// ready to hand back through `FakeTransport.enqueueInbound`.
    @available(macOS 13.0, iOS 16.0, *)
    private func makeResponseBytes(
        respondingTo request: UniversalMessage_RoutableMessage,
        plaintext: Data,
        counter: UInt32,
        sessionKey: SessionKey,
        verifierName: Data,
        domain: UniversalMessage_Domain,
    ) throws -> Data {
        let requestID = try XCTUnwrap(InboundVerifier.requestID(forSignedRequest: request))

        var response = UniversalMessage_RoutableMessage()
        response.requestUuid = request.uuid
        var from = UniversalMessage_Destination()
        from.domain = domain
        response.fromDestination = from

        let aad = try SessionMetadata.buildResponseAAD(
            message: response,
            verifierName: verifierName,
            requestID: requestID,
            counter: counter,
        )
        let fixedNonce = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
        let sealed = try MessageAuthenticator.sealFixed(
            plaintext: plaintext,
            associatedData: aad,
            nonce: fixedNonce,
            sessionKey: sessionKey,
        )

        var gcm = Signatures_AES_GCM_Response_Signature_Data()
        gcm.nonce = fixedNonce
        gcm.counter = counter
        gcm.tag = sealed.tag
        var sigData = Signatures_SignatureData()
        sigData.sigType = .aesGcmResponseData(gcm)
        response.subSigData = .signatureData(sigData)
        response.payload = .protobufMessageAsBytes(sealed.ciphertext)

        return try response.serializedData()
    }

    // MARK: - Dispatcher happy path

    @available(macOS 13.0, iOS 16.0, *)
    func testDispatcherSendAndReceivesResponse() async throws {
        let transport = FakeTransport()
        let dispatcher = Dispatcher(transport: transport)
        try await dispatcher.start()
        let session = makeSession(domain: .vehicleSecurity)
        await dispatcher.installSession(session, forDomain: .vehicleSecurity)

        // Kick off the send on a background task so we can interleave the
        // response injection below.
        let sendTask = Task { () throws -> Data in
            try await dispatcher.send(Data("lock".utf8), domain: .vehicleSecurity, timeout: .seconds(2))
        }

        // Wait for the outbound bytes to appear.
        var outbound: [Data] = []
        for _ in 0 ..< 50 {
            outbound = await transport.sentMessages
            if !outbound.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(outbound.count, 1, "dispatcher should have written exactly one outbound message")

        let outboundRequest = try UniversalMessage_RoutableMessage(serializedBytes: outbound[0])
        XCTAssertEqual(outboundRequest.toDestination.domain, .vehicleSecurity)

        // Seal a canned response using the same session parameters.
        let responseBytes = try makeResponseBytes(
            respondingTo: outboundRequest,
            plaintext: Data("OK".utf8),
            counter: 1,
            sessionKey: makeSessionKey(),
            verifierName: Data("test_verifier".utf8),
            domain: .vehicleSecurity,
        )
        await transport.enqueueInbound(responseBytes)

        let responsePlaintext = try await sendTask.value
        XCTAssertEqual(responsePlaintext, Data("OK".utf8))

        await dispatcher.stop()
    }

    // MARK: - Dispatcher timeout

    @available(macOS 13.0, iOS 16.0, *)
    func testDispatcherSendTimesOut() async throws {
        let transport = FakeTransport()
        let dispatcher = Dispatcher(transport: transport)
        try await dispatcher.start()
        let session = makeSession(domain: .vehicleSecurity)
        await dispatcher.installSession(session, forDomain: .vehicleSecurity)

        let start = ContinuousClock.now
        do {
            _ = try await dispatcher.send(Data("lock".utf8), domain: .vehicleSecurity, timeout: .milliseconds(200))
            XCTFail("expected timeout")
        } catch Dispatcher.Error.timeout {
            // ok
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertLessThan(elapsed, .seconds(1), "timeout should fire close to the deadline")

        await dispatcher.stop()
    }

    // MARK: - Dispatcher error paths

    @available(macOS 13.0, iOS 16.0, *)
    func testDispatcherRejectsSendWithoutSession() async throws {
        let transport = FakeTransport()
        let dispatcher = Dispatcher(transport: transport)
        try await dispatcher.start()

        do {
            _ = try await dispatcher.send(Data("lock".utf8), domain: .vehicleSecurity)
            XCTFail("expected noSessionForDomain")
        } catch let Dispatcher.Error.noSessionForDomain(d) {
            XCTAssertEqual(d, .vehicleSecurity)
        }

        await dispatcher.stop()
    }

    @available(macOS 13.0, iOS 16.0, *)
    func testDispatcherDropsInboundWithUnknownRequestUUID() async throws {
        let transport = FakeTransport()
        let dispatcher = Dispatcher(transport: transport)
        try await dispatcher.start()
        let session = makeSession(domain: .vehicleSecurity)
        await dispatcher.installSession(session, forDomain: .vehicleSecurity)

        // Enqueue a bogus inbound whose requestUuid does not match anything.
        var bogus = UniversalMessage_RoutableMessage()
        bogus.requestUuid = Data([0xFF, 0xFF])
        let bogusBytes = try bogus.serializedData()
        await transport.enqueueInbound(bogusBytes)

        // Give the inbound loop a moment to process+drop the unknown message.
        try await Task.sleep(nanoseconds: 50_000_000)

        // Now send a legit command. Dispatcher should work normally despite
        // the earlier dropped inbound.
        let sendTask = Task { () throws -> Data in
            try await dispatcher.send(Data("lock".utf8), domain: .vehicleSecurity, timeout: .seconds(2))
        }

        var outbound: [Data] = []
        for _ in 0 ..< 50 {
            outbound = await transport.sentMessages
            if !outbound.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(outbound.count, 1)

        let outboundRequest = try UniversalMessage_RoutableMessage(serializedBytes: outbound[0])
        let responseBytes = try makeResponseBytes(
            respondingTo: outboundRequest,
            plaintext: Data("OK".utf8),
            counter: 1,
            sessionKey: makeSessionKey(),
            verifierName: Data("test_verifier".utf8),
            domain: .vehicleSecurity,
        )
        await transport.enqueueInbound(responseBytes)

        let result = try await sendTask.value
        XCTAssertEqual(result, Data("OK".utf8))

        await dispatcher.stop()
    }

    // MARK: - Dispatcher stop() wakes in-flight sends

    @available(macOS 13.0, iOS 16.0, *)
    func testDispatcherStopFailsInFlightSends() async throws {
        let transport = FakeTransport()
        let dispatcher = Dispatcher(transport: transport)
        try await dispatcher.start()
        let session = makeSession(domain: .vehicleSecurity)
        await dispatcher.installSession(session, forDomain: .vehicleSecurity)

        let sendTask = Task { () throws -> Data in
            try await dispatcher.send(Data("lock".utf8), domain: .vehicleSecurity, timeout: .seconds(30))
        }

        // Wait for the outbound write to confirm the send is registered and suspended.
        for _ in 0 ..< 50 {
            let sent = await transport.sentMessages
            if !sent.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        // Stop the dispatcher — should wake the suspended send with .shutdown.
        await dispatcher.stop()

        do {
            _ = try await sendTask.value
            XCTFail("expected shutdown error")
        } catch Dispatcher.Error.shutdown {
            // ok
        }
    }

    // MARK: - Dispatcher handshake roundtrip

    @available(macOS 13.0, iOS 16.0, *)
    func testDispatcherNegotiateRoundtrip() async throws {
        let transport = FakeTransport()
        let dispatcher = Dispatcher(transport: transport)
        try await dispatcher.start()

        // Both sides get real P-256 keypairs.
        let clientKey = P256.KeyAgreement.PrivateKey()
        let vehicleKey = P256.KeyAgreement.PrivateKey()
        let vehiclePublicBytes = vehicleKey.publicKey.x963Representation

        // The shared secret is what the vehicle side "knows" for signing the
        // response tag. We pre-compute it the same way Dispatcher will.
        let sharedSecret = try P256ECDH.sharedSecret(
            localScalar: vehicleKey.rawRepresentation,
            peerPublicUncompressed: clientKey.publicKey.x963Representation,
        )
        let sessionKey = SessionKey.derive(fromSharedSecret: sharedSecret)

        let verifierName = Data("test_verifier".utf8)

        // Kick off the negotiation.
        let negotiateTask = Task { () throws -> (Signatures_SessionInfo, SessionKey) in
            try await dispatcher.negotiate(
                domain: .vehicleSecurity,
                localPrivateKey: clientKey,
                verifierName: verifierName,
                timeout: .seconds(2),
            )
        }

        // Wait for the SessionInfoRequest write.
        var outbound: [Data] = []
        for _ in 0 ..< 50 {
            outbound = await transport.sentMessages
            if !outbound.isEmpty { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(outbound.count, 1)
        let outboundRequest = try UniversalMessage_RoutableMessage(serializedBytes: outbound[0])
        guard case let .sessionInfoRequest(req)? = outboundRequest.payload else {
            XCTFail("expected SessionInfoRequest payload"); return
        }
        XCTAssertEqual(req.challenge.count, 8, "challenge is 8 random bytes")

        // Construct a SessionInfo response with the vehicle's real public key.
        var info = Signatures_SessionInfo()
        info.counter = 7
        info.epoch = Data(repeating: 0xAB, count: 16)
        info.clockTime = 99
        info.publicKey = vehiclePublicBytes
        let encoded = try info.serializedData()

        // Sign the response with the shared session key.
        let tag = try SessionNegotiator.computeSessionInfoTag(
            sessionKey: sessionKey,
            verifierName: verifierName,
            challenge: req.challenge,
            encodedInfo: encoded,
        )

        var response = UniversalMessage_RoutableMessage()
        response.requestUuid = outboundRequest.uuid
        response.payload = .sessionInfo(encoded)
        var sig = Signatures_SignatureData()
        var hmac = Signatures_HMAC_Signature_Data()
        hmac.tag = tag
        sig.sigType = .sessionInfoTag(hmac)
        response.subSigData = .signatureData(sig)
        let responseBytes = try response.serializedData()
        await transport.enqueueInbound(responseBytes)

        let (decodedInfo, derivedKey) = try await negotiateTask.value
        XCTAssertEqual(decodedInfo.counter, 7)
        XCTAssertEqual(decodedInfo.clockTime, 99)
        XCTAssertEqual(derivedKey, sessionKey, "dispatcher should derive the same session key")

        await dispatcher.stop()
    }
}
