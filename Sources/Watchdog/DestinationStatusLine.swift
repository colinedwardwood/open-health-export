// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// QA-14: what a destination's durable state looks like to the person reading it.
///
/// Two things have to be true for this to be worth anything. Staleness has to be
/// computed against the time of reading, because a destination that succeeded once and
/// then stopped keeps its stored state of `healthy` forever. And a failure has to name
/// its reason, because "failing" alone is not something anyone can act on or report.
public enum DestinationStatusLine {
    public static let emptyCopy = "No destination snapshots yet."

    public static func render(
        _ snapshot: DestinationStatusSnapshot,
        nowEpoch: TimeInterval,
        lastSuccess: (TimeInterval) -> String
    ) -> String {
        let state = snapshot.state(at: nowEpoch)
        let last = snapshot.lastSuccessEpoch.map(lastSuccess) ?? "never"
        var line = "\(snapshot.destinationLabel): \(state.rawValue) · last success \(last)"
        if let reason = reasonCode(snapshot) {
            line += " · \(reason)"
            if let phrase = ErrorClassManifest.userFacingReason(forRaw: snapshot.errorClass),
               phrase != reason {
                line += " · \(phrase)"
            }
        }
        let changes = snapshot.unacknowledgedSecurityEventCount
        if changes > 0 {
            line += " · \(changes) unacknowledged change(s)"
        }
        return line
    }

    /// The reason belongs on screen whenever the last run did not succeed. `none` is
    /// what a successful run records, and repeating it would be noise.
    static func reasonCode(_ snapshot: DestinationStatusSnapshot) -> String? {
        guard let errorClass = snapshot.errorClass,
              errorClass != ErrorClass.none.rawValue,
              !errorClass.isEmpty
        else {
            return nil
        }
        return errorClass
    }
}
