#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation
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

@Test func queryAnchorRoundTripsThroughOpaqueEnvelope() throws {
    let anchor = HKQueryAnchor(fromValue: 7)
    let data = try AnchorCoding.encode(anchor)
    #expect(try AnchorToken.fromEnvelope(data).format == AnchorToken.currentFormat)
    let restored = try AnchorCoding.decode(data)
    #expect(restored != nil)
}

@Test func healthKitIsUnavailableOnThisHostOrNot() {
    // macOS CI: unavailable. iOS device: available. Either is a valid observation.
    _ = HKHealthStore.isHealthDataAvailable()
}
#endif
