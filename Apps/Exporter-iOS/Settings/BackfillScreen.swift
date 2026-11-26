// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CorrectnessEngine
import SwiftUI

/// Send earlier Health history to the enabled destinations: choose how far back, start,
/// watch, cancel. The scopes each destination was granted still bound what is sent.
struct BackfillScreen: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage(SettingKey.backfillMode.rawValue) private var modeRaw = BackfillMode.aggregateOnly.rawValue
    @State private var range: BackfillRange = .days30
    @State private var model = BackfillModel()

    private var mode: BackfillMode { BackfillMode(rawValue: modeRaw) ?? .aggregateOnly }

    var body: some View {
        List {
            Section {
                ForEach(BackfillRange.allCases, id: \.self) { option in
                    ChoiceRow(title: Self.title(option), selected: range == option) { range = option }
                        .accessibilityIdentifier("backfill-range-\(option.rawValue)")
                }
            } header: {
                SectionTitle("How far back")
            }
            .disabled(model.isRunning)

            Section {
                ChoiceRow(title: "Daily summaries", selected: mode == .aggregateOnly) {
                    modeRaw = BackfillMode.aggregateOnly.rawValue
                }
                .accessibilityIdentifier("backfill-mode-summaries")
                ChoiceRow(title: "Every sample", selected: mode == .raw) {
                    modeRaw = BackfillMode.raw.rawValue
                }
                .accessibilityIdentifier("backfill-mode-raw")
            } header: {
                SectionTitle("What to send")
            }
            .disabled(model.isRunning)
            .disabled(model.isRunning)

            Section {
                // In a stack, as Export now is: a prominent button as a bare list row
                // doesn't scale with Dynamic Type.
                VStack(alignment: .leading, spacing: 12) {
                    // Body text rather than a section footer: UIKit footers don't scale
                    // with Dynamic Type under the audit.
                    Text("Sends only the types and dates each destination is set up to receive. Stopping keeps your place, and choosing the same range again carries on.")
                        .metadata()
                    progressAndResult
                    actionButton
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Earlier history")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private var progressAndResult: some View {
        switch model.phase {
        case let .running(progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView {
                    Text("Sending history…")
                }
                if !progress.isEmpty {
                    Text(verbatim: progress).metadata()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("backfill-progress")
        case let .finished(report):
            Text(Self.summary(report))
                .accessibilityIdentifier("backfill-result")
        case .cancelled:
            Text("Stopped. Your place is saved; start again with the same range to carry on.")
                .accessibilityIdentifier("backfill-result")
        case .idle:
            EmptyView()
        }
        if let error = model.error {
            ErrorCard(error: error, identifier: "backfill-error")
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if model.isRunning {
            Button(role: .cancel) { model.cancel() } label: {
                Text("Stop").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier("backfill-cancel")
        } else {
            Button {
                model.start(range: range, mode: mode) { appModel.refreshStatus() }
            } label: {
                Text("Send history").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("backfill-start")
        }
    }

    private static func title(_ range: BackfillRange) -> LocalizedStringKey {
        switch range {
        case .days7: "Last 7 days"
        case .days30: "Last 30 days"
        case .days90: "Last 90 days"
        case .all: "Everything available"
        }
    }

    private static func summary(_ report: BackfillReport) -> String {
        switch report {
        case let .completed(samples, batches):
            String(
                format: String(localized: "History sent. Samples read: %lld. Batches: %lld."),
                samples,
                batches
            )
        case let .parked(reason):
            String(
                format: String(localized: "Paused: %@ Your place is saved."),
                localized(reason)
            )
        case let .nothingToDo(line), let .blocked(line):
            localized(line)
        }
    }
}

/// One option in a list of exclusive choices. A button row rather than a Picker, so the
/// text is an ordinary label that scales with Dynamic Type.
private struct ChoiceRow: View {
    let title: LocalizedStringKey
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Color.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
