// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation
import MetricCatalog
import Testing
import WireFormat
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

@Test func conversionPreservesSourceDeviceAndUserEntryMetadata() throws {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let device = HKDevice(
        name: "Test Watch",
        manufacturer: "Synthetic",
        model: "Fixture",
        hardwareVersion: "1",
        firmwareVersion: nil,
        softwareVersion: "2",
        localIdentifier: nil,
        udiDeviceIdentifier: nil
    )
    let sample = HKQuantitySample(
        type: HKQuantityType(.heartRate),
        quantity: HKQuantity(
            unit: HKUnit.count().unitDivided(by: .minute()),
            doubleValue: 72
        ),
        start: start,
        end: start,
        device: device,
        metadata: [HKMetadataKeyWasUserEntered: true]
    )
    let record = SampleConversion.record(
        from: sample,
        metric: MetricCatalog.heartRate.id,
        context: .utc
    )
    #expect(record.source != nil)
    #expect(record.device?.name == "Test Watch")
    #expect(record.device?.manufacturer == "Synthetic")
    #expect(record.device?.softwareVersion == "2")
    #expect(record.wasUserEntered == true)
}

@Test func sleepCategoryPreservesItsEveningToMorningMeasurementSpan() {
    let start = Date(timeIntervalSince1970: 1_704_146_400)
    let end = start.addingTimeInterval(8 * 60 * 60)
    let sample = HKCategorySample(
        type: HKCategoryType(.sleepAnalysis),
        value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        start: start,
        end: end
    )
    let record = CategoryConversion.record(
        from: sample,
        metric: CategoryConversion.sleepMetric,
        context: .utc
    )
    #expect(record.key.uuid == sample.uuid.uuidString)
    #expect(record.categoryName == "asleepDeep")
    #expect(record.durationSeconds == 28_800)
    #expect(record.start.hasPrefix("2024-01-01T22:00:00"))
    #expect(record.end.hasPrefix("2024-01-02T06:00:00"))
    #expect(
        HealthKitAuthorization.readTypes(for: [CategoryConversion.sleepMetric])
            .contains(HKCategoryType(.sleepAnalysis))
    )
    #expect(MetricCatalog.sleepAnalysis.id == CategoryConversion.sleepMetric)
    #expect(MetricCatalog.workout.id == WorkoutConversion.metric)
    #expect(
        HealthKitAuthorization.readTypes(for: [MetricCatalog.mindfulSession.id])
            .contains(HKCategoryType(.mindfulSession))
    )
    #expect(
        HealthKitAuthorization.readTypes(for: [MetricCatalog.workout.id])
            .contains(HKWorkoutType.workoutType())
    )
}

@Test func everyDeclaredCategoryMetricResolvesToItsHealthKitType() {
    #expect(
        Set(CategoryConversion.identifiers.keys.map(\.rawValue))
            == Set(DemoCorpus.categoryTypes.map(\.metricID))
    )
    for category in DemoCorpus.categoryTypes {
        let metric = MetricID(rawValue: category.metricID)
        let type = CategoryConversion.categoryType(for: metric)
        #expect(type?.identifier == category.healthKitIdentifier)
        if let type {
            #expect(HealthKitAuthorization.readTypes(for: [metric]).contains(type))
        }
    }
}

@Test func bloodPressureCorrelationKeepsComponentUUIDsAndCanonicalValues() {
    let date = Date(timeIntervalSince1970: 1_704_067_200)
    let systolic = HKQuantitySample(
        type: HKQuantityType(.bloodPressureSystolic),
        quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 120),
        start: date,
        end: date
    )
    let diastolic = HKQuantitySample(
        type: HKQuantityType(.bloodPressureDiastolic),
        quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: 80),
        start: date,
        end: date
    )
    let correlation = HKCorrelation(
        type: HKCorrelationType(.bloodPressure),
        start: date,
        end: date,
        objects: [systolic, diastolic]
    )
    let converted = CorrelationConversion.records(
        from: correlation,
        metric: CorrelationConversion.bloodPressureMetric,
        context: .utc
    )
    #expect(converted.components.count == 2)
    #expect(Set(converted.components.map(\.key.uuid)) == [systolic.uuid.uuidString, diastolic.uuid.uuidString])
    #expect(converted.correlation.components.map(\.key.uuid) == converted.components.map(\.key.uuid))
    #expect(converted.correlation.correlationType == "bloodPressure")
}

@Test func bloodPressurePairingAuthorizesTheCorrelationTypeOnComponentReads() throws {
    let source = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HealthKitSource/HealthKitSampleSource.swift"),
        encoding: .utf8
    )
    #expect(source.contains("HKCorrelationQuery"))
    #expect(source.contains("isBloodPressureComponent"))
    #expect(source.contains("bloodPressurePairings"))
    let systolicReads = HealthKitAuthorization.readTypes(
        for: [MetricCatalog.bloodPressureSystolic.id]
    )
    let diastolicReads = HealthKitAuthorization.readTypes(
        for: [MetricCatalog.bloodPressureDiastolic.id]
    )
    let pairing = HKCorrelationType(.bloodPressure)
    #expect(systolicReads.contains(pairing))
    #expect(diastolicReads.contains(pairing))
    #expect(
        !HealthKitAuthorization.readTypes(for: [MetricCatalog.heartRate.id]).contains(pairing)
    )
    #expect(
        !MetricCatalog.selectable.contains {
            $0.hkIdentifier == "HKCorrelationTypeIdentifierBloodPressure"
        }
    )
}

@Test func workoutConversionKeepsHealthKitDurationAndRawActivityType() {
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let workout = HKWorkout(
        activityType: .running,
        start: start,
        end: start.addingTimeInterval(3_600),
        duration: 3_300,
        totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 431.2),
        totalDistance: HKQuantity(unit: .meter(), doubleValue: 10_000),
        metadata: [HKMetadataKeyIndoorWorkout: false]
    )
    let converted = WorkoutConversion.record(from: workout, context: .utc)
    #expect(converted.activityType == "running")
    #expect(converted.activityTypeRaw == Int(HKWorkoutActivityType.running.rawValue))
    #expect(converted.durationSeconds == 3_300)
    #expect(converted.totals["active_energy"]?.value == 431.2)
    #expect(converted.totals["distance"]?.value == 10)
    #expect(converted.hasRoute == false)
}

@Test func electrocardiogramClassificationNamesStayVerbatim() {
    #expect(
        ECGConversion.classificationName(.sinusRhythm) == "sinusRhythm"
    )
    #expect(
        ECGConversion.classificationName(.atrialFibrillation) == "atrialFibrillation"
    )
    #expect(
        HealthKitAuthorization.readTypes(for: [ECGConversion.metric])
            .contains(HKObjectType.electrocardiogramType())
    )
}

@Test func hk30CharacteristicTypesAuthorizeWithoutAnAnchoredQuery() {
    let metrics = MetricCatalog.characteristics.map(\.id)
    let types = HealthKitAuthorization.readTypes(for: metrics)
    #expect(types.count == 6)
    #expect(
        types.contains(
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
        )
    )
    #expect(
        types.contains(
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!
        )
    )
    #expect(
        CharacteristicConversion.dateOfBirthValue(year: 1998, month: 4, day: 17)
            == "1998-04-17"
    )
    #expect(CharacteristicConversion.dateOfBirthValue(year: nil, month: 4, day: 17) == nil)
    #expect(CharacteristicConversion.biologicalSexName(.female) == "female")
    #expect(CharacteristicConversion.bloodTypeName(.aPositive) == "aPositive")
    #expect(CharacteristicConversion.fitzpatrickName(.III) == "III")
    #expect(CharacteristicConversion.wheelchairName(.yes) == "yes")
    #expect(CharacteristicConversion.activityMoveModeName(.appleMoveTime) == "appleMoveTime")
}

@Test func coverageWindowProbeNamesTheDocumentedLimitedHistoryAPI() async throws {
    let source = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HealthKitSource/HealthKitSampleSource.swift"),
        encoding: .utf8
    )
    #expect(source.contains("earliestAuthorizedSampleDate(for:)"))
    #expect(HealthKitAuthorization.objectType(for: MetricCatalog.heartRate.id) == HKQuantityType(.heartRate))
    let days = try await HealthKitAuthorization.earliestAuthorizedDays(
        for: [MetricCatalog.heartRate.id]
    )
    #expect(days.isEmpty)
}

@Test func ux44PreferredDisplayUnitsReadHealthKitAndRefreshOnChange() throws {
    let source = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/HealthKitSource/HealthKitPreferredDisplayUnits.swift"),
        encoding: .utf8
    )
    #expect(source.contains("HKUserPreferencesDidChange"))
    #expect(source.contains("preferredUnits(for:"))
    let view = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Apps/Exporter-iOS/HarnessView.swift"),
        encoding: .utf8
    )
    #expect(view.contains("HealthKitPreferredDisplayUnits.policy"))
    #expect(view.contains("HealthKitPreferredDisplayUnits.didChange"))
    #expect(view.contains("refreshHealthKitDisplayUnits"))
}

@Test func structuredHealthKitTypesAreAuthorizedAndStateOfMindConverts() {
    let readTypes = HealthKitAuthorization.readTypes(
        for: [
            WorkoutConversion.metric,
            ECGConversion.metric,
            AudiogramConversion.metric,
            StateOfMindConversion.metric,
        ]
    )
    #expect(readTypes.contains(HKWorkoutType.workoutType()))
    #expect(readTypes.contains(HKObjectType.electrocardiogramType()))
    #expect(readTypes.contains(HKObjectType.audiogramSampleType()))
    #expect(readTypes.contains(HKObjectType.stateOfMindType()))

    let date = Date(timeIntervalSince1970: 1_704_067_200)
    let sample = HKStateOfMind(
        date: date,
        kind: .momentaryEmotion,
        valence: 0.5,
        labels: [.happy],
        associations: [.health]
    )
    let converted = StateOfMindConversion.record(from: sample, context: .utc)
    #expect(converted.key.uuid == sample.uuid.uuidString)
    #expect(converted.valence == 0.5)
    #expect(converted.kindOfEntry == "raw_1")
    #expect(converted.labels == ["raw_\(HKStateOfMind.Label.happy.rawValue)"])
    #expect(
        converted.associations
            == ["raw_\(HKStateOfMind.Association.health.rawValue)"]
    )
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
        (MetricCatalog.height, .meter(), 1.78, 1.78),
        (MetricCatalog.bodyFatPercentage, .percent(), 0.185, 18.5),
        (MetricCatalog.bodyMassIndex, .count(), 22.4, 22.4),
        (MetricCatalog.swimmingDistance, .meter(), 2_500, 2.5),
        (MetricCatalog.wheelchairDistance, .meter(), 800, 0.8),
        (MetricCatalog.pushCount, .count(), 40, 40),
        (MetricCatalog.swimmingStrokeCount, .count(), 18, 18),
        (MetricCatalog.walkingSpeed, HKUnit.meter().unitDivided(by: .second()), 1.4, 1.4),
        (MetricCatalog.runningSpeed, HKUnit.meter().unitDivided(by: .second()), 3.2, 3.2),
        (MetricCatalog.cyclingSpeed, HKUnit.meter().unitDivided(by: .second()), 6.1, 6.1),
        (MetricCatalog.stairAscentSpeed, HKUnit.meter().unitDivided(by: .second()), 0.4, 0.4),
        (MetricCatalog.timeInDaylight, .second(), 3_600, 60),
        (
            MetricCatalog.environmentalAudioExposure,
            .decibelAWeightedSoundPressureLevel(),
            65,
            65
        ),
        (MetricCatalog.appleMoveTime, .second(), 900, 15),
        (
            MetricCatalog.physicalEffort,
            HKUnit.kilocalorie().unitDivided(
                by: .gramUnit(with: .kilo).unitMultiplied(by: .hour())
            ),
            4.5,
            4.5
        ),
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
            end: start.addingTimeInterval(1)
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

@Test func healthKitAvailabilityOverrideForcesUnavailableWithoutMutatingProcessEnv() {
    #expect(
        HealthKitAvailability.isAvailable(
            environment: [HealthAvailability.unavailableEnvironmentKey: "1"]
        ) == false
    )
}

@Test func classifiedQueryErrorMapsLockAndDevicePolicyCodes() {
    let locked = NSError(
        domain: HKErrorDomain,
        code: HKError.Code.errorDatabaseInaccessible.rawValue
    )
    #expect(
        HealthKitSourceError.classifiedQueryError(locked) as? DestinationSendError
            == .deviceLocked
    )
    let restricted = NSError(
        domain: HKErrorDomain,
        code: HKError.Code.errorHealthDataRestricted.rawValue
    )
    #expect(
        HealthKitSourceError.classifiedQueryError(restricted) as? DestinationSendError
            == .healthDataRestricted
    )
    let guest = NSError(
        domain: HKErrorDomain,
        code: HKError.Code.errorNotPermissibleForGuestUserMode.rawValue
    )
    #expect(
        HealthKitSourceError.classifiedQueryError(guest) as? DestinationSendError
            == .healthDataRestricted
    )
}
#endif
