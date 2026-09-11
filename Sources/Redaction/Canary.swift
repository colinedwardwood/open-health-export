// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Seeded R-51 canary values. Every egress-capable sink is grepped for these tokens.
#if DEBUG
public enum RedactionCanary {
    public static let hostname = "clinic.example.org"
    public static let secret = "bearer-secret-token-0123456789"
    public static let sampleValue = "72.123456"
    public static let sourceName = "Dexcom G7"
    // The suffix keeps this distinguishable from the real supported HealthKit identifier.
    public static let healthType = "HKCategoryTypeIdentifierSexualActivity.redaction-canary"

    public static let tokens: [String] = [
        hostname,
        secret,
        sampleValue,
        sourceName,
        healthType,
    ]

    public static func leaks(in text: String) -> [String] {
        tokens.filter { text.contains($0) }
    }

    public static func isClean(_ text: String) -> Bool {
        leaks(in: text).isEmpty
    }
}
#endif

/// Adding a `RedactionSink` without updating this list fails the registry test.
public enum CanarySinkRegistry {
    public static let expected: [String] = [
        "bundle",
        "journal",
        "notification",
        "otlp",
        "ui",
        "widget",
    ]
}
