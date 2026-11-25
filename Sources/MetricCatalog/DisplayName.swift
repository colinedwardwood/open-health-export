// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

extension MetricDeclaration {
    /// Whether HealthKit can be read for this type one day at a time: quantity types
    /// (as samples) and category types (as category records). Day-by-day reconcile
    /// depends on it; asking the day reader for any other family fails the export
    /// (#45: Mindful minutes failed every first export).
    public var readsByDay: Bool {
        kind == "sample.quantity" || isCategory
    }

    public var isCategory: Bool { kind == "sample.category" }

    /// Whether this type gets a daily total (an aggregate record and a Home Assistant
    /// sensor): every quantity type, and the category types that declare one. Mindful
    /// minutes totals the sample durations; Sleep and the symptom events have no total.
    public var hasDailyTotal: Bool {
        kind == "sample.quantity" || (isCategory && haRequiresAggregate)
    }
}

/// UX-7: the name a person reads for a metric, in sentence case. The wire id stays
/// the stable machine name; this is only for screens.
extension MetricDeclaration {
    public var displayName: String {
        if let name = Self.displayNames[wireId] {
            return name
        }
        let words = wireId.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// Names that sentence-casing the wire id gets wrong.
    private static let displayNames: [String: String] = [
        "vo2_max": "VO₂ max",
        "heart_rate_variability_sdnn": "Heart rate variability",
        "walking_running_distance": "Walking and running distance",
        "body_mass": "Weight",
        "body_mass_index": "Body mass index",
        "dietary_water": "Water",
        "oxygen_saturation": "Blood oxygen",
        "sleep_analysis": "Sleep",
        "mindful_session": "Mindful minutes",
        "apple_move_time": "Move time",
        "activity_move_mode": "Move mode",
        "exercise_time": "Exercise minutes",
        "stand_time": "Stand minutes",
        "blood_pressure_systolic": "Blood pressure (systolic)",
        "blood_pressure_diastolic": "Blood pressure (diastolic)",
        "fitzpatrick_skin_type": "Skin type",
        "workout": "Workouts",
    ]
}
