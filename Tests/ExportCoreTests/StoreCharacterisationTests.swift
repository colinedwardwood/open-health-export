// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog
import Redaction
import Testing

@Test func storeCharacterisationEmitsOnlyAggregateShape() throws {
    let watch = SampleRecord(
        key: RecordKey(uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
        metric: MetricCatalog.heartRate.id,
        start: "2024-03-15T12:00:00Z",
        end: "2024-03-15T12:00:01Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 72.123456,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2024-03-15T12:00:01Z",
        source: SampleSourceIdentity(name: "Apple Watch", productType: "Watch6,2"),
        device: SampleDevice(name: "Watch", model: "Watch6,2"),
        wasUserEntered: false
    )
    let third = SampleRecord(
        key: RecordKey(uuid: "11111111-2222-4333-8444-555555555555"),
        metric: MetricCatalog.heartRate.id,
        start: "2024-04-15T12:00:00Z",
        end: "2024-04-15T12:00:00Z",
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: 72.123456,
        unit: CanonicalUnit(symbol: "count/min"),
        observedAt: "2024-04-15T12:00:00Z",
        source: SampleSourceIdentity(name: RedactionCanary.sourceName),
        wasUserEntered: false
    )
    let report = StoreCharacterisation.report(
        events: [watch, third].map(StoreCharacterisation.event(from:))
    )
    #expect(report.sampleCount == 2)
    #expect(report.typeCount == 1)
    let heart = try #require(report.types.first)
    #expect(heart.metricId == "heartRate")
    #expect(heart.count == 2)
    #expect(heart.firstMonth == "2024-03")
    #expect(heart.lastMonth == "2024-04")
    #expect(heart.sourceClasses[StoreCharacterisation.sourceClassAppleWatch] == 1)
    #expect(heart.sourceClasses[StoreCharacterisation.sourceClassThirdParty] == 1)
    #expect(heart.durationBuckets["0s"] == 1)
    #expect(heart.durationBuckets["1-59s"] == 1)
    #expect(heart.intervalBuckets["1d+"] == 1)

    let json = try String(decoding: StoreCharacterisation.json(report), as: UTF8.self)
    #expect(RedactionCanary.isClean(json))
    #expect(!json.contains("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"))
    #expect(!json.contains("Apple Watch"))
    #expect(!json.contains("Watch6,2"))
    #expect(json.contains("\"count\" : 2") || json.contains("\"count\":2"))
}

@Test func storeCharacterisationNDJSONSkipsBatchFramingAndDoesNotCopyValues() throws {
    let ndjson = """
    {"kind":"batch.header","exporterId":"clinic.example.org"}
    {"kind":"sample.quantity","metricId":"heart_rate","start":"2024-01-01T00:00:00Z","end":"2024-01-01T00:00:00Z","uuid":"deadbeef-0000-4000-8000-000000000001","value":72.123456,"source":{"name":"Dexcom G7","bundleId":"com.dexcom.CGM"}}
    {"kind":"batch.footer"}
    """
    let report = StoreCharacterisation.report(
        events: StoreCharacterisation.events(fromNDJSON: ndjson)
    )
    #expect(report.sampleCount == 1)
    let json = try String(decoding: StoreCharacterisation.json(report), as: UTF8.self)
    #expect(RedactionCanary.isClean(json))
    #expect(!json.contains("deadbeef"))
    #expect(!json.contains("com.dexcom"))
    #expect(json.contains("heart_rate"))
    #expect(report.types[0].sourceClasses[StoreCharacterisation.sourceClassThirdParty] == 1)
}
