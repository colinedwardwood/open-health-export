import CoreDomain
import Foundation
import MetricCatalog

public struct WireEnvelope: Sendable, Equatable {
    public var exporterId: String
    public var seq: Int
    public var emittedAt: String
    public var observedAt: String
    public var reason: String
    public var producerName: String
    public var producerVersion: String
    public var mode: String
    public var spec: String
    public var specVersion: String
    public var demo: Bool

    public init(
        exporterId: String,
        seq: Int,
        emittedAt: String,
        observedAt: String,
        reason: String = "delta",
        producerName: String = "open-health-exporter",
        producerVersion: String = "0.1.0",
        mode: String = "samples",
        spec: String = "ohe.wire/1",
        specVersion: String = "1.0",
        demo: Bool = false
    ) {
        self.exporterId = exporterId
        self.seq = seq
        self.emittedAt = emittedAt
        self.observedAt = observedAt
        self.reason = reason
        self.producerName = producerName
        self.producerVersion = producerVersion
        self.mode = mode
        self.spec = spec
        self.specVersion = specVersion
        self.demo = demo
    }
}

public enum NativeWire {
    public static func batchID(metric: MetricID, anchorBlob: Data) -> BatchID {
        var material = Data(metric.rawValue.utf8)
        material.append(0)
        material.append(anchorBlob)
        let digest = SHA256.hash(material)
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        let id = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        return BatchID(rawValue: String(id))
    }

    public static let demoFilePrefix = "DEMO-"

    public static func outputFileName(batchID: BatchID, demo: Bool) -> String {
        "\(demo ? demoFilePrefix : "")\(batchID.rawValue).ndjson"
    }

    public static func payloadIsDemo(_ data: Data) -> Bool {
        guard let first = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first else {
            return false
        }
        return first.contains("\"demo\":true")
    }

    public static func countRecords(in text: String) -> Int {
        text.split(whereSeparator: \.isNewline).filter { line in
            if line.isEmpty { return false }
            if line.contains("\"kind\":\"batch.header\"") { return false }
            if line.contains("\"kind\":\"batch.footer\"") { return false }
            return true
        }.count
    }

    public static func encode(
        samples: [SampleRecord],
        tombstones: [TombstoneRecord],
        aggregates: [AggregateRecord] = [],
        metric: MetricID,
        batchID: BatchID,
        envelope: WireEnvelope
    ) throws -> Data {
        let sampleLines = try samples
            .sorted { lhs, rhs in
                (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
            }
            .map { try encodeQuantity($0, metric: metric, envelope: envelope) }
        let tombLines = try tombstones
            .sorted { $0.key.uuid.lowercased() < $1.key.uuid.lowercased() }
            .map { try encodeTombstone($0, metric: metric, envelope: envelope) }
        let aggregateLines = try aggregates
            .sorted { lhs, rhs in
                (lhs.bucketStart, lhs.bucketKey) < (rhs.bucketStart, rhs.bucketKey)
            }
            .map { try encodeAggregate($0, envelope: envelope) }
        let records = sampleLines + tombLines + aggregateLines
        var body = Data()
        for line in records {
            body.append(contentsOf: line.utf8)
            body.append(0x0A)
        }
        let digest = "sha256:" + SHA256.hex(body)
        let header = try encodeHeader(
            batchID: batchID,
            envelope: envelope,
            types: [wireMetricID(metric)],
            recordCount: records.count
        )
        let footer = try encodeFooter(
            batchID: batchID,
            sampleCount: samples.count,
            tombstoneCount: tombstones.count,
            canaryCount: 0,
            digest: digest,
            aggregateCount: aggregates.count
        )
        var out = Data()
        out.append(contentsOf: header.utf8)
        out.append(0x0A)
        out.append(body)
        out.append(contentsOf: footer.utf8)
        out.append(0x0A)
        return out
    }

    public static func encode(_ sample: SampleRecord, envelope: WireEnvelope) throws -> String {
        try encodeQuantity(sample, metric: sample.metric, envelope: envelope)
    }

    public static func encodeCanary(code: String, batchID: BatchID, envelope: WireEnvelope) throws -> Data {
        var canaryEnvelope = envelope
        canaryEnvelope.reason = "destinationTest"
        let line = try encodeCanaryLine(code: code, envelope: canaryEnvelope)
        var body = Data()
        body.append(contentsOf: line.utf8)
        body.append(0x0A)
        let digest = "sha256:" + SHA256.hex(body)
        let header = try encodeHeader(
            batchID: batchID,
            envelope: canaryEnvelope,
            types: [],
            recordCount: 1
        )
        let footer = try encodeFooter(
            batchID: batchID,
            sampleCount: 0,
            tombstoneCount: 0,
            canaryCount: 1,
            digest: digest
        )
        var out = Data()
        out.append(contentsOf: header.utf8)
        out.append(0x0A)
        out.append(body)
        out.append(contentsOf: footer.utf8)
        out.append(0x0A)
        return out
    }
}

public enum WireError: Error, Equatable {
    case utf8
    case nonFiniteNumber
    case invertedInterval
}

private extension NativeWire {
    static func encodeHeader(
        batchID: BatchID,
        envelope: WireEnvelope,
        types: [String],
        recordCount: Int
    ) throws -> String {
        var object: [String: CanonicalJSON] = [
            "batchId": .string(batchID.rawValue),
            "emittedAt": .string(envelope.emittedAt),
            "exporterId": .string(envelope.exporterId),
            "kind": .string("batch.header"),
            "mode": .string(envelope.mode),
            "producer": .object([
                "name": .string(envelope.producerName),
                "version": .string(envelope.producerVersion),
            ]),
            "reason": .string(envelope.reason),
            "recordCount": .integer(recordCount),
            "seq": .integer(envelope.seq),
            "spec": .string(envelope.spec),
            "specVersion": .string(envelope.specVersion),
            "types": .array(types.map { .string($0) }),
        ]
        if envelope.demo {
            object["demo"] = .bool(true)
        }
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeFooter(
        batchID: BatchID,
        sampleCount: Int,
        tombstoneCount: Int,
        canaryCount: Int,
        digest: String,
        aggregateCount: Int = 0
    ) throws -> String {
        var counts: [String: CanonicalJSON] = [:]
        if sampleCount > 0 {
            counts["sample.quantity"] = .integer(sampleCount)
        }
        if tombstoneCount > 0 {
            counts["tombstone"] = .integer(tombstoneCount)
        }
        if aggregateCount > 0 {
            counts["aggregate"] = .integer(aggregateCount)
        }
        if canaryCount > 0 {
            counts["canary"] = .integer(canaryCount)
        }
        let json: CanonicalJSON = .object([
            "batchId": .string(batchID.rawValue),
            "complete": .bool(true),
            "contentDigest": .string(digest),
            "counts": .object(counts),
            "kind": .string("batch.footer"),
        ])
        return try json.serialized()
    }

    static func encodeQuantity(_ sample: SampleRecord, metric: MetricID, envelope: WireEnvelope) throws -> String {
        if sample.end < sample.start {
            throw WireError.invertedInterval
        }
        let decl = MetricCatalog.declaration(for: metric)
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "end": .string(sample.end),
            "hkIdentifier": .string(decl?.hkIdentifier ?? metric.rawValue),
            "kind": .string("sample.quantity"),
            "metricId": .string(decl?.wireId ?? metric.rawValue),
            "observedAt": .string(sample.observedAt),
            "semantics": .string(decl == nil ? "unmapped" : "curated"),
            "start": .string(sample.start),
            "tzOffsetMinutes": .integer(sample.timeZoneOffsetMinutes),
            "tzSource": .string(sample.timeZoneSource.rawValue),
            "unit": .string(decl?.wireUnit ?? sample.unit.symbol),
            "uuid": .string(sample.key.uuid.lowercased()),
            "v": .integer(1),
            "value": .number(sample.value),
        ]
        if envelope.demo {
            object["demo"] = .bool(true)
        }
        if let source = sample.source {
            var sourceObject: [String: CanonicalJSON] = [
                "name": .string(source.name),
            ]
            if let bundleIdentifier = source.bundleIdentifier {
                sourceObject["bundleId"] = .string(bundleIdentifier)
            }
            if let productType = source.productType {
                sourceObject["productType"] = .string(productType)
            }
            object["source"] = .object(sourceObject)
        }
        if let device = sample.device {
            var deviceObject: [String: CanonicalJSON] = [:]
            if let name = device.name { deviceObject["name"] = .string(name) }
            if let manufacturer = device.manufacturer {
                deviceObject["manufacturer"] = .string(manufacturer)
            }
            if let model = device.model { deviceObject["model"] = .string(model) }
            if let hardwareVersion = device.hardwareVersion {
                deviceObject["hardwareVersion"] = .string(hardwareVersion)
            }
            if let softwareVersion = device.softwareVersion {
                deviceObject["softwareVersion"] = .string(softwareVersion)
            }
            if !deviceObject.isEmpty {
                object["device"] = .object(deviceObject)
            }
        }
        if let wasUserEntered = sample.wasUserEntered {
            object["wasUserEntered"] = .bool(wasUserEntered)
        }
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeTombstone(_ tomb: TombstoneRecord, metric: MetricID, envelope: WireEnvelope) throws -> String {
        let decl = MetricCatalog.declaration(for: metric)
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "bestEffort": .bool(true),
            "hkIdentifier": .string(decl?.hkIdentifier ?? metric.rawValue),
            "kind": .string("tombstone"),
            "metricId": .string(decl?.wireId ?? metric.rawValue),
            "observedAt": .string(envelope.observedAt),
            "reason": .string("healthKitDeleted"),
            "uuid": .string(tomb.key.uuid.lowercased()),
            "v": .integer(1),
        ]
        if envelope.demo {
            object["demo"] = .bool(true)
        }
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeAggregate(_ record: AggregateRecord, envelope: WireEnvelope) throws -> String {
        let decl = MetricCatalog.declaration(for: record.metric)
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "bucketDurationSeconds": .integer(record.bucketDurationSeconds),
            "bucketEnd": .string(record.bucketEnd),
            "bucketKey": .string(record.bucketKey),
            "bucketStart": .string(record.bucketStart),
            "computation": .string(record.computation.rawValue),
            "computedAt": .string(record.computedAt),
            "emitSeq": .integer(record.emitSeq),
            "granularity": .string(record.granularity),
            "kind": .string("aggregate"),
            "localStart": .string(record.localStart),
            "metricId": .string(decl?.wireId ?? record.metric.rawValue),
            "observedAt": .string(record.observedAt),
            "sampleCount": .integer(record.sampleCount),
            "sourceScope": .string(record.sourceScope.rawValue),
            "state": .string(record.state.rawValue),
            "statistic": .string(record.statistic.rawValue),
            "tzId": .string(record.timeZoneIdentifier),
            "unit": .string(decl?.wireUnit ?? record.unit.symbol),
            "v": .integer(1),
        ]
        if let value = record.value {
            object["value"] = .number(value)
        }
        if let supersedes = record.supersedes {
            object["supersedes"] = .integer(supersedes)
        }
        if envelope.demo {
            object["demo"] = .bool(true)
        }
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeCanaryLine(code: String, envelope: WireEnvelope) throws -> String {
        let json: CanonicalJSON = .object([
            "batchSeq": .integer(envelope.seq),
            "code": .string(code),
            "kind": .string("canary"),
            "observedAt": .string(envelope.observedAt),
            "v": .integer(1),
        ])
        return try json.serialized()
    }

    static func wireMetricID(_ metric: MetricID) -> String {
        MetricCatalog.declaration(for: metric)?.wireId ?? metric.rawValue
    }
}
