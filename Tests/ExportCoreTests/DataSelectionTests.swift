// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import CoreDomain
import MetricCatalog
import Testing

@Test func presetsNeverIncludeATypeThatNeedsItsOwnOptIn() {
    let applied = DataSelection.applyingCoreDaily(to: [])
    for id in applied {
        let declaration = MetricCatalog.declaration(for: id)!
        #expect(!DataSelection.needsOwnOptIn(declaration), "\(id.rawValue)")
    }
    #expect(applied.contains(MetricCatalog.stepCount.id))
}

@Test func coreDailyKeepsTheSensitiveChoicesThePersonMade() {
    let sensitive = MetricCatalog.selectable.first(where: DataSelection.needsOwnOptIn)!.id
    let applied = DataSelection.applyingCoreDaily(to: [sensitive, MetricCatalog.vo2Max.id])
    #expect(applied.contains(sensitive))
}

@Test func dataRowsUseNamesAndUnitsPeopleRead() {
    let (everyday, ownOptIn) = DataSelection.rows(selected: [], search: "")
    #expect(!everyday.isEmpty && !ownOptIn.isEmpty)
    for row in everyday + ownOptIn {
        #expect(!row.name.contains("_"), "\(row.name)")
        if let unit = row.unit {
            #expect(!["degC", "dBASPL", "count/min", "1", "token"].contains(unit), "\(row.name): \(unit)")
        }
    }
    #expect(everyday.first { $0.id == MetricCatalog.heartRate.id }?.unit == "beats per minute")
}

@Test func searchMatchesTheNamePeopleSee() {
    let (everyday, _) = DataSelection.rows(selected: [], search: "heart")
    #expect(everyday.contains { $0.id == MetricCatalog.heartRate.id })
    #expect(!everyday.contains { $0.id == MetricCatalog.stepCount.id })
}
