// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import SwiftUI

#if !OHE_OBS25_SIZE_BASELINE
/// Your own OpenTelemetry collector (OTLP over HTTP).
struct OTLPSetupScreen: View {
    @State private var setup = OTLPSetupModel()
    let done: () -> Void

    var body: some View {
        @Bindable var setup = setup
        List {
            Section {
                Label {
                    Text("This sends the app's run outcomes to your collector: when exports ran, how they ended and how long they took. It never sends health values.")
                } icon: {
                    Image(systemName: "waveform.path.ecg").accessibilityHidden(true)
                }
                .accessibilityIdentifier("otlp-explainer")
            }
            Section {
                TextField("https://collector.example.com:4318/v1/traces", text: $setup.address)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("otlp-address")
                if !setup.address.isEmpty {
                    Text(copy: setup.addressCheck.message)
                        .metadata()
                        .accessibilityIdentifier("otlp-address-check")
                }
                SecureField("Token (optional)", text: $setup.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("otlp-token")
                Toggle("Allow plain HTTP (unsafe)", isOn: $setup.allowsPlainHTTP)
                    .accessibilityIdentifier("otlp-plain-http")
            } header: {
                SectionTitle("Collector")
            } footer: {
                SectionFooter("Sent as a bearer token. It's kept in the keychain and never shown again.")
            }
            if setup.stage != .form || setup.error != nil {
                TestChecklistSection(checklist: setup.checklist, error: setup.error) {
                    Task { await setup.test() }
                }
            }
            if case let .confirm(preview, _) = setup.stage {
                Section {
                    Text("The collector accepted the test. Here is what a real export carries.")
                    DisclosureGroup("What an export sends") {
                        Text(preview)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                } header: {
                    SectionTitle("Confirm this collector")
                }
                .accessibilityIdentifier("otlp-confirm-card")
            }
        }
        .navigationTitle("Your own collector")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if case .confirm = setup.stage {
                    Button("Save") { Task { await setup.save() } }
                        .accessibilityIdentifier("otlp-save")
                } else {
                    Button("Test") { Task { await setup.test() } }
                        .disabled(!setup.canTest)
                        .accessibilityIdentifier("otlp-test")
                }
            }
        }
        .onChange(of: setup.stage) { _, stage in
            if stage == .saved { done() }
        }
    }
}
#endif
