// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// OBS-02: the journal answers "why did it fail three days ago", and 90 days covers a
/// fault that only shows up intermittently. Both bounds are stated because either one
/// alone fails: a run count alone loses months of history for a heavy user, and an age
/// alone lets a pathological retry loop grow the store without limit.
///
/// The tighter of the two wins, which is the "whichever is reached first" in the
/// requirement. Pruning is not conditional on OTLP having projected a row — a bounded
/// footprint is a Must and the projection is best-effort, so an unread projection is
/// allowed to lose old rows rather than the store being allowed to grow.
public enum JournalRetention {
    public static let days = 90
    public static let runs = 1_000

    public static var seconds: TimeInterval {
        TimeInterval(days) * 24 * 60 * 60
    }

    /// Oldest wall-clock epoch a run may have and still be retained.
    public static func cutoffEpoch(now: TimeInterval) -> TimeInterval {
        now - seconds
    }
}
