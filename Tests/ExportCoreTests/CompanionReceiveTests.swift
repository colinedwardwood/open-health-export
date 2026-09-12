// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionReceive
import CompanionWire
import CoreDomain
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import SinkCompanion
import TestSupport
import Testing
import WireFormat

@Test func companionArchiveWritesAndReloadsReceipts() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-archive-\(UUID().uuidString)")
    let archive = CompanionArchive(directory: dir)
    let payload = Data("hello-batch".utf8)
    let digest = ContentSHA256.digest(payload)
    try archive.store(
        committed: CompanionCommitted(batchID: "batch-safe", digest: digest, payload: payload),
        receivedAtEpoch: 1_704_067_200
    )
    #expect(try archive.loadReceipts()["batch-safe"] == digest)
    #expect(try archive.loadWatch().lastReceivedEpoch == 1_704_067_200)
    #expect(try Data(contentsOf: archive.payloadURL(batchID: "batch-safe")) == payload)
    #expect(throws: CompanionArchiveError.unsafeBatchID) {
        try archive.store(
            committed: CompanionCommitted(batchID: "../etc", digest: digest, payload: payload),
            receivedAtEpoch: 1_704_067_200
        )
    }
}

@Test func companionDeleteEverythingIsScopedAndIdempotent() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
        "ohe-archive-delete-\(UUID().uuidString)"
    )
    defer { try? FileManager.default.removeItem(at: dir) }
    let archive = CompanionArchive(directory: dir)
    let payload = Data("received".utf8)
    try archive.store(
        committed: CompanionCommitted(
            batchID: "batch-received",
            digest: ContentSHA256.digest(payload),
            payload: payload
        ),
        receivedAtEpoch: 1_704_067_200
    )
    let unrelated = dir.appendingPathComponent("notes.ndjson")
    try Data("not managed by the companion".utf8).write(to: unrelated)

    #expect(try archive.deleteEverythingReceived() == 1)
    #expect(!FileManager.default.fileExists(atPath: try archive.payloadURL(batchID: "batch-received").path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
    #expect(try archive.loadReceipts().isEmpty)
    #expect(try archive.loadWatch().lastReceivedEpoch == nil)
    #expect(try archive.deleteEverythingReceived() == 0)
}

@Test func iCloudFolderIsAWarningNotARefusal() {
    let icloud = URL(fileURLWithPath: "/Users/colin/Library/Mobile Documents/com~apple~CloudDocs/Health")
    #expect(FolderRisk.iCloudSyncWarning(for: icloud) != nil)
    let local = FileManager.default.temporaryDirectory
    #expect(FolderRisk.iCloudSyncWarning(for: local) == nil)
    let archive = CompanionArchive(directory: icloud, warnOnlyOnICloud: true)
    #expect(archive.iCloudWarning() != nil)
}

@Test func companionInboundPersistsAcrossRestart() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-inbound-\(UUID().uuidString)")
    let archive = CompanionArchive(directory: dir)
    let pipes = CrossedBytePipes()
    let phone = await pipes.left()
    let mac = await pipes.right()
    let inbound = try CompanionInbound(
        stream: mac,
        archive: archive,
        installationID: "mac",
        nowEpoch: { 1_704_067_200 }
    )
    let serve = Task { try await inbound.serve() }
    let (file, batchID) = try writeInboundPayload()
    let sink = CompanionSink(pipe: ByteStreamCompanionPipe(stream: phone), installationID: "phone", chunkSize: 8)
    let first = try await sink.send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(first.accepted == 1)
    #expect(try archive.loadWatch().lastReceivedEpoch == 1_704_067_200)
    serve.cancel()

    let pipes2 = CrossedBytePipes()
    let phone2 = await pipes2.left()
    let mac2 = await pipes2.right()
    let inbound2 = try CompanionInbound(stream: mac2, archive: archive, installationID: "mac")
    let serve2 = Task { try await inbound2.serve() }
    let second = try await CompanionSink(
        pipe: ByteStreamCompanionPipe(stream: phone2),
        installationID: "phone",
        chunkSize: 8
    ).send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(second.accepted == 1)
    serve2.cancel()
}

@Test func companionInboundReportsPeerFromHelloForSAS() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-sas-\(UUID().uuidString)")
    let archive = CompanionArchive(directory: dir)
    let pipes = CrossedBytePipes()
    let phone = await pipes.left()
    let mac = await pipes.right()
    let seen = LockedBox<String>()
    let inbound = try CompanionInbound(
        stream: mac,
        archive: archive,
        installationID: "mac-9F2C",
        onPeerHello: { seen.set($0) }
    )
    let serve = Task { try await inbound.serve() }
    let (file, batchID) = try writeInboundPayload()
    _ = try await CompanionSink(
        pipe: ByteStreamCompanionPipe(stream: phone),
        installationID: "phone-1A7B",
        chunkSize: 8
    ).send(fileHandle: file.path, idempotencyKey: batchID)
    #expect(seen.get() == "phone-1A7B")
    serve.cancel()
}

@Test func companionQuietWatchFiresAfterThreeDaysAndResetsOnArrival() throws {
    let waiting = CompanionQuietWatch.evaluate(lastReceivedEpoch: nil, nowEpoch: 100)
    #expect(waiting == .waitingForFirstTransfer)
    #expect(CompanionQuietWatch.statusCopy(waiting) == CompanionQuietWatch.waitingCopy)

    let last: TimeInterval = 1_000
    let stillFresh = CompanionQuietWatch.evaluate(
        lastReceivedEpoch: last,
        nowEpoch: last + CompanionQuietWatch.quietAfterSeconds - 1
    )
    #expect(stillFresh == .receiving(lastReceivedEpoch: last))

    let quiet = CompanionQuietWatch.evaluate(
        lastReceivedEpoch: last,
        nowEpoch: last + CompanionQuietWatch.quietAfterSeconds
    )
    #expect(quiet == .quiet(lastReceivedEpoch: last))
    #expect(CompanionQuietWatch.statusCopy(quiet).contains(CompanionQuietWatch.quietTitle))
    #expect(!CompanionQuietWatch.statusCopy(quiet).contains("Tributary"))

    var watch = CompanionReceiveWatch(lastReceivedEpoch: last)
    #expect(
        CompanionQuietWatch.claimQuietNotice(kind: quiet, nowEpoch: last + CompanionQuietWatch.quietAfterSeconds, watch: &watch)
    )
    #expect(
        !CompanionQuietWatch.claimQuietNotice(
            kind: quiet,
            nowEpoch: last + CompanionQuietWatch.quietAfterSeconds + 60,
            watch: &watch
        )
    )
    #expect(
        CompanionQuietWatch.claimQuietNotice(
            kind: quiet,
            nowEpoch: last + CompanionQuietWatch.quietAfterSeconds + CompanionQuietWatch.noticeRepeatSeconds,
            watch: &watch
        )
    )
    watch.lastReceivedEpoch = last + CompanionQuietWatch.quietAfterSeconds + CompanionQuietWatch.noticeRepeatSeconds + 10
    let afterArrival = CompanionQuietWatch.evaluate(
        lastReceivedEpoch: watch.lastReceivedEpoch,
        nowEpoch: watch.lastReceivedEpoch!
    )
    #expect(afterArrival == .receiving(lastReceivedEpoch: watch.lastReceivedEpoch!))
    #expect(
        !CompanionQuietWatch.claimQuietNotice(kind: afterArrival, nowEpoch: watch.lastReceivedEpoch!, watch: &watch)
    )
}

@Test func noticeCopyCoversEveryKindWithoutCallSiteProse() {
    var kinds: Set<UserNotice.Kind> = []
    for kind in UserNotice.Kind.allCases {
        let notice = UserNotice(
            kind: kind,
            destination: "Home Assistant",
            fingerprint: "aaaa bbbb",
            previousFingerprint: "cccc dddd"
        )
        let copy = NoticeCopy.render(notice)
        #expect(!copy.title.isEmpty)
        #expect(copy.body.contains("Home Assistant"))
        kinds.insert(kind)
    }
    #expect(kinds.count == UserNotice.Kind.allCases.count)
}

@Test func interruptedNoticeNamesTheStartClockAndDestinationLabel() {
    let notice = UserNotice(
        kind: .exportInterrupted,
        destination: "Archive folder",
        startedAtEpoch: 1_704_100_440
    )
    let copy = NoticeCopy.render(notice)
    #expect(copy.title == "Export interrupted")
    #expect(copy.body.contains("Archive folder"))
    #expect(copy.body.contains("didn't finish"))
    #expect(
        NoticeCopy.startClock(
            1_704_100_440,
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "09:14"
    )
}

@Test func memorySecretStoreRoundTripsAndDeleteAllIsR43() async throws {
    let store = MemorySecretStore()
    let handle = SecretHandle(rawValue: "companion-psk")
    try await store.store([1, 2, 3, 4], handle: handle)
    #expect(try await store.load(handle) == [1, 2, 3, 4])
    try await store.deleteAll()
    await #expect(throws: SecretStoreError.notFound) {
        _ = try await store.load(handle)
    }
}

private func writeInboundPayload() throws -> (URL, BatchID) {
    let batchID = BatchID(rawValue: "0192f3c1-0000-0000-0000-0000000000d1")
    let data = try NativeWire.encode(
        samples: [heartSample("00000000-0000-0000-0000-0000000000d1")],
        tombstones: [],
        metric: MetricID(rawValue: "heartRate"),
        batchID: batchID,
        envelope: testEnvelope()
    )
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-in-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("batch.ndjson")
    try FileWriteKit.writeAtomically(data, to: file)
    return (file, batchID)
}

private final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func set(_ new: Value) {
        lock.lock()
        value = new
        lock.unlock()
    }

    func get() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
