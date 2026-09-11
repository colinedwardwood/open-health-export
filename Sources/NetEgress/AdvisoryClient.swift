// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import WireFormat

public struct AdvisoryState: Sendable, Equatable {
    public var enabled: Bool
    public var lastAttemptEpoch: TimeInterval?
    public var lastVerifiedEpoch: TimeInterval?
    public var lastSeenSeq: Int

    public init(
        enabled: Bool = true,
        lastAttemptEpoch: TimeInterval? = nil,
        lastVerifiedEpoch: TimeInterval? = nil,
        lastSeenSeq: Int = 0
    ) {
        self.enabled = enabled
        self.lastAttemptEpoch = lastAttemptEpoch
        self.lastVerifiedEpoch = lastVerifiedEpoch
        self.lastSeenSeq = lastSeenSeq
    }
}

public struct AdvisoryPresentation: Sendable, Equatable {
    public var items: [AdvisoryItem]
    public var banner: String?
    public var endpoint: String
    public var fetched: Bool

    public init(
        items: [AdvisoryItem] = [],
        banner: String? = nil,
        endpoint: String = AdvisoryPinnedKeys.urlString,
        fetched: Bool = false
    ) {
        self.items = items
        self.banner = banner
        self.endpoint = endpoint
        self.fetched = fetched
    }
}

public struct AdvisoryFetchResult: Sendable, Equatable {
    public var state: AdvisoryState
    public var presentation: AdvisoryPresentation
    public var ledgerOutcome: String

    public init(state: AdvisoryState, presentation: AdvisoryPresentation, ledgerOutcome: String) {
        self.state = state
        self.presentation = presentation
        self.ledgerOutcome = ledgerOutcome
    }
}

public enum AdvisorySchedule {
    public static let minInterval: TimeInterval = 24 * 60 * 60
    public static let maxJitter: TimeInterval = 120

    public static func shouldFetch(
        enabled: Bool,
        foregroundVisible: Bool,
        lastAttempt: Date?,
        now: Date
    ) -> Bool {
        guard enabled, foregroundVisible else { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= minInterval
    }
}

public enum AdvisoryRequest {
    public static let allowedHeaders: Set<String> = ["accept", "host", "user-agent"]

    public static func make(
        marketingVersion: String,
        emptyBody: URL
    ) throws -> OutboundHTTPRequest {
        let coarse = MarketingVersion.coarse(marketingVersion)
        let url = try EgressURL.parse(
            AdvisoryPinnedKeys.urlString,
            allowedHosts: [AdvisoryPinnedKeys.host],
            allowInsecureHTTP: false
        )
        guard url.query == nil, url.path == AdvisoryPinnedKeys.path else {
            throw EgressError.invalidURL
        }
        return OutboundHTTPRequest(
            method: "GET",
            url: url,
            headers: [
                "Accept": "application/json",
                "Host": AdvisoryPinnedKeys.host,
                "User-Agent": "OpenHealthExporter/\(coarse)",
            ],
            bodyFile: emptyBody
        )
    }

    /// Canonical outbound request for the R-38 golden fixture. Extra headers fail CI.
    public static func wireDump(_ request: OutboundHTTPRequest) throws -> String {
        guard request.method == "GET" else {
            throw EgressError.transport("advisory request must be GET")
        }
        guard request.url.query == nil else {
            throw EgressError.transport("advisory request must not carry a query")
        }
        guard request.url.path == AdvisoryPinnedKeys.path else {
            throw EgressError.transport("advisory path mismatch")
        }
        let body = try Data(contentsOf: request.bodyFile)
        guard body.isEmpty else {
            throw EgressError.transport("advisory request must have an empty body")
        }
        var canonical: [String: String] = [:]
        for (name, value) in request.headers {
            let key = name.lowercased()
            if ["if-none-match", "if-modified-since", "cookie", "authorization", "etag"].contains(key) {
                throw EgressError.transport("advisory request forbids \(key)")
            }
            guard allowedHeaders.contains(key) else {
                throw EgressError.transport("advisory request has extra header \(key)")
            }
            canonical[key] = value
        }
        guard Set(canonical.keys) == allowedHeaders else {
            throw EgressError.transport("advisory request is missing a required header")
        }
        let lines = [
            "GET \(AdvisoryPinnedKeys.path) HTTP/1.1",
            "accept: \(canonical["accept"]!)",
            "host: \(canonical["host"]!)",
            "user-agent: \(canonical["user-agent"]!)",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum AdvisoryClient {
    public static func fetch(
        transport: HTTPTransport,
        store: StateStore,
        state: AdvisoryState,
        now: Date,
        marketingVersion: String,
        foregroundVisible: Bool,
        emptyBody: URL
    ) async throws -> AdvisoryFetchResult {
        var next = state
        if !state.enabled {
            let last = lastCheckedCopy(state.lastVerifiedEpoch ?? state.lastAttemptEpoch)
            return AdvisoryFetchResult(
                state: next,
                presentation: AdvisoryPresentation(
                    banner: AdvisoryStaleness.disabledCopy(lastChecked: last)
                ),
                ledgerOutcome: "advisory:disabled"
            )
        }
        guard AdvisorySchedule.shouldFetch(
            enabled: true,
            foregroundVisible: foregroundVisible,
            lastAttempt: state.lastAttemptEpoch.map { Date(timeIntervalSince1970: $0) },
            now: now
        ) else {
            return AdvisoryFetchResult(
                state: next,
                presentation: presentation(state: state, items: [], fetched: false, now: now),
                ledgerOutcome: "advisory:not-due"
            )
        }

        next.lastAttemptEpoch = now.timeIntervalSince1970
        let request = try AdvisoryRequest.make(
            marketingVersion: marketingVersion,
            emptyBody: emptyBody
        )
        _ = try AdvisoryRequest.wireDump(request)

        do {
            let response = try await transport.execute(request)
            guard (200 ..< 300).contains(response.status) else {
                throw EgressError.httpStatus(response.status)
            }
            let feed = try AdvisoryDocument.parse(
                response.body,
                lastSeenSeq: state.lastSeenSeq,
                now: now
            )
            next.lastVerifiedEpoch = now.timeIntervalSince1970
            next.lastSeenSeq = feed.seq
            try await appendLedger(
                store: store,
                outcome: "advisory:verified",
                bytes: response.body.count,
                detail: "seq=\(feed.seq)",
                now: now
            )
            return AdvisoryFetchResult(
                state: next,
                presentation: AdvisoryPresentation(items: feed.items, fetched: true),
                ledgerOutcome: "advisory:verified"
            )
        } catch {
            try await appendLedger(
                store: store,
                outcome: "advisory:failed",
                bytes: 0,
                detail: "unreachable",
                now: now
            )
            return AdvisoryFetchResult(
                state: next,
                presentation: presentation(state: next, items: [], fetched: false, now: now),
                ledgerOutcome: "advisory:failed"
            )
        }
    }

    private static func presentation(
        state: AdvisoryState,
        items: [AdvisoryItem],
        fetched: Bool,
        now: Date
    ) -> AdvisoryPresentation {
        let last = state.lastVerifiedEpoch.map { Date(timeIntervalSince1970: $0) }
        let banner = AdvisoryStaleness.isStale(lastVerified: last, now: now)
            ? AdvisoryStaleness.staleCopy
            : nil
        return AdvisoryPresentation(items: items, banner: banner, fetched: fetched)
    }

    private static func lastCheckedCopy(_ epoch: TimeInterval?) -> String {
        guard let epoch else { return "never" }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: epoch))
    }

    private static func appendLedger(
        store: StateStore,
        outcome: String,
        bytes: Int,
        detail: String,
        now: Date
    ) async throws {
        try await store.transact { tx in
            try tx.appendLedger(
                EgressEntry(
                    destination: "advisory:\(AdvisoryPinnedKeys.host)",
                    sampleCount: 0,
                    outcomeKind: outcome,
                    byteCount: bytes,
                    detail: detail,
                    wallTimeEpoch: now.timeIntervalSince1970
                )
            )
        }
    }
}
