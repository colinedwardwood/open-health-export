// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import Watchdog

@Test func appRootTabsKeepDestinationsSecondFromRightAndDataBesideStatus() throws {
    #expect(AppRootTabs.allCases.map(\.rawValue) == [
        "status", "data", "destinations", "history",
    ])
    #expect(AppRootTabs.allCases.first == .status)
    #expect(AppRootTabs.allCases[1] == .data)
    #expect(AppRootTabs.destinationsIndex == AppRootTabs.allCases.count - 2)
    #expect(AppRootTabs.allCases.last == .history)
    #expect(AppRootTabs.destinations.accessibilityIdentifier == "tab-destinations")

    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let view = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessView.swift"),
        encoding: .utf8
    )
    #expect(view.contains("TabView(selection: $rootTab)"))
    #expect(view.contains("ForEach(AppRootTabs.allCases"))
    #expect(view.contains("Label(\"Status\""))
    #expect(view.contains("Label(\"Data\""))
    #expect(view.contains("Label(\"Destinations\""))
    #expect(view.contains("Label(\"History\""))
    #expect(view.contains(".tabViewStyle(.sidebarAdaptable)"))
    #expect(view.contains("rootTab = .status"))
    #expect(view.contains("rootTab = .destinations"))
    #expect(view.contains("accessibilityIdentifier(\"status-settings\")"))
    #expect(view.contains("Label(\"Settings\""))
    guard let settings = view.range(of: "private var statusSettings") else {
        Issue.record("statusSettings is missing")
        return
    }
    let window = String(view[settings.lowerBound...].prefix(1200))
    #expect(window.contains("settings-open-destinations"))
    #expect(window.contains("dataFlowExplainer"))
}
