// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import SwiftUI
import Watchdog

/// #46: "is it working?" at a glance. A plain sentence first, one action when
/// something needs the person, every destination with the widget's glyph and words,
/// and Export now. Mockup: design canvas boards 4 and 5.
struct StatusScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services

    var body: some View {
        // Relative times ("12 minutes ago") stay true while the screen is open.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
        .navigationTitle("Status")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("shell-settings")
            }
        }
        .refreshable { model.refreshStatus() }
    }

    private func content(now: Date) -> some View {
        // Read so a refresh, a finished export or a foreground re-renders this.
        _ = model.statusGeneration
        let snapshots = services.status.destinationSnapshots()
        let relative = Self.relative(now: now)
        let rows = StatusDashboard.rows(snapshots, nowEpoch: now.timeIntervalSince1970, relative: relative)
        // No destination yet reads "No destinations yet." with the setup action.
        let summary = StatusDashboard.summary(
            rows,
            lastSuccessEpoch: snapshots.compactMap(\.lastSuccessEpoch).max(),
            relative: relative
        )
        // #62/#63: what stops or delays background exports, shown even when every
        // destination looks fine.
        let notices = model.statusNotices
        return List {
            Section {
                SummaryHeader(summary: summary)
            }
            if !notices.isEmpty {
                Section {
                    ForEach(notices) { notice in
                        StatusNoticeRow(notice: notice)
                    }
                }
            }
            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        NavigationLink(value: AppRoute.destination(id: row.id)) {
                            DestinationRow(row: row)
                        }
                        .accessibilityIdentifier("status-row-\(row.id)")
                    }
                } header: {
                    SectionTitle("Destinations")
                }
            }
            if let owed = ScopeWidening.statusCopy(AppDestinations.repository.pendingBackfills()) {
                Section {
                    Text(copy: owed)
                        .accessibilityIdentifier("status-backfill-owed")
                    NavigationLink(value: AppRoute.settings) {
                        Text("Settings")
                    }
                }
            }
            Section {
                ExportNowControl()
            }
        }
    }

    private static func relative(now: Date) -> (TimeInterval) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return { epoch in
            formatter.localizedString(for: Date(timeIntervalSince1970: epoch), relativeTo: now)
        }
    }
}

private struct SummaryHeader: View {
    @Environment(AppModel.self) private var model
    let summary: StatusSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy: summary.headline)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("status-headline")
            Text(copy: summary.detail)
                .foregroundStyle(.secondaryText)
                .accessibilityIdentifier("status-detail")
            switch summary.action {
            case let .check(destinationID, label):
                NavigationLink(value: AppRoute.destination(id: destinationID)) {
                    Text("Check \(label)")
                }
                .buttonStyle(.bordered)
                .tint(summary.tone.color)
                .accessibilityIdentifier("status-check")
            case .setUp:
                Button("Choose where exports go") { model.resumeSetup() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("status-finish-setup")
            case nil:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatusNoticeRow: View {
    let notice: StatusNotice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(notice.tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(copy: notice.title)
                Text(copy: notice.detail).metadata()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status-notice-\(notice.id)")
    }
}

private struct DestinationRow: View {
    let row: StatusDestinationRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: row.glyph)
                .foregroundStyle(row.tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                Text("\(localized(row.stateLabel)) · \(row.detail.resolved)")
                    .metadata()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ExportNowControl: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.exporting {
                ProgressView(value: model.exportProgress) {
                    Text("Exporting…")
                }
                .accessibilityIdentifier("status-export-progress")
            }
            Button {
                // Never a greyed-out primary button: with nowhere to export to, the
                // same tap starts setup.
                if model.needsSetup {
                    model.resumeSetup()
                } else {
                    Task { await model.exportNow() }
                }
            } label: {
                // Text only: an icon-and-title Label inside a prominent button clips at
                // the larger accessibility sizes (contrast and Dynamic Type audit, #46).
                Text("Export now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.exporting)
            .accessibilityIdentifier("status-export-now")
            if !PurchaseStore.shared.state.isUnlocked {
                NavigationLink(value: AppRoute.settings) {
                    Text("Exports run when you tap Export now. Unlock automatic exports in Settings.")
                        .metadata()
                }
                .accessibilityIdentifier("status-unlock-note")
            }
            if let error = model.lastExportError {
                ErrorCard(error: error, identifier: "status-export-error")
            } else if let message = model.lastExportMessage, !model.exporting {
                Text(message)
                    .metadata()
                    .accessibilityIdentifier("status-export-result")
            }
        }
        .padding(.vertical, 4)
    }
}

/// The five-part error, compact: what happened, why, and what to do.
struct ErrorCard: View {
    let error: UserFacingErrorObject
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(copy: error.title).font(.headline)
            } icon: {
                DestinationDisplayState.failing.toneGlyph
            }
            Text(copy: error.cause)
            Text(copy: error.fix).foregroundStyle(.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
