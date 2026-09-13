// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-44: map HealthKit `preferredUnits` unit strings onto the display policy.
/// Unknown strings leave the fallback family unchanged so region policy still
/// covers types Health has not answered.
public enum HealthDisplayUnitMapping {
    public static func overlay(
        mass: String?,
        distance: String?,
        length: String?,
        temperature: String?,
        glucose: String?,
        volume: String?,
        onto fallback: UnitDisplayPolicy
    ) -> UnitDisplayPolicy {
        UnitDisplayPolicy(
            mass: Self.mass(from: mass) ?? fallback.mass,
            distance: Self.distance(from: distance) ?? fallback.distance,
            length: Self.length(from: length) ?? fallback.length,
            temperature: Self.temperature(from: temperature) ?? fallback.temperature,
            glucose: Self.glucose(from: glucose) ?? fallback.glucose,
            volume: Self.volume(from: volume) ?? fallback.volume
        )
    }

    public static func mass(from unit: String?) -> UnitDisplayPolicy.Mass? {
        switch normalize(unit) {
        case "lb", "lb_av": .pounds
        case "kg", "g": .kilograms
        default: nil
        }
    }

    public static func distance(from unit: String?) -> UnitDisplayPolicy.Distance? {
        switch normalize(unit) {
        case "mi": .miles
        case "m", "km": .kilometres
        default: nil
        }
    }

    public static func length(from unit: String?) -> UnitDisplayPolicy.Length? {
        switch normalize(unit) {
        case "in", "ft": .inches
        case "m", "cm": .metres
        default: nil
        }
    }

    public static func temperature(from unit: String?) -> UnitDisplayPolicy.Temperature? {
        switch normalize(unit) {
        case "degf": .fahrenheit
        case "degc": .celsius
        default: nil
        }
    }

    public static func glucose(from unit: String?) -> UnitDisplayPolicy.Glucose? {
        let unit = normalize(unit)
        if unit.contains("mmol") { return .millimolesPerLitre }
        if unit.contains("mg/dl") || unit == "mg%" { return .milligramsPerDecilitre }
        return nil
    }

    public static func volume(from unit: String?) -> UnitDisplayPolicy.Volume? {
        switch normalize(unit) {
        case "fl_oz", "cup_us": .fluidOunces
        case "ml", "l": .millilitres
        default: nil
        }
    }

    private static func normalize(_ unit: String?) -> String {
        (unit ?? "")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}
