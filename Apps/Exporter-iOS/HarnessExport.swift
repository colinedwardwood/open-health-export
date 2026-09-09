import CompanionWire
import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import DiagnosticBundle
import EnginePorts
import Foundation
import HealthKitSource
import MetricCatalog
import NetEgress
import RunJournal
import SinkCompanion
import SinkHTTP
import SinkLocalFile
import SinkMQTT
import StorageSQLite
import UIKit
import Watchdog
import WidgetKit
import WireFormat

private struct CompanionVerificationRecord: Codable {
    var serviceName: String
    var macInstallationID: String
    var report: DestinationTestReport
}

private struct HTTPSVerificationRecord: Codable {
    var urlString: String
    var allowedHosts: [String]
    var allowInsecureHTTP: Bool
    var report: DestinationTestReport
    var leafSPKISha256: String?
    var issuerSPKISha256: String?
    var firstSeen: String
    var hasBearer: Bool
}

private struct MQTTVerificationRecord: Codable {
    var urlString: String
    var allowedHosts: [String]
    var allowInsecure: Bool
    var clientID: String
    var topic: String
    var report: DestinationTestReport
}

private actor ObserverExportGate {
    static let shared = ObserverExportGate()
    private var pending: Set<MetricID> = []
    private var running = false

    func enqueue(_ metric: MetricID) async {
        pending.insert(metric)
        guard !running else { return }
        running = true
        defer { running = false }
        while let next = pending.first {
            pending.remove(next)
            _ = try? await HarnessExport.runOnePageEachMetric(
                metrics: [next],
                trigger: .observerQuery
            )
        }
    }
}

enum HarnessExport {
    private static let selectedMetricsKey = "ohe.selectedMetrics"

    static func selectedMetrics() -> [MetricID] {
        let allowed = Set(MetricCatalog.all.map(\.id))
        if let stored = UserDefaults.standard.stringArray(forKey: selectedMetricsKey) {
            return stored.map(MetricID.init(rawValue:)).filter { allowed.contains($0) }
        }
        return MetricCatalog.coreDaily.map(\.id)
    }

    static func saveSelectedMetrics(_ metrics: Set<MetricID>) {
        let allowed = Set(MetricCatalog.all.map(\.id))
        UserDefaults.standard.set(
            metrics.intersection(allowed).map(\.rawValue).sorted(),
            forKey: selectedMetricsKey
        )
    }

    static func applySelectedMetrics(
        _ metrics: Set<MetricID>,
        removing: Set<MetricID>
    ) async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let now = Date().timeIntervalSince1970
        for metric in removing {
            try await store.purgeType(
                metric: metric,
                reason: TypeDisableReason.explicitStop,
                destination: "local-file",
                atEpoch: now
            )
        }
        for metric in metrics.subtracting(removing) {
            try await store.reenableType(metric: metric, reason: "user_selected")
        }
        saveSelectedMetrics(metrics)
    }

    @MainActor
    static func fetchSecurityAdvisory(enabled: Bool) async throws -> AdvisoryPresentation {
        let defaults = UserDefaults.standard
        let state = AdvisoryState(
            enabled: enabled,
            lastAttemptEpoch: defaults.object(
                forKey: "ohe.advisoryLastAttemptEpoch"
            ) as? TimeInterval,
            lastVerifiedEpoch: defaults.object(
                forKey: "ohe.advisoryLastVerifiedEpoch"
            ) as? TimeInterval,
            lastSeenSeq: defaults.integer(forKey: "ohe.advisoryLastSeenSeq")
        )
        let root = try applicationSupportRoot()
        let emptyBody = root.appendingPathComponent("advisory-request-body")
        if !FileManager.default.fileExists(atPath: emptyBody.path) {
            try Data().write(to: emptyBody, options: .atomic)
        }
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let result = try await AdvisoryClient.fetch(
            transport: SystemHTTPTransport.make(),
            store: store,
            state: state,
            now: Date(),
            marketingVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.0.0",
            foregroundVisible: true,
            emptyBody: emptyBody
        )
        defaults.set(
            result.state.lastAttemptEpoch,
            forKey: "ohe.advisoryLastAttemptEpoch"
        )
        defaults.set(
            result.state.lastVerifiedEpoch,
            forKey: "ohe.advisoryLastVerifiedEpoch"
        )
        defaults.set(
            result.state.lastSeenSeq,
            forKey: "ohe.advisoryLastSeenSeq"
        )
        return result.presentation
    }

    static func installationID() throws -> String {
        let root = try applicationSupportRoot()
        let exporterURL = root.appendingPathComponent("exporter-id")
        if let existing = try? String(contentsOf: exporterURL, encoding: .utf8), !existing.isEmpty {
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = UUID().uuidString.lowercased()
        try id.write(to: exporterURL, atomically: true, encoding: .utf8)
        return id
    }

    static func runOnePageEachMetric(
        metrics: [MetricID]? = nil,
        trigger: RunTrigger = .manual
    ) async throws -> [String] {
        let metrics = metrics ?? selectedMetrics()
        let fm = FileManager.default
        let root = try applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("state.sqlite")
        let dest = root.appendingPathComponent("exports", isDirectory: true)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)

        let store = try SQLiteStateStore(path: sqliteURL.path)
        let gapIDsBefore = try await store.transact {
            Set(try $0.loadGaps().map(\.batchID))
        }
        let (verified, events) = try verifiedLocalFile(root: root, destinationDirectory: dest)
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let source = HealthKitAnchoredSource(context: context, limit: 1000)
        let observations = HealthKitDayObservationSource(context: context, limit: 1000)
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let exporterId = try installationID()
        let ledgerSeal = ledgerHeadSeal()
        let ledgerSealURL = root.appendingPathComponent("ledger-head-seal.json")

        var lines: [String] = []
        for metric in metrics {
            let snapshotURL = StatusSnapshotLocation.url(destinationID: "local-file")
            let run = ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "local-file",
                envelope: WireEnvelope(
                    exporterId: exporterId,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: statistics,
                observations: observations,
                trigger: trigger,
                snapshotURL: snapshotURL,
                externalStatusURL: dest.appendingPathComponent("status.json"),
                ledgerHeadSeal: ledgerSeal,
                ledgerSealURL: ledgerSealURL
            )
            let outcome = try await run.run()
            WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
            if (outcome.kind == .success || outcome.kind == .successNothingDue),
               let snapshotURL {
                await rescheduleOverdueNotification(snapshotURL: snapshotURL)
            }

            let reconcile = ReconcileSweep(
                observations: observations,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "local-file",
                envelope: WireEnvelope(
                    exporterId: exporterId,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: statistics,
                trigger: trigger,
                snapshotURL: snapshotURL,
                externalStatusURL: dest.appendingPathComponent("status.json"),
                ledgerHeadSeal: ledgerSeal,
                ledgerSealURL: ledgerSealURL
            )
            let reconciled = try await reconcile.run(throughDay: String(now.prefix(10)))
            lines.append("\(metric.rawValue) reconcile: \(reconciled.kind.rawValue)")
            if (reconciled.kind == .success || reconciled.kind == .successNothingDue),
               let snapshotURL {
                await rescheduleOverdueNotification(snapshotURL: snapshotURL)
            }
        }
        let newQueueGap = try await store.transact {
            try $0.loadGaps().contains {
                !gapIDsBefore.contains($0.batchID)
                    && $0.rangeDescription.hasPrefix("queue_eviction:")
            }
        }
        if newQueueGap {
            _ = try await LocalUserNotifier().notify(
                UserNotice(kind: .queueEvicted, destination: "Configured destinations")
            )
        }
        lines.append("Files: \(dest.path)")
        return lines
    }

    private static func rescheduleOverdueNotification(snapshotURL: URL) async {
        guard let snapshot = try? DestinationSnapshotFile.read(from: snapshotURL) else {
            return
        }
        _ = try? await LocalUserNotifier().rescheduleExportOverdue(snapshot: snapshot)
    }

    static func runFullReconcile(
        metrics: [MetricID]? = nil
    ) async throws -> [String] {
        let metrics = metrics ?? selectedMetrics()
        let root = try applicationSupportRoot()
        let dest = root.appendingPathComponent("exports", isDirectory: true)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dest,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: scratch,
            withIntermediateDirectories: true
        )
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let (verified, events) = try verifiedLocalFile(
            root: root,
            destinationDirectory: dest
        )
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let observations = HealthKitDayObservationSource(
            context: context,
            limit: 1000
        )
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let exporterID = try installationID()
        let seal = ledgerHeadSeal()
        var lines: [String] = []
        for metric in metrics {
            let outcome = try await ReconcileSweep(
                observations: observations,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "local-file",
                envelope: WireEnvelope(
                    exporterId: exporterID,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: statistics,
                trigger: .manual,
                snapshotURL: StatusSnapshotLocation.url(destinationID: "local-file"),
                externalStatusURL: dest.appendingPathComponent("status.json"),
                ledgerHeadSeal: seal,
                ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json")
            ).runFullHistory(throughDay: String(now.prefix(10)))
            lines.append("\(metric.rawValue) full reconcile: \(outcome.kind.rawValue)")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        lines.append("Files: \(dest.path)")
        return lines
    }

    static func queueEvictionGaps() async throws -> [GapRecord] {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        return try await store.transact {
            try $0.loadGaps().filter {
                $0.rangeDescription.hasPrefix("queue_eviction:")
                    && $0.rangeStartDay != nil
                    && $0.rangeEndDay != nil
            }
        }
    }

    static func recordNotificationSuppressionIfNeeded() async throws {
        let denied = await LocalUserNotifier().authorizationDenied()
        let defaults = UserDefaults.standard
        let key = "ohe.notificationsPreviouslyDenied"
        let previouslyDenied = defaults.bool(forKey: key)
        defer { defaults.set(denied, forKey: key) }
        guard NotificationSuppression.shouldRecord(
            previouslyDenied: previouslyDenied,
            currentlyDenied: denied
        ) else {
            return
        }
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        try await store.transact { tx in
            try tx.appendLedger(
                EgressEntry(
                    destination: "local-notifications",
                    sampleCount: 0,
                    outcomeKind: "security:notifications_denied",
                    detail: "watchdog_escalation_suppressed",
                    wallTimeEpoch: Date().timeIntervalSince1970
                )
            )
        }
        for snapshot in StatusSnapshotLocation.readAll() {
            if let url = StatusSnapshotLocation.url(
                destinationID: snapshot.destinationID
            ) {
                try DestinationSnapshotFile.recordSecurityEvents(
                    1,
                    destinationID: snapshot.destinationID,
                    destinationLabel: snapshot.destinationLabel,
                    writtenAtEpoch: Date().timeIntervalSince1970,
                    at: url
                )
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func reExportQueueGap(_ gap: GapRecord) async throws -> RunOutcome {
        let root = try applicationSupportRoot()
        let dest = root.appendingPathComponent("exports", isDirectory: true)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dest,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: scratch,
            withIntermediateDirectories: true
        )
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let (verified, events) = try verifiedLocalFile(
            root: root,
            destinationDirectory: dest
        )
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let outcome = try await ReconcileSweep(
            observations: HealthKitDayObservationSource(
                context: context,
                limit: 1000
            ),
            destination: verified,
            store: store,
            metric: gap.metric,
            scratchDirectory: scratch,
            destinationName: "local-file",
            envelope: WireEnvelope(
                exporterId: try installationID(),
                seq: 1,
                emittedAt: now,
                observedAt: now
            ),
            temporal: context,
            statistics: HealthKitStatisticsSource(context: context),
            trigger: .manual,
            snapshotURL: StatusSnapshotLocation.url(destinationID: "local-file"),
            externalStatusURL: dest.appendingPathComponent("status.json"),
            ledgerHeadSeal: ledgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json")
        ).run(gap: gap)
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return outcome
    }

    static func runDemoDataset(typedDestinationName: String) async throws -> [String] {
        try DemoExportGate.confirmSending(to: "local-file", typed: typedDestinationName)
        let fm = FileManager.default
        let root = try applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("demo-state.sqlite")
        let dest = root.appendingPathComponent("demo-exports", isDirectory: true)
        let scratch = root.appendingPathComponent("demo-scratch", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let store = try SQLiteStateStore(path: sqliteURL.path)
        let (verified, events) = try verifiedLocalFile(root: root, destinationDirectory: dest)
        try await emitTrustNotices(events)
        let context = TemporalContext.utcHost
        let now = Date().ISO8601Format()
        let exporterId = try installationID()
        var envelope = WireEnvelope(
            exporterId: exporterId,
            seq: 1,
            emittedAt: now,
            observedAt: now,
            demo: true
        )
        envelope.reason = "manual"
        let source = DemoSampleSource(seed: 1, samplesPerMetric: 4)
        var lines: [String] = ["DEMO MODE — synthetic data, not HealthKit"]
        for declaration in MetricCatalog.all {
            let run = ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: declaration.id,
                scratchDirectory: scratch,
                destinationName: "local-file",
                envelope: envelope,
                temporal: context,
                trigger: .manual
            )
            let outcome = try await run.run()
            lines.append("\(declaration.id.rawValue): \(outcome.kind.rawValue) (demo)")
        }
        lines.append("Files: \(dest.path)")
        return lines
    }

    static func runCompanion(session: PairingSession) async throws -> [String] {
        let fm = FileManager.default
        let root = try applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("state.sqlite")
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let store = try SQLiteStateStore(path: sqliteURL.path)
        let psk = try CompanionPSK.preSharedKey(from: session.secret)
        let discovered = try await CompanionDiscovery().find(pairedName: session.serviceName, for: .seconds(8))
        let options = NWByteStream.Options(
            requireTLS13: true,
            failFastOnWaiting: true,
            preSharedKey: psk
        )
        let deliveryPipe = ByteStreamCompanionPipe(
            stream: NWByteStream(service: discovered, options: options)
        )
        let verified: VerifiedDestination
        let verificationURL = companionTestReportURL(root: root)
        if let data = try? Data(contentsOf: verificationURL),
           let saved = try? JSONDecoder().decode(CompanionVerificationRecord.self, from: data),
           saved.serviceName == session.serviceName,
           saved.macInstallationID == session.macInstallationID,
           saved.report.allowsEnablement {
            verified = try CompanionDestinationEnable.resume(
                deliveryPipe: deliveryPipe,
                installationID: session.localInstallationID,
                testReport: saved.report
            )
        } else {
            let testPipe = ByteStreamCompanionPipe(
                stream: NWByteStream(service: discovered, options: options)
            )
            let completed = try await CompanionDestinationEnable.complete(
                testPipe: testPipe,
                deliveryPipe: deliveryPipe,
                installationID: session.localInstallationID,
                emittedAt: Date().ISO8601Format()
            )
            verified = completed.destination
            let record = CompanionVerificationRecord(
                serviceName: session.serviceName,
                macInstallationID: session.macInstallationID,
                report: completed.report
            )
            try JSONEncoder().encode(record).write(to: verificationURL, options: .atomic)
            if let snapshotURL = StatusSnapshotLocation.url(destinationID: "companion") {
                try DestinationSnapshotFile.recordSecurityEvents(
                    completed.events.count,
                    destinationID: "companion",
                    destinationLabel: "Mac companion · \(session.serviceName)",
                    writtenAtEpoch: Date().timeIntervalSince1970,
                    at: snapshotURL
                )
            }
            try await emitTrustNotices(completed.events, destination: session.serviceName)
        }
        let context = TemporalContext.utcHost
        let source = HealthKitAnchoredSource(context: context, limit: 1000)
        let observations = HealthKitDayObservationSource(context: context, limit: 1000)
        let statistics = HealthKitStatisticsSource(context: context)
        let now = Date().ISO8601Format()
        let ledgerSeal = ledgerHeadSeal()
        let ledgerSealURL = root.appendingPathComponent("ledger-head-seal.json")
        var lines: [String] = []
        for metric in [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id] {
            let run = ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "companion",
                envelope: WireEnvelope(
                    exporterId: session.localInstallationID,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: statistics,
                observations: observations,
                snapshotURL: StatusSnapshotLocation.url(destinationID: "companion"),
                ledgerHeadSeal: ledgerSeal,
                ledgerSealURL: ledgerSealURL
            )
            let outcome = try await run.run()
            WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
        }
        lines.append("Companion: \(session.serviceName)")
        return lines
    }

    private static func applicationSupportRoot() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("OpenHealthExporter", isDirectory: true)
        try fm.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        return root
    }

    @MainActor
    static func diagnosticBundle(
        minimumRuns: Int = 30,
        windowHours: Int = 24
    ) throws -> (preview: String, payload: Data) {
        let assembler = BundleAssembler(
            maxRuns: minimumRuns,
            windowSeconds: TimeInterval(windowHours) * 60 * 60
        )
        let root = try applicationSupportRoot()
        let journal = SQLiteDiagnosticReader.read(
            path: root.appendingPathComponent("state.sqlite").path,
            maxRuns: assembler.maxRuns,
            windowSeconds: assembler.windowSeconds
        )
        let payload = try assembler.assemble(
            header: DiagnosticHeader(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                osVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.current.model,
                localeIdentifier: Locale.current.identifier,
                utcOffsetMinutes: TimeZone.current.secondsFromGMT() / 60,
                generatedAt: Date().ISO8601Format(),
                degraded: journal.degraded
            ),
            events: journal.events
        )
        let text = String(decoding: payload, as: UTF8.self)
        let lines = assembler.previewLines(events: journal.events)
        let preview = lines.isEmpty ? text : lines.joined(separator: "\n") + "\n\n" + text
        return (preview, payload)
    }

    static func destinationStatusLines() -> [String] {
        let snapshots = StatusSnapshotLocation.readAll()
        guard !snapshots.isEmpty else { return ["No destination snapshots yet."] }
        return snapshots.map { snapshot in
            let last = snapshot.lastSuccessEpoch.map {
                Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened)
            } ?? "never"
            let changes = snapshot.unacknowledgedSecurityEventCount
            let changeSuffix = changes > 0 ? " · \(changes) unacknowledged change(s)" : ""
            return "\(snapshot.destinationLabel): \(snapshot.state.rawValue) · last success \(last)\(changeSuffix)"
        }
    }

    static func ledgerLines() async throws -> [String] {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        let entries = try await store.transact { tx in
            try tx.loadLedger()
        }
        let verification = await LedgerHeadSealRecordFile.verify(
            entries: entries,
            seal: ledgerHeadSeal(),
            url: root.appendingPathComponent("ledger-head-seal.json")
        )
        var lines: [String]
        switch verification {
        case .valid(let head, let count):
            let shortHead = head == LedgerChain.genesisHash ? "genesis" : String(head.prefix(12))
            lines = ["Chain and device seal valid · \(count) entries · head \(shortHead)"]
        case .chainInvalid(let sequence):
            lines = ["WARNING: chain verification failed at sequence \(sequence)"]
        case .sealMissing:
            lines = ["WARNING: ledger head has not been device-sealed"]
        case .headMismatch:
            lines = ["WARNING: sealed head does not match the ledger"]
        case .identityChanged:
            lines = ["WARNING: ledger identity changed"]
        }
        lines.append(contentsOf: entries.suffix(50).reversed().map { entry in
            let date = Date(timeIntervalSince1970: entry.wallTimeEpoch)
                .formatted(date: .abbreviated, time: .shortened)
            return "\(date) · \(entry.destination) · \(entry.outcomeKind) · \(entry.sampleCount) records · \(entry.byteCount) bytes"
        })
        return lines
    }

    static func ledgerIntegrityLine() async throws -> String {
        let lines = try await ledgerLines()
        return lines.first ?? "Ledger has not been written yet."
    }

    static func historyLines() async throws -> [String] {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let events = try await store.transact { try $0.loadJournal() }
        return RunHistory.problemsFirst(events).map { event in
            let date = Date(timeIntervalSince1970: event.wallTimeEpoch)
                .formatted(date: .abbreviated, time: .shortened)
            let error = event.errorClass.map { " · \($0)" } ?? ""
            return "\(date) · \(event.outcomeKind)\(error) · "
                + "\(event.samplesAcked)/\(event.samplesCommitted) acknowledged"
        }
    }

    static func wakeAttributionLine() async throws -> String {
        let snapshots = StatusSnapshotLocation.readAll()
        guard let expected = snapshots.compactMap(\.nextAttemptLatestEpoch).min() else {
            return "Wake attribution: no measured delivery deadline is configured."
        }
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let journal = try await store.transact { try $0.loadJournal() }
        let attribution = WakeAttribution.classify(
            wakes: try wakeLedger().records(),
            lastJournal: journal.last,
            nowEpoch: Date().timeIntervalSince1970,
            expectedWakeByEpoch: expected
        )
        switch attribution {
        case .none:
            return "Wake attribution: no overdue scheduling or execution failure."
        case .scheduling:
            return "Wake attribution: iOS did not wake the app by the measured deadline."
        case .execution:
            return "Wake attribution: the app woke, but export did not finish successfully."
        }
    }

    static func acknowledgeDestinationChanges() throws {
        let now = Date().timeIntervalSince1970
        for snapshot in StatusSnapshotLocation.readAll() where snapshot.unacknowledgedSecurityEventCount > 0 {
            guard let url = StatusSnapshotLocation.url(destinationID: snapshot.destinationID) else {
                continue
            }
            try DestinationSnapshotFile.acknowledgeSecurityEvents(writtenAtEpoch: now, at: url)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }

    static func enableHTTPSDestination(
        urlString: String,
        allowInsecureHTTP: Bool,
        bearer: String?
    ) async throws -> [String] {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            throw EgressError.invalidURL
        }
        let allowedHosts: Set<String> = [host]
        let destination = try HTTPSDestination(
            urlString: urlString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecureHTTP,
            authorizationBearer: bearer
        )
        let transport = try SystemHTTPTransport.make(
            probing: destination.url,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: allowInsecureHTTP
        )
        let now = Date().ISO8601Format()
        let completed = try await HTTPSDestinationEnable.complete(
            destination: destination,
            transport: transport,
            exporterID: try installationID(),
            emittedAt: now
        )
        let record = HTTPSVerificationRecord(
            urlString: destination.url.absoluteString,
            allowedHosts: allowedHosts.sorted(),
            allowInsecureHTTP: allowInsecureHTTP,
            report: completed.report,
            leafSPKISha256: completed.identity?.leafSPKISha256,
            issuerSPKISha256: completed.identity?.issuerSPKISha256,
            firstSeen: now,
            hasBearer: bearer != nil
        )
        let root = try applicationSupportRoot()
        let bearerStore = KeychainSecretStore(
            service: "app.openhealthexporter.ios.https"
        )
        let bearerHandle = SecretHandle(rawValue: "bearer")
        if let bearer {
            try await bearerStore.store(Array(bearer.utf8), handle: bearerHandle)
        } else {
            try? await bearerStore.delete(bearerHandle)
        }
        try JSONEncoder().encode(record).write(
            to: root.appendingPathComponent("https-destination.json"),
            options: .atomic
        )
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "https") {
            try DestinationSnapshotFile.recordSecurityEvents(
                completed.events.count,
                destinationID: "https",
                destinationLabel: host,
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        try await emitTrustNotices(completed.events, destination: host)
        if allowInsecureHTTP {
            let store = try SQLiteStateStore(
                path: root.appendingPathComponent("state.sqlite").path
            )
            try await store.transact { tx in
                try tx.appendLedger(
                    EgressEntry(
                        destination: host,
                        sampleCount: 0,
                        outcomeKind: "security:insecure_http_enabled",
                        detail: "explicit_user_opt_in",
                        wallTimeEpoch: Date().timeIntervalSince1970
                    )
                )
            }
        }
        var lines = completed.report.steps.map {
            "\($0.name.rawValue): \($0.outcome.rawValue)"
        }
        if let identity = completed.identity {
            lines.append("TLS \(identity.tlsVersion) · \(identity.cipherSuite)")
            lines.append("Leaf SPKI \(identity.groupedLeafFingerprint)")
            lines.append("Subject \(identity.leafSubject)")
            lines.append("Issuer \(identity.leafIssuer)")
        } else {
            lines.append("Plain HTTP enabled by explicit opt-in.")
        }
        return lines
    }

    static func enableMQTTDestination(
        urlString: String,
        allowInsecure: Bool,
        clientID: String,
        topic: String
    ) async throws -> [String] {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            throw EgressError.invalidURL
        }
        let allowedHosts: Set<String> = [host]
        let destination = try MQTTDestination(
            urlString: urlString,
            allowedHosts: allowedHosts,
            allowInsecure: allowInsecure,
            clientID: clientID,
            topic: topic
        )
        let sink = try MQTTSink.overNetwork(destination: destination, pin: nil)
        let now = Date().ISO8601Format()
        let completed = try await MQTTDestinationEnable.complete(
            destination: destination,
            pipe: sink.pipe,
            exporterID: try installationID(),
            emittedAt: now
        )
        let record = MQTTVerificationRecord(
            urlString: destination.url.absoluteString,
            allowedHosts: allowedHosts.sorted(),
            allowInsecure: allowInsecure,
            clientID: clientID,
            topic: topic,
            report: completed.report
        )
        let root = try applicationSupportRoot()
        try JSONEncoder().encode(record).write(
            to: root.appendingPathComponent("mqtt-destination.json"),
            options: .atomic
        )
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "mqtt") {
            try DestinationSnapshotFile.recordSecurityEvents(
                completed.events.count,
                destinationID: "mqtt",
                destinationLabel: host,
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        try await emitTrustNotices(completed.events, destination: host)
        if allowInsecure {
            let store = try SQLiteStateStore(
                path: root.appendingPathComponent("state.sqlite").path
            )
            try await store.transact { tx in
                try tx.appendLedger(
                    EgressEntry(
                        destination: host,
                        sampleCount: 0,
                        outcomeKind: "security:insecure_mqtt_enabled",
                        detail: "explicit_user_opt_in",
                        wallTimeEpoch: Date().timeIntervalSince1970
                    )
                )
            }
        }
        return completed.report.steps.map { "\($0.name.rawValue): \($0.outcome.rawValue)" }
    }

    static func runMQTTDestination() async throws -> [String] {
        let root = try applicationSupportRoot()
        let data = try Data(
            contentsOf: root.appendingPathComponent("mqtt-destination.json")
        )
        let saved = try JSONDecoder().decode(MQTTVerificationRecord.self, from: data)
        let allowedHosts = Set(saved.allowedHosts)
        let destination = try MQTTDestination(
            urlString: saved.urlString,
            allowedHosts: allowedHosts,
            allowInsecure: saved.allowInsecure,
            clientID: saved.clientID,
            topic: saved.topic
        )
        let sink = try MQTTSink.overNetwork(destination: destination, pin: nil)
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: saved.report)
        let verified = try setup.enable(sink: sink)
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratch,
            withIntermediateDirectories: true
        )
        let context = TemporalContext.utcHost
        let source = HealthKitAnchoredSource(context: context, limit: 1000)
        let now = Date().ISO8601Format()
        let exporterID = try installationID()
        var lines: [String] = []
        for metric in selectedMetrics() {
            let outcome = try await ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "mqtt",
                envelope: WireEnvelope(
                    exporterId: exporterID,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: HealthKitStatisticsSource(context: context),
                observations: HealthKitDayObservationSource(context: context),
                trigger: .manual,
                snapshotURL: StatusSnapshotLocation.url(destinationID: "mqtt"),
                ledgerHeadSeal: ledgerHeadSeal(),
                ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json")
            ).run()
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return lines
    }

    static func runHTTPSDestination() async throws -> [String] {
        let root = try applicationSupportRoot()
        let data = try Data(
            contentsOf: root.appendingPathComponent("https-destination.json")
        )
        let saved = try JSONDecoder().decode(HTTPSVerificationRecord.self, from: data)
        let allowedHosts = Set(saved.allowedHosts)
        let bearer: String?
        if saved.hasBearer {
            bearer = String(
                decoding: try await KeychainSecretStore(
                    service: "app.openhealthexporter.ios.https"
                ).load(SecretHandle(rawValue: "bearer")),
                as: UTF8.self
            )
        } else {
            bearer = nil
        }
        let destination = try HTTPSDestination(
            urlString: saved.urlString,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: saved.allowInsecureHTTP,
            authorizationBearer: bearer
        )
        let base = try SystemHTTPTransport.make(
            probing: destination.url,
            allowedHosts: allowedHosts,
            allowInsecureHTTP: saved.allowInsecureHTTP
        )
        let transport: any HTTPTransport
        if let leaf = saved.leafSPKISha256, let issuer = saved.issuerSPKISha256 {
            transport = PinningHTTPTransport(
                inner: base,
                pin: PinRecord(
                    leafSPKISha256: leaf,
                    issuerSPKISha256: issuer,
                    firstSeen: saved.firstSeen,
                    policy: .leaf
                )
            )
        } else {
            transport = base
        }
        var setup = DestinationSetup()
        try setup.resumeEnabled(testReport: saved.report)
        let verified = try setup.enable(
            sink: HTTPSSink(destination: destination, transport: transport)
        )
        let store = try SQLiteStateStore(
            path: root.appendingPathComponent("state.sqlite").path
        )
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratch,
            withIntermediateDirectories: true
        )
        let context = TemporalContext.utcHost
        let source = HealthKitAnchoredSource(context: context, limit: 1000)
        let now = Date().ISO8601Format()
        let exporterID = try installationID()
        var lines: [String] = []
        for metric in selectedMetrics() {
            let outcome = try await ExportRun(
                source: source,
                destination: verified,
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "https",
                envelope: WireEnvelope(
                    exporterId: exporterID,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                ),
                temporal: context,
                statistics: HealthKitStatisticsSource(context: context),
                observations: HealthKitDayObservationSource(context: context),
                trigger: .manual,
                snapshotURL: StatusSnapshotLocation.url(destinationID: "https"),
                ledgerHeadSeal: ledgerHeadSeal(),
                ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json")
            ).run()
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return lines
    }

    static func enableLocalFileDestination() async throws -> [String] {
        let root = try applicationSupportRoot()
        let dest = root.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: localFileTestReportURL(root: root))
        let (_, events) = try verifiedLocalFile(root: root, destinationDirectory: dest)
        try await emitTrustNotices(events)
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return destinationStatusLines()
    }

    static func stopExportingHeartRate() async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        try await store.purgeType(
            metric: MetricCatalog.heartRate.id,
            reason: "explicit_stop",
            destination: "local-file",
            atEpoch: Date().timeIntervalSince1970
        )
    }

    static func expireQueuesAndNotify() async throws -> QueueExpiryResult {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        let now = Date().timeIntervalSince1970
        let result = try await store.expirePending(
            nowEpoch: now,
            destination: "configured destinations"
        )
        guard result.expiredBatches > 0 else { return result }
        let entries = try await store.transact { try $0.loadLedger() }
        try await LedgerHeadSealRecordFile.update(
            entries: entries,
            seal: ledgerHeadSeal(),
            sealedAtEpoch: now,
            url: root.appendingPathComponent("ledger-head-seal.json")
        )
        _ = try await LocalUserNotifier().notify(
            UserNotice(kind: .queueExpired, destination: "Configured destinations")
        )
        return result
    }

    static func wipeEverything() async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        try await DestructiveWipe.perform(
            store: store,
            secretStores: [
                KeychainSecretStore(service: "app.openhealthexporter.ios.psk"),
                KeychainSecretStore(service: "app.openhealthexporter.ios.https"),
            ],
            ledgerSeal: resettableLedgerHeadSeal(),
            ledgerSealURL: root.appendingPathComponent("ledger-head-seal.json"),
            atEpoch: Date().timeIntervalSince1970
        )
        try? FileManager.default.removeItem(at: localFileTestReportURL(root: root))
        try? FileManager.default.removeItem(at: companionTestReportURL(root: root))
        try await vault().forget()
        if let directory = StatusSnapshotLocation.directory() {
            try? FileManager.default.removeItem(at: directory)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }

    private static func verifiedLocalFile(
        root: URL,
        destinationDirectory: URL
    ) throws -> (VerifiedDestination, [TrustEvent]) {
        let reportURL = localFileTestReportURL(root: root)
        if let saved = try? Data(contentsOf: reportURL),
           let report = try? JSONDecoder().decode(DestinationTestReport.self, from: saved),
           report.allowsEnablement {
            return (
                try LocalFileDestinationEnable.resume(
                    directory: destinationDirectory,
                    testReport: report
                ),
                []
            )
        }
        let completed = try LocalFileDestinationEnable.complete(
            directory: destinationDirectory,
            exporterId: try installationID(),
            emittedAt: Date().ISO8601Format()
        )
        try JSONEncoder().encode(completed.report).write(to: reportURL, options: .atomic)
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "local-file") {
            try DestinationSnapshotFile.recordSecurityEvents(
                completed.events.count,
                destinationID: "local-file",
                destinationLabel: "This iPhone → Archive folder",
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        return (completed.destination, completed.events)
    }

    private static func emitTrustNotices(_ events: [TrustEvent]) async throws {
        try await emitTrustNotices(events, destination: "local-file")
    }

    private static func emitTrustNotices(
        _ events: [TrustEvent],
        destination: String
    ) async throws {
        guard !events.isEmpty else { return }
        let notifier = LocalUserNotifier()
        for event in events {
            _ = try await notifier.notify(TrustNotice.notice(for: event, destination: destination))
        }
    }

    private static func localFileTestReportURL(root: URL) -> URL {
        root.appendingPathComponent("local-file-test.json")
    }

    static func isLocalFileEnabled() -> Bool {
        guard let root = try? applicationSupportRoot(),
              let data = try? Data(contentsOf: localFileTestReportURL(root: root)),
              let report = try? JSONDecoder().decode(DestinationTestReport.self, from: data)
        else {
            return false
        }
        return report.allowsEnablement
    }

    static func wakeLedger() throws -> WakeLedger {
        let root = try applicationSupportRoot()
        return WakeLedger(path: root.appendingPathComponent("wake-ledger.log").path)
    }

    @discardableResult
    static func observeAuthorizationChanges() async throws -> Bool {
        let root = try applicationSupportRoot()
        let grant = HealthAuthorizationGrant(
            id: "core-activity",
            metrics: selectedMetrics()
        )
        let observer = HealthAuthorizationObserver(
            recordURL: root.appendingPathComponent("health-authorization.json")
        )
        let changes = try await observer.observe(
            grants: [grant],
            atEpoch: Date().timeIntervalSince1970
        )
        guard !changes.isEmpty else { return false }

        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        for change in changes {
            for metric in change.grant.metrics {
                try await store.purgeType(
                    metric: metric,
                    reason: "authorization_revoked:\(change.grant.id)",
                    destination: "local-file",
                    atEpoch: change.observedAtEpoch
                )
            }
            await HealthKitBackgroundDelivery.disable(metrics: change.grant.metrics)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
        return true
    }

    static func reenableCoreActivityAfterAuthorizationRequest() async throws {
        let root = try applicationSupportRoot()
        let store = try SQLiteStateStore(path: root.appendingPathComponent("state.sqlite").path)
        for metric in selectedMetrics() {
            try await store.reenableType(
                metric: metric,
                reason: "user_requested_core_activity"
            )
        }
    }

    static func startHealthObservers() async throws -> HealthKitObserverCoordinator {
        let coordinator = HealthKitObserverCoordinator(
            wakeLedger: try wakeLedger()
        )
        try await coordinator.start(
            metrics: selectedMetrics()
        ) { metric in
            try? await observeAuthorizationChanges()
            await ObserverExportGate.shared.enqueue(metric)
        }
        return coordinator
    }

    private static func companionTestReportURL(root: URL) -> URL {
        root.appendingPathComponent("companion-test.json")
    }

    private static func ledgerHeadSeal() -> any LedgerHeadSeal {
        resettableLedgerHeadSeal()
    }

    private static func resettableLedgerHeadSeal() -> any ResettableLedgerHeadSeal {
        #if targetEnvironment(simulator)
        SecureEnclaveLedgerSeal(useSecureEnclave: false, permanent: true)
        #else
        SecureEnclaveLedgerSeal()
        #endif
    }

    static func vault() throws -> PairingVault {
        let root = try applicationSupportRoot()
        return PairingVault(
            store: KeychainSecretStore(service: "app.openhealthexporter.ios.psk"),
            recordFile: root.appendingPathComponent("pairing.json")
        )
    }

    static func forgetCompanion() async throws {
        let root = try applicationSupportRoot()
        try await vault().forget()
        try? FileManager.default.removeItem(at: companionTestReportURL(root: root))
        let event = TrustEvent.trustLost
        if let snapshotURL = StatusSnapshotLocation.url(destinationID: "companion") {
            try DestinationSnapshotFile.recordSecurityEvents(
                1,
                destinationID: "companion",
                destinationLabel: "Mac companion",
                enabled: false,
                state: .blocked,
                writtenAtEpoch: Date().timeIntervalSince1970,
                at: snapshotURL
            )
        }
        try await emitTrustNotices([event], destination: "companion")
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }
}
