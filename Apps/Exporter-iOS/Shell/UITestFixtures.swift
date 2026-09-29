// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

#if DEBUG
/// Launch-environment hooks for UI tests, gathered in one place so they can move
/// behind a UI_TESTING build configuration without touching the screens (#43).
enum UITestFixtures {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// `OHE_ROOT=harness` launches the engineering harness as the root view, which
    /// the existing UI suite drives until #56 re-points it at the product screens.
    static var launchesHarness: Bool {
        environment["OHE_ROOT"] == "harness"
    }

    /// `OHE_OPEN_URL` is delivered through the same router a tapped notification uses.
    @MainActor
    static func applyOpenURL(to model: AppModel) {
        if let raw = environment["OHE_OPEN_URL"], let url = URL(string: raw) {
            model.route(url)
        }
    }
}
#endif
