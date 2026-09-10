import Foundation

/// R-40 in-app rung: visible while unacknowledged destination changes exist.
/// There is no dismiss control; acknowledgement is the only clear path.
public enum DestinationChangeBanner {
    public static let title = "Unacknowledged destination change"

    public static func isVisible(_ snapshots: [DestinationStatusSnapshot]) -> Bool {
        snapshots.contains { $0.unacknowledgedSecurityEventCount > 0 }
    }

    public static func detail(_ snapshots: [DestinationStatusSnapshot]) -> String {
        let labels = snapshots
            .filter { $0.unacknowledgedSecurityEventCount > 0 }
            .map(\.destinationLabel)
        let joined = labels.joined(separator: ", ")
        return "\(joined) changed. This banner stays until you acknowledge it under Where your data goes."
    }
}
