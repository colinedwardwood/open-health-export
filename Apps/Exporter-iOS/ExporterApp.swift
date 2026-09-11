// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

@main
struct ExporterApp: App {
    @UIApplicationDelegateAdaptor(ExporterAppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            HarnessView()
        }
    }
}
