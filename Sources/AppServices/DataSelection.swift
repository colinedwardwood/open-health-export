// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog

/// One type on the Data screen, as a person reads it (#50).
public struct DataTypeRow: Sendable, Equatable, Identifiable {
    public var id: MetricID
    public var name: String
    /// The unit in words or a familiar symbol, or nil for counts of categories.
    public var unit: String?
    /// Health records that need their own opt-in: sensitive types, and the
    /// re-identifying characteristics such as date of birth (R-66, HK-30).
    public var needsOwnOptIn: Bool
    public var selected: Bool
}

/// The Data screen's list, search and preset, worked out from the catalog (#50).
public enum DataSelection {
    public static func rows(
        selected: Set<MetricID>,
        search: String,
        catalog: [MetricDeclaration] = MetricCatalog.selectable
    ) -> (everyday: [DataTypeRow], ownOptIn: [DataTypeRow]) {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = catalog
            .map { declaration in
                DataTypeRow(
                    id: declaration.id,
                    name: declaration.displayName,
                    unit: unitLabel(declaration.wireUnit),
                    needsOwnOptIn: needsOwnOptIn(declaration),
                    selected: selected.contains(declaration.id)
                )
            }
            .filter { query.isEmpty || $0.name.lowercased().contains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (rows.filter { !$0.needsOwnOptIn }, rows.filter(\.needsOwnOptIn))
    }

    public static func needsOwnOptIn(_ declaration: MetricDeclaration) -> Bool {
        declaration.sensitivity == .sensitive || declaration.reidentifying
    }

    /// Core Daily in one tap. It replaces the everyday choices and leaves every
    /// type that needs its own opt-in exactly as the person set it: a preset never
    /// adds one, and never removes one either.
    public static func applyingCoreDaily(to selected: Set<MetricID>) -> Set<MetricID> {
        let ownOptIn = Set(MetricCatalog.selectable.filter(needsOwnOptIn).map(\.id))
        let preset = Set(MetricCatalog.coreDaily.filter { !needsOwnOptIn($0) }.map(\.id))
        return preset.union(selected.intersection(ownOptIn))
    }

    /// UX-7: units as people write them. Machine forms (`degC`, `count/min`, `1`)
    /// never reach the screen.
    public static func unitLabel(_ wireUnit: String) -> String? {
        switch wireUnit {
        case "1", "token", "": nil
        case "degC": "°C"
        case "count/min", "bpm": "beats per minute"
        case "dBASPL": "dB"
        case "min": "minutes"
        case "s": "seconds"
        case "ms": "milliseconds"
        case "count": "count"
        default: wireUnit
        }
    }
}
