// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

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

    /// #43: release builds only ever show the product app; the harness is a debug
    /// Developer screen, and a debug root only while the UI suite still drives it.
    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if UITestFixtures.launchesHarness {
            HarnessView(authenticator: UserPresenceAuthenticatorFactory.make())
        } else {
            RootView(authenticator: UserPresenceAuthenticatorFactory.make())
        }
        #else
        RootView(authenticator: UserPresenceAuthenticatorFactory.make())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            root
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
