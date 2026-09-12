// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog
import Testing

private func browserSample(
    metric: MetricID,
    uuid: String,
    start: String,
    value: Double
) -> SampleRecord {
    SampleRecord(
        key: RecordKey(uuid: uuid),
        metric: metric,
        start: start,
        end: start,
        timeZoneOffsetMinutes: 0,
        timeZoneSource: .unknown,
        value: value,
        unit: MetricCatalog.declaration(for: metric)?.canonicalUnit
            ?? CanonicalUnit(symbol: "count"),
        observedAt: start
    )
}

@Test func dataBrowserDetailFiltersPeriodAndKeepsNewestFirst() throws {
    let metric = MetricCatalog.heartRate.id
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z"))
    let detail = try #require(
        DataBrowser.detail(
            metric: metric,
            samples: [
                browserSample(
                    metric: metric,
                    uuid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    start: "2026-09-08T11:00:00Z",
                    value: 72
                ),
                browserSample(
                    metric: metric,
                    uuid: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                    start: "2026-09-07T11:00:00Z",
                    value: 68
                ),
                browserSample(
                    metric: metric,
                    uuid: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                    start: "2026-08-01T11:00:00Z",
                    value: 60
                ),
            ],
            destinations: [
                DataBrowserDestination(name: "Archive folder", sentThroughDay: "2026-09-08"),
            ],
            period: .week,
            now: now
        )
    )
    #expect(detail.samples.map(\.value) == [72, 68])
    #expect(detail.latest?.value == 72)
    #expect(detail.exportUnit == "bpm")
    #expect(detail.destinations.map(\.name) == ["Archive folder"])
    #expect(
        DataBrowser.horizonCopy(day: "2025-11-02")
            == "Deletions older than 2025-11-02 are not attributed to a day until a full reconcile."
    )
}

@Test func aggregateDetailNamesTheExportComputation() throws {
    let detail = try #require(
        DataBrowser.detail(
            metric: MetricCatalog.stepCount.id,
            samples: [],
            now: Date(timeIntervalSince1970: 0)
        )
    )
    #expect(detail.aggregationExplanation == "sum · cumulative · local day")
    #expect(DataBrowser.emptyDetailCopy.contains("access is off in Health"))
}

/// R-60: the read that returns nothing because the type was denied and the read that
/// returns nothing because the iPhone holds no such data must be indistinguishable in
/// the product, because Apple makes them indistinguishable to us.
@Test func deniedTypeAndAbsentDataProduceIdenticalCopy() throws {
    let denied = MetricCatalog.heartRate.id
    let absent = MetricCatalog.stepCount.id
    let now = Date(timeIntervalSince1970: 0)

    let deniedDetail = try #require(DataBrowser.detail(metric: denied, samples: [], now: now))
    let absentDetail = try #require(DataBrowser.detail(metric: absent, samples: [], now: now))
    #expect(deniedDetail.samples.isEmpty)
    #expect(absentDetail.samples.isEmpty)

    let rows = DataBrowser.rows(latest: [:])
    let subtitles = Set(rows.filter { $0.id == denied || $0.id == absent }.map(\.subtitle))
    #expect(subtitles == [DataBrowser.noDataCopy])

    let copy = DataBrowser.emptyDetailCopy
    #expect(copy.contains("Either there aren't any"))
    #expect(copy.contains("access is off in Health"))
    #expect(copy.contains(DataBrowser.healthPathCopy))
    for claim in ["denied", "denial", "not authorised", "not authorized", "no permission"] {
        #expect(!copy.lowercased().contains(claim))
        #expect(!DataBrowser.noDataCopy.lowercased().contains(claim))
        #expect(!DataBrowser.nothingReturnedCopy.lowercased().contains(claim))
    }
}

@Test func coverageCheckClassifiesAvailableLimitedAndNothingReturned() throws {
    let available = CoverageObservation(
        sampleCount: 4812,
        latestStart: "2026-09-12T08:41:00Z"
    )
    let limited = CoverageObservation(
        sampleCount: 4,
        latestStart: "2026-08-02T00:00:00Z",
        earliestAuthorizedDay: "2026-08-01"
    )
    let empty = CoverageObservation()
    #expect(CoverageClassification.classify(available) == .dataAvailable(
        sampleCount: 4812,
        latestStart: "2026-09-12T08:41:00Z"
    ))
    #expect(CoverageClassification.classify(limited) == .limitedWindow(
        earliestAuthorizedDay: "2026-08-01",
        sampleCount: 4,
        latestStart: "2026-08-02T00:00:00Z"
    ))
    #expect(CoverageClassification.classify(empty) == .nothingReturned)

    let heart = MetricCatalog.heartRate.id
    let steps = MetricCatalog.stepCount.id
    let glucose = MetricCatalog.bloodGlucose.id
    let rows = DataBrowser.rows(
        latest: [:],
        coverage: [
            heart: limited,
            steps: available,
            glucose: empty,
        ]
    )
    let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    #expect(byID[heart]?.coverage == CoverageClassification.classify(limited))
    #expect(byID[heart]?.subtitle.contains("2026-08-01") == true)
    #expect(byID[heart]?.hasData == true)
    #expect(byID[steps]?.subtitle == "4812 samples, latest 2026-09-12T08:41:00Z")
    #expect(byID[glucose]?.subtitle == DataBrowser.nothingReturnedCopy)
    #expect(byID[glucose]?.hasData == false)
    #expect(
        DataBrowser.rows(
            latest: [:],
            onlyWithData: true,
            coverage: [heart: limited, glucose: empty]
        ).map(\.id).contains(heart)
    )
    #expect(
        !DataBrowser.rows(
            latest: [:],
            onlyWithData: true,
            coverage: [glucose: empty]
        ).map(\.id).contains(glucose)
    )
}

@Test func ux17SearchMatchesIdentifierDisplayNameAndSynonyms() {
    func ids(_ needle: String) -> Set<MetricID> {
        Set(DataBrowser.rows(latest: [:], search: needle).map(\.metric))
    }

    #expect(ids("HKQuantityTypeIdentifierStepCount") == [MetricCatalog.stepCount.id])
    #expect(ids("steps") == [MetricCatalog.stepCount.id])
    #expect(ids("step count") == [MetricCatalog.stepCount.id])
    #expect(ids("weight") == [MetricCatalog.bodyMass.id])
    #expect(ids("HRV") == [MetricCatalog.heartRateVariabilitySDNN.id])
    #expect(ids("SpO2") == [MetricCatalog.oxygenSaturation.id])
    #expect(ids("VO2") == [MetricCatalog.vo2Max.id])
    #expect(ids("glucose") == [MetricCatalog.bloodGlucose.id])
    #expect(
        ids("BP") == [
            MetricCatalog.bloodPressureSystolic.id,
            MetricCatalog.bloodPressureDiastolic.id,
        ]
    )
}

@Test func ux20SchedulingCopyNamesIOSTimingLockAndChosenTimeControls() {
    #expect(SchedulingHonesty.body.contains("iOS decides when background export runs"))
    #expect(SchedulingHonesty.body.contains("locked"))
    #expect(SchedulingHonesty.body.contains("Shortcut"))
    #expect(SchedulingHonesty.body.contains("Control Centre"))
    #expect(SchedulingHonesty.noSchedulePromise.contains("3 a.m."))
    #expect(!SchedulingHonesty.body.lowercased().contains("will definitely"))
    #expect(!SchedulingHonesty.body.lowercased().contains("every hour"))
}

@Test func ux07UnavailableCopyNamesThePlatformLimitWithoutRetryOrDashboard() {
    #expect(HealthAvailability.unavailableTitle == "Apple Health is not on this device")
    #expect(
        HealthAvailability.unavailableBody
            == "This hardware has no Health store. Destinations and pairing still work. Export of Health samples stays off."
    )
    let combined = HealthAvailability.unavailableTitle + " " + HealthAvailability.unavailableBody
    for banned in ["cannot", "can't", "treat", "retry", "spinner"] {
        #expect(!combined.lowercased().contains(banned))
    }
}

@Test func selectionReviewRequiresSensitiveIndividualConfirmation() throws {
    var draft = DataSelectionDraft(baseline: [MetricCatalog.stepCount.id])
    #expect(throws: DataSelectionError.sensitiveConfirmationRequired) {
        try draft.toggle(
            MetricCatalog.bodyMass.id,
            destinationName: "Archive folder"
        )
    }
    try draft.toggle(
        MetricCatalog.bodyMass.id,
        destinationName: "Archive folder",
        sensitiveConfirmation: "Archive folder"
    )
    try draft.toggle(
        MetricCatalog.stepCount.id,
        destinationName: "Archive folder"
    )
    let review = draft.review(authorized: [], destinationName: "Archive folder")
    #expect(review.adding == [MetricCatalog.bodyMass.id])
    #expect(review.removing == [MetricCatalog.stepCount.id])
    #expect(review.needingPermission == [MetricCatalog.bodyMass.id])
    #expect(
        review.removalWarning
            == "Removing a type does not delete data already sent to Archive folder."
    )
}

@Test func routineBulkInvertNeverSelectsSensitiveMetrics() {
    var draft = DataSelectionDraft(baseline: [])
    draft.invertRoutine([
        MetricCatalog.stepCount.id,
        MetricCatalog.bodyMass.id,
        MetricCatalog.heartRate.id,
    ])
    #expect(draft.selected == [MetricCatalog.stepCount.id, MetricCatalog.heartRate.id])
    draft.clearAll()
    #expect(draft.selected.isEmpty)
}

@Test func coreDailyPresetContainsOnlyRoutineMetrics() {
    #expect(!MetricCatalog.coreDaily.isEmpty)
    #expect(MetricCatalog.coreDaily.count >= 8)
    #expect(MetricCatalog.coreDaily.count <= 28)
    #expect(MetricCatalog.coreDaily.allSatisfy { $0.sensitivity == .routine })
    #expect(Set(MetricCatalog.coreDaily.map(\.id)).isSubset(of: Set(MetricCatalog.selectable.map(\.id))))
    #expect(
        Set(MetricCatalog.coreDaily.map(\.id)).isDisjoint(
            with: Set(MetricCatalog.all.filter { $0.sensitivity == .sensitive }.map(\.id))
        )
    )
    #expect(!MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.bloodGlucose.id })
    #expect(Set(MetricCatalog.coreDaily.map(\.id)).count == MetricCatalog.coreDaily.count)
    #expect(MetricCatalog.coreDaily.count == 27)
    #expect(MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.swimmingDistance.id })
    #expect(MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.environmentalAudioExposure.id })
    #expect(MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.sleepAnalysis.id })
    #expect(MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.mindfulSession.id })
    #expect(MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.workout.id })
    #expect(MetricCatalog.shareDisallowedHKIdentifiers.contains(MetricCatalog.appleMoveTime.hkIdentifier))
    #expect(Set(MetricCatalog.selectable.map(\.id)).count == MetricCatalog.selectable.count)
    #expect(MetricCatalog.selectable.contains { $0.kind == "sample.category" })
    #expect(MetricCatalog.all.allSatisfy { $0.kind == "sample.quantity" })
}

@Test func hk30CharacteristicsStayOffByDefaultAndAreFlaggedReidentifying() throws {
    #expect(MetricCatalog.characteristics.count == 6)
    #expect(MetricCatalog.characteristics.allSatisfy { $0.kind == "characteristic" })
    #expect(MetricCatalog.characteristics.allSatisfy { $0.reidentifying })
    #expect(MetricCatalog.characteristics.allSatisfy { $0.sensitivity == .sensitive })
    #expect(Set(MetricCatalog.coreDaily.map(\.id)).isDisjoint(with: Set(MetricCatalog.characteristics.map(\.id))))
    #expect(Set(MetricCatalog.all.map(\.id)).isDisjoint(with: Set(MetricCatalog.characteristics.map(\.id))))
    var draft = DataSelectionDraft(baseline: [])
    draft.invertRoutine(MetricCatalog.selectable.map(\.id))
    #expect(draft.selected.isDisjoint(with: Set(MetricCatalog.characteristics.map(\.id))))
    #expect(throws: DataSelectionError.sensitiveConfirmationRequired) {
        try draft.toggle(
            MetricCatalog.dateOfBirth.id,
            destinationName: "local-file"
        )
    }
    try draft.toggle(
        MetricCatalog.dateOfBirth.id,
        destinationName: "local-file",
        sensitiveConfirmation: "local-file"
    )
    #expect(draft.selected.contains(MetricCatalog.dateOfBirth.id))
    let rows = DataBrowser.rows(latest: [:])
    let dob = try #require(rows.first { $0.metric == MetricCatalog.dateOfBirth.id })
    #expect(dob.reidentifying)
    #expect(dob.sensitive)
    #expect(dob.subtitle == DataBrowser.characteristicCopy)
    let view = try String(
        contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Apps/Exporter-iOS/HarnessView.swift"),
        encoding: .utf8
    )
    #expect(view.contains("DataBrowser.reidentifyingBadge"))
}

@Test func ux18PresetUpgradeIsOptInDiffAndLeavesV1UntilAccepted() {
    let v1 = CoreDailyPreset.current
    #expect(v1.version == 1)
    #expect(MetricPresetAdoption.nextAction(
        shipped: v1,
        appliedVersion: nil,
        snapshots: CoreDailyPreset.snapshots
    ) == .applyNow)
    #expect(MetricPresetAdoption.nextAction(
        shipped: v1,
        appliedVersion: 1,
        snapshots: CoreDailyPreset.snapshots
    ) == .applyNow)

    let extra = MetricDeclaration(
        id: MetricID(rawValue: "ux18FixtureCadence"),
        wireId: "ux18_fixture_cadence",
        hkIdentifier: "HKQuantityTypeIdentifierWalkingSpeed",
        canonicalUnit: CanonicalUnit(symbol: "m/s"),
        wireUnit: "m/s",
        cumulative: false,
        usesHealthKitStatistics: false,
        sensitivity: .routine,
        haUnit: "m/s",
        haDeviceClass: "speed",
        haStateClass: "measurement",
        haRequiresAggregate: false
    )
    let v2 = MetricPreset(
        id: CoreDailyPreset.id,
        version: 2,
        metrics: MetricCatalog.coreDaily.filter { $0.id != MetricCatalog.mindfulSession.id } + [extra]
    )
    #expect(v2.metrics.allSatisfy { $0.sensitivity == .routine })
    let action = MetricPresetAdoption.nextAction(
        shipped: v2,
        appliedVersion: 1,
        snapshots: [1: v1]
    )
    guard case .offerDiff(let diff) = action else {
        Issue.record("expected an opt-in diff, not a silent apply")
        return
    }
    #expect(diff.added == [extra.id])
    #expect(diff.removed == [MetricCatalog.mindfulSession.id])
    #expect(diff.summary.contains("adds 1 type"))
    #expect(diff.summary.contains("removes 1 type"))

    var selection = v1.metricIDs
    #expect(selection.contains(MetricCatalog.mindfulSession.id))
    #expect(!selection.contains(extra.id))
    #expect(MetricPresetAdoption.nextAction(
        shipped: v2,
        appliedVersion: 1,
        snapshots: [1: v1]
    ) != .applyNow)

    selection = v2.metricIDs
    #expect(selection.contains(extra.id))
    #expect(!selection.contains(MetricCatalog.mindfulSession.id))
    #expect(MetricPresetAdoption.nextAction(
        shipped: v2,
        appliedVersion: 2,
        snapshots: [1: v1, 2: v2]
    ) == .applyNow)
}

/// R-65's locale matrix. The regions are chosen for the cases a single metric/imperial
/// switch gets wrong: the United Kingdom reads miles and kilograms at once, and Germany
/// reads mg/dL despite being metric throughout.
@Test(arguments: [
    ("en_US", UnitDisplayPolicy.Mass.pounds, UnitDisplayPolicy.Distance.miles, UnitDisplayPolicy.Temperature.fahrenheit, UnitDisplayPolicy.Glucose.milligramsPerDecilitre),
    ("en_GB", .kilograms, .miles, .celsius, .millimolesPerLitre),
    ("de_DE", .kilograms, .kilometres, .celsius, .milligramsPerDecilitre),
    ("fr_FR", .kilograms, .kilometres, .celsius, .milligramsPerDecilitre),
    ("sv_SE", .kilograms, .kilometres, .celsius, .millimolesPerLitre),
    ("ja_JP", .kilograms, .kilometres, .celsius, .milligramsPerDecilitre),
    ("en_AU", .kilograms, .kilometres, .celsius, .millimolesPerLitre),
])
func displayUnitsFollowTheRegion(
    identifier: String,
    mass: UnitDisplayPolicy.Mass,
    distance: UnitDisplayPolicy.Distance,
    temperature: UnitDisplayPolicy.Temperature,
    glucose: UnitDisplayPolicy.Glucose
) {
    let policy = UnitDisplayPolicy.following(Locale(identifier: identifier))
    #expect(policy.mass == mass)
    #expect(policy.distance == distance)
    #expect(policy.temperature == temperature)
    #expect(policy.glucose == glucose)

    // The override outranks the region in every direction, or it is not an override.
    let locale = Locale(identifier: identifier)
    #expect(DisplayUnitPreference.usCustomary.policy(locale: locale) == .usCustomary)
    #expect(DisplayUnitPreference.metric.policy(locale: locale) == .metric)
    #expect(DisplayUnitPreference.canonical.policy(locale: locale) == .canonical)
    #expect(DisplayUnitPreference.automatic.policy(locale: locale) == policy)
}

@Test(arguments: [
    ("en_US", false),
    ("en_GB", true),
    ("de_DE", true),
    ("ja_JP", true),
    ("en_AU", false),
])
func clockFormatFollowsTheRegionUntilOverridden(identifier: String, twentyFourHour: Bool) {
    let locale = Locale(identifier: identifier)
    #expect(ClockDisplay.system.usesTwentyFourHour(locale: locale) == twentyFourHour)
    #expect(ClockDisplay.twelveHour.usesTwentyFourHour(locale: locale) == false)
    #expect(ClockDisplay.twentyFourHour.usesTwentyFourHour(locale: locale) == true)

    // 13:45 UTC reads as an afternoon hour on both clocks, so the rendering differs
    // visibly rather than only in the formatter's configuration.
    let afternoon = Date(timeIntervalSince1970: 1_735_738_500)
    let utc = TimeZone(identifier: "UTC")!
    let twelve = ClockDisplay.twelveHour.timeString(afternoon, locale: locale, timeZone: utc)
    let twentyFour = ClockDisplay.twentyFourHour.timeString(afternoon, locale: locale, timeZone: utc)
    #expect(twelve != twentyFour)
    #expect(twentyFour.contains("13"))
    #expect(twelve.contains("1"))
}

@Test func displayUnitOverridesNeverChangeCanonicalExportValues() {
    let pounds = DataBrowser.displayMeasurement(
        10,
        unit: "kg",
        preference: .usCustomary
    )
    #expect(abs(pounds.value - 22.046_226_218_5) < 0.000_001)
    #expect(pounds.unit == "lb")
    let glucose = DataBrowser.displayMeasurement(
        180.182,
        unit: "mg/dL",
        preference: .metric
    )
    #expect(abs(glucose.value - 10) < 0.000_001)
    #expect(glucose.unit == "mmol/L")
    let canonical = DataBrowser.displayMeasurement(
        180.182,
        unit: "mg/dL",
        preference: .canonical
    )
    #expect(canonical == DisplayMeasurement(value: 180.182, unit: "mg/dL"))
}
