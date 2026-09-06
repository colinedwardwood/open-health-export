#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation
import MetricCatalog
import Testing
@testable import HealthKitSource

@Test func conversionHappensWithoutAuthorization() {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 72)
    let sample = HKQuantitySample(
        type: HKQuantityType(.heartRate),
        quantity: quantity,
        start: start,
        end: start
    )
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let record = SampleConversion.record(from: sample, metric: MetricID(rawValue: "heartRate"), context: context)
    #expect(record.key.uuid == sample.uuid.uuidString)
    #expect(record.value == 72)
    #expect(record.start.contains("2024-01-01"))
    #expect(record.timeZoneOffsetMinutes == 0)
}

@Test func oxygenSaturationIsPercentNotAHumidityClass() {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let quantity = HKQuantity(unit: .percent(), doubleValue: 0.98)
    let sample = HKQuantitySample(
        type: HKQuantityType(.oxygenSaturation),
        quantity: quantity,
        start: start,
        end: start
    )
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let record = SampleConversion.record(
        from: sample,
        metric: MetricCatalog.oxygenSaturation.id,
        context: context
    )
    #expect(record.value == 98)
    #expect(record.unit.symbol == "%")
}

@Test func walkingDistanceIsKilometresOnTheWire() {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let quantity = HKQuantity(unit: .meter(), doubleValue: 1500)
    let sample = HKQuantitySample(
        type: HKQuantityType(.distanceWalkingRunning),
        quantity: quantity,
        start: start,
        end: start
    )
    let context = TemporalContext(
        timeZoneIdentifier: "UTC",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let record = SampleConversion.record(
        from: sample,
        metric: MetricCatalog.walkingRunningDistance.id,
        context: context
    )
    #expect(record.value == 1.5)
    #expect(record.unit.symbol == "km")
}

@Test func queryAnchorRoundTripsThroughOpaqueEnvelope() throws {
    let anchor = HKQueryAnchor(fromValue: 7)
    let data = try AnchorCoding.encode(anchor)
    #expect(try AnchorToken.fromEnvelope(data).format == AnchorToken.currentFormat)
    let restored = try AnchorCoding.decode(data)
    #expect(restored != nil)
}

@Test func statisticsConversionUsesCanonicalHealthKitAggregateFields() throws {
    let context = TemporalContext(
        timeZoneIdentifier: "America/New_York",
        localeIdentifier: "en_US_POSIX",
        tzDatabaseVersion: "2024a"
    )
    let record = try #require(
        StatisticsConversion.record(
            metric: MetricCatalog.stepCount.id,
            day: "2024-03-10",
            value: 1_234,
            context: context,
            computedAt: "2024-03-11T00:00:00Z",
            observedAt: "2024-03-11T00:00:00Z"
        )
    )
    #expect(record.statistic == .sum)
    #expect(record.computation == .healthKitStatisticsCollectionQuery)
    #expect(record.value == 1_234)
    #expect(record.unit.symbol == "count")
    #expect(record.bucketDurationSeconds == 23 * 60 * 60)
    #expect(record.bucketKey.contains("step_count|sum|P1D"))
}

@Test func statisticsConversionRejectsLocalFoldMetrics() {
    #expect(
        StatisticsConversion.record(
            metric: MetricCatalog.heartRate.id,
            day: "2024-01-01",
            value: 72,
            context: .utc,
            computedAt: "2024-01-02T00:00:00Z",
            observedAt: "2024-01-02T00:00:00Z"
        ) == nil
    )
}

@Test func healthKitIsUnavailableOnThisHostOrNot() {
    // macOS CI: unavailable. iOS device: available. Either is a valid observation.
    _ = HKHealthStore.isHealthDataAvailable()
}
#endif
