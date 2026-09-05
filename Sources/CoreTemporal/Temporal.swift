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
}
