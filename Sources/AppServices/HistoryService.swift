// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import CorrectnessEngine
import EnginePorts
import Foundation
import RunJournal

/// What the History screen shows (#42): the run journal, problems first, and the
/// hash-chained egress ledger with its device-seal verdict.
public struct HistoryService: Sendable {
    private let store: @Sendable () throws -> any StateStore
    private let seal: @Sendable () -> any LedgerHeadSeal
    private let sealRecordURL: @Sendable () throws -> URL
    private let formatDate: @Sendable (Date) -> String

    /// How many ledger entries the History screen lists, newest first.
    public static let ledgerLineLimit = 50
    public static let emptyLedgerLine = "Ledger has not been written yet."

    public init(
        store: @escaping @Sendable () throws -> any StateStore,
        seal: @escaping @Sendable () -> any LedgerHeadSeal,
        sealRecordURL: @escaping @Sendable () throws -> URL,
        formatDate: @escaping @Sendable (Date) -> String = {
            $0.formatted(date: .abbreviated, time: .shortened)
        }
    ) {
        self.store = store
        self.seal = seal
        self.sealRecordURL = sealRecordURL
        self.formatDate = formatDate
    }

    /// The integrity verdict first, then the newest entries.
    public func ledgerLines() async throws -> [String] {
        let entries = try await store().transact { try $0.loadLedger() }
        let verification = await LedgerHeadSealRecordFile.verify(
            entries: entries,
            seal: seal(),
            url: try sealRecordURL()
        )
        var lines = [Self.integrityLine(verification)]
        lines.append(contentsOf: entries.suffix(Self.ledgerLineLimit).reversed().map { entry in
            let date = formatDate(Date(timeIntervalSince1970: entry.wallTimeEpoch))
            return "\(date) · \(entry.destination) · \(entry.outcomeKind) · \(entry.sampleCount) records · \(entry.byteCount) bytes"
        })
        return lines
    }

    public func ledgerIntegrityLine() async throws -> String {
        try await ledgerLines().first ?? Self.emptyLedgerLine
    }

    public static func integrityLine(_ verification: LedgerHeadSealVerification) -> String {
        switch verification {
        case .valid(let head, let count):
            let shortHead = head == LedgerChain.genesisHash ? "genesis" : String(head.prefix(12))
            return "Chain and device seal valid · \(count) entries · head \(shortHead)"
        case .chainInvalid(let sequence):
            return "WARNING: chain verification failed at sequence \(sequence)"
        case .sealMissing:
            return "WARNING: ledger head has not been device-sealed"
        case .headMismatch:
            return "WARNING: sealed head does not match the ledger"
        case .identityChanged:
            return "WARNING: ledger identity changed"
        }
    }

    public func historyEvents() async throws -> [RunEvent] {
        let events = try await store().transact { try $0.loadJournal() }
        return RunHistory.problemsFirst(events)
    }

    public func historyLines() async throws -> [String] {
        let events = try await historyEvents()
        guard !events.isEmpty else {
            return [RunHistoryDetail.emptyStateCopy, RunHistoryDetail.retentionCopy]
        }
        var lines = [RunHistoryDetail.retentionCopy]
        for event in events {
            lines.append(contentsOf: RunHistoryDetail.lines(for: event))
        }
        return lines
    }

    public func sentThroughDay(metric: MetricID) async throws -> String? {
        try await BrowserSendState.sentThroughDay(metric: metric, store: store())
    }

    public func indexHorizonDay() async throws -> String? {
        try await BrowserSendState.indexHorizonDay(store: store())
    }
}
