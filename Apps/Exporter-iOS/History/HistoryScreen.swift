// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import EnginePorts
import SwiftUI
import Watchdog

/// #51: every run, problems first. Mockup: design canvas board 7.
struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services
    @State private var events: [RunEvent] = []
    @State private var filter = HistoryPresentation.Filter.problems
    @State private var destinationID: String?
    @State private var loaded = false

    var body: some View {
        let rows = HistoryPresentation.rows(events, filter: filter, destinationID: destinationID)
        List {
            Section {
                Picker("Show", selection: $filter) {
                    Text("Problems").tag(HistoryPresentation.Filter.problems)
                    Text("All").tag(HistoryPresentation.Filter.all)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("history-filter")
            }
            if loaded, rows.isEmpty {
                Section {
                    Text(HistoryPresentation.emptyCopy(events, filter: filter))
                        .accessibilityIdentifier("history-empty")
                    if filter == .problems, !events.isEmpty {
                        Button("Show all runs") { filter = .all }
                    }
                }
            }
            Section {
                ForEach(rows) { row in
                    NavigationLink {
                        RunDetailScreen(row: row)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: row.state.glyph)
                                .foregroundStyle(row.state.tone.color)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text([row.destination, row.typeName].compactMap { $0 }.joined(separator: " · "))
                                Text("\(Date(timeIntervalSince1970: row.epoch).formatted(date: .abbreviated, time: .shortened)) · \(row.result)")
                                    .metadata()
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .accessibilityIdentifier("history-row")
                }
            } footer: {
                if !rows.isEmpty { SectionFooter(LocalizedStringKey(RunHistoryDetail.retentionCopy)) }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Destination", selection: $destinationID) {
                        Text("All destinations").tag(String?.none)
                        ForEach(DestinationRepository.healthDestinationIDs, id: \.self) { id in
                            Text(DestinationRepository.label(id)).tag(String?.some(id))
                        }
                    }
                } label: {
                    Label("Destination", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("history-destination")
            }
        }
        .task(id: model.statusGeneration) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        events = (try? await services.history.historyEvents()) ?? []
        loaded = true
    }
}

/// One run: everything the journal knows about it, in words and formatted numbers.
struct RunDetailScreen: View {
    let row: HistoryRow

    var body: some View {
        let event = row.event
        let facts = event.facts
        List {
            Section {
                // A stack, not a Label: a Label's title truncates in a list row at the
                // larger text sizes.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: row.state.glyph)
                        .foregroundStyle(row.state.tone.color)
                        .accessibilityHidden(true)
                    Text(row.result)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("run-result")
            }
            Section {
                LabeledContent("When", value: Date(timeIntervalSince1970: row.epoch).formatted(date: .long, time: .standard))
                LabeledContent("Started by", value: row.trigger)
                LabeledContent("Destination", value: row.destination)
                if let type = row.typeName { LabeledContent("Type", value: type) }
                LabeledContent("Records", value: event.samplesCommitted.formatted())
                LabeledContent("Data sent", value: ByteCountFormatter.string(fromByteCount: Int64(facts.byteCount), countStyle: .file))
                LabeledContent("Took", value: Duration.milliseconds(facts.durationMillis).formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
                if let start = facts.windowStartDay, let end = facts.windowEndDay {
                    LabeledContent("Covering", value: start == end ? start : "\(start) to \(end)")
                }
            }
            if !facts.stepTimings.isEmpty {
                Section {
                    ForEach(Array(facts.stepTimings.enumerated()), id: \.offset) { _, step in
                        LabeledContent(step.name, value: Duration.milliseconds(step.durationMillis).formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
                    }
                } header: {
                    SectionTitle("Steps")
                }
            }
            if let raw = event.errorClass, let errorClass = ErrorClass(rawValue: raw),
               let archetype = UserFacingErrorArchetype.fromErrorClass(errorClass) {
                let error = UserFacingErrorObject.make(archetype: archetype, destinationLabel: row.destination)
                Section {
                    Text(error.cause)
                    Text(error.fix).foregroundStyle(.secondaryText)
                } header: {
                    SectionTitle(LocalizedStringKey(error.title))
                }
            }
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }
}
