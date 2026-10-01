// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import MetricCatalog
import SwiftUI
import UniformTypeIdentifiers
import Watchdog

/// First run (#45), presented over the app until it finishes. Mockups: the design
/// canvas boards 1–3; copy follows the brand guide's voice.
struct OnboardingFlow: View {
    @State private var model: OnboardingModel

    init(resuming: Bool, finish: @escaping () -> Void) {
        _model = State(initialValue: OnboardingModel(resuming: resuming, finish: finish))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .welcome: WelcomeStep(model: model)
                case .types: TypesStep(model: model)
                case .destination: DestinationStep(model: model)
                case .howItWorks: HowItWorksStep(model: model)
                case .healthAccess: HealthAccessStep(model: model)
                case .firstExport: FirstExportStep(model: model)
                }
            }
            .animation(.default, value: model.step)
        }
        .interactiveDismissDisabled()
    }
}

// MARK: Shared layout

/// Title, body and a bottom button area, so every step has the same rhythm.
private struct StepLayout<Content: View, Actions: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) { actions }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
        }
    }
}

private struct PrimaryButton: View {
    let title: LocalizedStringKey
    var identifier: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }
}

private struct WorkStatus: View {
    let work: OnboardingModel.Work

    var body: some View {
        switch work {
        case .idle:
            EmptyView()
        case let .running(label):
            HStack(spacing: 10) {
                ProgressView()
                Text(label)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        case let .failed(message):
            Label {
                Text(message)
            } icon: {
                DestinationDisplayState.failing.toneGlyph
            }
            .accessibilityIdentifier("onboarding-error")
        }
    }
}

private struct Point: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: 1 Welcome

private struct WelcomeStep: View {
    let model: OnboardingModel

    var body: some View {
        StepLayout(title: "Your health data, delivered where you choose.", message: nil) {
            VStack(alignment: .leading, spacing: 24) {
                Point(
                    systemImage: "lock.shield",
                    title: "Only to places you control",
                    detail: "No account, and no cloud of ours. Data goes from \(DeviceNoun.thisDevice) to your destinations."
                )
                Point(
                    systemImage: "arrow.clockwise",
                    title: "Catches late data",
                    detail: "Readings your Watch syncs hours later are still picked up and sent."
                )
                Point(
                    systemImage: "bell",
                    title: "Tells you when something’s wrong",
                    detail: "If a destination stops answering, you’ll know which one and why."
                )
            }
            .padding(.top, 8)
        } actions: {
            PrimaryButton(title: "Get started", identifier: "onboarding-start") { model.advance() }
        }
    }
}

// MARK: 2 Types

private struct TypesStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepLayout(
            title: "Choose what to export",
            message: "These are the everyday types most people start with. You can change them any time in Data."
        ) {
            VStack(spacing: 0) {
                ForEach(model.types, id: \.id) { type in
                    Toggle(type.displayName, isOn: Binding(
                        get: { model.selected.contains(type.id) },
                        set: { on in
                            if on { model.selected.insert(type.id) } else { model.selected.remove(type.id) }
                        }
                    ))
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        } actions: {
            Text("\(model.selected.count) of \(model.types.count) types")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            PrimaryButton(
                title: "Continue",
                identifier: "onboarding-types-continue",
                disabled: model.selected.isEmpty
            ) { model.advance() }
        }
    }
}

// MARK: 3 Destination

private struct DestinationStep: View {
    let model: OnboardingModel
    @State private var picking = false

    var body: some View {
        StepLayout(
            title: "Where should exports go?",
            message: "Start with a folder in Files. You can add Home Assistant, MQTT or your own server afterwards."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    #if DEBUG
                    if UITestFixtures.seedsLocalExportFolder {
                        Task { await model.useSeededFolder() }
                        return
                    }
                    #endif
                    picking = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "folder")
                            .font(.title2)
                            .frame(width: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Files on \(DeviceNoun.thisDevice)").font(.headline)
                            Text(model.folderName.map { "Folder: \($0)" }
                                ?? "Choose a folder. Recommended for your first export.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.isWorking)
                .accessibilityIdentifier("onboarding-choose-files")
                WorkStatus(work: model.work)
                Label(
                    "Data goes straight from \(DeviceNoun.thisDevice) to the destination you set up. We never see it.",
                    systemImage: "lock.shield"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        } actions: {
            Button("Set up later") { model.setUpLater() }
                .disabled(model.isWorking)
                .accessibilityIdentifier("onboarding-setup-later")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            Task { await model.useFolder(url) }
        }
    }
}

// MARK: 4 How it works

private struct HowItWorksStep: View {
    let model: OnboardingModel

    var body: some View {
        StepLayout(title: "How exporting works", message: nil) {
            VStack(alignment: .leading, spacing: 24) {
                Point(
                    systemImage: "clock",
                    title: "iOS decides when it runs",
                    detail: "Background exports happen when iOS allows. Export now, the Control Centre button or a Shortcut runs one when you choose."
                )
                Point(
                    systemImage: "lock",
                    title: "Nothing while your \(DeviceNoun.current) is locked",
                    detail: "Apple keeps Health data locked until you unlock your phone, so exports catch up after that."
                )
                Point(
                    systemImage: "hand.raised",
                    title: "You choose what is read",
                    detail: "We don't send anything to ourselves, and there are no analytics."
                )
                Text("This is not a medical device. It does not diagnose or treat anything.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("first-run-disclaimer")
            }
        } actions: {
            PrimaryButton(title: "Continue", identifier: "disclosure-continue") { model.acknowledgeDisclosure() }
        }
    }
}

// MARK: 5 Health access

private struct HealthAccessStep: View {
    let model: OnboardingModel

    var body: some View {
        StepLayout(title: LocalizedStringKey(HealthAuthorizationPriming.title), message: nil) {
            VStack(alignment: .leading, spacing: 16) {
                Text(HealthAuthorizationPriming.typeCountCopy(model.selected.count))
                    .accessibilityIdentifier("health-priming-types")
                Text(HealthAuthorizationPriming.sheetFollows)
                Text(HealthAuthorizationPriming.invisibility)
                    .foregroundStyle(.secondary)
                WorkStatus(work: model.work)
            }
            .fixedSize(horizontal: false, vertical: true)
        } actions: {
            PrimaryButton(
                title: "Continue",
                identifier: "health-priming-continue",
                disabled: model.isWorking
            ) {
                Task { await model.requestHealthAccess() }
            }
            if case .failed = model.work {
                Button("Skip for now") { model.advance() }
                    .accessibilityIdentifier("health-priming-skip")
            }
        }
    }
}

// MARK: 6 First export

private struct FirstExportStep: View {
    let model: OnboardingModel

    var body: some View {
        StepLayout(title: "Your first export", message: nil) {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = model.exportSummary {
                    Label {
                        Text(summary)
                            .accessibilityIdentifier("onboarding-export-summary")
                    } icon: {
                        DestinationDisplayState.healthy.toneGlyph
                    }
                    if let folder = model.folderName {
                        Text("Open the \(folder) folder in Files to see it.")
                            .foregroundStyle(.secondary)
                    }
                } else if model.nothingCameBack {
                    Text("Your folder is set up, but Apple Health had nothing from the last seven days for the types you chose.")
                        .accessibilityIdentifier("onboarding-nothing-came-back")
                    Text("Types you turned off on Apple's screen stay empty. To change that, open the Health app, tap your profile, then Apps, then \(ProductName.display).")
                        .foregroundStyle(.secondary)
                } else if model.isWorking {
                    ProgressView(value: model.exportProgress) {
                        Text("Exporting…")
                    }
                    .accessibilityIdentifier("onboarding-export-progress")
                } else {
                    Text("Send the last seven days of your chosen types to \(model.folderName ?? "your folder") now.")
                }
                if case .failed = model.work {
                    WorkStatus(work: model.work)
                }
            }
        } actions: {
            if model.exportSummary != nil {
                PrimaryButton(title: "Done", identifier: "onboarding-done") { model.done() }
            } else if model.nothingCameBack {
                PrimaryButton(title: "Check again", identifier: "onboarding-check-again") {
                    Task { await model.runFirstExport() }
                }
                Button("Choose different types") { model.chooseDifferentTypes() }
                    .accessibilityIdentifier("onboarding-choose-types")
                Button("Done") { model.done() }
                    .accessibilityIdentifier("onboarding-done")
            } else {
                PrimaryButton(
                    title: "Export now",
                    identifier: "onboarding-export-now",
                    disabled: model.isWorking
                ) {
                    Task { await model.runFirstExport() }
                }
                Button("Later") { model.done() }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("onboarding-export-later")
            }
        }
        .task {
            // Starts on its own: reaching this screen is the request, and it saves a tap
            // on the way to the first export (#45: eight taps or fewer).
            if model.exportSummary == nil, !model.nothingCameBack, !model.isWorking {
                await model.runFirstExport()
            }
        }
    }
}
