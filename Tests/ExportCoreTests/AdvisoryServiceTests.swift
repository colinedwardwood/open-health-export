// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import EnginePorts
import Foundation
import NetEgress
import TestSupport
import Testing
import WireFormat
#if canImport(CryptoKit)
import CryptoKit
#endif

private final class MemoryAdvisoryStorage: AdvisoryStateStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var state = AdvisoryState()
    private(set) var saves = 0

    func load(enabled: Bool) -> AdvisoryState {
        lock.withLock {
            var loaded = state
            loaded.enabled = enabled
            return loaded
        }
    }

    func save(_ state: AdvisoryState) {
        lock.withLock {
            self.state = state
            saves += 1
        }
    }
}

private func emptyBody() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-advisory-service-\(UUID().uuidString)")
    try Data().write(to: url)
    return url
}

private let serviceNow = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-02T00:00:00Z

private func service(
    storage: MemoryAdvisoryStorage,
    transport: any HTTPTransport,
    verifier: AdvisoryVerifier = .pinned
) throws -> AdvisoryService {
    let body = try emptyBody()
    let store = MemoryStateStore()
    return AdvisoryService(
        storage: storage,
        transport: { transport },
        store: { store },
        emptyBody: { body },
        marketingVersion: "1.0.0",
        verifier: verifier
    )
}

/// #42: switched off, the service makes no request and says the feed is off.
@Test func advisoryServiceMakesNoRequestWhenDisabled() async throws {
    let transport = RecordingHTTPTransport(response: OutboundHTTPResponse(status: 200, body: Data()))
    let storage = MemoryAdvisoryStorage()
    let presentation = try await service(storage: storage, transport: transport)
        .refresh(enabled: false, now: serviceNow)
    #expect(presentation.banner == AdvisoryStaleness.offCopy)
    #expect(await transport.requests.isEmpty)
}

/// #42: a request that fails leaves an honest banner and nothing verified.
@Test func advisoryServiceReportsNeverCheckedWhenTheFetchFails() async throws {
    let storage = MemoryAdvisoryStorage()
    let service = try service(storage: storage, transport: ForbiddenHTTPTransport())
    let presentation = await service.refresh(enabled: true, now: serviceNow)
    #expect(presentation.banner == AdvisoryStaleness.neverCheckedCopy)
    #expect(service.lastVerified() == nil)
}

#if canImport(CryptoKit)
/// #42: a verified feed is shown and its counters are kept for the next launch.
@Test func advisoryServiceShowsAVerifiedFeedAndRemembersIt() async throws {
    let key = Curve25519.Signing.PrivateKey()
    let verifier = AdvisoryVerifier(publicKeys: [
        AdvisoryPinnedKeys.activeID: key.publicKey.rawRepresentation,
    ])
    let feed = AdvisoryFeed(
        seq: 1,
        validFrom: "2026-01-01T00:00:00Z",
        expiresAt: "2026-12-31T00:00:00Z",
        keyID: AdvisoryPinnedKeys.activeID,
        items: [
            AdvisoryItem(
                id: "ADV-1",
                published: "2026-01-01T00:00:00Z",
                severity: "high",
                affected: "1.0",
                description: "Update to 1.0.1.",
                url: "https://example.com/adv-1"
            ),
        ]
    )
    let signature = try key.signature(for: AdvisoryCanonical.bytes(feed))
    let body = AdvisoryCanonical.envelopeJSON(feed, signatureHex: Hex.encode(signature))
    let storage = MemoryAdvisoryStorage()
    let service = try service(
        storage: storage,
        transport: RecordingHTTPTransport(response: OutboundHTTPResponse(status: 200, body: body)),
        verifier: verifier
    )
    let presentation = await service.refresh(enabled: true, now: serviceNow)
    #expect(presentation.items.map(\.id) == ["ADV-1"])
    #expect(presentation.banner == nil)
    #expect(storage.load(enabled: true).lastSeenSeq == 1)
    #expect(service.lastVerified() == serviceNow)
}
#endif
