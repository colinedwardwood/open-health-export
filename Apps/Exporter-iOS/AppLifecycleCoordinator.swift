// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import BackgroundTasks
import CorrectnessEngine
import EnginePorts
import Foundation
import HealthKitSource
import RunJournal
import UIKit
import UserNotifications
import Watchdog

@MainActor
final class AppLifecycleCoordinator {
    static let shared = AppLifecycleCoordinator()

    private var healthObservers: HealthKitObserverCoordinator?
    private(set) var pendingDeepLink: URL?

    private init() {}

    func queueDeepLink(_ url: URL) {
        pendingDeepLink = url
        NotificationCenter.default.post(name: .oheOpenDeepLink, object: url)
    }

    func consumePendingDeepLink() -> URL? {
        let url = pendingDeepLink
        pendingDeepLink = nil
        return url
    }

    func recordWake(_ trigger: RunTrigger) {
        guard let ledger = try? HarnessExport.wakeLedger() else { return }
        try? ledger.append(
            WakeRecord(trigger: trigger, atEpoch: Date().timeIntervalSince1970)
        )
    }

    func startObserversIfEligible() async throws {
        guard HealthKitAvailability.isAvailable() else { return }
        guard UserDefaults.standard.bool(forKey: "ohe.disclosureAcknowledged") else {
            return
        }
        let revoked = try await HarnessExport.observeAuthorizationChanges()
        if revoked {
            stopObservers()
            return
        }
        guard HarnessExport.isLocalFileEnabled() else { return }
        guard healthObservers == nil else { return }
        healthObservers = try await HarnessExport.startHealthObservers()
        BackgroundTaskCoordinator.submit()
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
        BackgroundTaskCoordinator.register()
        ContinuedBackfillCoordinator.register()
        Task {
            try? await AppLifecycleCoordinator.shared.startObserversIfEligible()
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let url = FailureNotificationPayload.url(
            from: response.notification.request.content.userInfo
        ) else {
            return
        }
        AppLifecycleCoordinator.shared.queueDeepLink(url)
    }
}

@MainActor
enum ContinuedBackfillCoordinator {
    static let identifier = "app.openhealthexporter.backfill"
    private static let modeKey = "ohe.backfillMode"

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
                    try await HarnessExport.runBackfill(mode: mode)
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
    static let refreshIdentifier = "app.openhealthexporter.refresh"
    static let processingIdentifier = "app.openhealthexporter.processing"

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

    static func submit() {
        let refresh = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(refresh)

        let processing = BGProcessingTaskRequest(identifier: processingIdentifier)
        processing.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        processing.requiresNetworkConnectivity = false
        processing.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(processing)
    }

    private static func handle(_ task: BGTask, trigger: RunTrigger) {
        AppLifecycleCoordinator.shared.recordWake(trigger)
        let work = Task {
            do {
                try await AppLifecycleCoordinator.shared.startObserversIfEligible()
                if HarnessExport.isLocalFileEnabled() {
                    _ = try await HarnessExport.runOnePageEachMetric(trigger: trigger)
                }
                task.setTaskCompleted(success: true)
            } catch {
                await HarnessExport.notifyDestinationFailure(
                    destinationID: "local-file",
                    destinationLabel: "Archive folder"
                )
                task.setTaskCompleted(success: false)
            }
            submit()
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}
