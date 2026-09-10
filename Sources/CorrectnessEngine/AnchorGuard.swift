import EnginePorts
import Foundation

/// QA-17. An anchor that cannot be trusted must not quietly become "read everything".
///
/// Two situations are indistinguishable from a first run if nobody looks: a cursor row
/// that has gone missing, and a delta that comes back carrying the whole store. Both
/// would re-export years of history — duplicated downstream, paid for in battery, and
/// in some cases in the user's API quota. So both stop the metric and wait for a person.
public enum AnchorGuard {
    /// A delta page larger than this is not a delta. The bound is deliberately far above
    /// any plausible increment: it exists to catch a reset anchor, not a busy day.
    public static let implausibleDeltaSamples = 50_000

    /// There is no cursor. Whether that is a first run or a lost anchor is decided by
    /// whether this metric has ever emitted anything.
    public static func cursorIsLost(hasCursor: Bool, lastEmittedDay: String?) -> Bool {
        !hasCursor && lastEmittedDay != nil
    }

    /// A run that resumed from an anchor should return an increment, not a store.
    public static func replayIsSuspected(
        resumedFromAnchor: Bool,
        sampleCount: Int,
        limit: Int = implausibleDeltaSamples
    ) -> Bool {
        resumedFromAnchor && sampleCount > limit
    }

    /// Journal detail written when a hold is placed, and the string the UI keys on.
    public static let journalDetail = "anchor_invalidated"
    /// Journal detail written when a run is refused because a hold is already open.
    public static let heldJournalDetail = "anchor_hold"
}
