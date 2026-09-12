// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// HK-03: every SDK type identifier is either in the selectable catalogue or
/// listed with a reason. The identifier list is generated from HealthKit headers,
/// not typed by hand.
public enum HealthKitCoverage {
    public struct Exclusion: Sendable, Equatable, Codable {
        public var identifier: String
        public var reason: String
    }

    public static func identifiers(fromHeader text: String) -> [String] {
        var found: Set<String> = []
        let pattern = try! NSRegularExpression(pattern: #"const (HK[A-Za-z0-9]+)"#)
        let ns = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            found.insert(ns.substring(with: match.range(at: 1)))
        }
        return found.sorted()
    }

    public static func catalogIdentifiers(
        _ declarations: [MetricDeclaration] = MetricCatalog.selectable
    ) -> Set<String> {
        Set(declarations.map(\.hkIdentifier))
    }

    public static func uncovered(
        sdk: Set<String>,
        catalog: Set<String>,
        excluded: Set<String>
    ) -> Set<String> {
        sdk.subtracting(catalog).subtracting(excluded)
    }

    public static func overlap(catalog: Set<String>, excluded: Set<String>) -> Set<String> {
        catalog.intersection(excluded)
    }
}
