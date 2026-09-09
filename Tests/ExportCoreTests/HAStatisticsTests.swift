import Foundation
import MetricCatalog
import Testing
import WireFormat

@Test func haStatisticsContractIsGeneratedForEveryCatalogueMetric() {
    let cases = HAStatisticsContract.cases()
    #expect(cases.count == MetricCatalog.all.count)
    #expect(Set(cases.map(\.entityID)).count == cases.count)
    for (declaration, item) in zip(MetricCatalog.all, cases) {
        #expect(item.wireID == declaration.wireId)
        #expect(item.statistic == (declaration.cumulative ? "sum" : "mean"))
        #expect(item.granularity == (declaration.cumulative ? "P1D" : "PT1H"))
        #expect(item.unit == declaration.haUnit)
        #expect(item.deviceClass == declaration.haDeviceClass)
        #expect(item.stateClass == declaration.haStateClass)
    }
}

@Test func haStatisticsRung4FailsWhenStateClassIsOmittedEvenIfRungs123Pass() {
    let expected = HAStatisticsContract.cases().first { $0.wireID == "step_count" }!
    let mutant = HAEntitySnapshot(
        exists: true,
        state: "100",
        unit: expected.unit,
        deviceClass: expected.deviceClass,
        stateClass: nil
    )
    #expect(mutant.exists)
    #expect(mutant.unit == expected.unit)
    #expect(HAStatisticsContract.stateParses(mutant, expected: 100))
    #expect(!HAStatisticsContract.entityMatches(mutant, expected: expected))
    let rows = HARecorder.statisticsDuringPeriod(
        entityID: expected.entityID,
        states: [50, 100],
        stateClass: mutant.stateClass,
        deviceClass: mutant.deviceClass
    )
    #expect(rows.isEmpty)
}

@Test func haStatisticsRung4RecordsSumOrMeanAfterAForcedCycle() throws {
    for item in HAStatisticsContract.cases() {
        let states: [Double] = item.statistic == "sum" ? [10, 25] : [70, 80]
        let snapshot = HAEntitySnapshot(
            exists: true,
            state: String(states.last!),
            unit: item.unit,
            deviceClass: item.deviceClass,
            stateClass: item.stateClass
        )
        #expect(HAStatisticsContract.entityMatches(snapshot, expected: item))
        #expect(HAStatisticsContract.stateParses(snapshot, expected: states.last!))
        guard HAStatisticsContract.statisticsWouldRecord(
            stateClass: item.stateClass,
            deviceClass: item.deviceClass
        ) else {
            #expect(
                HARecorder.statisticsDuringPeriod(
                    entityID: item.entityID,
                    states: states,
                    stateClass: item.stateClass,
                    deviceClass: item.deviceClass
                ).isEmpty
            )
            continue
        }
        let rows = HARecorder.statisticsDuringPeriod(
            entityID: item.entityID,
            states: states,
            stateClass: item.stateClass,
            deviceClass: item.deviceClass
        )
        let row = try #require(rows.first)
        if item.statistic == "sum" {
            #expect(row.sum == 35)
            #expect(row.mean == nil)
        } else {
            #expect(row.mean == 75)
            #expect(row.sum == nil)
        }
    }
}

@Test func haStatisticsDuringPeriodParsesTheWebSocketEnvelope() throws {
    let entity = "sensor.ohe_device12_step_count_sum_p1d"
    let data = Data(
        """
        {"id":1,"type":"result","success":true,"result":{"\(entity)":[{"start":"2026-01-01T00:00:00+00:00","end":"2026-01-01T01:00:00+00:00","mean":null,"min":null,"max":null,"sum":35,"state":null}]}}
        """.utf8
    )
    let rows = try HARecorder.parseWebSocketResult(data, entityID: entity)
    #expect(rows == [
        HAStatisticsRow(
            start: "2026-01-01T00:00:00+00:00",
            end: "2026-01-01T01:00:00+00:00",
            mean: nil,
            sum: 35
        ),
    ])
}

@Test func haStatisticsRestAttributesOmitNullCatalogueFields() {
    let heart = HAStatisticsContract.cases().first { $0.wireID == "heart_rate" }!
    let attributes = HAStatisticsContract.restAttributes(for: heart)
    #expect(attributes["unit_of_measurement"] as? String == "bpm")
    #expect(attributes["state_class"] as? String == "measurement")
    #expect(attributes["device_class"] == nil)
    let snapshot = HAStatisticsContract.snapshot(from: attributes, state: "70")
    #expect(HAStatisticsContract.entityMatches(snapshot, expected: heart))
}

@Test func haStatisticsRejectsInvalidMeasurementAndEnumCombinations() {
    #expect(
        !HAStatisticsContract.statisticsWouldRecord(stateClass: "measurement", deviceClass: "energy")
    )
    #expect(
        !HAStatisticsContract.statisticsWouldRecord(stateClass: "measurement", deviceClass: "enum")
    )
    #expect(
        HARecorder.statisticsDuringPeriod(
            entityID: "sensor.bad",
            states: [1, 2],
            stateClass: "measurement",
            deviceClass: "volume"
        ).isEmpty
    )
}
