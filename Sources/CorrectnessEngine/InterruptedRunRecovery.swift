// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation

/// UX-26: a killed export cannot write its own outcome. Next launch seals every
/// leftover `open_runs` row as `cancelledBySystem` with the partial extent it had.
public enum InterruptedRunRecovery {
    public static func seal(
        store: any StateStore,
        nowEpoch: TimeInterval
    ) async throws -> [OpenRun] {
        try await store.transact { tx in
            let open = try tx.loadOpenRuns()
            for run in open {
                let durationMillis = max(0, Int(((nowEpoch - run.startedAtEpoch) * 1000).rounded()))
                try tx.appendJournal(
                    RunEvent(
                        runID: RunID(rawValue: "run-\(run.metric.rawValue)"),
                        outcomeKind: RunOutcome.Kind.cancelledBySystem.rawValue,
                        detail: "os_termination",
                        trigger: run.trigger,
                        samplesRead: run.samplesRead,
                        samplesCommitted: run.samplesCommitted,
                        samplesAcked: run.samplesAcked,
                        wallTimeEpoch: nowEpoch,
                        errorClass: ErrorClass.cancelledBySystem.rawValue,
                        facts: RunHistoryFacts(
                            destinationID: run.destinationID,
                            metric: run.metric.rawValue,
                            durationMillis: durationMillis,
                            redactedPayload: RunHistoryDetail.redactedPayload(
                                metric: run.metric.rawValue,
                                records: run.samplesCommitted,
                                byteCount: 0,
                                windowStartDay: nil,
                                windowEndDay: nil
                            )
                        )
                    )
                )
                try tx.closeOpenRun(destinationID: run.destinationID, metric: run.metric)
            }
            return open
        }
    }
}
