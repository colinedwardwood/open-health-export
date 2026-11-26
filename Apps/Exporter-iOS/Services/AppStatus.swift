// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import DestinationTrust
import EnginePorts
import Foundation
import RunJournal
import StorageSQLite
import UIKit
import Watchdog
import WidgetKit

/// Destination status snapshots in the shared container the widget reads.
struct SharedContainerStatusStore: DestinationStatusStore {
    func readAll() -> [DestinationStatusSnapshot] {
        StatusSnapshotLocation.readAll()
    }

    func read(destinationID: String) -> DestinationStatusSnapshot? {
        guard let url = StatusSnapshotLocation.url(destinationID: destinationID) else { return nil }
        return try? DestinationSnapshotFile.read(from: url)
    }

    func write(_ snapshot: DestinationStatusSnapshot) throws {
        guard let url = StatusSnapshotLocation.url(destinationID: snapshot.destinationID) else { return }
        try DestinationSnapshotFile.write(snapshot, to: url)
    }
}

/// Local notifications and widget timelines.
struct SystemStatusNotifier: StatusNotifier {
    func notify(_ notice: UserNotice) async {
        _ = try? await LocalUserNotifier().notify(notice)
    }

    func rescheduleOverdue(for snapshot: DestinationStatusSnapshot) async {
        _ = try? await LocalUserNotifier().rescheduleExportOverdue(snapshot: snapshot)
    }

    func authorizationDenied() async -> Bool {
        await LocalUserNotifier().authorizationDenied()
    }

    func reloadAllWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    func reloadStatusWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }
}

/// The remembered notification denial, in the app's preferences (key in SettingsStore).
struct PreferencesNotificationDenialMemory: NotificationDenialMemory {
    func previouslyDenied() -> Bool {
        UserDefaults.standard.bool(forKey: SettingKey.notificationsPreviouslyDenied.rawValue)
    }

    func setPreviouslyDenied(_ denied: Bool) {
        UserDefaults.standard.set(denied, forKey: SettingKey.notificationsPreviouslyDenied.rawValue)
    }
}

/// #62: launch and background failures that have not cleared, in the app's preferences.
struct PreferencesLaunchIssues: LaunchIssueMemory {
    private var key: String { SettingKey.launchIssuesV1.rawValue }

    func issues() -> [LaunchIssue] {
        UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([LaunchIssue].self, from: $0) } ?? []
    }

    func save(_ issues: [LaunchIssue]) {
        if issues.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(issues) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Reads the verified destination records the data-flow explainer names. Only the
/// fields it shows are decoded; the records themselves belong to the destinations.
enum DataFlowSourceFiles {
    private struct WebRecord: Decodable {
        var urlString: String
        var allowInsecureHTTP: Bool
        var hasBearer: Bool
        var report: DestinationTestReport
    }

    private struct MQTTRecord: Decodable {
        var urlString: String
        var allowInsecure: Bool
        var report: DestinationTestReport
        var hasClientPKCS12: Bool?
        var username: String?
        var hasPassword: Bool?
    }

    private struct CompanionRecord: Decodable {
        var serviceName: String
        var report: DestinationTestReport
    }

    private struct OTLPRecord: Decodable {
        var urlString: String
    }

    static func read() -> DataFlowSources? {
        guard let root = try? AppFiles.applicationSupportRoot() else { return nil }
        func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else {
                return nil
            }
            return try? JSONDecoder().decode(type, from: data)
        }
        var sources = DataFlowSources()
        if AppDestinations.repository.isLocalFileEnabled() {
            sources.localFolder = .some(AppDestinations.repository.localExportFolderName())
        }
        if let record = decode(WebRecord.self, "https-destination.json"),
           record.report.allowsEnablement
        {
            sources.https = .init(
                urlString: record.urlString,
                allowInsecureHTTP: record.allowInsecureHTTP,
                hasBearer: record.hasBearer
            )
        }
        if let record = decode(WebRecord.self, "home-assistant-destination.json"),
           record.report.allowsEnablement
        {
            sources.homeAssistant = .init(
                urlString: record.urlString,
                allowInsecureHTTP: record.allowInsecureHTTP
            )
        }
        if let record = decode(MQTTRecord.self, "mqtt-destination.json"),
           record.report.allowsEnablement
        {
            sources.mqtt = .init(
                urlString: record.urlString,
                allowInsecure: record.allowInsecure,
                hasClientCertificate: record.hasClientPKCS12 == true,
                hasUsernameOrPassword: record.username != nil || record.hasPassword == true
            )
        }
        if let record = decode(CompanionRecord.self, "companion-test.json"),
           record.report.allowsEnablement
        {
            sources.companionServiceName = record.serviceName
        }
        #if !OHE_OBS25_SIZE_BASELINE
        sources.otlpURLString = decode(OTLPRecord.self, "otlp-destination.json")?.urlString
        #endif
        return sources
    }
}

enum AppStatus {
    private static let stateStore: @Sendable () throws -> any StateStore = {
        let root = try AppFiles.applicationSupportRoot()
        return try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
    }

    private static let marketingVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

    static let status = StatusService(
        snapshots: SharedContainerStatusStore(),
        notifier: SystemStatusNotifier(),
        denialMemory: PreferencesNotificationDenialMemory(),
        store: stateStore,
        wakes: { try AppHealth.service.wakeLedger().records() },
        now: { Date() }
    )

    /// #62: every launch and background step that used to be `try?` reports here.
    static let launchFailures = LaunchFailureRecorder(
        store: stateStore,
        memory: PreferencesLaunchIssues(),
        now: { Date() }
    )

    /// #62/#63: persistent Status rows for what stops or delays background exports.
    @MainActor
    static func statusNotices() -> [StatusNotice] {
        StatusNotices.notices(
            backgroundRefresh: backgroundRefreshAvailability,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            submitFailure: BackgroundTaskCoordinator.submitFailures(),
            issues: launchFailures.issues()
        )
    }

    @MainActor
    private static var backgroundRefreshAvailability: BackgroundRefreshAvailability {
        #if DEBUG
        // UI tests inject the setting rather than depend on the simulator's.
        if let seeded = ProcessInfo.processInfo.environment["OHE_SEED_BACKGROUND_REFRESH"],
           let availability = BackgroundRefreshAvailability(rawValue: seeded)
        {
            return availability
        }
        #endif
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return .available
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .available
        }
    }

    static let history = HistoryService(
        store: stateStore,
        seal: { AppFiles.ledgerHeadSeal() },
        sealRecordURL: {
            try AppFiles.applicationSupportRoot().appendingPathComponent("ledger-head-seal.json")
        }
    )

    static let transparency = TransparencyService(
        sources: { DataFlowSourceFiles.read() },
        selectedTypeCount: { (try? await AppDestinations.repository.selectedMetrics())?.count ?? 0 },
        store: stateStore,
        networkActivityURL: {
            try AppFiles.applicationSupportRoot().appendingPathComponent("network-activity.json")
        },
        diagnosticJournal: { maxRuns, windowSeconds in
            let root = try AppFiles.applicationSupportRoot()
            let read = SQLiteDiagnosticReader.read(
                path: root.appendingPathComponent("state.sqlite").path,
                maxRuns: maxRuns,
                windowSeconds: windowSeconds
            )
            return DiagnosticJournal(events: read.events, degraded: read.degraded)
        },
        marketingVersion: marketingVersion,
        now: { Date() },
        formatDate: { date in
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    )

    /// The device half of a diagnostic bundle's header.
    @MainActor
    static func diagnosticEnvironment() -> DiagnosticEnvironment {
        DiagnosticEnvironment(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            localeIdentifier: Locale.current.identifier,
            utcOffsetMinutes: TimeZone.current.secondsFromGMT() / 60
        )
    }

    /// A run that threw before any destination could report for itself. One notice
    /// still goes out, against the destination that has evidence of the failure, or the
    /// first one this trigger was allowed to use. Returns the label that notice used,
    /// so on-screen text can say the same thing.
    @discardableResult
    static func notifyRunFailure(trigger: RunTrigger) async -> String? {
        await status.notifyRunFailure(
            planned: DestinationRepository.healthDestinationIDs.filter {
                AppDestinations.repository.isEnabled($0)
                    && AppDestinations.repository.allowsExport($0, trigger: trigger)
            },
            label: DestinationRepository.label
        )
    }

    /// UI tests seed a denied notification authorization rather than depend on the
    /// simulator's real setting.
    static var seededNotificationsDenied: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["OHE_SEED_NOTIFICATION_AUTHORIZATION"] == "denied"
        #else
        false
        #endif
    }
}
