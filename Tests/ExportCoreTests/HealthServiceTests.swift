// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import Foundation
import Testing

private final class MemoryObserverFailureStorage: ObserverFailureStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: String]?

    init(_ stored: [String: String]? = nil) {
        self.stored = stored
    }

    var value: [String: String]? { lock.withLock { stored } }

    func load() -> [String: String]? { lock.withLock { stored } }

    func save(_ failures: [String: String]?) { lock.withLock { stored = failures } }
}

@Test func healthObserversNeedHealthAndAnAcknowledgedDisclosure() {
    #expect(HealthObserverPolicy.mayObserve(healthAvailable: true, disclosureAcknowledged: true))
    #expect(!HealthObserverPolicy.mayObserve(healthAvailable: false, disclosureAcknowledged: true))
    #expect(!HealthObserverPolicy.mayObserve(healthAvailable: true, disclosureAcknowledged: false))
    #expect(!HealthObserverPolicy.mayObserve(healthAvailable: false, disclosureAcknowledged: false))
}

@Test func revocationStopsObserversWithoutConsultingAutomaticExport() {
    var consulted = false
    func automatic() -> Bool {
        consulted = true
        return true
    }
    #expect(HealthObserverPolicy.action(revoked: true, automaticExport: automatic(), running: true) == .stop)
    #expect(HealthObserverPolicy.action(revoked: true, automaticExport: automatic(), running: false) == .stop)
    #expect(!consulted)
}

@Test func observersFollowAutomaticExportAndStartOnlyOnce() {
    #expect(HealthObserverPolicy.action(revoked: false, automaticExport: false, running: true) == .stop)
    #expect(HealthObserverPolicy.action(revoked: false, automaticExport: false, running: false) == .stop)
    #expect(HealthObserverPolicy.action(revoked: false, automaticExport: true, running: true) == .keep)
    #expect(HealthObserverPolicy.action(revoked: false, automaticExport: true, running: false) == .start)
}

@Test func revocationPurgesEveryTypeForEveryOwedDestination() {
    let heart = MetricID(rawValue: "heart_rate")
    let steps = MetricID(rawValue: "step_count")
    let purges = HealthAuthorizationPlan.purges(
        grantID: HealthAuthorizationPlan.grantID,
        metrics: [heart, steps],
        observedAtEpoch: 1_700_000_000,
        owedDestinations: ["local-file", "mqtt"]
    )
    #expect(purges == [
        HealthRevocationPurge(
            metric: heart,
            reason: "authorization_revoked:core-activity",
            destination: "local-file,mqtt",
            atEpoch: 1_700_000_000
        ),
        HealthRevocationPurge(
            metric: steps,
            reason: "authorization_revoked:core-activity",
            destination: "local-file,mqtt",
            atEpoch: 1_700_000_000
        ),
    ])
}

@Test func revocationWithNoEnabledDestinationSaysSo() {
    let purges = HealthAuthorizationPlan.purges(
        grantID: "core-activity",
        metrics: [MetricID(rawValue: "heart_rate")],
        observedAtEpoch: 0,
        owedDestinations: []
    )
    #expect(purges.map(\.destination) == ["no enabled destination"])
    #expect(HealthAuthorizationPlan.reenableReason == "user_requested_core_activity")
}

@Test func healthReadAccessWaitsForAConfiguredScopeAndIsOrdered() throws {
    let unconfigured = try DestinationExportScope(
        destinationID: "mqtt",
        metrics: [MetricID(rawValue: "step_count")]
    )
    #expect(HealthAuthorizationPlan.readRequest(for: unconfigured, disclosureAcknowledged: true) == nil)

    let configured = try DestinationExportScope(
        destinationID: "mqtt",
        metrics: [MetricID(rawValue: "step_count"), MetricID(rawValue: "heart_rate")],
        startInclusive: Date(timeIntervalSince1970: 0)
    )
    #expect(HealthAuthorizationPlan.readRequest(for: configured, disclosureAcknowledged: true) == [
        MetricID(rawValue: "heart_rate"), MetricID(rawValue: "step_count"),
    ])
}

/// #45: enabling a destination during first run used to open Apple's Health sheet
/// before the disclosure screen.
@Test func healthReadAccessIsNeverRequestedBeforeTheDisclosure() throws {
    let configured = try DestinationExportScope(
        destinationID: "local-file",
        metrics: [MetricID(rawValue: "step_count")],
        startInclusive: Date(timeIntervalSince1970: 0)
    )
    #expect(HealthAuthorizationPlan.readRequest(for: configured, disclosureAcknowledged: false) == nil)
}

@Test func observerFailuresAreRecordedClearedAndSummarised() {
    let storage = MemoryObserverFailureStorage()
    let log = ObserverFailureLog(storage: storage)
    #expect(log.summary() == nil)

    log.record([
        MetricID(rawValue: "sleep_analysis"): "denied",
        MetricID(rawValue: "heart_rate"): "unavailable",
    ])
    #expect(storage.value == ["sleep_analysis": "denied", "heart_rate": "unavailable"])
    #expect(
        log.summary()
            == "Background Health delivery is not registered for: heart rate, sleep analysis. These still export when the app opens or iOS schedules a run."
    )

    log.record([:])
    #expect(storage.value == nil)
    #expect(log.summary() == nil)
}

@Test func anEmptyStoredFailureSetHasNoSummary() {
    #expect(ObserverFailureLog(storage: MemoryObserverFailureStorage([:])).summary() == nil)
}
