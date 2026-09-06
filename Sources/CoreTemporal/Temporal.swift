import Foundation

/// The only module that constructs `Calendar`, `TimeZone`, and `Locale`.
public struct TemporalContext: Sendable {
    public var timeZoneIdentifier: String
    public var localeIdentifier: String
    public var tzDatabaseVersion: String

    public init(
        timeZoneIdentifier: String,
        localeIdentifier: String,
        tzDatabaseVersion: String
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localeIdentifier = localeIdentifier
        self.tzDatabaseVersion = tzDatabaseVersion
    }

    public func timeZone() -> TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
    }

    public func locale() -> Locale {
        Locale(identifier: localeIdentifier)
    }

    public func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone()
        calendar.locale = locale()
        return calendar
    }
}

public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

public struct FrozenClock: Clock {
    public var instant: Date
    public init(instant: Date) { self.instant = instant }
    public func now() -> Date { instant }
}

public struct DayBucket: Hashable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func containing(_ date: Date, context: TemporalContext) -> DayBucket {
        let components = context.calendar().dateComponents([.year, .month, .day], from: date)
        return DayBucket(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }

    public var isoDay: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public struct DayBucketBounds: Sendable, Equatable {
    public var bucketStart: String
    public var bucketEnd: String
    public var bucketDurationSeconds: Int
    public var localStart: String

    public init(bucketStart: String, bucketEnd: String, bucketDurationSeconds: Int, localStart: String) {
        self.bucketStart = bucketStart
        self.bucketEnd = bucketEnd
        self.bucketDurationSeconds = bucketDurationSeconds
        self.localStart = localStart
    }
}

public enum BucketKey {
    /// Stable R-06 identity: metric|statistic|granularity|bucketStart|tz|scope.
    public static func render(
        metricWireId: String,
        statistic: String,
        granularity: String,
        bucketStart: String,
        timeZoneIdentifier: String,
        sourceScope: String
    ) -> String {
        [metricWireId, statistic, granularity, bucketStart, timeZoneIdentifier, sourceScope]
            .joined(separator: "|")
    }

    /// P1D bounds in the context time zone. DST may yield 23h/25h durations.
    public static func boundsP1D(day: String, context: TemporalContext) -> DayBucketBounds? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let calendar = context.calendar()
        var startComponents = DateComponents()
        startComponents.year = parts[0]
        startComponents.month = parts[1]
        startComponents.day = parts[2]
        startComponents.hour = 0
        startComponents.minute = 0
        startComponents.second = 0
        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let duration = Int(end.timeIntervalSince(start))
        return DayBucketBounds(
            bucketStart: formatter.string(from: start),
            bucketEnd: formatter.string(from: end),
            bucketDurationSeconds: duration,
            localStart: "\(day)T00:00:00"
        )
    }
}
