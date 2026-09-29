// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import Watchdog

/// The product app's four tabs, in tab-bar order (#43).
public enum AppTab: String, Sendable, Hashable, CaseIterable {
    case status
    case data
    case destinations
    case history
}

/// A screen pushed onto a tab's navigation stack.
public enum AppRoute: Sendable, Hashable {
    case destination(id: String)
    /// The five-part error for one destination. The archetype is the one the
    /// notification named; without it the screen works it out from the snapshot.
    case destinationError(id: String, archetype: UserFacingErrorArchetype?)
    case settings
}

/// Where a link sends the app: which tab, what is pushed on it, and whether the
/// link also asks for an export.
public struct NavigationTarget: Sendable, Equatable {
    public var tab: AppTab
    public var path: [AppRoute]
    public var exportNow: Bool

    public init(tab: AppTab, path: [AppRoute] = [], exportNow: Bool = false) {
        self.tab = tab
        self.path = path
        self.exportNow = exportNow
    }
}

/// One place that turns every link the app receives (failure notifications, the
/// widget, the Export Now control, the URL scheme) into a navigation target, so a
/// cold launch and a warm one land on the same screen (SWE-10).
public enum DeepLinkRouter {
    /// Nil when the URL is not one of ours. Before the disclosure is acknowledged
    /// every link lands on Status, where first run takes over; nothing opens a
    /// destination or starts an export for someone who has not read what the app does.
    public static func target(for url: URL, disclosureAcknowledged: Bool) -> NavigationTarget? {
        let target: NavigationTarget
        if let route = UserFacingErrorRoute(url: url) {
            target = NavigationTarget(
                tab: .status,
                path: [.destinationError(id: route.destinationID, archetype: route.archetype)]
            )
        } else if ExportNowRoute(url: url) != nil {
            target = NavigationTarget(tab: .status, exportNow: true)
        } else if let route = WidgetStatusRoute(url: url) {
            target = NavigationTarget(
                tab: .status,
                path: route.destinationID.map { [.destination(id: $0)] } ?? []
            )
        } else {
            return nil
        }
        return disclosureAcknowledged ? target : NavigationTarget(tab: .status)
    }
}
