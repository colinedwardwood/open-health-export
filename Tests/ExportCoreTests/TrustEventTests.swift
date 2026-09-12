// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import TestSupport
import Testing

private func pinnedSetup(
    identity: TLSIdentity,
    policy: PinPolicy = .leaf
) throws -> DestinationSetup {
    var setup = DestinationSetup()
    try setup.recordPreview(Data("preview".utf8))
    try setup.markCanarySent(code: "ABCD-EF01")
    try setup.confirmCanary("ABCD-EF01")
    try setup.recordPin(from: identity, at: "2024-01-01T00:00:00Z", policy: policy)
    try setup.recordTest(.passedLocalFile)
    return setup
}

private let everyTrustEvent: [TrustEvent] = [
    .canaryConfirmed,
    .pinRecorded(groupedFingerprint: "aaaa bbbb cccc dddd"),
    .pinChangedAndHalted(previous: "aaaa bbbb cccc dddd", observed: "eeee ffff 0000 1111"),
    .destinationEnabled,
    .trustLost,
]

@Test func happyPathEmitsOrderedTrustEvents() throws {
    let identity = sampleIdentity(leaf: "aaaabbbbccccdddd")
    var setup = try pinnedSetup(identity: identity)
    _ = try setup.enable(sink: TrustEventSinkStub())
    #expect(setup.state == .enabled)
    #expect(setup.drainEvents() == [
        .canaryConfirmed,
        .pinRecorded(groupedFingerprint: identity.groupedLeafFingerprint),
        .destinationEnabled,
    ])
    #expect(identity.groupedLeafFingerprint == "aaaa bbbb cccc dddd")
}

@Test func pinningWithoutTLSCarriesNoFingerprint() throws {
    var setup = DestinationSetup()
    try setup.recordPreview(Data())
    try setup.markCanarySent(code: "C")
    try setup.confirmCanary("C")
    try setup.pinWithoutTLS()
    #expect(setup.drainEvents() == [.canaryConfirmed, .pinRecorded(groupedFingerprint: nil)])
}

@Test func drainEventsIsIdempotent() throws {
    var setup = try pinnedSetup(identity: sampleIdentity(leaf: "aaaabbbbccccdddd"))
    #expect(!setup.drainEvents().isEmpty)
    #expect(setup.drainEvents().isEmpty)
}

@Test func pinChangeHaltsAndEmitsOneHaltEvent() throws {
    let pinned = sampleIdentity(leaf: "aaaabbbbccccdddd")
    let rotated = sampleIdentity(leaf: "eeeeffff00001111")
    var setup = try pinnedSetup(identity: pinned)
    _ = setup.drainEvents()

    #expect(throws: PinError.mismatch) {
        try setup.observeIdentity(rotated, at: "2024-01-02T00:00:00Z")
    }
    #expect(setup.state == .halted)
    #expect(setup.drainEvents() == [
        .pinChangedAndHalted(
            previous: pinned.groupedLeafFingerprint,
            observed: rotated.groupedLeafFingerprint
        ),
    ])

    #expect(throws: PinError.mismatch) {
        try setup.observeIdentity(rotated, at: "2024-01-03T00:00:00Z")
    }
    #expect(setup.drainEvents().isEmpty)
}

@Test func matchingIdentityEmitsNothing() throws {
    let identity = sampleIdentity(leaf: "aaaabbbbccccdddd")
    var setup = try pinnedSetup(identity: identity)
    _ = setup.drainEvents()
    try setup.observeIdentity(identity, at: "2024-01-02T00:00:00Z")
    #expect(setup.state == .pinned)
    #expect(setup.drainEvents().isEmpty)
}

@Test func transportFailureEmitsNoTrustEvent() throws {
    var setup = try pinnedSetup(identity: sampleIdentity(leaf: "aaaabbbbccccdddd"))
    _ = setup.drainEvents()
    setup.noteTransportFailure()
    #expect(setup.state == .pinned)
    #expect(setup.drainEvents().isEmpty)
}

@Test func trustLossHaltsAndNotifiesOnce() throws {
    var setup = try pinnedSetup(identity: sampleIdentity(leaf: "aaaabbbbccccdddd"))
    _ = setup.drainEvents()
    setup.noteTrustLost()
    setup.noteTrustLost()
    #expect(setup.state == .halted)
    #expect(setup.drainEvents() == [.trustLost])
}

@Test func everyTrustEventMapsToADistinctNoticeKind() {
    let kinds = everyTrustEvent.map { TrustNotice.notice(for: $0, destination: "ha.example").kind }
    #expect(kinds.count == everyTrustEvent.count)
    #expect(Set(kinds).count == everyTrustEvent.count)
    #expect(
        Set(kinds) == Set(
            UserNotice.Kind.allCases.filter {
                $0 != .queueEvicted
                    && $0 != .queueExpired
                    && $0 != .exportFailed
                    && $0 != .exportOverdue
                    && $0 != .healthAccessRevoked
                    && $0 != .anchorInvalidated
            }
        )
    )
}

@Test func noticesCarryNoProse() {
    let destination = "ha.example"
    let previous = "aaaa bbbb cccc dddd"
    let observed = "eeee ffff 0000 1111"
    let notice = TrustNotice.notice(
        for: .pinChangedAndHalted(previous: previous, observed: observed),
        destination: destination
    )
    let stored = Mirror(reflecting: notice).children.compactMap { $0.value as? String }
    // `destinationID` and the user-visible label intentionally default to the
    // same value, so the destination appears twice in storage but adds no prose.
    #expect(stored.count == 4)
    #expect(Set(stored) == [destination, previous, observed])

    for event in everyTrustEvent {
        let mapped = TrustNotice.notice(for: event, destination: destination)
        let allowed: Set<String> = [destination, previous, observed]
        for value in Mirror(reflecting: mapped).children.compactMap({ $0.value as? String }) {
            if !allowed.contains(value) {
                Issue.record("notice for \(event) carries unexpected string \(value)")
            }
        }
    }
}

@Test func notifierRecordsDrainedEventsInOrder() async throws {
    let identity = sampleIdentity(leaf: "aaaabbbbccccdddd")
    var setup = try pinnedSetup(identity: identity)
    _ = try setup.enable(sink: TrustEventSinkStub())
    let notifier = RecordingNotifier()
    for event in setup.drainEvents() {
        _ = try await notifier.notify(TrustNotice.notice(for: event, destination: "ha.example"))
    }
    #expect(await notifier.kinds == [.destinationVerified, .destinationPinned, .destinationEnabled])
    let recorded = await notifier.notices
    #expect(recorded[1].fingerprint == identity.groupedLeafFingerprint)
    #expect(recorded.allSatisfy { $0.destination == "ha.example" })
}

@Test func notifierFailurePropagatesToCaller() async throws {
    var setup = try pinnedSetup(identity: sampleIdentity(leaf: "aaaabbbbccccdddd"))
    let events = setup.drainEvents()
    let notifier = RecordingNotifier(failOnAttempt: 2)
    await #expect(throws: RecordingNotifier.Failure.injected(attempt: 2)) {
        for event in events {
            _ = try await notifier.notify(TrustNotice.notice(for: event, destination: "ha.example"))
        }
    }
    #expect(await notifier.kinds == [.destinationVerified])
    #expect(await notifier.attempts == 2)
}

@Test func notifierPostsEnableAndPinChangeAndRecordsDeniedDelivery() async throws {
    let identity = sampleIdentity(leaf: "aaaabbbbccccdddd")
    var setup = try pinnedSetup(identity: identity)
    _ = try setup.enable(sink: TrustEventSinkStub())
    let posting = RecordingNotifier()
    let posted = try await TrustNoticePosting.post(
        events: setup.drainEvents(),
        destination: "ha.example",
        notifier: posting
    )
    #expect(posted == [.posted, .posted, .posted])
    #expect(await posting.kinds == [.destinationVerified, .destinationPinned, .destinationEnabled])

    var halted = try pinnedSetup(identity: identity)
    _ = halted.drainEvents()
    #expect(throws: PinError.mismatch) {
        try halted.observeIdentity(
            sampleIdentity(leaf: "eeeeffff00001111"),
            at: "2024-01-02T00:00:00Z"
        )
    }
    let change = RecordingNotifier()
    _ = try await TrustNoticePosting.post(
        events: halted.drainEvents(),
        destination: "ha.example",
        notifier: change
    )
    #expect(await change.kinds == [.destinationRepointed])

    let denied = RecordingNotifier(authorizationDenied: true)
    let skipped = try await TrustNoticePosting.post(
        events: [.destinationEnabled],
        destination: "ha.example",
        notifier: denied
    )
    #expect(skipped == [.skippedAuthorizationDenied])
    #expect(TrustNoticePosting.suppressedCount(skipped) == 1)
    #expect(await denied.notices.isEmpty)
}

private struct TrustEventSinkStub: DestinationSink {
    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        DeliveryReceipt(batchID: idempotencyKey, accepted: 0, statusOnly: true)
    }
}
