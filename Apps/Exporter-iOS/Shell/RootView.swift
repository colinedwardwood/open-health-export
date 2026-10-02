// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import SwiftUI

/// The product app's root: four tabs, one navigation stack each, with the privacy
/// lock over everything (#43). Screens are filled in by #45–#52.
struct RootView: View {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init(authenticator: any UserPresenceAuthenticating) {
        #if DEBUG
        UITestFixtures.applyLaunchResets()
        #endif
        _model = State(initialValue: AppModel(authenticator: authenticator))
    }

    var body: some View {
        ZStack {
            TabView(selection: $model.selectedTab) {
                Tab("Status", systemImage: "checkmark.circle", value: AppTab.status) {
                    stack(.status) { StatusScreen() }
                }
                Tab("Data", systemImage: "chart.bar", value: AppTab.data) {
                    stack(.data) { PlaceholderScreen(title: "Data") }
                }
                Tab("Destinations", systemImage: "arrow.right.to.line", value: AppTab.destinations) {
                    stack(.destinations) { DestinationsScreen() }
                }
                Tab("History", systemImage: "clock", value: AppTab.history) {
                    stack(.history) { PlaceholderScreen(title: "History") }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .environment(model)

            if model.isLocked {
                PrivacyLockScreen(gate: model.privacyGate) {
                    Task { await model.unlock() }
                }
            }
        }
        .fullScreenCover(item: $model.onboarding) { onboarding in
            OnboardingFlow(resuming: onboarding.resuming) {
                model.finishOnboarding()
            }
        }
        .task { await model.start() }
        .onOpenURL { model.route($0) }
        .onChange(of: scenePhase) { _, next in
            if next == .active {
                Task { await model.sceneBecameActive() }
            } else {
                model.sceneLeftForeground()
            }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $model.showsDeveloper) {
            DeveloperScreen()
        }
        #endif
    }

    private func stack(_ tab: AppTab, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: Binding(
            get: { model.paths[tab] ?? [] },
            set: { model.paths[tab] = $0 }
        )) {
            root()
                .navigationDestination(for: AppRoute.self) { route in
                    RouteScreen(route: route)
                }
        }
    }
}

/// One screen per pushable route.
private struct RouteScreen: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case let .destination(id):
            DestinationDetailScreen(destinationID: id)
        case let .destinationError(id, archetype):
            DestinationErrorScreen(destinationID: id, archetype: archetype)
        case .settings:
            SettingsScreen()
        }
    }
}
