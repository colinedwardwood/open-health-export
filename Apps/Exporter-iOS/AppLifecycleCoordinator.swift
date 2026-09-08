import BackgroundTasks
import EnginePorts
import Foundation
import HealthKitSource
import RunJournal
import UIKit

@MainActor
final class AppLifecycleCoordinator {
    static let shared = AppLifecycleCoordinator()

    private var healthObservers: HealthKitObserverCoordinator?

    private init() {}

    func recordWake(_ trigger: RunTrigger) {
        guard let ledger = try? HarnessExport.wakeLedger() else { return }
        try? ledger.append(
            WakeRecord(trigger: trigger, atEpoch: Date().timeIntervalSince1970)
        )
    }

    func startObserversIfEligible() async throws {
        guard UserDefaults.standard.bool(forKey: "disclosureAcknowledged"),
              HarnessExport.isLocalFileEnabled(),
              healthObservers == nil
        else {
            return
        }
        healthObservers = try await HarnessExport.startHealthObservers()
        BackgroundTaskCoordinator.submit()
    }

    func stopObservers() {
        healthObservers?.stop()
        healthObservers = nil
    }
}

@MainActor
final class ExporterAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        AppLifecycleCoordinator.shared.recordWake(.launch)
        BackgroundTaskCoordinator.register()
        Task {
            try? await AppLifecycleCoordinator.shared.startObserversIfEligible()
        }
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
                task.setTaskCompleted(success: false)
            }
            submit()
        }
        task.expirationHandler = {
            work.cancel()
        }
    }
}
