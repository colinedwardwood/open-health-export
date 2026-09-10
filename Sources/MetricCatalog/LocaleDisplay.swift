import Foundation

/// R-65: display units follow the region, per measurement family rather than per
/// measurement system. A single metric/US-customary switch gets the United Kingdom wrong
/// twice over — road distances there are miles while body mass is kilograms — and it
/// cannot express that blood pressure is read in mmHg almost everywhere regardless.
public struct UnitDisplayPolicy: Sendable, Equatable, Codable {
    public enum Mass: String, Sendable, Codable, CaseIterable { case kilograms, pounds }
    public enum Distance: String, Sendable, Codable, CaseIterable { case kilometres, miles }
    public enum Length: String, Sendable, Codable, CaseIterable { case metres, inches }
    public enum Temperature: String, Sendable, Codable, CaseIterable { case celsius, fahrenheit }
    public enum Glucose: String, Sendable, Codable, CaseIterable { case millimolesPerLitre, milligramsPerDecilitre }
    public enum Volume: String, Sendable, Codable, CaseIterable { case millilitres, fluidOunces }

    public var mass: Mass
    public var distance: Distance
    public var length: Length
    public var temperature: Temperature
    public var glucose: Glucose
    public var volume: Volume

    public init(
        mass: Mass,
        distance: Distance,
        length: Length,
        temperature: Temperature,
        glucose: Glucose,
        volume: Volume
    ) {
        self.mass = mass
        self.distance = distance
        self.length = length
        self.temperature = temperature
        self.glucose = glucose
        self.volume = volume
    }

    /// The wire units, shown unchanged. This is what a person exporting data wants to see
    /// when they are checking what we send.
    public static let canonical = UnitDisplayPolicy(
        mass: .kilograms,
        distance: .kilometres,
        length: .metres,
        temperature: .celsius,
        glucose: .milligramsPerDecilitre,
        volume: .millilitres
    )

    public static let metric = UnitDisplayPolicy(
        mass: .kilograms,
        distance: .kilometres,
        length: .metres,
        temperature: .celsius,
        glucose: .millimolesPerLitre,
        volume: .millilitres
    )

    public static let usCustomary = UnitDisplayPolicy(
        mass: .pounds,
        distance: .miles,
        length: .inches,
        temperature: .fahrenheit,
        glucose: .milligramsPerDecilitre,
        volume: .fluidOunces
    )

    /// Regions are grouped by what people there actually read, which is why the United
    /// Kingdom keeps miles, and why Germany and the United States share mg/dL for glucose
    /// while nearly everyone else reads mmol/L.
    public static func following(_ locale: Locale) -> UnitDisplayPolicy {
        let region = locale.region?.identifier ?? ""
        let customary: Set<String> = ["US", "LR", "MM"]
        let milesForDistance: Set<String> = ["US", "GB", "LR", "MM"]
        let milligramsPerDecilitre: Set<String> = ["US", "DE", "AT", "FR", "JP", "IL", "IN", "BR", "MX", "LR", "MM"]
        return UnitDisplayPolicy(
            mass: customary.contains(region) ? .pounds : .kilograms,
            distance: milesForDistance.contains(region) ? .miles : .kilometres,
            length: customary.contains(region) ? .inches : .metres,
            temperature: customary.contains(region) ? .fahrenheit : .celsius,
            glucose: milligramsPerDecilitre.contains(region) ? .milligramsPerDecilitre : .millimolesPerLitre,
            volume: customary.contains(region) ? .fluidOunces : .millilitres
        )
    }
}

/// R-65's clock half. `system` reads the region's own convention; the other two are the
/// explicit override, because a person's device region and their reading habit differ
/// more often than region data suggests.
public enum ClockDisplay: String, Sendable, Codable, CaseIterable {
    case system
    case twelveHour
    case twentyFourHour

    public var label: String {
        switch self {
        case .system: "Follow this iPhone"
        case .twelveHour: "12-hour"
        case .twentyFourHour: "24-hour"
        }
    }

    /// Asks ICU for the region's hour convention through the `j` skeleton rather than
    /// hard-coding a region list, so a locale we have never heard of still reads right.
    public func usesTwentyFourHour(locale: Locale) -> Bool {
        switch self {
        case .twelveHour:
            return false
        case .twentyFourHour:
            return true
        case .system:
            // `h` and `K` are the 12-hour pattern letters, `H` and `k` the 24-hour ones.
            // Quoted literals must be skipped: German's pattern is `HH 'Uhr'`, and a
            // substring search finds an `h` inside the quoted word.
            let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "HH"
            var quoted = false
            for character in template {
                if character == "'" {
                    quoted.toggle()
                    continue
                }
                guard !quoted else { continue }
                if character == "h" || character == "K" { return false }
            }
            return true
        }
    }

    public func timeString(
        _ date: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = DateFormatter.dateFormat(
            fromTemplate: usesTwentyFourHour(locale: locale) ? "Hmm" : "hmma",
            options: 0,
            locale: locale
        )
        return formatter.string(from: date)
    }
}
