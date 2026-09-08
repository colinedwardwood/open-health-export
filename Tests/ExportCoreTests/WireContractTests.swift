import CoreDomain
import Foundation
import MetricCatalog
import Testing
import WireFormat

private enum WireContractFixture {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func data(_ relative: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relative))
    }

    static func schema() throws -> [String: Any] {
        try WireJSONSchema.load(data("spec/v1.0.0/schema/ohe.wire.1.json"))
    }

    static func clone(_ object: [String: Any]) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(
                with: JSONSerialization.data(withJSONObject: object)
            ) as? [String: Any]
        )
    }
}

private func sleepCategory(value: Int = 3) -> CategoryRecord {
    CategoryRecord(
        key: RecordKey(uuid: "f0000000-0000-4000-8000-000000000001"),
        metric: MetricID(rawValue: "sleep_analysis"),
        healthKitIdentifier: "HKCategoryTypeIdentifierSleepAnalysis",
        start: "2026-09-07T22:00:00Z",
        end: "2026-09-08T06:00:00Z",
        timeZoneOffsetMinutes: 60,
        timeZoneSource: .sampleMetadata,
        categoryValue: value,
        categoryName: "asleepDeep",
        durationSeconds: 28_800,
        observedAt: "2026-09-08T08:00:00Z",
        source: SampleSourceIdentity(
            name: "Synthetic Apple Watch",
            bundleIdentifier: "com.apple.health.synthetic.watch",
            productType: "Watch6,18"
        )
    )
}

@Test func tierZeroCorpusValidatesAgainstCommittedJSONSchema() throws {
    let schema = try WireContractFixture.schema()
    let corpus = String(
        decoding: try WireContractFixture.data("spec/v1.0.0/fixtures/tier0.ndjson"),
        as: UTF8.self
    )
    try WireJSONSchema.validateNDJSON(corpus, schema: schema)
}

@Test func tierZeroCorpusDeclaresProvenanceSourcesSpansAndStructuralFamilies() throws {
    let corpus = String(
        decoding: try WireContractFixture.data("spec/v1.0.0/fixtures/tier0.ndjson"),
        as: UTF8.self
    )
    let records = try corpus.split(whereSeparator: \.isNewline).map {
        try #require(
            JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        )
    }
    let header = try #require(records.first)
    #expect(header["synthetic"] as? Bool == true)
    #expect(header["generatorVersion"] as? Int == 1)
    #expect(header["seed"] as? Int == 1)
    #expect(header["tier"] as? String == "T0")
    #expect(header["recordCount"] as? Int == 200)
    #expect(records.count == 201)
    let kinds = Set(records.compactMap { $0["kind"] as? String })
    #expect(kinds.isSuperset(of: ["sample.quantity", "sample.category", "sample.correlation", "workout"]))
    let sourceBundles = Set(records.compactMap {
        ($0["source"] as? [String: Any])?["bundleId"] as? String
    })
    #expect(sourceBundles.count == 6)
    let interval = try #require(records.first { $0["kind"] as? String == "sample.category" })
    #expect(interval["start"] as? String != interval["end"] as? String)
}

@Test func categoryIntervalValidatesAndConvergesByUUID() throws {
    let category = sleepCategory()
    let line = try NativeWire.encode(category, envelope: testEnvelope())
    let object = try #require(
        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    )
    #expect(object["kind"] as? String == "sample.category")
    #expect(object["durationSeconds"] as? Double == 28_800)
    try WireJSONSchema.validate(instance: object, schema: WireContractFixture.schema())

    let batch = try NativeWire.encode(
        samples: [],
        categories: [category],
        tombstones: [],
        metric: category.metric,
        batchID: BatchID(rawValue: "f0000000-0000-4000-8000-000000000002"),
        envelope: testEnvelope()
    )
    var receiver = ReferenceReceiver()
    for _ in 0 ..< 10 {
        try receiver.ingest(ndjson: String(decoding: batch, as: UTF8.self))
    }
    #expect(receiver.categories == [category.key.uuid: 3])

    let updated = try NativeWire.encode(
        sleepCategory(value: 4),
        envelope: testEnvelope()
    )
    try receiver.ingest(line: Data(updated.utf8))
    #expect(receiver.categories[category.key.uuid] == 4)
    let tombstone = try NativeWire.encode(
        samples: [],
        tombstones: [TombstoneRecord(key: category.key, metric: category.metric)],
        metric: category.metric,
        batchID: BatchID(rawValue: "f0000000-0000-4000-8000-000000000003"),
        envelope: testEnvelope()
    )
    try receiver.ingest(ndjson: String(decoding: tombstone, as: UTF8.self))
    #expect(receiver.categories.isEmpty)
    #expect(receiver.tombstones == [category.key.uuid])
}

@Test func correlationAndWorkoutStructuralRecordsValidateAndConverge() throws {
    let correlation = CorrelationRecord(
        key: RecordKey(uuid: "f1000000-0000-4000-8000-000000000001"),
        metric: MetricID(rawValue: "blood_pressure"),
        healthKitIdentifier: "HKCorrelationTypeIdentifierBloodPressure",
        correlationType: "bloodPressure",
        start: "2026-09-08T06:00:00Z",
        end: "2026-09-08T06:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        components: [
            CorrelationComponent(
                key: RecordKey(uuid: "f1000000-0000-4000-8000-000000000002"),
                metric: MetricID(rawValue: "blood_pressure_systolic"),
                healthKitIdentifier: "HKQuantityTypeIdentifierBloodPressureSystolic",
                value: 120,
                unit: CanonicalUnit(symbol: "mmHg")
            ),
            CorrelationComponent(
                key: RecordKey(uuid: "f1000000-0000-4000-8000-000000000003"),
                metric: MetricID(rawValue: "blood_pressure_diastolic"),
                healthKitIdentifier: "HKQuantityTypeIdentifierBloodPressureDiastolic",
                value: 80,
                unit: CanonicalUnit(symbol: "mmHg")
            ),
        ],
        observedAt: "2026-09-08T06:01:00Z"
    )
    let workout = WorkoutRecord(
        key: RecordKey(uuid: "f2000000-0000-4000-8000-000000000001"),
        activityType: "running",
        activityTypeRaw: 37,
        start: "2026-09-08T07:00:00Z",
        end: "2026-09-08T08:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        durationSeconds: 3_300,
        isIndoor: false,
        totals: [
            "active_energy": WorkoutTotal(
                value: 431.2,
                unit: CanonicalUnit(symbol: "kcal"),
                statistic: .sum
            ),
        ],
        events: [
            WorkoutEventRecord(
                timestamp: "2026-09-08T07:30:00Z",
                type: "pause",
                durationSeconds: 300
            ),
        ],
        hasRoute: true,
        seriesIncluded: [],
        observedAt: "2026-09-08T08:01:00Z"
    )
    let schema = try WireContractFixture.schema()
    for line in [
        try NativeWire.encode(correlation, envelope: testEnvelope()),
        try NativeWire.encode(workout, envelope: testEnvelope()),
    ] {
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        try WireJSONSchema.validate(instance: object, schema: schema)
    }
    let batch = try NativeWire.encode(
        samples: [],
        correlations: [correlation],
        workouts: [workout],
        tombstones: [],
        metric: MetricID(rawValue: "structural"),
        batchID: BatchID(rawValue: "f3000000-0000-4000-8000-000000000001"),
        envelope: testEnvelope()
    )
    var receiver = ReferenceReceiver()
    try receiver.ingest(ndjson: String(decoding: batch, as: UTF8.self))
    #expect(receiver.structuralRecords[correlation.key.uuid] == "sample.correlation")
    #expect(receiver.structuralRecords[workout.key.uuid] == "workout")
}

@Test func nativeBatchKindsValidateAgainstCommittedJSONSchema() throws {
    let schema = try WireContractFixture.schema()
    let envelope = testEnvelope()
    let sample = heartSample("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    let tombstone = TombstoneRecord(
        key: RecordKey(uuid: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
        metric: MetricCatalog.heartRate.id
    )
    let batch = try NativeWire.encode(
        samples: [sample],
        tombstones: [tombstone],
        aggregates: [statisticsRecord(metric: MetricCatalog.heartRate.id)],
        metric: MetricCatalog.heartRate.id,
        batchID: BatchID(rawValue: "cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
        envelope: envelope
    )
    try WireJSONSchema.validateNDJSON(String(decoding: batch, as: UTF8.self), schema: schema)

    let canary = try NativeWire.encodeCanary(
        code: "ABCD-EF01",
        batchID: BatchID(rawValue: "dddddddd-dddd-4ddd-8ddd-dddddddddddd"),
        envelope: envelope
    )
    try WireJSONSchema.validateNDJSON(String(decoding: canary, as: UTF8.self), schema: schema)
}

@Test func quantityWirePreservesSourceDeviceAndUserEntry() throws {
    var sample = heartSample("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee")
    sample.source = SampleSourceIdentity(
        name: "Apple Watch",
        bundleIdentifier: "com.apple.health",
        productType: "Watch6,18"
    )
    sample.device = SampleDevice(
        name: "Colin's Watch",
        manufacturer: "Apple Inc.",
        model: "Watch",
        hardwareVersion: "1",
        softwareVersion: "26.0"
    )
    sample.wasUserEntered = false
    let line = try NativeWire.encode(sample, envelope: testEnvelope())
    let object = try #require(
        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    )
    let source = try #require(object["source"] as? [String: Any])
    let device = try #require(object["device"] as? [String: Any])
    #expect(source["name"] as? String == "Apple Watch")
    #expect(source["bundleId"] as? String == "com.apple.health")
    #expect(source["productType"] as? String == "Watch6,18")
    #expect(device["name"] as? String == "Colin's Watch")
    #expect(device["softwareVersion"] as? String == "26.0")
    #expect(object["wasUserEntered"] as? Bool == false)
    try WireJSONSchema.validate(instance: object, schema: WireContractFixture.schema())
}

@Test func schemaRejectsMissingRequiredWrongTypesAndClosedEnums() throws {
    let schema = try WireContractFixture.schema()
    let valid: [String: Any] = [
        "batchSeq": 1,
        "end": "2026-01-01T00:00:00Z",
        "hkIdentifier": "future.health.type",
        "kind": "sample.quantity",
        "metricId": "future_metric",
        "observedAt": "2026-01-01T00:00:00Z",
        "semantics": "unmapped",
        "start": "2026-01-01T00:00:00Z",
        "tzOffsetMinutes": 0,
        "tzSource": "unknown",
        "unit": "count",
        "uuid": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        "v": 1,
        "value": 1.5,
        "futureOptional": "ignored",
    ]
    try WireJSONSchema.validate(instance: valid, schema: schema)

    var missing = valid
    missing.removeValue(forKey: "uuid")
    #expect(throws: JSONSchemaError.missingRequired("uuid")) {
        try WireJSONSchema.validate(instance: missing, schema: schema)
    }

    var wrongType = valid
    wrongType["value"] = "1.5"
    #expect(throws: JSONSchemaError.typeMismatch("value")) {
        try WireJSONSchema.validate(instance: wrongType, schema: schema)
    }

    var closedEnum = valid
    closedEnum["tzSource"] = "future"
    #expect(throws: JSONSchemaError.enumMismatch("enum")) {
        try WireJSONSchema.validate(instance: closedEnum, schema: schema)
    }
}

@Test func freezeDiffClassifiesBreakingAndAdditiveChanges() throws {
    let frozen = try WireContractFixture.schema()

    var removed = try WireContractFixture.clone(frozen)
    var removedDefs = try #require(removed["$defs"] as? [String: Any])
    var removedQuantity = try #require(removedDefs["quantity"] as? [String: Any])
    var removedProperties = try #require(removedQuantity["properties"] as? [String: Any])
    removedProperties.removeValue(forKey: "uuid")
    removedQuantity["properties"] = removedProperties
    removedDefs["quantity"] = removedQuantity
    removed["$defs"] = removedDefs
    #expect(
        WireJSONSchema.freezeDiff(frozen: frozen, current: removed)
            .contains(FreezeChange(classification: .breaking, code: "B1", detail: "quantity.uuid removed"))
    )

    var additive = try WireContractFixture.clone(frozen)
    var additiveDefs = try #require(additive["$defs"] as? [String: Any])
    var additiveQuantity = try #require(additiveDefs["quantity"] as? [String: Any])
    var additiveProperties = try #require(additiveQuantity["properties"] as? [String: Any])
    additiveProperties["futureOptional"] = ["type": "string"]
    additiveQuantity["properties"] = additiveProperties
    additiveDefs["quantity"] = additiveQuantity
    additive["$defs"] = additiveDefs
    #expect(
        WireJSONSchema.freezeGate(frozen: frozen, current: additive, markedFrozen: true)
            == "A-class change without a MINOR specVersion bump"
    )
    additive["x-ohe-specVersion"] = "1.1"
    #expect(WireJSONSchema.freezeGate(frozen: frozen, current: additive, markedFrozen: true) == nil)

    var closed = try WireContractFixture.clone(frozen)
    var closedDefs = try #require(closed["$defs"] as? [String: Any])
    var header = try #require(closedDefs["header"] as? [String: Any])
    var headerProperties = try #require(header["properties"] as? [String: Any])
    var mode = try #require(headerProperties["mode"] as? [String: Any])
    mode["enum"] = ["samples", "future"]
    headerProperties["mode"] = mode
    header["properties"] = headerProperties
    closedDefs["header"] = header
    closed["$defs"] = closedDefs
    #expect(
        WireJSONSchema.freezeGate(frozen: frozen, current: closed, markedFrozen: true)?
            .contains("B8 header.mode gained closed enum member") == true
    )

    var tightened = try WireContractFixture.clone(frozen)
    var tightenedDefs = try #require(tightened["$defs"] as? [String: Any])
    var tightenedQuantity = try #require(tightenedDefs["quantity"] as? [String: Any])
    tightenedQuantity["additionalProperties"] = false
    tightenedDefs["quantity"] = tightenedQuantity
    tightened["$defs"] = tightenedDefs
    #expect(
        WireJSONSchema.freezeGate(frozen: frozen, current: tightened, markedFrozen: true)?
            .contains("B13 quantity rejects additive fields") == true
    )
}

@Test func referenceReceiverConvergesAndIgnoresAdditiveRecordsAndFields() throws {
    let sequence = String(
        decoding: try WireContractFixture.data("spec/v1.0.0/fixtures/receiver-sequence.ndjson"),
        as: UTF8.self
    )
    var receiver = ReferenceReceiver()
    try receiver.ingest(ndjson: sequence)

    let expected = try JSONSerialization.jsonObject(
        with: WireContractFixture.data("spec/v1.0.0/fixtures/receiver-expected-state.json")
    )
    let actualData = try JSONSerialization.data(
        withJSONObject: receiver.expectedState(),
        options: [.sortedKeys]
    )
    let expectedData = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
    #expect(actualData == expectedData)

    try receiver.ingest(ndjson: sequence)
    #expect(receiver.quantities.count == 1)
    #expect(receiver.tombstones.count == 1)
}
