// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

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

}
