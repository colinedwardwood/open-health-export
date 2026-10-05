// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import CorrectnessEngine
import SwiftUI
import UIKit

/// #52: Settings. Expert surfaces (OTLP, traceparent) stay in the debug Developer
/// screen and never reach a release build.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.services) private var services
    @AppStorage(SettingKey.appPrivacyGateEnabled.rawValue) private var appLock = false
    @AppStorage(SettingKey.advisoryEnabled.rawValue) private var securityNotices = false
    @State private var canOfferAlerts = false
    @State private var confirmingWipe = false
    @State private var wipeInventory: WipeInventory?
    @State private var message: String?

    var body: some View {
        List {
            UnlockSection()

            Section {
                if canOfferAlerts {
                    Button("Get alerts for failures") {
                        Task { canOfferAlerts = !(await LocalUserNotifier().requestAlerts()) }
                    }
                    .accessibilityIdentifier("settings-alerts")
                }
                Button("Notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                SectionTitle("Notifications")
            } footer: {
                SectionFooter("Failures and overdue exports arrive quietly in Notification Centre until you ask for alerts.")
            }

            Section {
                Toggle("Lock with Face ID or passcode", isOn: Binding(
                    get: { appLock },
                    set: { on in
                        if on {
                            Task {
                                // Turning the lock on proves the person can open it.
                                if await model.privacyGate.authenticateIfNeeded(enabled: true) {
                                    appLock = true
                                    message = nil
                                } else {
                                    message = "The lock wasn't turned on because authentication didn't finish."
                                }
                            }
                        } else {
                            appLock = false
                            model.privacyGate.prepare(enabled: false)
                        }
                    }
                ))
                .accessibilityIdentifier("settings-app-lock")
                Toggle("Check for security notices", isOn: $securityNotices)
                    .accessibilityIdentifier("settings-security-notices")
                if let message {
                    Text(message).foregroundStyle(.secondaryText)
                }
                DisclosureGroup("If someone else set this up") {
                    Text("iOS can hide this app. We can't prevent that, and there's no stealth mode, alternate icon or second name. Check Settings → Apps → Hidden Apps, Screen Time, Battery, and your App Store purchase history.")
                    Link("Apple's Personal Safety guide", destination: URL(string: "https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web")!)
                }
                .accessibilityIdentifier("settings-someone-else")
            } header: {
                SectionTitle("Privacy and security")
            } footer: {
                SectionFooter("The lock protects this screen only; exports keep running. Security notices are signed and come only from advisories.cewdesign.com, and checking sends nothing about you.")
            }

            Section {
                Button(WipeCopy.title, role: .destructive) {
                    Task {
                        wipeInventory = await AppStatus.transparency.wipeInventory()
                        confirmingWipe = true
                    }
                }
                .accessibilityIdentifier("settings-delete-everything")
            }

            Section {
                if let privacy = About.links.first(where: { $0.title == "Privacy policy" }) {
                    Link(privacy.title, destination: privacy.url)
                        .accessibilityIdentifier("settings-privacy-policy")
                }
                NavigationLink("About KeepMyMetrics") { AboutScreen() }
                    .accessibilityIdentifier("settings-about")
            }

            #if DEBUG
            Section {
                Button("Developer") { model.showsDeveloper = true }
                    .accessibilityIdentifier("shell-developer")
            }
            #endif
        }
        .navigationTitle("Settings")
        .task { canOfferAlerts = await LocalUserNotifier().canOfferAlerts() }
        .confirmationDialog(WipeCopy.confirmTitle, isPresented: $confirmingWipe, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) {
                Task {
                    try? await services.export.wipeEverything()
                    model.didDeleteEverything()
                }
            }
            .accessibilityIdentifier("settings-delete-confirm")
        } message: {
            Text(wipeMessage)
        }
    }

    private var wipeMessage: String {
        [
            wipeInventory.map(WipeCopy.counts),
            WipeCopy.receivedLimit,
            WipeCopy.healthLimit,
            WipeCopy.healthPath,
        ].compactMap { $0 }.joined(separator: "\n\n")
    }
}

/// #52: who made this, under what licence, and where its source is (ADR-0005).
struct AboutScreen: View {
    var body: some View {
        let identity = BuildIdentity.current
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        List {
            Section {
                Text(About.copyright)
                    .accessibilityIdentifier("about-copyright")
                Text(About.licence)
                Text(About.warranty).foregroundStyle(.secondaryText)
                Text(About.medical).foregroundStyle(.secondaryText)
            }
            Section {
                Link(destination: About.sourceLink(commit: identity.sourceCommit)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Source code for this version")
                        Text(About.versionLine(version: version, build: build, commit: identity.sourceCommit))
                            .metadata()
                    }
                }
                .accessibilityIdentifier("about-source")
                ForEach(About.links) { link in
                    Link(link.title, destination: link.url)
                }
                NavigationLink("Acknowledgements") { NoticesScreen() }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        // A reading page: the tab bar would cover and fade its last links.
        .toolbar(.hidden, for: .tabBar)
    }
}

/// The NOTICE file shipped in the bundle: third-party licences and attributions.
struct NoticesScreen: View {
    var body: some View {
        ScrollView {
            Text(Self.notice)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    static var notice: String {
        guard let url = Bundle.main.url(forResource: "NOTICE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "The notices file is missing from this build." }
        return text
    }
}
