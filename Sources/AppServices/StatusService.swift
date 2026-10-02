// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import RunJournal
import Watchdog

/// Where each destination's status snapshot lives. The app keeps them in the shared
/// container the widget reads; tests use memory.
public protocol DestinationStatusStore: Sendable {
    /// Every readable snapshot, in display order.
    func readAll() -> [DestinationStatusSnapshot]
    func read(destinationID: String) -> DestinationStatusSnapshot?
    /// Replaces the snapshot for `snapshot.destinationID`. A store with nowhere to
    /// write does nothing, as the status surface did before it was a service.
    func write(_ snapshot: DestinationStatusSnapshot) throws
}

/// The system surfaces that show status outside the app: notifications and widgets.
public protocol StatusNotifier: Sendable {
    /// Posts one notice. Delivery failures are the notifier's to swallow.
    func notify(_ notice: UserNotice) async
    /// Replaces the pending "export overdue" reminder for this destination.
    func rescheduleOverdue(for snapshot: DestinationStatusSnapshot) async
    func authorizationDenied() async -> Bool
    func reloadAllWidgets()
    func reloadStatusWidget()
}

/// Whether notifications were already denied the last time the app looked, so a
/// denial is recorded once rather than on every launch.
public protocol NotificationDenialMemory: Sendable {
    func previouslyDenied() -> Bool
    func setPreviouslyDenied(_ denied: Bool)
}

/// What the Status screen shows and which notifications fire (#42). Views ask it for
/// lines and banners; it owns the snapshot reads, the rules for when a destination is
/// overdue or changed, and the notices a failure produces.
public struct StatusService: Sendable {
    private let snapshots: any DestinationStatusStore
    private let notifier: any StatusNotifier
    private let denialMemory: any NotificationDenialMemory
    private let store: @Sendable () throws -> any StateStore
    private let wakes: @Sendable () throws -> [WakeRecord]
    private let now: @Sendable () -> Date
    private let formatDate: @Sendable (Date) -> String

    public init(
        snapshots: any DestinationStatusStore,
        notifier: any StatusNotifier,
        denialMemory: any NotificationDenialMemory,
        store: @escaping @Sendable () throws -> any StateStore,
        wakes: @escaping @Sendable () throws -> [WakeRecord],
        now: @escaping @Sendable () -> Date,
        formatDate: @escaping @Sendable (Date) -> String = {
            $0.formatted(date: .abbreviated, time: .shortened)
        }
    ) {
        self.snapshots = snapshots
        self.notifier = notifier
        self.denialMemory = denialMemory
        self.store = store
        self.wakes = wakes
        self.now = now
        self.formatDate = formatDate
    }

    // MARK: Status screen

    /// Every destination's snapshot, for the Status rows (#46).
    public func destinationSnapshots() -> [DestinationStatusSnapshot] {
        snapshots.readAll()
    }

    public func destinationStatusLines() -> [String] {
        let all = snapshots.readAll()
        guard !all.isEmpty else { return [DestinationStatusLine.emptyCopy] }
        let nowEpoch = now().timeIntervalSince1970
        return all.map { snapshot in
            DestinationStatusLine.render(snapshot, nowEpoch: nowEpoch) {
                formatDate(Date(timeIntervalSince1970: $0))
            }
        }
    }

    /// The five-part error a failure notification or a Status row opens (#43). The
    /// archetype the link named wins; without one it comes from the snapshot, and a
    /// destination with nothing wrong has no error to show.
    public func userFacingError(
        destinationID: String,
        archetype: UserFacingErrorArchetype?
    ) -> UserFacingErrorObject? {
        UserFacingErrorPresentation.object(
            route: UserFacingErrorRoute(destinationID: destinationID, archetype: archetype),
            snapshot: snapshots.read(destinationID: destinationID),
            nowEpoch: now().timeIntervalSince1970
        )
    }

    /// One line per freshness class: the measured estimate for each destination that
    /// has one, otherwise the class's target.
    public func freshnessDisclosureLines() -> [(id: String, text: String)] {
        let all = snapshots.readAll()
        return FreshnessClass.allCases.flatMap { freshnessClass in
            let measured = all.compactMap { snapshot -> (String, LocalFreshnessEstimate)? in
                snapshot.freshnessEstimates[freshnessClass].map {
                    (snapshot.destinationLabel, $0)
                }
            }
            guard !measured.isEmpty else {
                return [(
                    "freshness-class-\(freshnessClass.rawValue)",
                    FreshnessTarget.classDisclosure(freshnessClass)
                )]
            }
            return measured.map { label, estimate in
                (
                    "freshness-\(freshnessClass.rawValue)-\(label)",
                    "\(label) — \(FreshnessTarget.classDisclosure(freshnessClass, estimate: estimate))"
                )
            }
        }
    }

    public func destinationChangeBannerDetail() -> String? {
        let all = snapshots.readAll()
        guard DestinationChangeBanner.isVisible(all) else { return nil }
        return DestinationChangeBanner.detail(all)
    }

    /// QA-15 / R-23: the in-app rung. Staleness is computed at read time, so a destination
    /// that succeeded once and then went quiet still surfaces without a server.
    public func overdueBannerDetail() -> String? {
        let nowEpoch = now().timeIntervalSince1970
        let overdue = snapshots.readAll().filter { $0.state(at: nowEpoch) == .overdue }
        guard !overdue.isEmpty else { return nil }
        let names = overdue.map(\.destinationLabel).joined(separator: ", ")
        return "\(names). \(EscalationCopy.overdue)"
    }

    public func wakeAttributionLine() async throws -> String {
        guard let expected = snapshots.readAll().compactMap(\.nextAttemptLatestEpoch).min() else {
            return "Wake attribution: no measured delivery deadline is configured."
        }
        let journal = try await store().transact { try $0.loadJournal() }
        let attribution = WakeAttribution.classify(
            wakes: try wakes(),
            lastJournal: journal.last,
            nowEpoch: now().timeIntervalSince1970,
            expectedWakeByEpoch: expected
        )
        return "Wake attribution: \(attribution.userFacingCopy)"
    }

    /// Clears the "destination changed" count once the person has seen it.
    public func acknowledgeDestinationChanges() throws {
        let nowEpoch = now().timeIntervalSince1970
        for snapshot in snapshots.readAll() where snapshot.unacknowledgedSecurityEventCount > 0 {
            var acknowledged = snapshot
            acknowledged.unacknowledgedSecurityEventCount = 0
            acknowledged.writtenAtEpoch = nowEpoch
            try snapshots.write(acknowledged)
        }
        notifier.reloadStatusWidget()
    }

    // MARK: Notifications

    /// After a successful run, moves this destination's overdue reminder to its new
    /// deadline.
    public func rescheduleOverdueNotification(destinationID: String) async {
        guard let snapshot = snapshots.read(destinationID: destinationID) else { return }
        await rescheduleOverdueNotification(for: snapshot)
    }

    public func rescheduleOverdueNotification(for snapshot: DestinationStatusSnapshot) async {
        await notifier.rescheduleOverdue(for: snapshot)
    }

    public func notifyIfFailed(
        _ kind: RunOutcome.Kind,
        destinationID: String,
        destinationLabel: String
    ) async {
        guard kind == .failed else { return }
        await notifyDestinationFailure(
            destinationID: destinationID,
            destinationLabel: destinationLabel
        )
    }

    /// A run that threw before any destination could report for itself. Naming the
    /// archive folder here was a guess: it told users the wrong destination had
    /// failed, and told them anything at all when that folder was not even enabled.
    /// One notice still goes out, against the destination in `planned` that has
    /// evidence of the failure, or the first one. Returns the label that notice used,
    /// so on-screen text can say the same thing.
    @discardableResult
    public func notifyRunFailure(
        planned: [String],
        label: (String) -> String
    ) async -> String? {
        guard let first = planned.first else { return nil }
        let failing = snapshots.readAll().first {
            planned.contains($0.destinationID) && $0.errorClass != nil
        }?.destinationID
        let destinationID = failing ?? first
        let destinationLabel = label(destinationID)
        await notifyDestinationFailure(
            destinationID: destinationID,
            destinationLabel: destinationLabel
        )
        return destinationLabel
    }

    public func notifyDestinationFailure(
        destinationID: String,
        destinationLabel: String
    ) async {
        let errorClass = snapshots.readAll().first {
            $0.destinationID == destinationID
        }?.errorClass
        await notifier.notify(
            UserNotice(
                kind: .exportFailed,
                destinationID: destinationID,
                destination: destinationLabel,
                errorClass: errorClass
            )
        )
    }

    /// Marks one destination's own status as failed, for the case where the run
    /// never reached it: its last outcome must not inherit the combined result of
    /// the destinations that did run.
    public func recordDestinationFailureSnapshot(
        _ destinationID: String,
        errorClass: ErrorClass
    ) {
        guard var snapshot = snapshots.read(destinationID: destinationID) else { return }
        snapshot.applyLastOutcome(RunOutcome.Kind.failed.rawValue)
        snapshot.errorClass = errorClass.rawValue
        snapshot.writtenAtEpoch = now().timeIntervalSince1970
        try? snapshots.write(snapshot)
    }

    /// When notifications become denied, the watchdog can no longer escalate: record
    /// that once in the ledger and as a security event on every destination.
    /// `forcedDenied` is the UI-test seed; it also ignores what was remembered.
    public func recordNotificationSuppressionIfNeeded(forcedDenied: Bool = false) async throws {
        let systemDenied = await notifier.authorizationDenied()
        let denied = forcedDenied || systemDenied
        let previouslyDenied = forcedDenied ? false : denialMemory.previouslyDenied()
        defer { denialMemory.setPreviouslyDenied(denied) }
        guard NotificationSuppression.shouldRecord(
            previouslyDenied: previouslyDenied,
            currentlyDenied: denied
        ) else {
            return
        }
        let ledgerEpoch = now().timeIntervalSince1970
        try await store().transact { tx in
            try tx.appendLedger(
                EgressEntry(
                    destination: "local-notifications",
                    sampleCount: 0,
                    outcomeKind: "security:notifications_denied",
                    detail: "watchdog_escalation_suppressed",
                    wallTimeEpoch: ledgerEpoch
                )
            )
        }
        for snapshot in snapshots.readAll() {
            var flagged = snapshot
            flagged.unacknowledgedSecurityEventCount += 1
            flagged.writtenAtEpoch = now().timeIntervalSince1970
            try snapshots.write(flagged)
        }
        notifier.reloadAllWidgets()
    }
}
