// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import MetricCatalog
import SwiftUI

/// #50: which types each destination receives, and from when. Everyday types are a
/// searchable list with Core Daily one tap away; sensitive and re-identifying types
/// sit apart and are turned on one at a time, each with its own confirmation (R-66).
struct DataScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services
    @State private var destinationID: String?
    @State private var selected: Set<MetricID> = []
    @State private var baseline: Set<MetricID> = []
    @State private var start = Date()
    @State private var baselineStart = Date()
    @State private var search = ""
    @State private var confirming: DataTypeRow?
    @State private var saving = false

    private var destinations: [String] {
        _ = model.statusGeneration
        return DestinationRepository.healthDestinationIDs.filter { services.destinations.isEnabled($0) }
    }

    private var changed: Bool { selected != baseline || start != baselineStart }

    var body: some View {
        let ids = destinations
        Group {
            if ids.isEmpty {
                ContentUnavailableView {
                    Label("No destinations yet", systemImage: "chart.bar")
                } description: {
                    Text("Add a destination first. Then choose which types it receives here.")
                }
            } else {
                list(ids)
            }
        }
        .navigationTitle("Data")
        .task(id: destinationID ?? ids.first) { await load(destinationID ?? ids.first) }
    }

    private func list(_ ids: [String]) -> some View {
        let rows = DataSelection.rows(selected: selected, search: search)
        return List {
            if changed {
                Section {
                    VStack {
                        Button {
                            Task { await save(destinationID ?? ids[0]) }
                        } label: {
                            Text("Save changes").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(saving || selected.isEmpty)
                        .accessibilityIdentifier("data-save")
                    }
                    .padding(.vertical, 4)
                } footer: {
                    SectionFooter(selected.isEmpty ? "Choose at least one type." : "Nothing changes until you save.")
                }
            }
            Section {
                if ids.count > 1 {
                    Picker("Destination", selection: Binding(
                        get: { destinationID ?? ids[0] },
                        set: { destinationID = $0 }
                    )) {
                        ForEach(ids, id: \.self) { Text(DestinationRepository.label($0)).tag($0) }
                    }
                    .accessibilityIdentifier("data-destination")
                }
                DatePicker("Export data from", selection: $start, in: ...Date(), displayedComponents: .date)
                    .accessibilityIdentifier("data-start")
                Button("Use Core Daily") {
                    selected = DataSelection.applyingCoreDaily(to: selected)
                }
                .accessibilityIdentifier("data-core-daily")
            } footer: {
                SectionFooter("Core Daily is the everyday set most people start with. It never includes sensitive types.")
            }
            Section {
                ForEach(rows.everyday) { row in
                    TypeToggle(row: row) { on in toggle(row, on: on) }
                }
            } header: {
                SectionTitle("Everyday")
            }
            if !rows.ownOptIn.isEmpty {
                Section {
                    ForEach(rows.ownOptIn) { row in
                        TypeToggle(row: row) { on in
                            if on { confirming = row } else { toggle(row, on: false) }
                        }
                    }
                } header: {
                    SectionTitle("Sensitive")
                } footer: {
                    SectionFooter("These can identify you or describe sensitive health. Each one is turned on separately.")
                }
            }
        }
        .searchable(text: $search, prompt: "Search types")
        .alert(
            "Export \(confirming?.name ?? "")?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { row in
            Button("Export it") { toggle(row, on: true) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This is sensitive health data. It will be sent to \(DestinationRepository.label(destinationID ?? ids[0])) along with your other types.")
        }
    }

    private func toggle(_ row: DataTypeRow, on: Bool) {
        if on { selected.insert(row.id) } else { selected.remove(row.id) }
    }

    private func load(_ id: String?) async {
        guard let id, let scope = try? await services.destinations.scope(id) else { return }
        destinationID = id
        selected = scope.metrics
        baseline = scope.metrics
        start = scope.startInclusive ?? OnboardingPlan.defaultScopeStart(now: Date(), calendar: .current)
        baselineStart = start
    }

    /// Saves the types and start date, asks Apple Health for any new types, and
    /// re-registers the background observers for the new set.
    private func save(_ id: String) async {
        saving = true
        defer { saving = false }
        do {
            let scope = try DestinationExportScope(destinationID: id, metrics: selected, startInclusive: start)
            try await services.destinations.applyScope(scope, previousMetrics: baseline)
            try? await services.health.requestReadAccess(for: scope)
            AppLifecycleCoordinator.shared.stopObservers()
            try? await AppLifecycleCoordinator.shared.startObserversIfEligible()
            baseline = selected
            baselineStart = start
            model.refreshStatus()
        } catch {
            // The scope is unchanged; the toolbar keeps offering Save.
        }
    }
}

private struct TypeToggle: View {
    let row: DataTypeRow
    let set: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { row.selected }, set: set)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                if let unit = row.unit {
                    Text(unit).metadata()
                }
            }
        }
        .accessibilityIdentifier("data-type-\(row.id.rawValue)")
    }
}
