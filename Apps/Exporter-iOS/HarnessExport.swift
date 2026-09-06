import CompanionWire
import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import DiagnosticBundle
import Foundation
import HealthKitSource
import MetricCatalog
import NetEgress
import SinkCompanion
import SinkLocalFile
import StorageSQLite
import UIKit
import WireFormat

enum HarnessExport {
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

    static func runOnePageEachMetric() async throws -> [String] {
        let fm = FileManager.default
        let root = try applicationSupportRoot()
        let sqliteURL = root.appendingPathComponent("state.sqlite")
        let dest = root.appendingPathComponent("exports", isDirectory: true)
        let scratch = root.appendingPathComponent("scratch", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)

        let store = try SQLiteStateStore(path: sqliteURL.path)
        let sink = LocalFileSink(directory: dest)
        let context = TemporalContext(
            timeZoneIdentifier: "UTC",
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "host"
        )
        let source = HealthKitSampleSource(context: context, limit: 1000)
        let now = Date().ISO8601Format()
        let exporterId = try installationID()

        var lines: [String] = []
        for metric in [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id] {
            let run = ExportRun(
                source: source,
                destination: .testing(sink),
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "local-file",
                envelope: WireEnvelope(
                    exporterId: exporterId,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                )
            )
            let outcome = try await run.run()
            lines.append("\(metric.rawValue): \(outcome.kind.rawValue)")
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
        let stream = NWByteStream(
            service: discovered,
            options: NWByteStream.Options(requireTLS13: true, failFastOnWaiting: true, preSharedKey: psk)
        )
        let sink = CompanionSink(
            pipe: ByteStreamCompanionPipe(stream: stream),
            installationID: session.localInstallationID
        )
        let context = TemporalContext(
            timeZoneIdentifier: "UTC",
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "host"
        )
        let source = HealthKitSampleSource(context: context, limit: 1000)
        let now = Date().ISO8601Format()
        var lines: [String] = []
        for metric in [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id] {
            let run = ExportRun(
                source: source,
                destination: .testing(sink),
                store: store,
                metric: metric,
                scratchDirectory: scratch,
                destinationName: "companion",
                envelope: WireEnvelope(
                    exporterId: session.localInstallationID,
                    seq: 1,
                    emittedAt: now,
                    observedAt: now
                )
            )
            let outcome = try await run.run()
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

    static func diagnosticBundle() throws -> (preview: String, payload: Data) {
        let assembler = BundleAssembler()
        let payload = try assembler.assemble(
            header: DiagnosticHeader(
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
                osVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.current.model,
                localeIdentifier: Locale.current.identifier,
                utcOffsetMinutes: TimeZone.current.secondsFromGMT() / 60,
                generatedAt: Date().ISO8601Format()
            ),
            events: []
        )
        let text = String(decoding: payload, as: UTF8.self)
        let lines = assembler.previewLines(events: [])
        let preview = lines.isEmpty ? text : lines.joined(separator: "\n") + "\n\n" + text
        return (preview, payload)
    }

    static func vault() throws -> PairingVault {
        let root = try applicationSupportRoot()
        return PairingVault(
            store: KeychainSecretStore(service: "app.openhealthexporter.ios.psk"),
            recordFile: root.appendingPathComponent("pairing.json")
        )
    }
}
