// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(HealthKit)
import CoreDomain
import Foundation
import HealthKitSource
import MetricCatalog
import Testing

private actor ScriptedAuthorizationProvider: HealthAuthorizationStatusProvider {
    private var states: [HealthAuthorizationRequestState]

    init(_ states: [HealthAuthorizationRequestState]) {
        self.states = states
    }

    func requestState(
        for metrics: [MetricID]
    ) async throws -> HealthAuthorizationRequestState {
        states.removeFirst()
    }
}

@Test func authorizationObserverPurgesOnlyOnAnObservedRevocationTransition() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-auth-\(UUID().uuidString).json")
    let provider = ScriptedAuthorizationProvider([
        .shouldRequest,
        .unnecessary,
        .unknown,
        .shouldRequest,
    ])
    let observer = HealthAuthorizationObserver(provider: provider, recordURL: url)
    let grant = HealthAuthorizationGrant(
        id: "core-activity",
        metrics: [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id]
    )

    #expect(try await observer.observe(grants: [grant], atEpoch: 1).isEmpty)
    #expect(try await observer.observe(grants: [grant], atEpoch: 2).isEmpty)
    #expect(try await observer.observe(grants: [grant], atEpoch: 3).isEmpty)
    let changes = try await observer.observe(grants: [grant], atEpoch: 4)
    #expect(changes == [HealthAuthorizationChange(grant: grant, observedAtEpoch: 4)])
}

@Test func authorizationObserverPersistsStateAcrossProcessReplacement() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-auth-restart-\(UUID().uuidString).json")
    let grant = HealthAuthorizationGrant(
        id: "core-activity",
        metrics: [MetricCatalog.heartRate.id]
    )
    let first = HealthAuthorizationObserver(
        provider: ScriptedAuthorizationProvider([.unnecessary]),
        recordURL: url
    )
    #expect(try await first.observe(grants: [grant], atEpoch: 1).isEmpty)

    let afterRestart = HealthAuthorizationObserver(
        provider: ScriptedAuthorizationProvider([.shouldRequest]),
        recordURL: url
    )
    #expect(
        try await afterRestart.observe(grants: [grant], atEpoch: 2)
            == [HealthAuthorizationChange(grant: grant, observedAtEpoch: 2)]
    )
}
#endif
