// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import EnginePorts
import Foundation
import Watchdog

/// #62: the launch and background steps that used to fail silently. Each one is journalled
/// and shown on Status instead of being discarded with `try?`.
public enum LaunchStage: String, Sendable, Codable, CaseIterable {
    case observerStart = "observer_start"
    case interruptedRecovery = "interrupted_recovery"
    case wakeLedger = "wake_ledger"
    case observerExport = "observer_export"
    case authorizationObservation = "authorization_observation"
    case queueExpiry = "queue_expiry"
    case notificationCheck = "notification_check"

    public var label: LocalizedCopy {
        switch self {
        case .observerStart: "Watching for new Health data"
        case .interruptedRecovery: "Recovering an interrupted export"
        case .wakeLedger: "Recording background wakes"
        case .observerExport: "Exporting new Health data"
        case .authorizationObservation: "Checking Health access"
        case .queueExpiry: "Clearing old queued exports"
        case .notificationCheck: "Checking notification permission"
        }
    }
}

/// One failure still worth showing: the latest per stage.
public struct LaunchIssue: Sendable, Codable, Equatable {
    public var stage: LaunchStage
    public var errorClass: String
    public var atEpoch: TimeInterval

    public init(stage: LaunchStage, errorClass: String, atEpoch: TimeInterval) {
        self.stage = stage
        self.errorClass = errorClass
        self.atEpoch = atEpoch
    }
}

/// Where the unresolved issues live between launches. The app keeps them in its
/// preferences; tests use memory.
public protocol LaunchIssueMemory: Sendable {
    func issues() -> [LaunchIssue]
    func save(_ issues: [LaunchIssue])
}

/// #62: records a failed launch or background step in the run journal with an error
/// class, and remembers it so Status can show it. Recording never throws: a failure
/// to record a failure must not take the wake down with it. Observer wakes, the wake
/// handler and the foreground path call in concurrently, so the remembered list is
/// guarded by a lock and cached after the first read.
public final class LaunchFailureRecorder: @unchecked Sendable {
    private let store: @Sendable () throws -> any StateStore
    private let memory: any LaunchIssueMemory
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var cached: [LaunchIssue]?

    public init(
        store: @escaping @Sendable () throws -> any StateStore,
        memory: any LaunchIssueMemory,
        now: @escaping @Sendable () -> Date
    ) {
        self.store = store
        self.memory = memory
        self.now = now
    }

    /// A locked keychain is a deferral the next unlocked wake retries, so it is
    /// classified as a locked device rather than a fault.
    public static func errorClass(for error: Error) -> ErrorClass {
        if let secret = error as? SecretStoreError, secret == .locked {
            return .deviceLocked
        }
        if let send = error as? DestinationSendError {
            return send.errorClass
        }
        return .internalFault
    }

    /// Runs one launch or background step. Success clears the stage's earlier failure;
    /// a throw is recorded and returns nil.
    @discardableResult
    public func run<T>(
        _ stage: LaunchStage,
        trigger: RunTrigger,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async -> T? {
        do {
            let value = try await body()
            resolve(stage)
            return value
        } catch {
            await record(stage, error: error, trigger: trigger)
            return nil
        }
    }

    public func record(_ stage: LaunchStage, error: Error, trigger: RunTrigger) async {
        let errorClass = Self.errorClass(for: error)
        let epoch = now().timeIntervalSince1970
        if let store = try? store() {
            _ = try? await store.transact { tx in
                try tx.appendJournal(
                    RunEvent(
                        runID: RunID(rawValue: "launch-\(stage.rawValue)"),
                        outcomeKind: "launch_failure",
                        detail: stage.rawValue,
                        trigger: trigger,
                        wallTimeEpoch: epoch,
                        errorClass: errorClass.rawValue
                    )
                )
            }
        }
        update { issues in
            issues.removeAll { $0.stage == stage }
            issues.append(LaunchIssue(stage: stage, errorClass: errorClass.rawValue, atEpoch: epoch))
        }
    }

    /// The step worked this time; its earlier failure is no longer news. Costs nothing
    /// when nothing is outstanding, which is almost always.
    public func resolve(_ stage: LaunchStage) {
        update { $0.removeAll { $0.stage == stage } }
    }

    public func issues() -> [LaunchIssue] {
        lock.withLock { load() }
    }

    private func update(_ change: (inout [LaunchIssue]) -> Void) {
        lock.withLock {
            var issues = load()
            let before = issues
            change(&issues)
            guard issues != before else { return }
            cached = issues
            memory.save(issues)
        }
    }

    private func load() -> [LaunchIssue] {
        if let cached { return cached }
        let loaded = memory.issues()
        cached = loaded
        return loaded
    }
}

/// Whether iOS lets the app refresh in the background (`UIBackgroundRefreshStatus`).
public enum BackgroundRefreshAvailability: String, Sendable, Equatable, CaseIterable {
    case available
    case denied
    case restricted
}

/// A persistent row on Status for something that stops or delays exports.
public struct StatusNotice: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: LocalizedCopy
    public var detail: LocalizedCopy
    public var tone: StatusTone
}

public enum StatusNotices {
    /// #62/#63: everything the person should see even when each destination looks fine.
    public static func notices(
        backgroundRefresh: BackgroundRefreshAvailability,
        lowPowerMode: Bool,
        submitFailure: String?,
        issues: [LaunchIssue]
    ) -> [StatusNotice] {
        var notices: [StatusNotice] = []
        if backgroundRefresh != .available {
            notices.append(StatusNotice(
                id: "background-refresh",
                title: "Background App Refresh is not available",
                detail: "It is off or restricted on this device, so exports only run when you open the app. To turn it on, open Settings, then General, then Background App Refresh.",
                tone: .attention
            ))
        }
        if lowPowerMode {
            notices.append(StatusNotice(
                id: "low-power",
                title: "Low Power Mode is on",
                detail: "iOS pauses background exports while Low Power Mode is on. They resume when it turns off.",
                tone: .attention
            ))
        }
        if let submitFailure {
            notices.append(StatusNotice(
                id: "background-submit",
                title: "Background exports are not scheduled",
                detail: LocalizedCopy(
                    "iOS refused to schedule them: %@. Exports still run when the app opens.",
                    .text(submitFailure)
                ),
                tone: .blocked
            ))
        }
        for issue in issues.sorted(by: { $0.atEpoch > $1.atEpoch }) {
            let reason = StatusDashboard.humanReason(issue.errorClass)
                ?? "Open History for the recorded error."
            notices.append(StatusNotice(
                id: "launch-\(issue.stage.rawValue)",
                title: "Part of the app failed to run",
                detail: LocalizedCopy(
                    "%@ failed. %@",
                    .copy(issue.stage.label),
                    .copy(reason)
                ),
                tone: issue.errorClass == ErrorClass.deviceLocked.rawValue ? .attention : .blocked
            ))
        }
        return notices
    }
}
