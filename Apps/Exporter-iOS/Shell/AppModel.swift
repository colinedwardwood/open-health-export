// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import EnginePorts
import Foundation
import Observation

/// App-wide navigation and lifecycle state for the product UI (#43). Every link the
/// app receives goes through `route(_:)`, and the launch and foreground work that
/// used to live in the harness's `onAppear` runs here, once.
@MainActor
@Observable
final class AppModel {
    var selectedTab: AppTab = .status
    var paths: [AppTab: [AppRoute]] = [:]
    private(set) var exporting = false
    private(set) var lastExportMessage: String?
    #if DEBUG
    var showsDeveloper = false
    #endif

    let privacyGate: AppPrivacyGate

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let services: AppEnvironment
    @ObservationIgnored private var started = false

    init(
        authenticator: any UserPresenceAuthenticating,
        services: AppEnvironment = .live,
        defaults: UserDefaults = .standard
    ) {
        privacyGate = AppPrivacyGate(authenticator: authenticator)
        self.services = services
        self.defaults = defaults
        privacyGate.prepare(enabled: privacyGateEnabled)
    }

    var privacyGateEnabled: Bool {
        defaults.bool(forKey: SettingKey.appPrivacyGateEnabled.rawValue)
    }

    var disclosureAcknowledged: Bool {
        defaults.bool(forKey: SettingKey.disclosureAcknowledged.rawValue)
    }

    var isLocked: Bool {
        privacyGateEnabled && privacyGate.state != .unlocked
    }

    // MARK: Navigation

    func route(_ url: URL) {
        guard let target = DeepLinkRouter.target(
            for: url,
            disclosureAcknowledged: disclosureAcknowledged
        ) else { return }
        selectedTab = target.tab
        paths[target.tab] = target.path
        if target.exportNow {
            Task { await exportNow() }
        }
    }

    func push(_ route: AppRoute) {
        paths[selectedTab, default: []].append(route)
    }

    // MARK: Lifecycle

    /// Launch work. Safe to call from every `task` that fires; it runs once.
    func start() async {
        guard !started else { return }
        started = true
        // Before anything awaits, so a notification tapped on a cold launch is routed
        // the moment the model exists rather than when the harness used to look.
        AppLifecycleCoordinator.shared.setDeepLinkHandler { [weak self] url in
            self?.route(url)
        }
        #if DEBUG
        UITestFixtures.applyOpenURL(to: self)
        #endif
        await privacyGate.authenticateIfNeeded(enabled: privacyGateEnabled)
        _ = try? await services.export.expireQueuesAndNotify()
        _ = try? await services.export.recoverInterruptedExports()
        try? await services.status.recordNotificationSuppressionIfNeeded(
            forcedDenied: AppStatus.seededNotificationsDenied
        )
        await refreshAdvisory()
        if disclosureAcknowledged, services.destinations.hasAutomaticExport(trigger: .appForeground) {
            await exportNow(trigger: .appForeground)
        }
    }

    func sceneBecameActive() async {
        AppLifecycleCoordinator.shared.recordWake(.appForeground)
        await privacyGate.authenticateIfNeeded(enabled: privacyGateEnabled)
        try? await services.status.recordNotificationSuppressionIfNeeded(
            forcedDenied: AppStatus.seededNotificationsDenied
        )
        try? await AppLifecycleCoordinator.shared.startObserversIfEligible()
        BackgroundTaskCoordinator.submit()
        await refreshAdvisory()
    }

    func sceneLeftForeground() {
        privacyGate.lockIfEnabled(privacyGateEnabled)
    }

    func unlock() async {
        await privacyGate.authenticateIfNeeded(enabled: privacyGateEnabled)
    }

    // MARK: Export

    func exportNow(trigger: RunTrigger = .manual) async {
        guard disclosureAcknowledged, !exporting else { return }
        exporting = true
        defer { exporting = false }
        do {
            // #46 replaces this with the Status screen's own export presentation.
            let lines = try await HarnessExport.runOnePageEachMetric(trigger: trigger)
            lastExportMessage = lines.first ?? "Export finished."
        } catch {
            let label = await HarnessExport.notifyRunFailure(trigger: trigger)
            lastExportMessage = "\(label ?? "Export") failed: \(error.localizedDescription)"
        }
    }

    private func refreshAdvisory() async {
        // No network egress of any kind before the person has read what the app does.
        guard disclosureAcknowledged else { return }
        _ = await services.advisory.refresh(
            enabled: defaults.bool(forKey: SettingKey.advisoryEnabled.rawValue),
            now: Date()
        )
    }
}
