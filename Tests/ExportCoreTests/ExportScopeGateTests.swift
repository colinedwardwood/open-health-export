// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import Foundation
import Testing

private let gateDestination = "https"
private let gateHeart = MetricID(rawValue: "heart_rate")
private let gateSteps = MetricID(rawValue: "step_count")

/// Grant covering 2024-01-10 up to, but not including, 2024-02-01, all UTC.
private func gateScope(
    metrics: Set<MetricID> = [gateHeart],
    start: String? = "2024-01-10",
    end: String? = "2024-02-01"
) throws -> DestinationExportScope {
    try DestinationExportScope(
        destinationID: gateDestination,
        metrics: metrics,
        startInclusive: start.flatMap(ExportScopeGate.dayStartUTC),
        endExclusive: end.flatMap(ExportScopeGate.dayStartUTC)
    )
}

private func gateDay(_ day: String) throws -> Date {
    try #require(ExportScopeGate.dayStartUTC(day))
}

// MARK: - Configuration

@Test func exportScopeGateRefusesNewDestination() throws {
    let scope = try DestinationExportScope(destinationID: gateDestination)
    let notConfigured = ExportScopeViolation.scopeNotConfigured(destinationID: gateDestination)

    #expect(throws: notConfigured) { try ExportScopeGate.requireConfigured(scope) }
    #expect(throws: notConfigured) { try ExportScopeGate.require(metric: gateHeart, scope: scope) }
    #expect(throws: notConfigured) {
        try ExportScopeGate.require(
            metric: gateHeart,
            startDate: Date(timeIntervalSince1970: 0),
            scope: scope
        )
    }
    #expect(throws: notConfigured) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-01-15",
            rangeEndDay: "2024-01-15",
            scope: scope
        )
    }
}

@Test func exportScopeGateRefusesHalfConfiguredScopes() throws {
    let noStart = try gateScope(start: nil, end: nil)
    let noMetrics = try gateScope(metrics: [])
    let notConfigured = ExportScopeViolation.scopeNotConfigured(destinationID: gateDestination)

    #expect(throws: notConfigured) { try ExportScopeGate.requireConfigured(noStart) }
    #expect(throws: notConfigured) { try ExportScopeGate.requireConfigured(noMetrics) }
}

@Test func exportScopeGateAcceptsOpenEndedGrant() throws {
    let scope = try gateScope(end: nil)
    try ExportScopeGate.requireConfigured(scope)
    try ExportScopeGate.require(
        metric: gateHeart,
        startDate: Date(timeIntervalSince1970: 4_000_000_000),
        scope: scope
    )
    try ExportScopeGate.require(
        metric: gateHeart,
        rangeStartDay: "2099-06-01",
        rangeEndDay: nil,
        scope: scope
    )
}

// MARK: - Metric selection

@Test func exportScopeGateAllowsSelectedMetricAndRefusesOthers() throws {
    let scope = try gateScope(metrics: [gateHeart])
    let notSelected = ExportScopeViolation.metricNotSelected(
        destinationID: gateDestination,
        metric: gateSteps
    )
    let inWindow = try gateDay("2024-01-15")

    try ExportScopeGate.require(metric: gateHeart, scope: scope)

    #expect(throws: notSelected) {
        try ExportScopeGate.require(metric: gateSteps, scope: scope)
    }
    #expect(throws: notSelected) {
        try ExportScopeGate.require(metric: gateSteps, startDate: inWindow, scope: scope)
    }
    #expect(throws: notSelected) {
        try ExportScopeGate.require(
            metric: gateSteps,
            rangeStartDay: "2024-01-15",
            rangeEndDay: "2024-01-15",
            scope: scope
        )
    }
}

// MARK: - Single samples

@Test func exportScopeGateHonoursInclusiveStartAndExclusiveEnd() throws {
    let scope = try gateScope()
    let start = try gateDay("2024-01-10")
    let end = try gateDay("2024-02-01")

    try ExportScopeGate.require(metric: gateHeart, startDate: start, scope: scope)
    try ExportScopeGate.require(
        metric: gateHeart,
        startDate: end.addingTimeInterval(-1),
        scope: scope
    )

    #expect(
        throws: ExportScopeViolation.sampleBeforeStart(
            destinationID: gateDestination,
            metric: gateHeart
        )
    ) {
        try ExportScopeGate.require(
            metric: gateHeart,
            startDate: start.addingTimeInterval(-1),
            scope: scope
        )
    }
    #expect(
        throws: ExportScopeViolation.sampleAtOrAfterEnd(
            destinationID: gateDestination,
            metric: gateHeart
        )
    ) {
        try ExportScopeGate.require(metric: gateHeart, startDate: end, scope: scope)
    }
}

// MARK: - Day-granularity ranges

@Test func exportScopeGateAllowsRangeInsideWindow() throws {
    let scope = try gateScope()
    try ExportScopeGate.require(
        metric: gateHeart,
        rangeStartDay: "2024-01-10",
        rangeEndDay: "2024-01-31",
        scope: scope
    )
    try ExportScopeGate.require(
        metric: gateHeart,
        rangeStartDay: "2024-01-15",
        rangeEndDay: "2024-01-15",
        scope: scope
    )
}

@Test func exportScopeGateRefusesRangeOutsideWindow() throws {
    let scope = try gateScope()
    let atOrAfterEnd = ExportScopeViolation.rangeAtOrAfterEnd(
        destinationID: gateDestination,
        metric: gateHeart
    )

    #expect(
        throws: ExportScopeViolation.rangeBeforeStart(
            destinationID: gateDestination,
            metric: gateHeart
        )
    ) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-01-09",
            rangeEndDay: "2024-01-31",
            scope: scope
        )
    }
    // The grant's end is an exclusive instant, so a batch covering the boundary day
    // reaches past it.
    #expect(throws: atOrAfterEnd) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-02-01",
            rangeEndDay: "2024-02-01",
            scope: scope
        )
    }
    #expect(throws: atOrAfterEnd) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-01-10",
            rangeEndDay: "2024-02-01",
            scope: scope
        )
    }
}

@Test func exportScopeGateRefusesRangeStraddlingMidDayStart() throws {
    let scope = try DestinationExportScope(
        destinationID: gateDestination,
        metrics: [gateHeart],
        startInclusive: gateDay("2024-01-10").addingTimeInterval(6 * 3600),
        endExclusive: gateDay("2024-02-01")
    )
    #expect(
        throws: ExportScopeViolation.rangeBeforeStart(
            destinationID: gateDestination,
            metric: gateHeart
        )
    ) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-01-10",
            rangeEndDay: "2024-01-10",
            scope: scope
        )
    }
}

@Test func exportScopeGateRefusesReversedRange() throws {
    let scope = try gateScope()
    #expect(
        throws: ExportScopeViolation.rangeDaysReversed(
            destinationID: gateDestination,
            metric: gateHeart
        )
    ) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-01-20",
            rangeEndDay: "2024-01-15",
            scope: scope
        )
    }
}

@Test func exportScopeGateRefusesMissingDayMetadata() throws {
    let bounded = try gateScope()
    let openEnded = try gateScope(end: nil)
    let startMissing = ExportScopeViolation.rangeDayMissing(
        destinationID: gateDestination,
        metric: gateHeart,
        boundary: .rangeStart
    )

    #expect(throws: startMissing) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: nil,
            rangeEndDay: "2024-01-15",
            scope: bounded
        )
    }
    #expect(
        throws: ExportScopeViolation.rangeDayMissing(
            destinationID: gateDestination,
            metric: gateHeart,
            boundary: .rangeEnd
        )
    ) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-01-15",
            rangeEndDay: nil,
            scope: bounded
        )
    }
    // An open-ended grant still needs a start day: the grant's start always exists.
    #expect(throws: startMissing) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: nil,
            rangeEndDay: nil,
            scope: openEnded
        )
    }
}

@Test func exportScopeGateRefusesMalformedDayMetadata() throws {
    let scope = try gateScope()
    let openEnded = try gateScope(end: nil)
    let malformed = [
        "",
        "2024-1-5",
        "20240115",
        "2024/01/15",
        "2024-01-15T00:00:00Z",
        "2024-01-15 ",
        "2024-13-01",
        "2024-00-10",
        "2024-01-00",
        "2024-01-32",
        "2024-02-30",
        "2023-02-29",
        "2100-02-29",
        "1900-02-29",
        "0000-01-01",
        "abcd-ef-gh",
        "+024-01-15",
    ]
    for value in malformed {
        #expect(ExportScopeGate.dayStartUTC(value) == nil, "parsed \(value)")
        #expect(
            throws: ExportScopeViolation.rangeDayMalformed(
                destinationID: gateDestination,
                metric: gateHeart,
                boundary: .rangeStart,
                value: value
            )
        ) {
            try ExportScopeGate.require(
                metric: gateHeart,
                rangeStartDay: value,
                rangeEndDay: "2024-01-15",
                scope: scope
            )
        }
    }
    #expect(
        throws: ExportScopeViolation.rangeDayMalformed(
            destinationID: gateDestination,
            metric: gateHeart,
            boundary: .rangeEnd,
            value: "2024-01-99"
        )
    ) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-01-15",
            rangeEndDay: "2024-01-99",
            scope: scope
        )
    }
    // Corrupt end metadata denies even when the grant has no end to check against.
    #expect(
        throws: ExportScopeViolation.rangeDayMalformed(
            destinationID: gateDestination,
            metric: gateHeart,
            boundary: .rangeEnd,
            value: "not-a-day"
        )
    ) {
        try ExportScopeGate.require(
            metric: gateHeart,
            rangeStartDay: "2024-01-15",
            rangeEndDay: "not-a-day",
            scope: openEnded
        )
    }
}

// MARK: - Day parsing

@Test func exportScopeGateParsesDaysDeterministicallyInUTC() throws {
    let known: [(String, TimeInterval)] = [
        ("1970-01-01", 0),
        ("1969-12-31", -86_400),
        ("1900-03-01", -2_203_891_200),
        ("2000-02-29", 951_782_400),
        ("2000-03-01", 951_868_800),
        ("2024-01-01", 1_704_067_200),
        ("2024-01-15", 1_705_276_800),
        ("2024-02-29", 1_709_164_800),
        ("2024-12-31", 1_735_603_200),
        ("9999-12-31", 253_402_214_400),
    ]
    for (day, epoch) in known {
        #expect(ExportScopeGate.dayStartUTC(day) == Date(timeIntervalSince1970: epoch), "\(day)")
    }
    // Consecutive days are exactly 24h apart, with no locale or DST influence.
    let first = try gateDay("2024-03-30")
    #expect(try gateDay("2024-03-31") == first.addingTimeInterval(86_400))
    #expect(try gateDay("2024-04-01") == first.addingTimeInterval(2 * 86_400))
}

// MARK: - Journalling

@Test func exportScopeGateViolationsCarryStableJournalDetails() {
    let violations: [ExportScopeViolation] = [
        .scopeNotConfigured(destinationID: gateDestination),
        .metricNotSelected(destinationID: gateDestination, metric: gateHeart),
        .sampleBeforeStart(destinationID: gateDestination, metric: gateHeart),
        .sampleAtOrAfterEnd(destinationID: gateDestination, metric: gateHeart),
        .rangeDayMissing(destinationID: gateDestination, metric: gateHeart, boundary: .rangeEnd),
        .rangeDayMalformed(
            destinationID: gateDestination,
            metric: gateHeart,
            boundary: .rangeStart,
            value: "x"
        ),
        .rangeDaysReversed(destinationID: gateDestination, metric: gateHeart),
        .rangeBeforeStart(destinationID: gateDestination, metric: gateHeart),
        .rangeAtOrAfterEnd(destinationID: gateDestination, metric: gateHeart),
    ]
    #expect(
        violations.map(\.journalDetail) == [
            "scope_not_configured",
            "metric_not_selected",
            "sample_before_start",
            "sample_at_or_after_end",
            "range_day_missing",
            "range_day_malformed",
            "range_days_reversed",
            "range_before_start",
            "range_at_or_after_end",
        ]
    )
    #expect(violations.allSatisfy { $0.destinationID == gateDestination })
}
