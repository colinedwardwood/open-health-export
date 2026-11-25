// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CompanionWire
import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import FileWriteKit
import Foundation
import NetEgress
#if !OHE_OBS25_SIZE_BASELINE
import OTLPExport
#endif
import SinkCompanion
import SinkHTTP
import SinkLocalFile
import SinkMQTT
import StorageSQLite
import Watchdog
import WidgetKit

// MARK: Storage adapters

/// The setup sidecars in Application Support. The MQTT client certificate and the
/// OTLP record live beside the verification records.
struct DestinationSetupFileStore: DestinationSetupFiles {
    let root: @Sendable () throws -> URL

    static let mqttClientCertificate = "mqtt-client.p12"
    static let otlpRecord = "otlp-destination.json"

    func httpsRecord(_ destinationID: String) -> HTTPSVerificationRecord? {
        read(HTTPSVerificationRecord.self, DestinationSidecar.httpsRecord(destinationID: destinationID).filename)
    }

    func writeHTTPSRecord(_ record: HTTPSVerificationRecord, destinationID: String) throws {
        try write(record, DestinationSidecar.httpsRecord(destinationID: destinationID).filename)
    }

    func mqttRecord() -> MQTTVerificationRecord? {
        read(MQTTVerificationRecord.self, DestinationSidecar.mqttRecord.filename)
    }

    func writeMQTTRecord(_ record: MQTTVerificationRecord) throws {
        try write(record, DestinationSidecar.mqttRecord.filename)
    }

    func writeMQTTClientCertificate(_ pkcs12: Data?) throws {
        let url = try root().appendingPathComponent(Self.mqttClientCertificate)
        if let pkcs12 {
            try pkcs12.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func companionRecord() -> CompanionVerificationRecord? {
        read(CompanionVerificationRecord.self, DestinationSidecar.companionTestReport.filename)
    }

    func writeCompanionRecord(_ record: CompanionVerificationRecord) throws {
        try write(record, DestinationSidecar.companionTestReport.filename)
    }

    func removeCompanionRecord() {
        remove(DestinationSidecar.companionTestReport.filename)
    }

    func localFileTestReport() -> DestinationTestReport? {
        read(DestinationTestReport.self, DestinationSidecar.localFileTestReport.filename)
    }

    func writeLocalFileTestReport(_ report: DestinationTestReport) throws {
        try write(report, DestinationSidecar.localFileTestReport.filename)
    }

    func removeLocalFileTestReport() {
        remove(DestinationSidecar.localFileTestReport.filename)
    }

    func otlpRecord() -> OTLPDestinationRecord? {
        read(OTLPDestinationRecord.self, Self.otlpRecord)
    }

    func writeOTLPRecord(_ record: OTLPDestinationRecord) throws {
        try write(record, Self.otlpRecord)
    }

    func removeOTLPRecord() {
        remove(Self.otlpRecord)
    }

    private func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let root = try? root(),
              let data = try? Data(contentsOf: root.appendingPathComponent(name))
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) throws {
        try JSONEncoder().encode(value).write(
            to: try root().appendingPathComponent(name),
            options: .atomic
        )
    }

    private func remove(_ name: String) {
        guard let root = try? root() else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
    }
}

/// Status snapshots in the shared container, and the widget that reads them.
struct SharedContainerSetupSnapshots: SetupStatusSnapshots {
    func readAll() -> [DestinationStatusSnapshot] {
        StatusSnapshotLocation.readAll()
    }

    func recordSecurityEvents(
        _ count: Int,
        destinationID: String,
        destinationLabel: String?,
        enabled: Bool?,
        state: DestinationDisplayState?,
        writtenAtEpoch: TimeInterval
    ) throws {
        guard let url = StatusSnapshotLocation.url(destinationID: destinationID) else { return }
        try DestinationSnapshotFile.recordSecurityEvents(
            count,
            destinationID: destinationID,
            destinationLabel: destinationLabel,
            enabled: enabled,
            state: state,
            writtenAtEpoch: writtenAtEpoch,
            at: url
        )
    }

    func write(_ snapshot: DestinationStatusSnapshot) throws {
        guard let url = StatusSnapshotLocation.url(destinationID: snapshot.destinationID) else { return }
        try DestinationSnapshotFile.write(snapshot, to: url)
    }

    func remove(destinationID: String) {
        guard let url = StatusSnapshotLocation.url(destinationID: destinationID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func reloadStatusWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: "ExportStatusWidget")
    }
}
