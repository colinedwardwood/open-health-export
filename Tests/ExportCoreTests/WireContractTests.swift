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

@Test func tierZeroCorpusValidatesAgainstCommittedJSONSchema() throws {
    let schema = try WireContractFixture.schema()
    let corpus = String(
        decoding: try WireContractFixture.data("spec/v1.0.0/fixtures/tier0.ndjson"),
        as: UTF8.self
    )
    try WireJSONSchema.validateNDJSON(corpus, schema: schema)
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
