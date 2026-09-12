// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// UX-17: search matches display name, HealthKit identifier, and curated synonyms.
public enum MetricSearch {
    public static let synonyms: [MetricID: [String]] = [
        MetricCatalog.stepCount.id: ["steps", "step"],
        MetricCatalog.bodyMass.id: ["weight"],
        MetricCatalog.heartRateVariabilitySDNN.id: ["hrv"],
        MetricCatalog.oxygenSaturation.id: ["spo2", "o2sat"],
        MetricCatalog.bloodPressureSystolic.id: ["bp", "blood pressure"],
        MetricCatalog.bloodPressureDiastolic.id: ["bp", "blood pressure"],
        MetricCatalog.vo2Max.id: ["vo2", "vo2max", "vo2 max"],
        MetricCatalog.bloodGlucose.id: ["glucose"],
        MetricCatalog.biologicalSex.id: ["sex", "gender"],
        MetricCatalog.bloodType.id: ["blood type"],
        MetricCatalog.dateOfBirth.id: ["dob", "birthday", "birth date"],
        MetricCatalog.fitzpatrickSkinType.id: ["skin type"],
        MetricCatalog.wheelchairUse.id: ["wheelchair"],
        MetricCatalog.activityMoveMode.id: ["move mode"],
    ]

    public static func haystack(for declaration: MetricDeclaration) -> String {
        let title = declaration.wireId.replacingOccurrences(of: "_", with: " ")
        var parts = [
            title,
            declaration.wireId,
            declaration.hkIdentifier,
            declaration.id.rawValue,
            camelWords(declaration.id.rawValue),
        ]
        parts.append(contentsOf: synonyms[declaration.id] ?? [])
        return parts.joined(separator: " ").lowercased()
    }

    public static func matches(_ declaration: MetricDeclaration, needle: String) -> Bool {
        let trimmed = needle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        let blob = haystack(for: declaration)
        if trimmed.count >= 4 {
            return blob.contains(trimmed)
        }
        let tokens = blob.split { !$0.isLetter && !$0.isNumber }
        if tokens.contains(where: { $0 == trimmed }) { return true }
        return (synonyms[declaration.id] ?? []).contains { $0.lowercased() == trimmed }
    }

    private static func camelWords(_ raw: String) -> String {
        raw.unicodeScalars.reduce(into: "") { acc, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !acc.isEmpty {
                acc.append(" ")
            }
            acc.append(Character(scalar))
        }
    }
}
