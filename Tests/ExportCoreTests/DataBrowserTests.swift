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
    #expect(Set(MetricCatalog.coreDaily.map(\.id)).isSubset(of: Set(MetricCatalog.all.map(\.id))))
    #expect(
        Set(MetricCatalog.coreDaily.map(\.id)).isDisjoint(
            with: Set(MetricCatalog.all.filter { $0.sensitivity == .sensitive }.map(\.id))
        )
    )
    #expect(!MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.bloodGlucose.id })
    #expect(Set(MetricCatalog.coreDaily.map(\.id)).count == MetricCatalog.coreDaily.count)
    #expect(MetricCatalog.coreDaily.count == 24)
    #expect(MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.swimmingDistance.id })
    #expect(MetricCatalog.coreDaily.contains { $0.id == MetricCatalog.environmentalAudioExposure.id })
    #expect(MetricCatalog.shareDisallowedHKIdentifiers.contains(MetricCatalog.appleMoveTime.hkIdentifier))
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
