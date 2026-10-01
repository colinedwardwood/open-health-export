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

    /// `OHE_RESET_FIRST_RUN=1` clears the disclosure acknowledgement so first run
    /// starts again. A launch argument can't do this: it lands in the read-only
    /// argument domain, where first run's own write would never take effect.
    static func applyLaunchResets() {
        // Destinations and reports survive across cases in one simulator; the harness
        // applies the same reset when it is the root.
        if environment["OHE_RESET_SEEDED_SURFACES"] == "1" {
            try? HarnessExport.resetSeededSurfacesForUITests()
        }
        if environment["OHE_RESET_FIRST_RUN"] == "1" {
            UserDefaults.standard.removeObject(forKey: SettingKey.disclosureAcknowledged.rawValue)
        }
    }

    /// `OHE_SEED_LOCAL_EXPORT_FOLDER=1`: first run uses a seeded folder in place of
    /// the Files picker, which UI tests can't drive.
    static var seedsLocalExportFolder: Bool {
        environment["OHE_SEED_LOCAL_EXPORT_FOLDER"] == "1"
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
