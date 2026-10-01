// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import SwiftUI

// Interim screens for the shell (#43). Each is replaced by its own issue: Status by
// #46, Destinations by #47, Data by #50, History by #51 and Settings by #52.

struct StatusTabScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services

    var body: some View {
        List {
            if model.needsSetup, model.disclosureAcknowledged {
                Section {
                    Button {
                        model.resumeSetup()
                    } label: {
                        Label("Finish setup: choose where exports go", systemImage: "arrow.right.circle")
                    }
                    .accessibilityIdentifier("shell-finish-setup")
                    .attentionCard(.attention)
                }
            }
            Section {
                ForEach(services.status.destinationStatusLines(), id: \.self) { line in
                    Text(line)
                }
            } header: {
                SectionTitle("Destinations")
            }
            Section {
                Button(model.exporting ? "Exporting…" : "Export now") {
                    Task { await model.exportNow() }
                }
                .disabled(model.exporting || !model.disclosureAcknowledged)
                .accessibilityIdentifier("shell-export-now")
                if let message = model.lastExportMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("shell-export-result")
                }
            }
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
    }
}

struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text("Not built yet."))
            .navigationTitle(title)
    }
}

/// The five-part error for one destination, as a notification opens it.
struct DestinationErrorScreen: View {
    let destinationID: String
    let archetype: UserFacingErrorArchetype?
    @Environment(\.services) private var services
    @State private var canOfferAlerts = false

    var body: some View {
        let error = services.status.userFacingError(destinationID: destinationID, archetype: archetype)
        List {
            if let error {
                Section {
                    Text(error.title)
                        .font(.headline)
                        .accessibilityIdentifier("shell-error-title")
                    Text(error.cause)
                }
                Section {
                    Text(error.fix)
                } header: {
                    SectionTitle("How to fix it")
                }
                if canOfferAlerts {
                    Section {
                        Button("Get alerts for failures like this") {
                            Task { canOfferAlerts = !(await LocalUserNotifier().requestAlerts()) }
                        }
                        .accessibilityIdentifier("shell-error-request-alerts")
                    } footer: {
                        Text("Right now these arrive quietly in Notification Centre.")
                    }
                }
            } else {
                Text("Nothing is wrong with this destination.")
                    .accessibilityIdentifier("shell-error-none")
            }
        }
        .navigationTitle(error?.destinationLabel ?? destinationID)
        .navigationBarTitleDisplayMode(.inline)
        .task { canOfferAlerts = error != nil ? await LocalUserNotifier().canOfferAlerts() : false }
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            }
            #if DEBUG
            Section {
                Button("Developer") { model.showsDeveloper = true }
                    .accessibilityIdentifier("shell-developer")
            }
            #endif
        }
        .navigationTitle("Settings")
    }
}

struct PrivacyLockScreen: View {
    let gate: AppPrivacyGate
    let unlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text("\(ProductName.display) is locked")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("privacy-gate-locked-title")
            Text("Unlocking protects this screen only. Background exports and destination delivery continue without a prompt.")
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("privacy-gate-background-scope")
            if gate.authenticationFailed {
                Text("Authentication was not completed.")
                    .accessibilityIdentifier("privacy-gate-failure")
            }
            Button(gate.state == .authenticating ? "Authenticating…" : "Unlock", action: unlock)
                .buttonStyle(.borderedProminent)
                .disabled(gate.state == .authenticating)
                .accessibilityIdentifier("privacy-gate-unlock")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("privacy-gate")
    }
}

#if DEBUG
/// The engineering harness, reachable from Settings in debug builds only.
struct DeveloperScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HarnessView(authenticator: UserPresenceAuthenticatorFactory.make())
            .overlay(alignment: .topTrailing) {
                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .padding(.trailing)
                    .accessibilityIdentifier("developer-close")
            }
    }
}
#endif
