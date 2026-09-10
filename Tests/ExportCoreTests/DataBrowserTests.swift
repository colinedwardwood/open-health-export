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
                DataBrowserDestination(name: "Archive folder", lastSent: "2026-09-08T11:30:00Z"),
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
    #expect(MetricCatalog.coreDaily.allSatisfy { $0.sensitivity == .routine })
    #expect(
        Set(MetricCatalog.coreDaily.map(\.id)).isDisjoint(
            with: Set(MetricCatalog.all.filter { $0.sensitivity == .sensitive }.map(\.id))
        )
    )
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
