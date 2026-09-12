// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Production iPhone/iPad root tabs. Order is load-bearing (R-41): Destinations is
/// always second from the right, Data is always adjacent to the default Status tab.
public enum AppRootTabs: String, CaseIterable, Hashable, Sendable {
    case status
    case data
    case destinations
    case history

    public var accessibilityIdentifier: String {
        "tab-\(rawValue)"
    }

    public var systemImage: String {
        switch self {
        case .status: "checkmark.circle"
        case .data: "heart"
        case .destinations: "paperplane"
        case .history: "clock"
        }
    }

    public static var destinationsIndex: Int {
        allCases.firstIndex(of: .destinations)!
    }
}
