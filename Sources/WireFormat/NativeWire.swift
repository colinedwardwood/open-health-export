// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
    public var completeThrough: String?
    public var tzDatabaseVersion: String?

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
        demo: Bool = false,
        completeThrough: String? = nil,
        tzDatabaseVersion: String? = nil
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
        self.completeThrough = completeThrough
        self.tzDatabaseVersion = tzDatabaseVersion
    }
}

public enum NativeWire {
    public static func batchID(metric: MetricID, anchorBlob: Data) -> BatchID {
        batchID(metric: metric, anchorBlob: anchorBlob, aggregateVersions: [])
    }

    public static func batchID(
        metric: MetricID,
        anchorBlob: Data,
        aggregateVersions: [String]
    ) -> BatchID {
        var material = Data(metric.rawValue.utf8)
        material.append(0)
        material.append(anchorBlob)
        for version in aggregateVersions.sorted() {
            material.append(0)
            material.append(Data(version.utf8))
        }
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
        categories: [CategoryRecord] = [],
        correlations: [CorrelationRecord] = [],
        workouts: [WorkoutRecord] = [],
        minds: [StateOfMindRecord] = [],
        electrocardiograms: [ECGRecord] = [],
        audiograms: [AudiogramRecord] = [],
        medicationDoses: [MedicationDoseRecord] = [],
        series: [SeriesRecord] = [],
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
            .map { try encodeQuantity($0, metric: $0.metric, envelope: envelope) }
        let categoryLines = try categories
            .sorted { lhs, rhs in
                (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
            }
            .map { try encodeCategory($0, envelope: envelope) }
        let correlationLines = try correlations
            .sorted { $0.key.uuid.lowercased() < $1.key.uuid.lowercased() }
            .map { try encodeCorrelation($0, envelope: envelope) }
        let workoutLines = try workouts
            .sorted { lhs, rhs in
                (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
            }
            .map { try encodeWorkout($0, envelope: envelope) }
        let mindLines = try minds
            .sorted { lhs, rhs in
                (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
            }
            .map { try encodeStateOfMind($0, envelope: envelope) }
        let ecgLines = try electrocardiograms
            .sorted { lhs, rhs in
                (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
            }
            .map { try encodeECG($0, envelope: envelope) }
        let audiogramLines = try audiograms
            .sorted { lhs, rhs in
                (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
            }
            .map { try encodeAudiogram($0, envelope: envelope) }
        let doseLines = try medicationDoses
            .sorted { lhs, rhs in
                (lhs.start, lhs.key.uuid.lowercased()) < (rhs.start, rhs.key.uuid.lowercased())
            }
            .map { try encodeMedicationDose($0, envelope: envelope) }
        let seriesLines = try series
            .sorted { lhs, rhs in
                (lhs.parentUUID.lowercased(), lhs.payload.wireKind, lhs.chunkIndex)
                    < (rhs.parentUUID.lowercased(), rhs.payload.wireKind, rhs.chunkIndex)
            }
            .map { try encodeSeries($0, envelope: envelope) }
        let tombLines = try tombstones
            .sorted { $0.key.uuid.lowercased() < $1.key.uuid.lowercased() }
            .map { try encodeTombstone($0, metric: metric, envelope: envelope) }
        let aggregateLines = try aggregates
            .sorted { lhs, rhs in
                (lhs.bucketStart, lhs.bucketKey) < (rhs.bucketStart, rhs.bucketKey)
            }
            .map { try encodeAggregate($0, envelope: envelope) }
        let records = sampleLines + categoryLines + correlationLines
            + workoutLines + mindLines + ecgLines + audiogramLines + doseLines
            + seriesLines + tombLines + aggregateLines
        var body = Data()
        for line in records {
            body.append(contentsOf: line.utf8)
            body.append(0x0A)
        }
        let digest = "sha256:" + SHA256.hex(body)
        let header = try encodeHeader(
            batchID: batchID,
            envelope: envelope,
            types: Set(
                [wireMetricID(metric)]
                    + samples.map { wireMetricID($0.metric) }
                    + categories.map(\.metric.rawValue)
                    + correlations.map(\.metric.rawValue)
                    + workouts.map(\.metric.rawValue)
                    + minds.map(\.metric.rawValue)
                    + electrocardiograms.map(\.metric.rawValue)
                    + audiograms.map(\.metric.rawValue)
                    + medicationDoses.map(\.metric.rawValue)
            ).sorted(),
            recordCount: records.count
        )
        let footer = try encodeFooter(
            batchID: batchID,
            sampleCount: samples.count,
            categoryCount: categories.count,
            correlationCount: correlations.count,
            workoutCount: workouts.count,
            mindCount: minds.count,
            ecgCount: electrocardiograms.count,
            audiogramCount: audiograms.count,
            medicationCount: medicationDoses.count,
            seriesCounts: Dictionary(
                grouping: series,
                by: { $0.payload.wireKind }
            ).mapValues(\.count),
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

    public static func encode(_ category: CategoryRecord, envelope: WireEnvelope) throws -> String {
        try encodeCategory(category, envelope: envelope)
    }

    public static func encode(
        _ correlation: CorrelationRecord,
        envelope: WireEnvelope
    ) throws -> String {
        try encodeCorrelation(correlation, envelope: envelope)
    }

    public static func encode(_ workout: WorkoutRecord, envelope: WireEnvelope) throws -> String {
        try encodeWorkout(workout, envelope: envelope)
    }

    public static func encode(_ mind: StateOfMindRecord, envelope: WireEnvelope) throws -> String {
        try encodeStateOfMind(mind, envelope: envelope)
    }

    public static func encode(_ ecg: ECGRecord, envelope: WireEnvelope) throws -> String {
        try encodeECG(ecg, envelope: envelope)
    }

    public static func encode(_ audiogram: AudiogramRecord, envelope: WireEnvelope) throws -> String {
        try encodeAudiogram(audiogram, envelope: envelope)
    }

    public static func encode(_ dose: MedicationDoseRecord, envelope: WireEnvelope) throws -> String {
        try encodeMedicationDose(dose, envelope: envelope)
    }

    public static func encode(_ series: SeriesRecord, envelope: WireEnvelope) throws -> String {
        try encodeSeries(series, envelope: envelope)
    }

    public static func encode(
        _ tombstone: TombstoneRecord,
        envelope: WireEnvelope
    ) throws -> String {
        try encodeTombstone(
            tombstone,
            metric: tombstone.metric,
            envelope: envelope
        )
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
    case documentExceedsByteLimit
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
        if let completeThrough = envelope.completeThrough {
            object["completeThrough"] = .string(completeThrough)
        }
        if let tzDatabaseVersion = envelope.tzDatabaseVersion, !tzDatabaseVersion.isEmpty {
            object["tzDatabaseVersion"] = .string(tzDatabaseVersion)
        }
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeFooter(
        batchID: BatchID,
        sampleCount: Int,
        categoryCount: Int = 0,
        correlationCount: Int = 0,
        workoutCount: Int = 0,
        mindCount: Int = 0,
        ecgCount: Int = 0,
        audiogramCount: Int = 0,
        medicationCount: Int = 0,
        seriesCounts: [String: Int] = [:],
        tombstoneCount: Int,
        canaryCount: Int,
        digest: String,
        aggregateCount: Int = 0
    ) throws -> String {
        var counts: [String: CanonicalJSON] = [:]
        if sampleCount > 0 {
            counts["sample.quantity"] = .integer(sampleCount)
        }
        if categoryCount > 0 {
            counts["sample.category"] = .integer(categoryCount)
        }
        if correlationCount > 0 {
            counts["sample.correlation"] = .integer(correlationCount)
        }
        if workoutCount > 0 {
            counts["workout"] = .integer(workoutCount)
        }
        if mindCount > 0 {
            counts["sample.stateOfMind"] = .integer(mindCount)
        }
        if ecgCount > 0 {
            counts["sample.ecg"] = .integer(ecgCount)
        }
        if audiogramCount > 0 {
            counts["sample.audiogram"] = .integer(audiogramCount)
        }
        if medicationCount > 0 {
            counts["medicationDose"] = .integer(medicationCount)
        }
        for (kind, count) in seriesCounts.sorted(by: { $0.key < $1.key }) where count > 0 {
            counts[kind] = .integer(count)
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
        appendProvenance(
            source: sample.source,
            device: sample.device,
            wasUserEntered: sample.wasUserEntered,
            to: &object
        )
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeCategory(
        _ category: CategoryRecord,
        envelope: WireEnvelope
    ) throws -> String {
        if category.end < category.start {
            throw WireError.invertedInterval
        }
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "categoryName": .string(category.categoryName),
            "categoryValue": .integer(category.categoryValue),
            "end": .string(category.end),
            "hkIdentifier": .string(category.healthKitIdentifier),
            "kind": .string("sample.category"),
            "metricId": .string(category.metric.rawValue),
            "observedAt": .string(category.observedAt),
            "semantics": .string("unmapped"),
            "start": .string(category.start),
            "tzOffsetMinutes": .integer(category.timeZoneOffsetMinutes),
            "tzSource": .string(category.timeZoneSource.rawValue),
            "uuid": .string(category.key.uuid.lowercased()),
            "v": .integer(1),
        ]
        if let durationSeconds = category.durationSeconds {
            object["durationSeconds"] = .number(durationSeconds)
        }
        if envelope.demo {
            object["demo"] = .bool(true)
        }
        appendProvenance(
            source: category.source,
            device: category.device,
            wasUserEntered: category.wasUserEntered,
            to: &object
        )
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeCorrelation(
        _ correlation: CorrelationRecord,
        envelope: WireEnvelope
    ) throws -> String {
        if correlation.end < correlation.start {
            throw WireError.invertedInterval
        }
        let components: [CanonicalJSON] = correlation.components
            .sorted { $0.key.uuid.lowercased() < $1.key.uuid.lowercased() }
            .map {
                .object([
                    "hkIdentifier": .string($0.healthKitIdentifier),
                    "metricId": .string($0.metric.rawValue),
                    "unit": .string($0.unit.symbol),
                    "uuid": .string($0.key.uuid.lowercased()),
                    "value": .number($0.value),
                ])
            }
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "components": .array(components),
            "correlationType": .string(correlation.correlationType),
            "end": .string(correlation.end),
            "hkIdentifier": .string(correlation.healthKitIdentifier),
            "kind": .string("sample.correlation"),
            "metricId": .string(correlation.metric.rawValue),
            "observedAt": .string(correlation.observedAt),
            "start": .string(correlation.start),
            "tzOffsetMinutes": .integer(correlation.timeZoneOffsetMinutes),
            "tzSource": .string(correlation.timeZoneSource.rawValue),
            "uuid": .string(correlation.key.uuid.lowercased()),
            "v": .integer(1),
        ]
        if envelope.demo { object["demo"] = .bool(true) }
        appendProvenance(
            source: correlation.source,
            device: correlation.device,
            wasUserEntered: correlation.wasUserEntered,
            to: &object
        )
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeWorkout(
        _ workout: WorkoutRecord,
        envelope: WireEnvelope
    ) throws -> String {
        if workout.end < workout.start {
            throw WireError.invertedInterval
        }
        let totals = workout.totals.reduce(into: [String: CanonicalJSON]()) {
            $0[$1.key] = .object([
                "statistic": .string($1.value.statistic.rawValue),
                "unit": .string($1.value.unit.symbol),
                "value": .number($1.value.value),
            ])
        }
        let events: [CanonicalJSON] = workout.events
            .sorted { ($0.timestamp, $0.type) < ($1.timestamp, $1.type) }
            .map {
                .object([
                    "durationSeconds": .number($0.durationSeconds),
                    "t": .string($0.timestamp),
                    "type": .string($0.type),
                ])
            }
        var object: [String: CanonicalJSON] = [
            "activityType": .string(workout.activityType),
            "activityTypeRaw": .integer(workout.activityTypeRaw),
            "batchSeq": .integer(envelope.seq),
            "durationSeconds": .number(workout.durationSeconds),
            "end": .string(workout.end),
            "events": .array(events),
            "hasRoute": .bool(workout.hasRoute),
            "kind": .string("workout"),
            "metricId": .string(workout.metric.rawValue),
            "observedAt": .string(workout.observedAt),
            "seriesIncluded": .array(
                workout.seriesIncluded.sorted().map { .string($0) }
            ),
            "start": .string(workout.start),
            "totals": .object(totals),
            "tzOffsetMinutes": .integer(workout.timeZoneOffsetMinutes),
            "tzSource": .string(workout.timeZoneSource.rawValue),
            "uuid": .string(workout.key.uuid.lowercased()),
            "v": .integer(1),
        ]
        if let isIndoor = workout.isIndoor {
            object["isIndoor"] = .bool(isIndoor)
        }
        if envelope.demo { object["demo"] = .bool(true) }
        appendProvenance(
            source: workout.source,
            device: workout.device,
            wasUserEntered: workout.wasUserEntered,
            to: &object
        )
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeStateOfMind(
        _ mind: StateOfMindRecord,
        envelope: WireEnvelope
    ) throws -> String {
        if mind.end < mind.start { throw WireError.invertedInterval }
        var object: [String: CanonicalJSON] = [
            "associations": .array(mind.associations.sorted().map { .string($0) }),
            "batchSeq": .integer(envelope.seq),
            "end": .string(mind.end),
            "kind": .string("sample.stateOfMind"),
            "kindOfEntry": .string(mind.kindOfEntry),
            "labels": .array(mind.labels.sorted().map { .string($0) }),
            "metricId": .string(mind.metric.rawValue),
            "observedAt": .string(mind.observedAt),
            "start": .string(mind.start),
            "tzOffsetMinutes": .integer(mind.timeZoneOffsetMinutes),
            "tzSource": .string(mind.timeZoneSource.rawValue),
            "uuid": .string(mind.key.uuid.lowercased()),
            "v": .integer(1),
            "valence": .number(mind.valence),
            "valenceClassification": .string(mind.valenceClassification),
        ]
        if envelope.demo { object["demo"] = .bool(true) }
        appendProvenance(
            source: mind.source,
            device: mind.device,
            wasUserEntered: mind.wasUserEntered,
            to: &object
        )
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeECG(_ ecg: ECGRecord, envelope: WireEnvelope) throws -> String {
        if ecg.end < ecg.start { throw WireError.invertedInterval }
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "classification": .string(ecg.classification),
            "end": .string(ecg.end),
            "kind": .string("sample.ecg"),
            "metricId": .string(ecg.metric.rawValue),
            "observedAt": .string(ecg.observedAt),
            "samplingHz": .number(ecg.samplingHz),
            "start": .string(ecg.start),
            "tzOffsetMinutes": .integer(ecg.timeZoneOffsetMinutes),
            "tzSource": .string(ecg.timeZoneSource.rawValue),
            "uuid": .string(ecg.key.uuid.lowercased()),
            "v": .integer(1),
            "voltageCount": .integer(ecg.voltageCount),
        ]
        if let averageHeartRate = ecg.averageHeartRate {
            object["averageHeartRate"] = .number(averageHeartRate)
        }
        if let symptomsStatus = ecg.symptomsStatus {
            object["symptomsStatus"] = .string(symptomsStatus)
        }
        if envelope.demo { object["demo"] = .bool(true) }
        appendProvenance(
            source: ecg.source,
            device: ecg.device,
            wasUserEntered: ecg.wasUserEntered,
            to: &object
        )
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeAudiogram(
        _ audiogram: AudiogramRecord,
        envelope: WireEnvelope
    ) throws -> String {
        if audiogram.end < audiogram.start { throw WireError.invertedInterval }
        let points: [CanonicalJSON] = audiogram.sensitivityPoints
            .sorted { $0.frequencyHz < $1.frequencyHz }
            .map { point in
                var object: [String: CanonicalJSON] = [
                    "frequencyHz": .number(point.frequencyHz),
                ]
                if let leftEarDbHL = point.leftEarDbHL {
                    object["leftEarDbHL"] = .number(leftEarDbHL)
                }
                if let rightEarDbHL = point.rightEarDbHL {
                    object["rightEarDbHL"] = .number(rightEarDbHL)
                }
                if let leftEarMasked = point.leftEarMasked {
                    object["leftEarMasked"] = .bool(leftEarMasked)
                }
                if let rightEarMasked = point.rightEarMasked {
                    object["rightEarMasked"] = .bool(rightEarMasked)
                }
                return .object(object)
            }
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "end": .string(audiogram.end),
            "kind": .string("sample.audiogram"),
            "metricId": .string(audiogram.metric.rawValue),
            "observedAt": .string(audiogram.observedAt),
            "sensitivityPoints": .array(points),
            "start": .string(audiogram.start),
            "tzOffsetMinutes": .integer(audiogram.timeZoneOffsetMinutes),
            "tzSource": .string(audiogram.timeZoneSource.rawValue),
            "uuid": .string(audiogram.key.uuid.lowercased()),
            "v": .integer(1),
        ]
        if envelope.demo { object["demo"] = .bool(true) }
        appendProvenance(
            source: audiogram.source,
            device: audiogram.device,
            wasUserEntered: audiogram.wasUserEntered,
            to: &object
        )
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeMedicationDose(
        _ dose: MedicationDoseRecord,
        envelope: WireEnvelope
    ) throws -> String {
        if dose.end < dose.start { throw WireError.invertedInterval }
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "end": .string(dose.end),
            "kind": .string("medicationDose"),
            "medicationName": .string(dose.medicationName),
            "metricId": .string(dose.metric.rawValue),
            "observedAt": .string(dose.observedAt),
            "start": .string(dose.start),
            "status": .string(dose.status),
            "tzOffsetMinutes": .integer(dose.timeZoneOffsetMinutes),
            "tzSource": .string(dose.timeZoneSource.rawValue),
            "uuid": .string(dose.key.uuid.lowercased()),
            "v": .integer(1),
        ]
        if let doseQuantity = dose.doseQuantity {
            object["doseQuantity"] = .number(doseQuantity)
        }
        if let doseUnit = dose.doseUnit {
            object["doseUnit"] = .string(doseUnit)
        }
        if let scheduledAt = dose.scheduledAt {
            object["scheduledAt"] = .string(scheduledAt)
        }
        if envelope.demo { object["demo"] = .bool(true) }
        appendProvenance(
            source: dose.source,
            device: dose.device,
            wasUserEntered: dose.wasUserEntered,
            to: &object
        )
        return try CanonicalJSON.object(object).serialized()
    }

    static func encodeSeries(_ series: SeriesRecord, envelope: WireEnvelope) throws -> String {
        var object: [String: CanonicalJSON] = [
            "batchSeq": .integer(envelope.seq),
            "chunkIndex": .integer(series.chunkIndex),
            "kind": .string(series.payload.wireKind),
            "parentUuid": .string(series.parentUUID.lowercased()),
            "startIndex": .integer(series.startIndex),
            "uuid": .string(series.uuid),
            "v": .integer(1),
        ]
        if let chunkCount = series.chunkCount {
            object["chunkCount"] = .integer(chunkCount)
        }
        if envelope.demo { object["demo"] = .bool(true) }
        switch series.payload {
        case .ecgVoltage(let voltages, let samplingHz):
            object["samplingHz"] = .number(samplingHz)
            object["unit"] = .string("uV")
            object["voltages"] = .array(voltages.map { .number($0) })
        case .heartbeat(let intervalsMs, let precededByGap):
            object["intervalsMs"] = .array(intervalsMs.map { .number($0) })
            object["precededByGap"] = .array(precededByGap.map { .bool($0) })
        case .workoutRoute(let points):
            object["points"] = .array(points.map { point in
                var row: [String: CanonicalJSON] = [
                    "lat": .jsonNumber(coordinateToken(point.latitude)),
                    "lon": .jsonNumber(coordinateToken(point.longitude)),
                    "t": .string(point.timestamp),
                ]
                if let altitudeM = point.altitudeM { row["altitudeM"] = .number(altitudeM) }
                if let horizontalAccuracyM = point.horizontalAccuracyM {
                    row["horizontalAccuracyM"] = .number(horizontalAccuracyM)
                }
                if let verticalAccuracyM = point.verticalAccuracyM {
                    row["verticalAccuracyM"] = .number(verticalAccuracyM)
                }
                if let speedMps = point.speedMps { row["speedMps"] = .number(speedMps) }
                if let speedAccuracyMps = point.speedAccuracyMps {
                    row["speedAccuracyMps"] = .number(speedAccuracyMps)
                }
                if let courseDeg = point.courseDeg { row["courseDeg"] = .number(courseDeg) }
                if let courseAccuracyDeg = point.courseAccuracyDeg {
                    row["courseAccuracyDeg"] = .number(courseAccuracyDeg)
                }
                return .object(row)
            })
        case .workoutMetric(let metricId, let unit, let points):
            object["metricId"] = .string(metricId)
            object["unit"] = .string(unit)
            object["points"] = .array(points.map {
                .object(["t": .string($0.timestamp), "value": .number($0.value)])
            })
        }
        return try CanonicalJSON.object(object).serialized()
    }

    static func roundedCoordinate(_ value: Double) -> Double {
        (value * 10_000_000).rounded() / 10_000_000
    }

    static func coordinateToken(_ value: Double) -> String {
        String(format: "%.7f", roundedCoordinate(value))
    }

    static func appendProvenance(
        source: SampleSourceIdentity?,
        device: SampleDevice?,
        wasUserEntered: Bool?,
        to object: inout [String: CanonicalJSON]
    ) {
        if let source {
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
        if let device {
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
        if let wasUserEntered {
            object["wasUserEntered"] = .bool(wasUserEntered)
        }
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
