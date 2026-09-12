// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

public enum DestinationDisplayState: String, Sendable, Equatable, Codable, CaseIterable {
    case notSetUp = "not_set_up"
    case noExportsYet = "no_exports_yet"
    case manualOnly = "manual_only"
    case healthy
    case quiet
    case sentUnconfirmed = "sent_unconfirmed"
    case partial
    case stale
    case failing
    case blocked
    case waiting
    case limitedByIOS = "limited_by_ios"
    case paused
    case overdue
}

/// File the widget, Control Centre, and watchdog read. Never SQLite (observability Q4).
public struct DestinationStatusSnapshot: Sendable, Equatable, Codable {
    public var schemaVersion: Int
    public var destinationID: String
    public var destinationLabel: String
    public var enabled: Bool
    public var state: DestinationDisplayState
    public var lastOutcome: String?
    public var lastSuccessEpoch: TimeInterval?
    public var lastConfirmedAckEpoch: TimeInterval?
    public var attribution: String?
    public var attributionConfidence: String?
    public var errorClass: String?
    public var staleThresholdSeconds: TimeInterval?
    public var overdueThresholdSeconds: TimeInterval?
    public var nextAttemptEarliestEpoch: TimeInterval?
    public var nextAttemptLatestEpoch: TimeInterval?
    public var freshnessEstimates: [FreshnessClass: LocalFreshnessEstimate]
    /// I6: green / amber / red / over_cap. Amber and above show on the destination row.
    public var queueOccupancy: String?
    public var unacknowledgedSecurityEventCount: Int
    public var writtenAtEpoch: TimeInterval

    public init(
        destinationID: String,
        destinationLabel: String? = nil,
        enabled: Bool,
        state: DestinationDisplayState? = nil,
        lastOutcome: String? = nil,
        lastSuccessEpoch: TimeInterval? = nil,
        lastConfirmedAckEpoch: TimeInterval? = nil,
        attribution: String? = nil,
        attributionConfidence: String? = nil,
        errorClass: String? = nil,
        staleThresholdSeconds: TimeInterval? = nil,
        overdueThresholdSeconds: TimeInterval? = nil,
        nextAttemptEarliestEpoch: TimeInterval? = nil,
        nextAttemptLatestEpoch: TimeInterval? = nil,
        freshnessEstimates: [FreshnessClass: LocalFreshnessEstimate] = [:],
        queueOccupancy: String? = nil,
        unacknowledgedSecurityEventCount: Int = 0,
        writtenAtEpoch: TimeInterval
    ) {
        self.schemaVersion = 2
        self.destinationID = destinationID
        self.destinationLabel = destinationLabel ?? destinationID
        self.enabled = enabled
        self.state = state ?? Self.inferState(enabled: enabled, lastOutcome: lastOutcome)
        self.lastOutcome = lastOutcome
        self.lastSuccessEpoch = lastSuccessEpoch
        self.lastConfirmedAckEpoch = lastConfirmedAckEpoch
        self.attribution = attribution
        self.attributionConfidence = attributionConfidence
        self.errorClass = errorClass
        self.staleThresholdSeconds = staleThresholdSeconds
        self.overdueThresholdSeconds = overdueThresholdSeconds
        self.nextAttemptEarliestEpoch = nextAttemptEarliestEpoch
        self.nextAttemptLatestEpoch = nextAttemptLatestEpoch
        self.freshnessEstimates = freshnessEstimates
        self.queueOccupancy = queueOccupancy
        self.unacknowledgedSecurityEventCount = max(0, unacknowledgedSecurityEventCount)
        self.writtenAtEpoch = writtenAtEpoch
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case destinationID
        case destinationLabel
        case enabled
        case state
        case lastOutcome
        case lastSuccessEpoch
        case lastConfirmedAckEpoch
        case attribution
        case attributionConfidence
        case errorClass
        case staleThresholdSeconds
        case overdueThresholdSeconds
        case nextAttemptEarliestEpoch
        case nextAttemptLatestEpoch
        case freshnessEstimates
        case queueOccupancy
        case unacknowledgedSecurityEventCount
        case writtenAtEpoch
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        destinationID = try values.decode(String.self, forKey: .destinationID)
        destinationLabel = try values.decodeIfPresent(String.self, forKey: .destinationLabel)
            ?? destinationID
        enabled = try values.decode(Bool.self, forKey: .enabled)
        lastOutcome = try values.decodeIfPresent(String.self, forKey: .lastOutcome)
        state = try values.decodeIfPresent(DestinationDisplayState.self, forKey: .state)
            ?? Self.inferState(enabled: enabled, lastOutcome: lastOutcome)
        lastSuccessEpoch = try values.decodeIfPresent(TimeInterval.self, forKey: .lastSuccessEpoch)
        lastConfirmedAckEpoch = try values.decodeIfPresent(
            TimeInterval.self,
            forKey: .lastConfirmedAckEpoch
        )
        attribution = try values.decodeIfPresent(String.self, forKey: .attribution)
        attributionConfidence = try values.decodeIfPresent(
            String.self,
            forKey: .attributionConfidence
        )
        errorClass = try values.decodeIfPresent(String.self, forKey: .errorClass)
        staleThresholdSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .staleThresholdSeconds)
        overdueThresholdSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .overdueThresholdSeconds)
        nextAttemptEarliestEpoch = try values.decodeIfPresent(TimeInterval.self, forKey: .nextAttemptEarliestEpoch)
        nextAttemptLatestEpoch = try values.decodeIfPresent(TimeInterval.self, forKey: .nextAttemptLatestEpoch)
        freshnessEstimates =
            try values.decodeIfPresent(
                [FreshnessClass: LocalFreshnessEstimate].self,
                forKey: .freshnessEstimates
            ) ?? [:]
        queueOccupancy = try values.decodeIfPresent(String.self, forKey: .queueOccupancy)
        unacknowledgedSecurityEventCount =
            try values.decodeIfPresent(Int.self, forKey: .unacknowledgedSecurityEventCount) ?? 0
        writtenAtEpoch = try values.decode(TimeInterval.self, forKey: .writtenAtEpoch)
    }

    public func state(at epoch: TimeInterval) -> DestinationDisplayState {
        guard enabled, let lastSuccessEpoch else { return state }
        if let overdueThresholdSeconds,
           epoch >= lastSuccessEpoch + overdueThresholdSeconds {
            return .overdue
        }
        if let staleThresholdSeconds,
           epoch >= lastSuccessEpoch + staleThresholdSeconds {
            return .stale
        }
        return state
    }

    private static func inferState(enabled: Bool, lastOutcome: String?) -> DestinationDisplayState {
        guard enabled else { return .paused }
        switch lastOutcome {
        case nil:
            return .noExportsYet
        case "success", "success_nothing_due":
            return .healthy
        case "unknown_ack":
            return .sentUnconfirmed
        case "partial":
            return .partial
        case "failed":
            return .failing
        case "abandoned_no_budget", "cancelled_by_system":
            return .waiting
        default:
            return .waiting
        }
    }
}

public enum DestinationSnapshotFile {
    public static func write(_ snapshot: DestinationStatusSnapshot, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> DestinationStatusSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DestinationStatusSnapshot.self, from: data)
    }

    public static func recordSecurityEvents(
        _ count: Int,
        destinationID: String,
        destinationLabel: String? = nil,
        enabled: Bool? = nil,
        state: DestinationDisplayState? = nil,
        writtenAtEpoch: TimeInterval,
        at url: URL
    ) throws {
        guard count > 0 else { return }
        var snapshot: DestinationStatusSnapshot
        if FileManager.default.fileExists(atPath: url.path) {
            snapshot = try read(from: url)
            snapshot.unacknowledgedSecurityEventCount += count
        } else {
            snapshot = DestinationStatusSnapshot(
                destinationID: destinationID,
                destinationLabel: destinationLabel,
                enabled: true,
                state: .noExportsYet,
                unacknowledgedSecurityEventCount: count,
                writtenAtEpoch: writtenAtEpoch
            )
        }
        if let enabled {
            snapshot.enabled = enabled
        }
        if let state {
            snapshot.state = state
        }
        snapshot.writtenAtEpoch = writtenAtEpoch
        try write(snapshot, to: url)
    }

    public static func acknowledgeSecurityEvents(
        writtenAtEpoch: TimeInterval,
        at url: URL
    ) throws {
        var snapshot = try read(from: url)
        snapshot.unacknowledgedSecurityEventCount = 0
        snapshot.writtenAtEpoch = writtenAtEpoch
        try write(snapshot, to: url)
    }
}

public struct DestinationTimelineEntry: Sendable, Equatable {
    public var dateEpoch: TimeInterval
    public var snapshots: [DestinationStatusSnapshot]

    public init(dateEpoch: TimeInterval, snapshots: [DestinationStatusSnapshot]) {
        self.dateEpoch = dateEpoch
        self.snapshots = snapshots
    }
}

public enum DestinationTimelinePlanner {
    /// Pre-computes the no-further-execution schedule required by R-23.
    public static func entries(
        snapshots: [DestinationStatusSnapshot],
        nowEpoch: TimeInterval
    ) -> [DestinationTimelineEntry] {
        var dates: Set<TimeInterval> = [nowEpoch]
        for snapshot in snapshots {
            guard let lastSuccess = snapshot.lastSuccessEpoch else { continue }
            if let stale = snapshot.staleThresholdSeconds {
                let staleAt = lastSuccess + stale
                if staleAt > nowEpoch {
                    dates.insert(staleAt)
                }
            }
            if let overdue = snapshot.overdueThresholdSeconds {
                let overdueAt = lastSuccess + overdue
                for date in [overdueAt, overdueAt + 24 * 60 * 60, overdueAt + 48 * 60 * 60]
                    where date > nowEpoch {
                    dates.insert(date)
                }
            }
        }
        return dates.sorted().map {
            DestinationTimelineEntry(dateEpoch: $0, snapshots: snapshots)
        }
    }
}
