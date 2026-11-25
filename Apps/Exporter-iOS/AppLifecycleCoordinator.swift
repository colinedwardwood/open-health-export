// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import BackgroundTasks
import CorrectnessEngine
import EnginePorts
import Foundation
import HealthKitSource
import NetEgress
import RunJournal
import UIKit
import UserNotifications
import Watchdog

@MainActor
final class AppLifecycleCoordinator {
    static let shared = AppLifecycleCoordinator()

    private var healthObservers: HealthKitObserverCoordinator?
    private(set) var pendingDeepLink: URL?
    private var deepLinkHandler: ((URL) -> Void)?

    private init() {}

    /// #43: the product app's router. A link that arrived before it existed (a
    /// notification tapped on a cold launch) is handed over straight away.
    func setDeepLinkHandler(_ handler: @escaping (URL) -> Void) {
        deepLinkHandler = handler
        if let url = consumePendingDeepLink() {
            handler(url)
        }
    }

    func queueDeepLink(_ url: URL) {
        if let deepLinkHandler {
            deepLinkHandler(url)
            return
        }
        pendingDeepLink = url
        NotificationCenter.default.post(name: .oheOpenDeepLink, object: url)
    }

    func consumePendingDeepLink() -> URL? {
        let url = pendingDeepLink
        pendingDeepLink = nil
        return url
    }

    /// #62: a wake that cannot be logged is journalled and shown on Status, never dropped.
    func recordWake(_ trigger: RunTrigger) {
        do {
            try AppHealth.service.wakeLedger().append(
                WakeRecord(trigger: trigger, atEpoch: Date().timeIntervalSince1970)
            )
            AppStatus.launchFailures.resolve(.wakeLedger)
        } catch {
            Task { await AppStatus.launchFailures.record(.wakeLedger, error: error, trigger: trigger) }
        }
    }

    /// Registers the Health observers when allowed. Failures are recorded against
    /// `trigger` and surface on Status; they never stop the caller (#62).
    func startObserversIfEligible(trigger: RunTrigger = .appForeground) async {
        guard HealthObserverPolicy.mayObserve(
            healthAvailable: HealthKitAvailability.isAvailable(),
            disclosureAcknowledged: UserDefaults.standard.bool(
                forKey: SettingKey.disclosureAcknowledged.rawValue
            )
        ) else { return }
        let revoked: Bool
        do {
            revoked = try await AppHealth.service.observeAuthorizationChanges()
            AppStatus.launchFailures.resolve(.authorizationObservation)
        } catch {
            await AppStatus.launchFailures.record(.authorizationObservation, error: error, trigger: trigger)
            return
        }
        switch HealthObserverPolicy.action(
            revoked: revoked,
            automaticExport: AppDestinations.repository.hasAutomaticExport(trigger: .observerQuery),
            running: healthObservers != nil
        ) {
        case .stop:
            stopObservers()
        case .keep:
            return
        case .start:
            do {
                healthObservers = try await AppHealth.service.startObservers {
                    await ObserverExportGate.shared.enqueue($0)
                }
                AppStatus.launchFailures.resolve(.observerStart)
            } catch {
                await AppStatus.launchFailures.record(.observerStart, error: error, trigger: trigger)
                return
            }
            BackgroundTaskCoordinator.submit()
        }
    }

    func stopObservers() {
        healthObservers?.stop()
        healthObservers = nil
    }
}

@MainActor
final class ExporterAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        AppLifecycleCoordinator.shared.recordWake(.launch)
        AppStatus.transparency.attachNetworkActivityLedger()
        BackgroundTaskCoordinator.register()
        ContinuedBackfillCoordinator.register()
        BackgroundTaskCoordinator.submit()
        Task {
            await AppLifecycleCoordinator.shared.startObserversIfEligible(trigger: .launch)
            await AppExport.service.recoverInterruptedExportsRecordingFailure(trigger: .launch)
        }
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo[
            FailureNotificationPayload.openURLKey
        ] as? String
        guard let url = FailureNotificationPayload.url(fromOpenURLString: raw) else {
            return
        }
        await AppLifecycleCoordinator.shared.queueDeepLink(url)
    }
}

@MainActor
enum ContinuedBackfillCoordinator {
    static let identifier = IdentifierRoot.qualified("backfill")
    private static let modeKey = SettingKey.backfillMode.rawValue

    static func register() {
        guard #available(iOS 26.0, *) else { return }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                let mode = BackfillMode(
                    rawValue: UserDefaults.standard.string(forKey: modeKey) ?? ""
                ) ?? .aggregateOnly
                let work = Task {
                    try await AppExport.service.runBackfill(mode: mode)
                }
                continued.progress.totalUnitCount = 1
                continued.expirationHandler = {
                    work.cancel()
                }
                do {
                    _ = try await work.value
                    continued.progress.completedUnitCount = 1
                    continued.setTaskCompleted(success: true)
                } catch {
                    continued.setTaskCompleted(success: false)
                }
            }
        }
    }

    static func submit(mode: BackfillMode) throws -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: mode == .raw
                ? "Backfilling raw Health history"
                : "Backfilling Health summaries",
            subtitle: "Newest history first"
        )
        request.strategy = .queue
        try BGTaskScheduler.shared.submit(request)
        return true
    }
}

@MainActor
enum BackgroundTaskCoordinator {
    static let refreshIdentifier = IdentifierRoot.qualified("refresh")
    static let processingIdentifier = IdentifierRoot.qualified("processing")

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                handle(refresh, trigger: .bgAppRefresh)
            }
        }
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingIdentifier,
            using: nil
        ) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                handle(processing, trigger: .bgProcessing)
            }
        }
    }

    private static let submitFailureKey = SettingKey.backgroundSubmitFailure.rawValue

    /// Submitting again replaces the pending request with the same identifier, so this
    /// is safe on every launch and foreground (#29).
    static func submit() {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        let processing = BGProcessingTaskRequest(identifier: processingIdentifier)
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        processing.requiresNetworkConnectivity = false
        processing.requiresExternalPower = false

        var failures: [String] = []
        for (name, request) in [("refresh", refresh as BGTaskRequest), ("processing", processing)] {
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                #if targetEnvironment(simulator)
                // The simulator refuses every background task request.
                continue
                #else
                failures.append("\(name) (code \((error as NSError).code))")
                #endif
            }
        }
        if failures.isEmpty {
            UserDefaults.standard.removeObject(forKey: submitFailureKey)
        } else {
            UserDefaults.standard.set(failures.joined(separator: ", "), forKey: submitFailureKey)
        }
    }

    /// The requests iOS refused, for the Status row (#62).
    static func submitFailures() -> String? {
        UserDefaults.standard.string(forKey: submitFailureKey)
    }

    private static func handle(_ task: BGTask, trigger: RunTrigger) {
        AppLifecycleCoordinator.shared.recordWake(trigger)
        let work = Task {
            do {
                // ADR-R8: reported as a successful wake, because it is one. Telling iOS the
                // wake failed would make it back off scheduling over a deferral we chose.
                if AppExport.service.deferWakeIfMigrationPending(trigger: trigger) {
                    task.setTaskCompleted(success: true)
                    submit()
                    return
                }
                // #28: observer registration is best-effort on a wake. Failing it is
                // recorded (#62) but must not skip the export pass the wake exists for.
                await AppLifecycleCoordinator.shared.startObserversIfEligible(trigger: trigger)
                // #63: a queue past its seven days is cleared on every wake, not only
                // when someone opens the app.
                await AppExport.service.expireQueuesRecordingFailure(trigger: trigger)
                if AppDestinations.repository.hasAutomaticExport(trigger: trigger) {
                    _ = try await AppExport.service.runOnePageEachMetric(trigger: trigger)
                }
                task.setTaskCompleted(success: true)
            } catch {
                // A keychain sealed before first unlock is a deferral, not a failure:
                // retry on the next wake instead of telling iOS this one failed.
                if LaunchFailureRecorder.isDeferral(error) {
                    await AppStatus.launchFailures.record(.observerExport, error: error, trigger: trigger)
                    task.setTaskCompleted(success: true)
                } else {
                    await AppStatus.notifyRunFailure(trigger: trigger)
                    task.setTaskCompleted(success: false)
                }
            }
            submit()
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}
