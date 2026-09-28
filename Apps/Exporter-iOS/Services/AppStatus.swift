// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
        guard let root = try? HarnessExport.applicationSupportRoot() else { return nil }
        func decode<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
            guard let data = try? Data(contentsOf: root.appendingPathComponent(name)) else {
                return nil
            }
            return try? JSONDecoder().decode(type, from: data)
        }
        var sources = DataFlowSources()
        if HarnessExport.isLocalFileEnabled() {
            sources.localFolder = .some(HarnessExport.localExportFolderName())
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
        let root = try HarnessExport.applicationSupportRoot()
        return try StateStoreHost.store(path: root.appendingPathComponent("state.sqlite").path)
    }

    private static let marketingVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

    static let status = StatusService(
        snapshots: SharedContainerStatusStore(),
        notifier: SystemStatusNotifier(),
        denialMemory: PreferencesNotificationDenialMemory(),
        store: stateStore,
        wakes: { try HarnessExport.wakeLedger().records() },
        now: { Date() }
    )

    static let history = HistoryService(
        store: stateStore,
        seal: { HarnessExport.ledgerHeadSeal() },
        sealRecordURL: {
            try HarnessExport.applicationSupportRoot().appendingPathComponent("ledger-head-seal.json")
        }
    )

    static let transparency = TransparencyService(
        sources: { DataFlowSourceFiles.read() },
        selectedTypeCount: { (try? await HarnessExport.selectedMetrics())?.count ?? 0 },
        store: stateStore,
        networkActivityURL: {
            try HarnessExport.applicationSupportRoot().appendingPathComponent("network-activity.json")
        },
        diagnosticJournal: { maxRuns, windowSeconds in
            let root = try HarnessExport.applicationSupportRoot()
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
