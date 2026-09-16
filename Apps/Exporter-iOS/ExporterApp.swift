// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import SwiftUI
import UIKit

@main
struct ExporterApp: App {
    @UIApplicationDelegateAdaptor(ExporterAppDelegate.self)
    private var appDelegate

    init() {
        // The same binary runs on both, and every piece of copy that names the
        // device asks here rather than assuming a phone.
        DeviceNoun.configure(
            idiomIsPad: UIDevice.current.userInterfaceIdiom == .pad
        )
    }

    var body: some Scene {
        WindowGroup {
            HarnessView(authenticator: UserPresenceAuthenticatorFactory.make())
                .modifier(AccessibilityMatrixModifier())
        }
    }
}

private struct AccessibilityMatrixModifier: ViewModifier {
    #if DEBUG
    private let enabled =
        ProcessInfo.processInfo.environment["OHE_ACCESSIBILITY_MATRIX"]
            == "combined"
    #endif

    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG
        if enabled {
            content
                .environment(\.colorScheme, .dark)
                .environment(\.legibilityWeight, .bold)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
