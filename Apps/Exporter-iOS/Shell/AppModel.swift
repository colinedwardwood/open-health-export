// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
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
    /// Determinate progress while exporting, 0...1.
    private(set) var exportProgress: Double = 0
    /// The last Export now: a one-line result, or the five-part error (#46).
    private(set) var lastExportMessage: String?
    private(set) var lastExportError: UserFacingErrorObject?
    /// Bumped whenever destination state may have changed, so Status re-reads it.
    private(set) var statusGeneration = 0
    /// #45: first run, shown over the app until the disclosure is acknowledged; a
    /// "Finish setup" row resumes it later.
    var onboarding: Onboarding?
    /// Bumped when first run finishes, so screens re-read what it changed.
    private(set) var setupGeneration = 0
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
        if OnboardingPlan.launchStep(disclosureAcknowledged: disclosureAcknowledged) != nil {
            onboarding = Onboarding(resuming: false)
        }
    }

    struct Onboarding: Identifiable {
        let id = UUID()
        let resuming: Bool
    }

    /// No destination can receive an export yet.
    var needsSetup: Bool {
        _ = setupGeneration
        return !DestinationRepository.healthDestinationIDs.contains { services.destinations.isEnabled($0) }
    }

    func resumeSetup() {
        onboarding = Onboarding(resuming: true)
    }

    /// After Delete everything: the app is as new, so first run starts again (#52).
    func didDeleteEverything() {
        paths = [:]
        selectedTab = .status
        lastExportMessage = nil
        lastExportError = nil
        onboarding = Onboarding(resuming: false)
        refreshStatus()
    }

    func finishOnboarding() {
        onboarding = nil
        setupGeneration += 1
        refreshStatus()
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
        // #68: purchases made elsewhere, Family Sharing and refunds update the unlock.
        PurchaseStore.shared.start()
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
        refreshStatus()
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
        exportProgress = 0
        lastExportError = nil
        defer {
            exporting = false
            refreshStatus()
        }
        do {
            let lines = try await HarnessExport.runOnePageEachMetric(trigger: trigger) { current, total in
                await MainActor.run {
                    self.exportProgress = total > 0 ? Double(current) / Double(total) : 0
                }
            }
            lastExportMessage = lines.first ?? "Export finished."
        } catch {
            let label = await HarnessExport.notifyRunFailure(trigger: trigger)
            lastExportMessage = nil
            lastExportError = UserFacingFailure.object(for: error, destinationLabel: label ?? "your destination")
        }
    }

    func refreshStatus() {
        statusGeneration += 1
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
