// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import NetEgress
import SinkCompanion
import TestSupport
import Testing
import WireFormat

@Test func companionFrameRoundTripsWithoutAlignedLoad() throws {
    let payload = Data("hello-companion".utf8)
    let encoded = try CompanionFrame(type: .hello, payload: payload).encode()
    let decoded = try CompanionFrame.decodePrefix(encoded)
    #expect(decoded?.consumed == encoded.count)
    #expect(decoded?.frame.payload == payload)
    #expect(try CompanionFrame.decodePrefix(encoded.prefix(3)) == nil)
}

@Test func companionHelloOfferResumeCommit() throws {
    var receiver = CompanionReceiver(installationID: "mac")
    let payload = Data("abcdef".utf8)
    let digest = ContentSHA256.digest(payload)
    let offer = CompanionOffer(
        batchID: "batch-1",
        idempotencyKey: "batch-1",
        byteCount: UInt64(payload.count),
        digest: digest
    )
    let hello = receiver.handle(.hello(
        protocolVersion: 1,
        installationID: "phone",
        capabilities: CompanionReceiver.capabilities
    ))
    guard case .hello(let version, let id, _) = hello.first else {
        Issue.record("expected hello")
        return
    }
    #expect(version == 1)
    #expect(id == "mac")

    #expect(receiver.handle(.offer(offer)) == [.resume(fromChunk: 0)])
    let parts = CompanionChunks.split(payload, size: 2)
    #expect(receiver.handle(.chunk(seq: 0, bytes: parts[0])) == [.chunkAck(seq: 0)])
    #expect(receiver.handle(.chunk(seq: 1, bytes: parts[1])) == [.chunkAck(seq: 1)])
    #expect(receiver.handle(.chunk(seq: 2, bytes: parts[2])) == [.chunkAck(seq: 2)])
    #expect(receiver.handle(.commit(digest: digest)) == [.receipt(batchID: "batch-1", digest: digest)])
    #expect(receiver.handle(.offer(offer)) == [.receipt(batchID: "batch-1", digest: digest)])
}

@Test func companionResumeAfterDroppedTail() throws {
    var receiver = CompanionReceiver(installationID: "mac")
    let payload = Data("abcdefgh".utf8)
    let digest = ContentSHA256.digest(payload)
    let offer = CompanionOffer(
        batchID: "batch-resume",
        idempotencyKey: "batch-resume",
        byteCount: UInt64(payload.count),
        digest: digest
    )
    _ = receiver.handle(.hello(protocolVersion: 1, installationID: "phone", capabilities: []))
    #expect(receiver.handle(.offer(offer)) == [.resume(fromChunk: 0)])
    let parts = CompanionChunks.split(payload, size: 3)
    _ = receiver.handle(.chunk(seq: 0, bytes: parts[0]))
    #expect(receiver.handle(.offer(offer)) == [.resume(fromChunk: 1)])
    for seq in 1..<UInt32(parts.count) {
        _ = receiver.handle(.chunk(seq: seq, bytes: parts[Int(seq)]))
    }
    #expect(receiver.handle(.commit(digest: digest)) == [
        .receipt(batchID: "batch-resume", digest: digest)
    ])
}

@Test func companionRejectsConflictingDigestOnKnownBatch() throws {
    var receiver = CompanionReceiver(installationID: "mac")
    let payload = Data("ok".utf8)
    let digest = ContentSHA256.digest(payload)
    let offer = CompanionOffer(
        batchID: "batch-x",
        idempotencyKey: "batch-x",
        byteCount: 2,
        digest: digest
    )
    _ = receiver.handle(.offer(offer))
    _ = receiver.handle(.chunk(seq: 0, bytes: payload))
    _ = receiver.handle(.commit(digest: digest))
    let other = CompanionOffer(
        batchID: "batch-x",
        idempotencyKey: "batch-x",
        byteCount: 2,
        digest: ContentSHA256.digest(Data("no".utf8))
    )
    guard case .reject(_, let detail, false) = receiver.handle(.offer(other)).first else {
        Issue.record("expected reject")
        return
    }
    #expect(detail == "digestMismatch")
}

@Test func companionSinkDeliversAndReofferIsIdempotent() async throws {
    let (file, batchID, digest) = try writeCompanionPayload()
    let broker = LoopbackCompanionBroker()
    let sink = CompanionSink(pipe: broker, installationID: "phone", chunkSize: 32)
    let first = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(first.accepted == 1)
    #expect(await broker.storedDigest(batchID: batchID.rawValue) == digest)
    let second = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(second.accepted == 1)
}

@Test func companionSinkRefusesMeteredPathBeforeAnyByte() async throws {
    let (file, batchID, _) = try writeCompanionPayload()
    let broker = LoopbackCompanionBroker()
    let sink = CompanionSink(
        pipe: broker,
        installationID: "phone",
        chunkSize: 32,
        meteredPolicy: .refuseMetered,
        pathConditions: NetworkPathConditions(isExpensive: true, isConstrained: false)
    )
    await #expect(throws: DestinationSendError.awaitingUnmetered) {
        _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    }
    #expect(await broker.storedDigest(batchID: batchID.rawValue) == nil)
}

@Test func companionEnableRefusesMeteredPathBeforeCanary() async throws {
    let broker = LoopbackCompanionBroker()
    await #expect(throws: DestinationSendError.awaitingUnmetered) {
        _ = try await CompanionDestinationEnable.complete(
            testPipe: broker,
            deliveryPipe: broker,
            installationID: "phone",
            emittedAt: "2026-01-01T00:00:00Z",
            meteredPolicy: .refuseMetered,
            pathConditions: NetworkPathConditions(isExpensive: true, isConstrained: false)
        )
    }
    #expect(await broker.storedDigest(batchID: "00000000-0000-4000-8000-000000000002") == nil)
}

@Test func companionSinkDrivesAcknowledgedOnTheEngine() async throws {
    let metric = MetricID(rawValue: "heartRate")
    let page = SamplePage(
        samples: [heartSample("11111111-1111-1111-1111-111111111111")],
        tombstones: [],
        metric: metric,
        anchorBlob: Data([0x11]),
        observedThrough: Date(timeIntervalSince1970: 0)
    )
    let broker = LoopbackCompanionBroker()
    let sink = CompanionSink(pipe: broker, installationID: "phone", chunkSize: 64)
    let store = MemoryStateStore()
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-companion-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let run = ExportRun(
        source: FixtureSource(pages: [page]),
        destination: .testing(sink),
        store: store,
        metric: metric,
        scratchDirectory: scratch,
        destinationName: "companion",
        envelope: testEnvelope()
    )
    let outcome = try await run.run()
    #expect(outcome.kind == .success)
    #expect(outcome.ackEvidence == .receiptFull)
}

private func writeCompanionPayload() throws -> (URL, BatchID, String) {
    let sample = heartSample("00000000-0000-0000-0000-0000000000c1")
    let batchID = BatchID(rawValue: "0192f3c1-0000-0000-0000-0000000000c1")
    let data = try NativeWire.encode(
        samples: [sample],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: batchID,
        envelope: testEnvelope()
    )
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-companion-payload-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("batch.ndjson")
    try FileWriteKit.writeAtomically(data, to: file)
    return (file, batchID, ContentSHA256.digest(data))
}

@Test func companionDestinationTestRoundTripsACanary() async throws {
    let broker = LoopbackCompanionBroker()
    let report = await CompanionDestinationTest.run(
        pipe: broker,
        installationID: "phone",
        canary: Data("companion-canary".utf8)
    )
    #expect(report.verdict == .passed)
    #expect(report.failingStep == nil)
}

@Test func companionDestinationEnableTestsBeforeReturningVerifiedSink() async throws {
    let broker = LoopbackCompanionBroker()
    let enabled = try await CompanionDestinationEnable.complete(
        testPipe: broker,
        deliveryPipe: broker,
        installationID: "phone",
        emittedAt: "2024-01-01T00:00:00Z"
    )
    #expect(enabled.report.verdict == .passed)
    #expect(enabled.events == [
        .canaryConfirmed,
        .pinRecorded(groupedFingerprint: nil),
        .destinationEnabled,
    ])
    let (file, batchID, _) = try writeCompanionPayload()
    let receipt = try await enabled.destination.sink.send(
        fileHandle: file.path,
        idempotencyKey: batchID
    )
    #expect(receipt.accepted == 1)

    let resumed = try CompanionDestinationEnable.resume(
        deliveryPipe: broker,
        installationID: "phone",
        testReport: enabled.report
    )
    _ = resumed.sink
}

@Test func companionOfferTraceparentRoundTripsAndReceiverNeverContinuesIt() throws {
    let inbound = Traceparent.make(seed: "attacker")
    let offer = CompanionOffer(
        batchID: "batch-tp",
        idempotencyKey: "batch-tp",
        byteCount: 4,
        digest: ContentSHA256.digest(Data("abcd".utf8)),
        traceparent: inbound
    )
    let encoded = try CompanionMessage.offer(offer).encodedFrame()
    let decoded = try #require(try CompanionFrame.decodePrefix(encoded))
    let message = try CompanionMessage.decode(decoded.frame)
    guard case .offer(let parsed) = message else {
        Issue.record("expected offer")
        return
    }
    #expect(parsed.traceparent == inbound)

    var receiver = CompanionReceiver(installationID: "mac-root")
    _ = receiver.handle(.hello(
        protocolVersion: 1,
        installationID: "phone",
        capabilities: CompanionReceiver.capabilities
    ))
    _ = receiver.handle(.offer(parsed))
    #expect(receiver.exportReceipts().isEmpty)
    #expect(CompanionReceiver.capabilities.contains("traceparent"))
}

@Test func companionSinkOmitsTraceparentByDefault() async throws {
    let (file, batchID, _) = try writeCompanionPayload()
    let broker = LoopbackCompanionBroker()
    let capture = CompanionOfferCapture(inner: broker)
    let sink = CompanionSink(pipe: capture, installationID: "phone", chunkSize: 32)
    _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    let offers = await capture.offers
    #expect(!offers.isEmpty)
    #expect(offers.allSatisfy { $0.traceparent == nil })
}

@Test func companionSinkSendsTraceparentWhenPeerAdvertisesIt() async throws {
    let (file, batchID, _) = try writeCompanionPayload()
    let broker = LoopbackCompanionBroker()
    let capture = CompanionOfferCapture(inner: broker)
    let emission = TraceparentEmission(enabled: true)
    let sink = CompanionSink(
        pipe: capture,
        installationID: "phone",
        chunkSize: 32,
        traceparent: emission
    )
    _ = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    let offers = await capture.offers
    #expect(offers.contains { $0.traceparent == Traceparent.make(seed: batchID.rawValue) })
}

private actor CompanionOfferCapture: CompanionBytePipe {
    let inner: LoopbackCompanionBroker
    var offers: [CompanionOffer] = []

    init(inner: LoopbackCompanionBroker) {
        self.inner = inner
    }

    func send(_ data: Data) async throws {
        var remainder = data
        while let decoded = try CompanionFrame.decodePrefix(remainder) {
            remainder.removeFirst(decoded.consumed)
            if case .offer(let offer) = try CompanionMessage.decode(decoded.frame) {
                offers.append(offer)
            }
        }
        try await inner.send(data)
    }

    func receive(max: Int) async throws -> Data {
        try await inner.receive(max: max)
    }
}
