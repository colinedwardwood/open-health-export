import SwiftUI
import Watchdog
import WidgetKit

struct ExportStatusEntry: TimelineEntry {
    var date: Date
    var snapshots: [DestinationStatusSnapshot]
}

struct ExportStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> ExportStatusEntry {
        ExportStatusEntry(
            date: Date(timeIntervalSince1970: 0),
            snapshots: [
                DestinationStatusSnapshot(
                    destinationID: "preview",
                    destinationLabel: "Destinations",
                    enabled: true,
                    state: .healthy,
                    lastOutcome: "success",
                    lastSuccessEpoch: 0,
                    writtenAtEpoch: 0
                ),
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ExportStatusEntry) -> Void) {
        let now = Date()
        completion(ExportStatusEntry(date: now, snapshots: StatusSnapshotLocation.readAll()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ExportStatusEntry>) -> Void) {
        let now = Date()
        let snapshots = StatusSnapshotLocation.readAll()
        let plan = DestinationTimelinePlanner.entries(
            snapshots: snapshots,
            nowEpoch: now.timeIntervalSince1970
        )
        let entries = plan.map {
            ExportStatusEntry(
                date: Date(timeIntervalSince1970: $0.dateEpoch),
                snapshots: $0.snapshots
            )
        }
        completion(Timeline(entries: entries, policy: entries.count > 1 ? .atEnd : .never))
    }
}

struct ExportStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ExportStatusEntry

    var body: some View {
        Group {
            if entry.snapshots.isEmpty {
                empty
            } else if family == .accessoryCircular {
                accessoryCircular
            } else if family == .accessoryRectangular {
                accessoryRectangular
            } else if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(statusURL)
    }

    private var small: some View {
        let worst = worstSnapshot
        let state = worst?.state(at: entry.date.timeIntervalSince1970) ?? .notSetUp
        return VStack(alignment: .leading, spacing: 8) {
            Label(state.label, systemImage: state.glyph)
                .font(.headline)
            Spacer()
            if let success = worst?.lastSuccessEpoch {
                Text("Last export")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Date(timeIntervalSince1970: success), style: .relative)
                    .font(.title3)
                    .bold()
            } else {
                Text("No exports yet")
                    .font(.title3)
                    .bold()
            }
            Spacer()
            if securityEventCount > 0 {
                Label("\(securityEventCount) change", systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
            } else {
                Text(destinationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let worst = worstSnapshot {
                let state = worst.state(at: entry.date.timeIntervalSince1970)
                Label(state.label, systemImage: state.glyph)
                    .font(.headline)
            }
            ForEach(Array(entry.snapshots.prefix(3)), id: \.destinationID) { snapshot in
                HStack {
                    let state = snapshot.state(at: entry.date.timeIntervalSince1970)
                    Image(systemName: state.glyph)
                        .accessibilityHidden(true)
                    Text(snapshot.destinationLabel)
                        .lineLimit(1)
                    Spacer()
                    if let success = snapshot.lastSuccessEpoch {
                        Text(Date(timeIntervalSince1970: success), style: .relative)
                    } else {
                        Text(state.label)
                    }
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
            if let nextAttempt = nextAttemptText {
                Text(nextAttempt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if securityEventCount > 0 {
                Label(
                    "\(securityEventCount) unacknowledged destination change",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.caption2)
            }
        }
    }

    private var accessoryRectangular: some View {
        let worst = worstSnapshot
        let state = worst?.state(at: entry.date.timeIntervalSince1970) ?? .notSetUp
        return HStack(spacing: 8) {
            Image(systemName: securityEventCount > 0 ? "exclamationmark.shield.fill" : state.glyph)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(securityEventCount > 0 ? "Destination changed" : state.label)
                    .font(.headline)
                if let success = worst?.lastSuccessEpoch {
                    HStack(spacing: 3) {
                        Text("Last export")
                        Text(Date(timeIntervalSince1970: success), style: .relative)
                    }
                    .font(.caption)
                } else {
                    Text("No exports yet")
                        .font(.caption)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var accessoryCircular: some View {
        let state = worstSnapshot?.state(at: entry.date.timeIntervalSince1970) ?? .notSetUp
        return VStack(spacing: 2) {
            Image(systemName: securityEventCount > 0 ? "exclamationmark.shield.fill" : state.glyph)
                .font(.title2)
            Text(securityEventCount > 0 ? "Changed" : state.label)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Not set up", systemImage: DestinationDisplayState.notSetUp.glyph)
                .font(.headline)
            Spacer()
            Text("Nothing set up yet")
                .font(.title3)
                .bold()
            Text("Tap to start")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("widget-empty")
    }

    private var worstSnapshot: DestinationStatusSnapshot? {
        entry.snapshots.max {
            $0.state(at: entry.date.timeIntervalSince1970).severity
                < $1.state(at: entry.date.timeIntervalSince1970).severity
        }
    }

    private var destinationSummary: String {
        entry.snapshots.count == 1
            ? (entry.snapshots.first?.destinationLabel ?? "Destination")
            : "\(entry.snapshots.count) destinations"
    }

    private var securityEventCount: Int {
        entry.snapshots.reduce(0) { $0 + $1.unacknowledgedSecurityEventCount }
    }

    private var nextAttemptText: String? {
        guard let next = entry.snapshots.compactMap(\.nextAttemptEarliestEpoch).min() else {
            return nil
        }
        return "Next attempt \(Date(timeIntervalSince1970: next).formatted(date: .omitted, time: .shortened))"
    }

    private var statusURL: URL? {
        WidgetStatusRoute(destinationID: worstSnapshot?.destinationID).url
    }
}

private extension DestinationDisplayState {
    var glyph: String {
        switch self {
        case .notSetUp: "circle.dashed"
        case .noExportsYet: "circle.dotted"
        case .manualOnly: "hand.tap"
        case .healthy: "checkmark.circle.fill"
        case .quiet: "clock"
        case .sentUnconfirmed: "paperplane.circle"
        case .partial: "circle.lefthalf.filled"
        case .stale: "clock.badge.exclamationmark"
        case .failing: "exclamationmark.triangle.fill"
        case .blocked: "exclamationmark.octagon.fill"
        case .waiting: "pause.circle.fill"
        case .limitedByIOS: "bolt.slash.fill"
        case .paused: "pause.fill"
        case .overdue: "clock.badge.exclamationmark.fill"
        }
    }

    var label: String {
        switch self {
        case .notSetUp: "Not set up"
        case .noExportsYet: "No exports yet"
        case .manualOnly: "Manual only"
        case .healthy: "Up to date"
        case .quiet: "Quiet"
        case .sentUnconfirmed: "Sent, unconfirmed"
        case .partial: "Partly delivered"
        case .stale: "Stale"
        case .failing: "Failing"
        case .blocked: "Waiting for you"
        case .waiting: "Waiting"
        case .limitedByIOS: "Limited by iOS"
        case .paused: "Paused"
        case .overdue: "Overdue"
        }
    }

    var severity: Int {
        switch self {
        case .healthy, .manualOnly, .paused: 0
        case .notSetUp, .noExportsYet, .waiting: 1
        case .quiet, .sentUnconfirmed: 2
        case .partial, .limitedByIOS, .stale: 3
        case .failing, .blocked, .overdue: 4
        }
    }
}

struct ExportStatusWidget: Widget {
    let kind = "ExportStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ExportStatusProvider()) { entry in
            ExportStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Export status")
        .description("Shows destination status and time since the last export. Never shows health values.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}
