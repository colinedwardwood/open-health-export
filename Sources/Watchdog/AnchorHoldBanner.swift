import EnginePorts
import Foundation

/// QA-17 in-app rung. A held metric has stopped exporting and will stay stopped, so the
/// banner says so plainly and stays put until the hold is decided. There is no dismiss:
/// dismissing would leave a type silently not exporting, which is the failure this
/// requirement exists to prevent.
public enum AnchorHoldBanner {
    public static let title = "Export paused for some data"

    public static func isVisible(_ holds: [AnchorHold]) -> Bool {
        !holds.isEmpty
    }

    public static func detail(_ holds: [AnchorHold]) -> String {
        let names = holds.map(\.metric.rawValue).sorted().joined(separator: ", ")
        return "\(names) stopped because the export lost its place. "
            + "Nothing is being sent for it until you choose what to do under Data gaps."
    }

    /// Says what happened and what each choice costs, in the order the user needs it.
    public static func explanation(_ hold: AnchorHold) -> String {
        let sent = hold.lastEmittedDay.map { "Data through \($0) has already been sent." }
            ?? "Nothing has been sent yet for this data."
        switch hold.reason {
        case .cursorLost:
            return "The export lost track of how far it had got in \(hold.metric.rawValue). "
                + "\(sent) It can start again from the beginning, which sends that history "
                + "a second time, or you can stop exporting this data."
        case .replaySuspected:
            return "\(hold.metric.rawValue) returned \(hold.observedSamples) records in one "
                + "update, which is far more than an update should contain. \(sent) "
                + "Sending it would repeat history already at your server. You can allow it "
                + "anyway, or stop exporting this data."
        }
    }

    public static let reexportChoice = "Send it all again"
    public static let stopChoice = "Stop exporting this data"
}
