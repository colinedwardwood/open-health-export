// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import EnginePorts
import Foundation
import NetEgress
import WireFormat

/// Where the advisory client's small amount of state lives between launches. The app
/// keeps it in its preferences; tests use memory.
public protocol AdvisoryStateStorage: Sendable {
    func load(enabled: Bool) -> AdvisoryState
    func save(_ state: AdvisoryState)
}

/// Fetches, verifies and remembers the security-advisory feed (#42). Views ask it for a
/// presentation; they never touch the transport, the ledger or the stored counters.
public struct AdvisoryService: Sendable {
    private let storage: any AdvisoryStateStorage
    private let transport: @Sendable () -> any HTTPTransport
    private let store: @Sendable () throws -> any StateStore
    private let emptyBody: @Sendable () throws -> URL
    private let marketingVersion: String
    private let verifier: AdvisoryVerifier

    public init(
        storage: any AdvisoryStateStorage,
        transport: @escaping @Sendable () -> any HTTPTransport,
        store: @escaping @Sendable () throws -> any StateStore,
        emptyBody: @escaping @Sendable () throws -> URL,
        marketingVersion: String,
        verifier: AdvisoryVerifier = .pinned
    ) {
        self.storage = storage
        self.transport = transport
        self.store = store
        self.emptyBody = emptyBody
        self.marketingVersion = marketingVersion
        self.verifier = verifier
    }

    /// Checks the feed if it is enabled and due, saves what changed, and returns what to
    /// show. A failed check returns the banner that fits what has been verified before.
    public func refresh(enabled: Bool, now: Date) async -> AdvisoryPresentation {
        do {
            let result = try await AdvisoryClient.fetch(
                transport: transport(),
                store: store(),
                state: storage.load(enabled: enabled),
                now: now,
                marketingVersion: marketingVersion,
                foregroundVisible: true,
                emptyBody: emptyBody(),
                verifier: verifier
            )
            storage.save(result.state)
            return result.presentation
        } catch {
            return AdvisoryPresentation(
                banner: AdvisoryStaleness.bannerCopy(lastVerified: lastVerified(), now: now)
            )
        }
    }

    public func lastVerified() -> Date? {
        storage.load(enabled: false).lastVerifiedEpoch.map { Date(timeIntervalSince1970: $0) }
    }
}
