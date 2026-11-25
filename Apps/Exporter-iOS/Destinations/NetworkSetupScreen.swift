// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import DestinationTrust
import MetricCatalog
import NetEgress
import SwiftUI
import Watchdog

/// #48: your own HTTPS server, or a Home Assistant webhook.
struct NetworkSetupScreen: View {
    @State private var setup: NetworkSetupModel
    let done: () -> Void

    init(kind: DestinationKind, done: @escaping () -> Void) {
        _setup = State(initialValue: NetworkSetupModel(kind: kind))
        self.done = done
    }

    var body: some View {
        @Bindable var setup = setup
        List {
            if let caveat = setup.kind.caveat {
                Section {
                    Label {
                        Text(caveat)
                    } icon: {
                        DestinationDisplayState.stale.toneGlyph
                    }
                    .accessibilityIdentifier("network-caveat")
                }
            }
            Section {
                TextField(addressPrompt, text: $setup.address)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("network-address")
                if !setup.address.isEmpty {
                    Text(setup.addressCheck.message)
                        .metadata()
                        .accessibilityIdentifier("network-address-check")
                }
                if setup.kind == .mqtt {
                    TextField("Username (optional)", text: $setup.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("network-username")
                }
                SecureField(secretPrompt, text: $setup.secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("network-secret")
                Toggle(setup.kind == .mqtt ? "Allow unencrypted (unsafe)" : "Allow plain HTTP (unsafe)", isOn: $setup.allowsPlainHTTP)
                    .accessibilityIdentifier("network-plain-http")
            } header: {
                SectionTitle("Server")
            } footer: {
                SectionFooter(secretFooter)
            }
            if setup.kind == .mqtt {
                Section {
                    Picker("Delivery", selection: $setup.qos) {
                        Text("Confirmed (QoS 1)").tag(UInt8(1))
                        Text("Best effort (QoS 0)").tag(UInt8(0))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("network-qos")
                    DisclosureGroup("Advanced") {
                        LabeledContent("Client ID") {
                            TextField("Client ID", text: $setup.clientID)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledContent("Topic") {
                            TextField("Topic", text: $setup.topic)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    SectionTitle("Delivery")
                } footer: {
                    SectionFooter("Confirmed waits for the broker to acknowledge each export, so nothing is marked sent until it arrived.")
                }
                Section {
                    ForEach(HomeAssistantDiscoveryPreview.entityNames(for: MetricCatalog.coreDaily), id: \.self) { name in
                        Text(name)
                    }
                } header: {
                    SectionTitle("What you'll see in Home Assistant")
                } footer: {
                    SectionFooter("Home Assistant finds these sensors by itself through MQTT discovery, under one device. Each updates when an export arrives.")
                }
                .accessibilityIdentifier("network-discovery-preview")
            }
            if setup.kind == .homeAssistantWebhook {
                Section {
                    Text(HomeAssistantWebhookExample.yaml)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("network-example-yaml")
                    ShareLink(item: HomeAssistantWebhookExample.yaml) {
                        Label("Share or copy the example", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    SectionTitle("Example automation")
                } footer: {
                    SectionFooter("Paste this into a new automation in Home Assistant (Edit in YAML), then use the same webhook ID here.")
                }
            }
            if setup.stage != .form || setup.error != nil || setup.checklist.steps.contains(where: { $0.state != .pending }) {
                TestChecklistSection(checklist: setup.checklist, error: setup.error) {
                    Task { await setup.test() }
                }
            }
            if case let .confirmServer(card) = setup.stage {
                ConfirmServerSection(card: card, phrase: $setup.publicPhrase)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                switch setup.stage {
                case .confirmServer:
                    Button("Save") { Task { await setup.confirm() } }
                        .disabled(!setup.canConfirm)
                        .accessibilityIdentifier("network-save")
                default:
                    Button("Test") { Task { await setup.test() } }
                        .disabled(!setup.canTest)
                        .accessibilityIdentifier("network-test")
                }
            }
        }
        .sheet(item: Binding(
            get: { setup.certificate },
            set: { if $0 == nil { Task { await setup.cancel() } } }
        )) { identity in
            CertificateCheckSheet(identity: identity.value) {
                Task { await setup.trustCertificate(identity.value) }
            } cancel: {
                Task { await setup.cancel() }
            }
        }
        .onChange(of: setup.stage) { _, stage in
            if stage == .saved { done() }
        }
    }

    private var title: LocalizedStringKey {
        switch setup.kind {
        case .mqtt: "Home Assistant sensors"
        case .homeAssistantWebhook: "Home Assistant webhook"
        default: "Your own server"
        }
    }

    private var addressPrompt: LocalizedStringKey {
        switch setup.kind {
        case .mqtt: "mqtts://homeassistant.local:8883"
        case .homeAssistantWebhook: "https://homeassistant.local:8123"
        default: "https://example.com/ingest"
        }
    }

    private var secretPrompt: LocalizedStringKey {
        switch setup.kind {
        case .mqtt: "Password (optional)"
        case .homeAssistantWebhook: "Webhook ID"
        default: "Token (optional)"
        }
    }

    private var secretFooter: LocalizedStringKey {
        switch setup.kind {
        case .mqtt: "Use the login you created for the Mosquitto add-on. The password is kept in the keychain and never shown again."
        case .homeAssistantWebhook: "The webhook ID works like a password. It's kept in the keychain and never shown again."
        default: "Sent as a bearer token. It's kept in the keychain and never shown again."
        }
    }
}

/// The card shown once the test passes: who this server is, and what will be sent.
private struct ConfirmServerSection: View {
    let card: DestinationConfirmationCard
    @Binding var phrase: String

    var body: some View {
        Section {
            LabeledContent("Server", value: card.host)
            if let identity = card.identity {
                LabeledContent("Address", value: "\(identity.resolvedAddress), \(ConfirmationCopy.addressClassPhrase(identity.addressClass))")
                LabeledContent("Encryption", value: identity.tlsVersion)
                LabeledContent("Certificate", value: identity.leafSubject)
                LabeledContent("Issued by", value: identity.leafIssuer)
            } else if card.insecureWithoutTLS {
                Text("Not encrypted, by your choice.").foregroundStyle(StatusTone.attention.color)
            }
            Text(ConfirmationCopy.remember).metadata()
            if card.requiresPublicAddressConfirmation {
                Text(ConfirmationCopy.publicAddressWarning)
                TextField(ConfirmationCopy.publicAddressPhrase, text: $phrase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("network-public-phrase")
            }
            DisclosureGroup("What the test sent") {
                Text(String(decoding: card.preview, as: UTF8.self))
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            SectionTitle("Confirm this server")
        }
        .accessibilityIdentifier("network-confirm-card")
    }
}

/// #66: a certificate that isn't publicly trusted is compared by fingerprint first.
private struct CertificateCheckSheet: View {
    let identity: TLSIdentity
    let trust: () -> Void
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Nothing has been sent to \(identity.leafSubject) yet: no test data, no token and no health data.")
                    Text("Continue only if this fingerprint exactly matches the one your server shows. If you didn't set up a self-signed certificate yourself, cancel.")
                        .foregroundStyle(.secondaryText)
                }
                Section {
                    Text(TLSIdentity.grouped(identity.leafSPKISha256))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("certificate-fingerprint")
                } header: {
                    SectionTitle("Public-key fingerprint (SHA-256)")
                }
            }
            .navigationTitle("Check the certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("It matches", action: trust)
                        .accessibilityIdentifier("certificate-trust")
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

/// Lets a sheet be driven by the identity awaiting a decision.
struct IdentifiedIdentity: Identifiable {
    let value: TLSIdentity
    var id: String { value.leafSPKISha256 }
}

extension NetworkSetupModel {
    var certificate: IdentifiedIdentity? {
        if case let .confirmCertificate(identity) = stage { return IdentifiedIdentity(value: identity) }
        return nil
    }
}
