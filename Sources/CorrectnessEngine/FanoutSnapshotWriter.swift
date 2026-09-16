// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import Watchdog

/// Writes each sink's own status after a fan-out, rather than the combined
/// run outcome onto the primary snapshot.
enum FanoutSnapshotWriter {
    static func write(
        destinations: [RunDestination],
        destinationName: String,
        fallbackURL: URL?,
        children: [DestinationRunRow],
        outcome: RunOutcome,
        combinedErrorClass: String?,
        now: TimeInterval,
        trigger: RunTrigger,
        freshnessCadenceSeconds: TimeInterval,
        freshnessEstimates: [FreshnessClass: LocalFreshnessEstimate],
        queueOccupancy: String
    ) throws {
        let targets: [(id: String, url: URL, kind: RunOutcome.Kind, errorClass: String?, ack: RunOutcome.AckEvidence)]
        if destinations.count > 1, !children.isEmpty {
            targets = destinations.compactMap { dest in
                let url = dest.snapshotURL
                    ?? (dest.id == destinationName ? fallbackURL : nil)
                guard let url,
                      let kind = DestinationRunRow.kind(for: dest.id, in: children)
                else { return nil }
                let row = children.first { $0.destinationID == dest.id }
                let ack: RunOutcome.AckEvidence =
                    kind == .success || kind == .successNothingDue
                    ? outcome.ackEvidence
                    : .none
                return (dest.id, url, kind, row?.errorClass, ack)
            }
        } else if let fallbackURL {
            targets = [(
                destinationName,
                fallbackURL,
                outcome.kind,
                combinedErrorClass,
                outcome.ackEvidence
            )]
        } else {
            targets = []
        }
        for target in targets {
            let prior = try? DestinationSnapshotFile.read(from: target.url)
            let succeeded = target.kind == .success || target.kind == .successNothingDue
            let estimates = freshnessEstimates.isEmpty
                ? (prior?.freshnessEstimates ?? [:])
                : freshnessEstimates
            let thresholds = FreshnessTarget.snapshotThresholds(
                estimates: estimates,
                cadenceSeconds: freshnessCadenceSeconds
            )
            try DestinationSnapshotFile.write(
                DestinationStatusSnapshot(
                    destinationID: target.id,
                    destinationLabel: prior?.destinationLabel ?? target.id,
                    enabled: true,
                    exportRole: prior?.exportRole ?? .designated,
                    lastOutcome: target.kind.rawValue,
                    lastSuccessEpoch: succeeded ? now : prior?.lastSuccessEpoch,
                    lastConfirmedAckEpoch:
                        target.ack == .receiptFull ? now : prior?.lastConfirmedAckEpoch,
                    attribution: ExternalStatusRecord.attribution(for: trigger),
                    attributionConfidence: "evidenced",
                    errorClass: target.errorClass,
                    staleThresholdSeconds: thresholds.stale,
                    overdueThresholdSeconds: thresholds.overdue,
                    nextAttemptEarliestEpoch: prior?.nextAttemptEarliestEpoch,
                    nextAttemptLatestEpoch: prior?.nextAttemptLatestEpoch,
                    freshnessEstimates: estimates,
                    queueOccupancy: queueOccupancy,
                    unacknowledgedSecurityEventCount:
                        prior?.unacknowledgedSecurityEventCount ?? 0,
                    writtenAtEpoch: now
                ),
                to: target.url
            )
        }
    }
}
