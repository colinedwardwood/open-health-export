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
    /// QA-17: held types, read from the store with status. They are the only source of
    /// the anchor-hold notices, and an unchanged set is not assigned, so it doesn't re-render.
    private var holds: [AnchorHold] = []
    /// #62/#63: what stops or delays background exports, read once per refresh.
    private var baseNotices: [StatusNotice] = []
    @ObservationIgnored private var holdsTask: Task<Void, Never>?
    /// #45: first run, shown over the app until the disclosure is acknowledged; a
    /// "Finish setup" row resumes it later.
    var onboarding: Onboarding?
    /// Bumped when first run finishes, so screens re-read what it changed.
    private(set) var setupGeneration = 0

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

    /// Rows for what stops or delays exports. Held types come first: nothing exports
    /// for them until the person decides.
    var statusNotices: [StatusNotice] {
        StatusNotices.anchorHoldNotices(holds) + baseNotices
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
            // Control Centre's button is the only link that asks for this.
            Task { await exportNow(trigger: .widgetControl) }
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
        await UITestFixtures.seedAnchorHoldOnce(using: services.export)
        #endif
        await privacyGate.authenticateIfNeeded(enabled: privacyGateEnabled)
        await services.export.expireQueuesRecordingFailure(trigger: .launch)
        await services.export.recoverInterruptedExportsRecordingFailure(trigger: .launch)
        await recordNotificationSuppression()
        // Once per launch: runs re-arm their own destination afterwards.
        await services.status.rescheduleAllOverdueNotifications()
        refreshStatus()
        await refreshAdvisory()
        if disclosureAcknowledged, services.destinations.hasAutomaticExport(trigger: .appForeground) {
            await exportNow(trigger: .appForeground)
        }
    }

    func sceneBecameActive() async {
        AppLifecycleCoordinator.shared.recordWake(.appForeground)
        refreshStatus()
        await privacyGate.authenticateIfNeeded(enabled: privacyGateEnabled)
        await recordNotificationSuppression()
        await AppLifecycleCoordinator.shared.startObserversIfEligible(trigger: .appForeground)
        await services.export.expireQueuesRecordingFailure(trigger: .appForeground)
        refreshStatus()
        BackgroundTaskCoordinator.submit()
        await refreshAdvisory()
    }

    /// #62: the watchdog notices that notifications went off; failing to record that
    /// is itself shown on Status.
    private func recordNotificationSuppression() async {
        await AppStatus.launchFailures.run(.notificationCheck, trigger: .appForeground) {
            try await services.status.recordNotificationSuppressionIfNeeded(
                forcedDenied: AppStatus.seededNotificationsDenied
            )
        }
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
            let lines = try await AppExport.service.runOnePageEachMetric(trigger: trigger) { current, total in
                await MainActor.run {
                    self.exportProgress = total > 0 ? Double(current) / Double(total) : 0
                }
            }
            lastExportMessage = lines.first ?? "Export finished."
        } catch {
            let label = await AppStatus.notifyRunFailure(trigger: trigger)
            lastExportMessage = nil
            lastExportError = UserFacingFailure.object(for: error, destinationLabel: label ?? "your destination")
        }
    }

    func refreshStatus() {
        statusGeneration += 1
        baseNotices = AppStatus.statusNotices()
        reloadHolds()
    }

    /// Re-reads the held types, replacing any read still in flight.
    private func reloadHolds() {
        holdsTask?.cancel()
        holdsTask = Task {
            guard let loaded = try? await services.export.anchorHolds(), !Task.isCancelled,
                  loaded != holds
            else { return }
            holds = loaded
        }
    }

    /// QA-17: the person's answer to a held type. Either choice changes what Status shows.
    func resolveAnchorHold(metric: MetricID, reexport: Bool) async {
        holdsTask?.cancel()
        do {
            if reexport {
                try await services.export.authoriseAnchorReexport(metric: metric)
                holds = holds.map { hold in
                    guard hold.metric == metric else { return hold }
                    var decided = hold
                    decided.decision = .reexportAuthorized
                    return decided
                }
            } else {
                try await services.export.stopExportingHeldType(metric: metric)
                holds.removeAll { $0.metric == metric }
            }
        } catch {
            // The re-read below shows whatever the store still holds.
        }
        refreshStatus()
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
