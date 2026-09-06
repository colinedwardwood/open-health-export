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

@Test func restingHeartRateUsesCountPerMinute() {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let quantity = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 58)
    let sample = HKQuantitySample(
        type: HKQuantityType(.restingHeartRate),
        quantity: quantity,
        start: start,
        end: start
    )
    let record = SampleConversion.record(
        from: sample,
        metric: MetricCatalog.restingHeartRate.id,
        context: .utc
    )
    #expect(record.value == 58)
    #expect(record.unit.symbol == "count/min")
}

@Test func vo2MaxUsesMillilitresPerKilogramMinute() {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let unit = HKUnit.literUnit(with: .milli)
        .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
    let quantity = HKQuantity(unit: unit, doubleValue: 42)
    let sample = HKQuantitySample(
        type: HKQuantityType(.vo2Max),
        quantity: quantity,
        start: start,
        end: start
    )
    let record = SampleConversion.record(
        from: sample,
        metric: MetricCatalog.vo2Max.id,
        context: .utc
    )
    #expect(record.value == 42)
    #expect(record.unit.symbol == "mL/kg/min")
}

@Test func bloodGlucoseConvertsOnceToCanonicalMilligramsPerDecilitre() {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let unit = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    let quantity = HKQuantity(unit: unit, doubleValue: 99)
    let sample = HKQuantitySample(
        type: HKQuantityType(.bloodGlucose),
        quantity: quantity,
        start: start,
        end: start
    )
    let record = SampleConversion.record(
        from: sample,
        metric: MetricCatalog.bloodGlucose.id,
        context: .utc
    )
    #expect(record.value == 99)
    #expect(record.unit.symbol == "mg/dL")
}

@Test func expandedCatalogueUsesCanonicalAdapterUnits() {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let fixtures: [(MetricDeclaration, HKUnit, Double, Double)] = [
        (MetricCatalog.cyclingDistance, .meter(), 1_500, 1.5),
        (MetricCatalog.flightsClimbed, .count(), 12, 12),
        (MetricCatalog.basalEnergy, .kilocalorie(), 450, 450),
        (MetricCatalog.exerciseTime, .second(), 1_800, 30),
        (MetricCatalog.standTime, .minute(), 10, 10),
        (
            MetricCatalog.walkingHeartRateAverage,
            HKUnit.count().unitDivided(by: .minute()),
            91,
            91
        ),
        (MetricCatalog.heartRateVariabilitySDNN, .second(), 0.042, 42),
        (MetricCatalog.bodyTemperature, .degreeFahrenheit(), 98.6, 37),
        (MetricCatalog.basalBodyTemperature, .degreeCelsius(), 36.5, 36.5),
        (MetricCatalog.leanBodyMass, .gramUnit(with: .kilo), 55, 55),
        (MetricCatalog.dietaryWater, .liter(), 0.25, 250),
        (MetricCatalog.bloodPressureSystolic, .millimeterOfMercury(), 120, 120),
        (MetricCatalog.bloodPressureDiastolic, .millimeterOfMercury(), 80, 80),
    ]
    for (declaration, sourceUnit, sourceValue, expected) in fixtures {
        guard let type = SampleConversion.quantityType(for: declaration.id) else {
            Issue.record("missing HealthKit quantity type for \(declaration.id.rawValue)")
            continue
        }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: sourceUnit, doubleValue: sourceValue),
            start: start,
            end: start
        )
        let record = SampleConversion.record(
            from: sample,
            metric: declaration.id,
            context: .utc
        )
        #expect(abs(record.value - expected) < 0.000_001)
        #expect(record.unit == declaration.canonicalUnit)
    }
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
