// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import SwiftUI

// Shell screens (#43): the destination error a notification opens, the privacy
// lock, and the debug Developer screen.

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
                        SectionFooter("Right now these arrive quietly in Notification Centre.")
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
