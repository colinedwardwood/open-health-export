// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import DestinationTrust
import SwiftUI
import UniformTypeIdentifiers
import Watchdog

// #47: the Destinations tab, adding a destination, and one destination's detail.
// Mockup: design canvas boards 3 and 6.

struct DestinationsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services
    @State private var adding = false

    var body: some View {
        _ = model.statusGeneration
        let rows = StatusDashboard.rows(
            services.status.destinationSnapshots(),
            nowEpoch: Date().timeIntervalSince1970,
            relative: Self.relative
        )
        return List {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("No destinations yet", systemImage: "arrow.right.to.line")
                } description: {
                    Text("Add a folder in Files to start. You can add servers later.")
                }
            } else {
                Section {
                    ForEach(rows) { row in
                        NavigationLink(value: AppRoute.destination(id: row.id)) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: row.glyph)
                                    .foregroundStyle(row.tone.color)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.label)
                                    Text("\(row.stateLabel) · \(row.detail)").metadata()
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .accessibilityIdentifier("destinations-row-\(row.id)")
                    }
                }
            }
            Section {
                Button {
                    adding = true
                } label: {
                    Label("Add destination", systemImage: "plus")
                }
                .accessibilityIdentifier("destinations-add")
            }
        }
        .navigationTitle("Destinations")
        .refreshable { model.refreshStatus() }
        .sheet(isPresented: $adding, onDismiss: { model.refreshStatus() }) {
            AddDestinationFlow()
        }
    }

    static func relative(_ epoch: TimeInterval) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: Date(timeIntervalSince1970: epoch), relativeTo: Date())
    }
}

/// The type picker, then the chosen type's setup, in one sheet.
struct AddDestinationFlow: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DestinationKind.addable) { kind in
                        NavigationLink {
                            switch kind {
                            case .files: FilesSetupScreen { dismiss() }
                            case .https, .homeAssistantWebhook, .mqtt: NetworkSetupScreen(kind: kind) { dismiss() }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Self.title(kind)).font(.headline)
                                Text(kind.requirement).metadata()
                            }
                        }
                        .accessibilityIdentifier("add-\(kind.rawValue)")
                    }
                } footer: {
                    SectionFooter("Data goes straight from \(DeviceNoun.thisDevice) to the destination you set up. KeepMyMetrics never sees it.")
                }
            }
            .navigationTitle("Add destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    static func title(_ kind: DestinationKind) -> LocalizedStringKey {
        switch kind {
        case .files: "Files on \(DeviceNoun.thisDevice)"
        case .https: "Your own server (HTTPS)"
        case .homeAssistantWebhook: "Home Assistant webhook (advanced)"
        case .mqtt: "Home Assistant sensors (MQTT, recommended)"
        }
    }
}

/// Pick a folder, watch the test, save once it passes.
struct FilesSetupScreen: View {
    @State private var setup = FilesSetupModel()
    @State private var picking = false
    let done: () -> Void

    var body: some View {
        List {
            Section {
                Button {
                    #if DEBUG
                    if UITestFixtures.seedsLocalExportFolder {
                        Task { await setup.useSeededFolder() }
                        return
                    }
                    #endif
                    picking = true
                } label: {
                    LabeledContent("Folder", value: setup.folderName ?? "Choose…")
                }
                .disabled(setup.testing)
                .accessibilityIdentifier("files-choose-folder")
            } footer: {
                SectionFooter("Exports are written as JSON Lines files. A folder in iCloud Drive syncs your health data to iCloud.")
            }
            if setup.folderName != nil {
                TestChecklistSection(checklist: setup.checklist, error: setup.error) {
                    Task { await setup.runTest() }
                }
            }
        }
        .navigationTitle("Files")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { done() }
                    .disabled(!setup.canSave)
                    .accessibilityIdentifier("files-save")
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            Task { await setup.useFolder(url) }
        }
    }
}

/// The named test steps with live state, shared by every destination type.
struct TestChecklistSection: View {
    let checklist: DestinationTestChecklist
    let error: UserFacingErrorObject?
    let testAgain: () -> Void

    var body: some View {
        Section {
            ForEach(checklist.steps) { step in
                HStack(spacing: 12) {
                    symbol(step.state)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(step.title)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(Self.spoken(step.state))
                .accessibilityIdentifier("test-step-\(step.step.rawValue)")
            }
            if let error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.title).font(.headline)
                    Text(error.fix).foregroundStyle(.secondaryText)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("test-error")
            }
            if checklist.failed {
                Button("Test again", action: testAgain)
                    .accessibilityIdentifier("test-again")
            }
        } header: {
            SectionTitle("Test")
        }
        .onChange(of: checklist.announcement) { _, announcement in
            if let announcement {
                AccessibilityNotification.Announcement(announcement).post()
            }
        }
    }

    @ViewBuilder
    private func symbol(_ state: DestinationTestChecklist.StepState) -> some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondaryText)
        case .running: ProgressView()
        case .passed: DestinationDisplayState.healthy.toneGlyph
        case .failed: DestinationDisplayState.failing.toneGlyph
        }
    }

    static func spoken(_ state: DestinationTestChecklist.StepState) -> String {
        switch state {
        case .pending: "Not started"
        case .running: "In progress"
        case .passed: "Passed"
        case .failed: "Failed"
        }
    }
}

/// One destination: its state, what's wrong if anything, and what you can do.
struct DestinationDetailScreen: View {
    let destinationID: String
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var setup = FilesSetupModel()
    @State private var confirmingRemove = false
    @State private var automatic = true

    var body: some View {
        _ = model.statusGeneration
        let snapshot = services.status.destinationSnapshots().first { $0.destinationID == destinationID }
        let row = snapshot.flatMap {
            StatusDashboard.rows([$0], nowEpoch: Date().timeIntervalSince1970, relative: DestinationsScreen.relative).first
        }
        let error = services.status.userFacingError(destinationID: destinationID, archetype: nil)
        return List {
            if let row {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.stateLabel).font(.headline)
                            Text(row.detail).foregroundStyle(.secondaryText)
                        }
                    } icon: {
                        Image(systemName: row.glyph).foregroundStyle(row.tone.color)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("detail-state")
                }
            }
            if let error {
                Section {
                    Text(error.cause)
                    Text(error.fix).foregroundStyle(.secondaryText)
                } header: {
                    SectionTitle(LocalizedStringKey(error.title))
                }
            }
            if destinationID == "local-file", setup.checklist.steps.contains(where: { $0.state != .pending }) {
                TestChecklistSection(checklist: setup.checklist, error: setup.error) {
                    Task { await setup.runTest() }
                }
            }
            Section {
                Toggle("Automatic exports", isOn: $automatic)
                    .accessibilityIdentifier("detail-automatic")
                    .onChange(of: automatic) { _, on in
                        try? services.destinations.setExportRole(on ? .designated : .manualOnly, destinationID: destinationID)
                        model.refreshStatus()
                    }
            } footer: {
                SectionFooter("When this is off, this destination only receives data when you tap Export now.")
            }
            if destinationID == "local-file" {
                Section {
                    Button("Test again") { Task { await setup.runTest(); model.refreshStatus() } }
                        .disabled(setup.testing)
                        .accessibilityIdentifier("detail-test-again")
                    Button("Remove destination", role: .destructive) { confirmingRemove = true }
                        .accessibilityIdentifier("detail-remove")
                }
            }
        }
        .navigationTitle(row?.label ?? snapshot?.destinationLabel ?? destinationID)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { automatic = services.destinations.exportRole(destinationID) == .designated }
        .confirmationDialog(
            "Remove this destination?",
            isPresented: $confirmingRemove,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                try? AppDestinationSetup.removeLocalFile()
                model.refreshStatus()
                dismiss()
            }
        } message: {
            Text("Files already exported stay in the folder. Nothing more is written there.")
        }
    }
}
