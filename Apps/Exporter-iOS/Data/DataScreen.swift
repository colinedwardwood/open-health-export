// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

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
    @State private var saveError: UserFacingErrorObject?

    private var destinations: [String] {
        _ = model.statusGeneration
        return DestinationRepository.healthDestinationIDs.filter { services.destinations.isEnabled($0) }
    }

    private func current(_ ids: [String]) -> String { destinationID ?? ids[0] }

    private var changed: Bool { selected != baseline || start != baselineStart }

    var body: some View {
        let ids = destinations
        Group {
            if ids.isEmpty {
                EmptyState(
                    symbol: "chart.bar",
                    title: "No destinations yet",
                    message: "Add a destination first. Then choose which types it receives here."
                )
                .accessibilityIdentifier("data-empty")
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
            if let saveError {
                Section {
                    ErrorCard(error: saveError, identifier: "data-save-error")
                }
            }
            if changed {
                Section {
                    Button {
                        Task { await save(current(ids)) }
                    } label: {
                        Text("Save changes").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.vertical, 4)
                    .disabled(saving || selected.isEmpty)
                    .accessibilityIdentifier("data-save")
                } footer: {
                    SectionFooter(selected.isEmpty ? "Choose at least one type." : "Nothing changes until you save.")
                }
            }
            Section {
                if ids.count > 1 {
                    Picker("Destination", selection: Binding(
                        get: { current(ids) },
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
            Text("This is sensitive health data. It will be sent to \(DestinationRepository.label(current(ids))) along with your other types.")
        }
    }

    private func toggle(_ row: DataTypeRow, on: Bool) {
        if on { selected.insert(row.id) } else { selected.remove(row.id) }
    }

    private func load(_ id: String?) async {
        guard let id, let scope = try? await services.destinations.scope(id) else { return }
        destinationID = id
        saveError = nil
        selected = scope.metrics
        baseline = scope.metrics
        start = scope.startInclusive ?? OnboardingPlan.defaultScopeStart(now: Date(), calendar: .current)
        baselineStart = start
    }

    /// Saves the types and start date, asks Apple Health for any new types, and
    /// re-registers the background observers for the new set.
    private func save(_ id: String) async {
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            #if DEBUG
            if UITestFixtures.failsDataSave { throw UITestFixtures.InjectedFailure() }
            #endif
            let scope = try DestinationExportScope(destinationID: id, metrics: selected, startInclusive: start)
            try await services.destinations.applyScope(scope, previousMetrics: baseline)
            try? await services.health.requestReadAccess(for: scope)
            AppLifecycleCoordinator.shared.stopObservers()
            await AppLifecycleCoordinator.shared.startObserversIfEligible()
            baseline = selected
            baselineStart = start
            model.refreshStatus()
        } catch {
            // The scope is unchanged; Save stays on offer, and the person is told why.
            saveError = UserFacingFailure.object(for: error, destinationLabel: DestinationRepository.label(id))
        }
    }
}

private struct TypeToggle: View {
    let row: DataTypeRow
    let set: @MainActor (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { row.selected }, set: { set($0) })) {
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
