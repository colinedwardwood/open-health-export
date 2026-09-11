// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

public enum UnitMathError: Error, Equatable {
    case nonFinite
    case zeroSpeed
}

/// Canonical SI conversions used on the Linux core. HealthKit adapters convert *into* these units;
/// the exporter never silently clamps or emits non-finite results.
public enum UnitMath {
    public static let glucoseMillimolesPerLitreToMilligramsPerDecilitre = 18.0182

    public static func milligramsPerDecilitre(fromMillimolesPerLitre value: Double) throws -> Double {
        try finite(value) * glucoseMillimolesPerLitreToMilligramsPerDecilitre
    }

    public static func celsius(fromFahrenheit value: Double) throws -> Double {
        (try finite(value) - 32) * 5 / 9
    }

    public static func fahrenheit(fromCelsius value: Double) throws -> Double {
        try finite(value) * 9 / 5 + 32
    }

    public static func kilograms(fromPounds value: Double) throws -> Double {
        try finite(value) * 0.45359237
    }

    public static func pounds(fromKilograms value: Double) throws -> Double {
        try finite(value) / 0.45359237
    }

    public static func kilometres(fromMiles value: Double) throws -> Double {
        try finite(value) * 1.609344
    }

    public static func miles(fromKilometres value: Double) throws -> Double {
        try finite(value) / 1.609344
    }

    public static func millimolesPerLitre(fromMilligramsPerDecilitre value: Double) throws -> Double {
        try finite(value) / glucoseMillimolesPerLitreToMilligramsPerDecilitre
    }

    public static func inches(fromMetres value: Double) throws -> Double {
        try finite(value) / 0.0254
    }

    public static func fluidOunces(fromMillilitres value: Double) throws -> Double {
        try finite(value) / 29.5735295625
    }

    public static func kilojoules(fromKilocalories value: Double) throws -> Double {
        try finite(value) * 4.184
    }

    public static func kilopascals(fromMillimetresOfMercury value: Double) throws -> Double {
        try finite(value) * 0.133322
    }

    public static func paceMinutesPerKilometre(metersPerSecond: Double) throws -> Double {
        let speed = try finite(metersPerSecond)
        guard speed > 0 else { throw UnitMathError.zeroSpeed }
        return (1000 / speed) / 60
    }

    private static func finite(_ value: Double) throws -> Double {
        guard value.isFinite else { throw UnitMathError.nonFinite }
        return value
    }
}
