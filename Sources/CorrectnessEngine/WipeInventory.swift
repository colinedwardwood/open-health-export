// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation

/// UX-46 / R-43: itemised wipe scope plus the two limits we cannot honour.
public struct WipeReceivedRange: Sendable, Equatable {
    public var destination: String
    public var startDay: String
    public var endDay: String

    public init(destination: String, startDay: String, endDay: String) {
        self.destination = destination
        self.startDay = startDay
        self.endDay = endDay
    }
}

public struct WipeInventory: Sendable, Equatable {
    public var destinationCount: Int
    public var credentialCount: Int
    public var queuedRecords: Int
    public var queuedBytes: Int
    public var runCount: Int
    public var ledgerCount: Int
    public var received: [WipeReceivedRange]

    public init(
        destinationCount: Int = 0,
        credentialCount: Int = 0,
        queuedRecords: Int = 0,
        queuedBytes: Int = 0,
        runCount: Int = 0,
        ledgerCount: Int = 0,
        received: [WipeReceivedRange] = []
    ) {
        self.destinationCount = destinationCount
        self.credentialCount = credentialCount
        self.queuedRecords = queuedRecords
        self.queuedBytes = queuedBytes
        self.runCount = runCount
        self.ledgerCount = ledgerCount
        self.received = received
    }

    public static func build(
        destinationCount: Int,
        credentialCount: Int,
        pending: [PendingBatch],
        journal: [RunEvent],
        ledger: [EgressEntry]
    ) -> WipeInventory {
        var ranges: [String: (start: TimeInterval, end: TimeInterval)] = [:]
        for entry in ledger where entry.sampleCount > 0 && entry.wallTimeEpoch > 0 {
            if var existing = ranges[entry.destination] {
                existing.start = min(existing.start, entry.wallTimeEpoch)
                existing.end = max(existing.end, entry.wallTimeEpoch)
                ranges[entry.destination] = existing
            } else {
                ranges[entry.destination] = (entry.wallTimeEpoch, entry.wallTimeEpoch)
            }
        }
        let received = ranges.keys.sorted().map { destination in
            let span = ranges[destination]!
            return WipeReceivedRange(
                destination: destination,
                startDay: day(span.start),
                endDay: day(span.end)
            )
        }
        return WipeInventory(
            destinationCount: destinationCount,
            credentialCount: credentialCount,
            queuedRecords: pending.reduce(0) { $0 + $1.expectedRecords },
            queuedBytes: pending.reduce(0) { $0 + $1.byteCount },
            runCount: journal.count,
            ledgerCount: ledger.count,
            received: received
        )
    }

    private static func day(_ epoch: TimeInterval) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return String(formatter.string(from: Date(timeIntervalSince1970: epoch)).prefix(10))
    }
}

public enum WipeCopy {
    public static let title = "Delete everything on this device"
    public static let confirmTitle = "Confirm: delete credentials and ledger identity"
    public static let receivedLimit =
        "We cannot delete data your destinations already received."
    public static let healthLimit = "We cannot turn off our own Health access."
    public static let healthPath =
        "To turn access off: Health → your profile picture → Privacy → Apps → Open Health Exporter."
    public static let macLimit =
        "A Mac companion keeps its own copy. Use Delete everything received there. Deleting here does not reach it."
    public static let noneReceived = "No destination has received data yet."

    public static func counts(_ inventory: WipeInventory) -> String {
        let megabytes = Double(inventory.queuedBytes) / 1_048_576
        let queuedSize = String(format: "%.1f", megabytes)
        return "Destinations: \(inventory.destinationCount). "
            + "Stored credentials: \(inventory.credentialCount). "
            + "Queued payloads: \(inventory.queuedRecords) records, \(queuedSize) MB. "
            + "Run history: \(inventory.runCount). "
            + "Egress ledger: \(inventory.ledgerCount)."
    }

    public static func receivedLine(_ range: WipeReceivedRange) -> String {
        if range.startDay == range.endDay {
            return "\(range.destination) received data on \(range.startDay)."
        }
        return "\(range.destination) received data from \(range.startDay) to \(range.endDay)."
    }
}
