// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// Which end of a day-granularity range a violation refers to.
public enum ExportScopeDayBoundary: String, Sendable, Equatable {
    case rangeStart
    case rangeEnd
}

/// SEC-16 refusals. One case per reason so a caller can journal the cause without
/// re-deriving it, and `Equatable` so tests assert the reason rather than "it threw".
public enum ExportScopeViolation: Error, Equatable, Sendable {
    /// The destination has no grant yet: no metrics, or no start date, or neither.
    case scopeNotConfigured(destinationID: String)
    /// The metric is not one the user chose for this destination.
    case metricNotSelected(destinationID: String, metric: MetricID)
    /// The sample begins before the granted start instant.
    case sampleBeforeStart(destinationID: String, metric: MetricID)
    /// The sample begins at or after the granted end instant, which is exclusive.
    case sampleAtOrAfterEnd(destinationID: String, metric: MetricID)
    /// Day metadata needed to bound the check is absent, so nothing can be proven.
    case rangeDayMissing(destinationID: String, metric: MetricID, boundary: ExportScopeDayBoundary)
    /// Day metadata is present but is not a calendar day in `yyyy-MM-dd` form.
    case rangeDayMalformed(
        destinationID: String,
        metric: MetricID,
        boundary: ExportScopeDayBoundary,
        value: String
    )
    /// The end day precedes the start day, so the covered interval is not knowable.
    case rangeDaysReversed(destinationID: String, metric: MetricID)
    /// The range starts before the granted start instant.
    case rangeBeforeStart(destinationID: String, metric: MetricID)
    /// The range extends to or past the granted end instant.
    case rangeAtOrAfterEnd(destinationID: String, metric: MetricID)

    /// Stable snake_case cause for journal details and status records.
    public var journalDetail: String {
        switch self {
        case .scopeNotConfigured: "scope_not_configured"
        case .metricNotSelected: "metric_not_selected"
        case .sampleBeforeStart: "sample_before_start"
        case .sampleAtOrAfterEnd: "sample_at_or_after_end"
        case .rangeDayMissing: "range_day_missing"
        case .rangeDayMalformed: "range_day_malformed"
        case .rangeDaysReversed: "range_days_reversed"
        case .rangeBeforeStart: "range_before_start"
        case .rangeAtOrAfterEnd: "range_at_or_after_end"
        }
    }

    public var destinationID: String {
        switch self {
        case let .scopeNotConfigured(destinationID),
             let .metricNotSelected(destinationID, _),
             let .sampleBeforeStart(destinationID, _),
             let .sampleAtOrAfterEnd(destinationID, _),
             let .rangeDayMissing(destinationID, _, _),
             let .rangeDayMalformed(destinationID, _, _, _),
             let .rangeDaysReversed(destinationID, _),
             let .rangeBeforeStart(destinationID, _),
             let .rangeAtOrAfterEnd(destinationID, _):
            destinationID
        }
    }
}

/// SEC-16: the one place that decides whether a health record may leave for a
/// destination. Every check is pure and fail-closed — it throws unless the grant
/// positively permits the data — so a missing scope, an unselected metric or
/// unreadable range metadata all deny rather than fall back to a global default.
///
/// Policy, stated once so callers do not each invent their own:
///
/// - A start instant is mandatory. `DestinationExportScope.isConfigured` is false
///   without one, and an absent start is deny, not "since forever".
/// - An absent end is allowed and means open-ended: the grant runs to now and past it.
/// - The window is start-inclusive and end-exclusive, matching
///   `DestinationExportScope.allows(metric:sampleStart:)`.
/// - Day metadata (`PendingBatch.rangeStartDay`, `GapRecord.rangeEndDay`) denotes UTC
///   days and is read as the half-open instant interval
///   `[startDay 00:00Z, endDay 00:00Z + 24h)`. That whole interval must fall inside the
///   grant, because a batch queued under a wider grant must not be delivered after the
///   user narrows it.
public enum ExportScopeGate {
    /// A destination with no chosen metrics or no start date receives nothing.
    public static func requireConfigured(_ scope: DestinationExportScope) throws {
        guard scope.isConfigured else {
            throw ExportScopeViolation.scopeNotConfigured(destinationID: scope.destinationID)
        }
    }

    /// The metric must be one the user selected for this destination.
    public static func require(metric: MetricID, scope: DestinationExportScope) throws {
        try requireConfigured(scope)
        guard scope.metrics.contains(metric) else {
            throw ExportScopeViolation.metricNotSelected(
                destinationID: scope.destinationID,
                metric: metric
            )
        }
    }

    /// One sample. `startDate` is the sample's start instant, the same instant the
    /// model's `allows(metric:sampleStart:)` judges.
    public static func require(
        metric: MetricID,
        startDate: Date,
        scope: DestinationExportScope
    ) throws {
        try require(metric: metric, scope: scope)
        guard let startInclusive = scope.startInclusive else {
            throw ExportScopeViolation.scopeNotConfigured(destinationID: scope.destinationID)
        }
        guard startDate >= startInclusive else {
            throw ExportScopeViolation.sampleBeforeStart(
                destinationID: scope.destinationID,
                metric: metric
            )
        }
        if let endExclusive = scope.endExclusive, startDate >= endExclusive {
            throw ExportScopeViolation.sampleAtOrAfterEnd(
                destinationID: scope.destinationID,
                metric: metric
            )
        }
    }

    /// A queued batch or a reconcile gap, which carry UTC day strings rather than
    /// instants. The start day is always required because the grant's start always
    /// exists; the end day is required only when the grant has an end to check against.
    public static func require(
        metric: MetricID,
        rangeStartDay: String?,
        rangeEndDay: String?,
        scope: DestinationExportScope
    ) throws {
        try require(metric: metric, scope: scope)
        guard let startInclusive = scope.startInclusive else {
            throw ExportScopeViolation.scopeNotConfigured(destinationID: scope.destinationID)
        }

        let startDay = try day(
            rangeStartDay,
            boundary: .rangeStart,
            metric: metric,
            scope: scope
        )
        guard startDay >= startInclusive else {
            throw ExportScopeViolation.rangeBeforeStart(
                destinationID: scope.destinationID,
                metric: metric
            )
        }

        // Present-but-unparseable end metadata is a refusal even when the grant is
        // open-ended: corrupt metadata is never evidence that the data is in scope.
        guard scope.endExclusive != nil || rangeEndDay != nil else { return }
        let endDay = try day(
            rangeEndDay,
            boundary: .rangeEnd,
            metric: metric,
            scope: scope
        )
        guard endDay >= startDay else {
            throw ExportScopeViolation.rangeDaysReversed(
                destinationID: scope.destinationID,
                metric: metric
            )
        }
        guard let endExclusive = scope.endExclusive else { return }
        guard endDay.addingTimeInterval(secondsPerDay) <= endExclusive else {
            throw ExportScopeViolation.rangeAtOrAfterEnd(
                destinationID: scope.destinationID,
                metric: metric
            )
        }
    }

    /// Midnight UTC starting the given `yyyy-MM-dd` day, or nil if the string is not
    /// exactly that. Pure integer arithmetic on the proleptic Gregorian calendar: no
    /// locale, no time zone database, identical on every host and OS version.
    public static func dayStartUTC(_ day: String) -> Date? {
        guard let daysFromEpoch = civilDaysFromEpoch(day) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(daysFromEpoch) * secondsPerDay)
    }

    static let secondsPerDay: TimeInterval = 86_400

    private static func day(
        _ value: String?,
        boundary: ExportScopeDayBoundary,
        metric: MetricID,
        scope: DestinationExportScope
    ) throws -> Date {
        guard let value else {
            throw ExportScopeViolation.rangeDayMissing(
                destinationID: scope.destinationID,
                metric: metric,
                boundary: boundary
            )
        }
        guard let start = dayStartUTC(value) else {
            throw ExportScopeViolation.rangeDayMalformed(
                destinationID: scope.destinationID,
                metric: metric,
                boundary: boundary,
                value: value
            )
        }
        return start
    }

    /// Strict `yyyy-MM-dd`: ten ASCII characters, zero-padded fields, real calendar
    /// days only. "2024-1-5", "2024-02-30" and "2024-01-15T00:00:00Z" are all rejected,
    /// because a gate that guesses at a date is a gate that lets data out.
    private static func civilDaysFromEpoch(_ day: String) -> Int? {
        let bytes = Array(day.utf8)
        let dash = UInt8(ascii: "-")
        guard bytes.count == 10, bytes[4] == dash, bytes[7] == dash,
              let year = number(bytes, 0 ..< 4),
              let month = number(bytes, 5 ..< 7),
              let dayOfMonth = number(bytes, 8 ..< 10),
              year >= 1, year <= 9999,
              month >= 1, month <= 12,
              dayOfMonth >= 1, dayOfMonth <= daysIn(month: month, year: year)
        else { return nil }

        // Hinnant's days_from_civil, with March as month zero so the leap day lands at
        // the end of the year and needs no special case.
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = shiftedYear / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + dayOfMonth - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func number(_ bytes: [UInt8], _ range: Range<Int>) -> Int? {
        var value = 0
        for index in range {
            let digit = Int(bytes[index]) - Int(UInt8(ascii: "0"))
            guard digit >= 0, digit <= 9 else { return nil }
            value = value * 10 + digit
        }
        return value
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    private static func isLeap(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }
}
