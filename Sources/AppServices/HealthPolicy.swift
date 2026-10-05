// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import Foundation

/// What the app does with its Health observers after checking authorization (#42).
public enum HealthObserverAction: Sendable, Equatable {
    /// Tear down any running observers: access was revoked or nothing exports on its own.
    case stop
    /// Observers are already running; leave them.
    case keep
    /// Register observers and schedule background work.
    case start
}

/// The decisions behind starting Health observers, without HealthKit (#42).
public enum HealthObserverPolicy {
    /// Whether it is worth looking at Health authorization at all. Before the disclosure
    /// is acknowledged the app must not touch Health.
    public static func mayObserve(healthAvailable: Bool, disclosureAcknowledged: Bool) -> Bool {
        healthAvailable && disclosureAcknowledged
    }

    /// After authorization has been checked. A revocation always stops the observers, and
    /// automatic export is only consulted when nothing was revoked.
    public static func action(
        revoked: Bool,
        automaticExport: @autoclosure () -> Bool,
        running: Bool
    ) -> HealthObserverAction {
        if revoked { return .stop }
        guard automaticExport() else { return .stop }
        return running ? .keep : .start
    }
}

/// One type's pending work to drop after its Health access was revoked.
public struct HealthRevocationPurge: Sendable, Equatable {
    public var metric: MetricID
    public var reason: String
    public var destination: String
    public var atEpoch: TimeInterval

    public init(metric: MetricID, reason: String, destination: String, atEpoch: TimeInterval) {
        self.metric = metric
        self.reason = reason
        self.destination = destination
        self.atEpoch = atEpoch
    }
}

/// The authorization grant the app tracks and what a revocation of it drops (R-44).
public enum HealthAuthorizationPlan {
    /// The one grant the app observes: the union of every enabled destination's types.
    public static let grantID = "core-activity"

    /// The journal reason when the user asks Health for access again.
    public static let reenableReason = "user_requested_core_activity"

    /// A revoked type drops what every enabled destination was owed, so the ledger entry
    /// names them all rather than the archive folder alone.
    public static func purges(
        grantID: String,
        metrics: [MetricID],
        observedAtEpoch: TimeInterval,
        owedDestinations: [String]
    ) -> [HealthRevocationPurge] {
        let destination = owedDestinations.isEmpty
            ? "no enabled destination"
            : owedDestinations.joined(separator: ",")
        return metrics.map {
            HealthRevocationPurge(
                metric: $0,
                reason: "authorization_revoked:\(grantID)",
                destination: destination,
                atEpoch: observedAtEpoch
            )
        }
    }

    /// The types to ask Health for on behalf of one destination, in a stable order, or
    /// nil when its scope is not configured yet (SEC-16: absence is deny). Nothing is
    /// asked before the disclosure is acknowledged (R-63): enabling a destination during
    /// first run must not put Apple's sheet ahead of it. First run asks on its own
    /// priming screen instead (#45).
    public static func readRequest(
        for scope: DestinationExportScope,
        disclosureAcknowledged: Bool
    ) -> [MetricID]? {
        guard disclosureAcknowledged, scope.isConfigured else { return nil }
        return scope.metrics.sorted { $0.rawValue < $1.rawValue }
    }
}

/// Where the observer-registration failures live between launches. The app keeps them
/// in its preferences; tests use memory. Nil means none are recorded.
public protocol ObserverFailureStorage: Sendable {
    func load() -> [String: String]?
    func save(_ failures: [String: String]?)
}

/// #28: a type whose observer could not register still exports on foreground and
/// scheduled wakes, but it will not wake the app itself. That has to be visible.
public struct ObserverFailureLog: Sendable {
    private let storage: any ObserverFailureStorage

    public init(storage: any ObserverFailureStorage) {
        self.storage = storage
    }

    public func record(_ failures: [MetricID: String]) {
        storage.save(
            failures.isEmpty
                ? nil
                : Dictionary(uniqueKeysWithValues: failures.map { ($0.key.rawValue, $0.value) })
        )
    }

    public func summary() -> String? {
        guard let failures = storage.load(), !failures.isEmpty else { return nil }
        let names = failures.keys.sorted()
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .joined(separator: ", ")
        return "Background Health delivery is not registered for: \(names). These still export when the app opens or iOS schedules a run."
    }
}
