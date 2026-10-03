// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import Watchdog

/// An error the app recognises as its own database failing. The app marks its storage
/// error type with this, so the mapping here needs no storage dependency.
public protocol StorageFailure: Error {}

/// #46: every caught error becomes the five-part object; nothing shows a raw error
/// domain or `localizedDescription`.
public enum UserFacingFailure {
    public static func object(for error: Error, destinationLabel: String) -> UserFacingErrorObject {
        if let egress = error as? EgressError {
            switch egress {
            case let .httpStatus(status):
                if let archetype = UserFacingErrorArchetype.fromHTTPStatus(status) {
                    return .make(
                        archetype: archetype,
                        destinationLabel: destinationLabel,
                        evidence: UserFacingErrorEvidence(statusCode: status)
                    )
                }
            case let .httpRetryAfter(status, seconds):
                return .make(
                    archetype: .http429,
                    destinationLabel: destinationLabel,
                    evidence: UserFacingErrorEvidence(statusCode: status, retryAfterSeconds: Int(seconds))
                )
            case .transport:
                return .make(archetype: .timeout, destinationLabel: destinationLabel)
            case .pinMismatch:
                return .make(archetype: .tlsTrustFailure, destinationLabel: destinationLabel)
            default:
                break
            }
        }
        if case let SetupError.testFailed(step) = error {
            return .make(archetype: archetype(failedAt: step), destinationLabel: destinationLabel)
        }
        if let send = error as? DestinationSendError,
           let archetype = UserFacingErrorArchetype.fromErrorClass(send.errorClass) {
            return .make(archetype: archetype, destinationLabel: destinationLabel)
        }
        if error is StorageFailure {
            return .make(archetype: .storageProblem, destinationLabel: destinationLabel)
        }
        return .make(archetype: .unexpected, destinationLabel: destinationLabel)
    }

    /// A destination test that stopped at a step says what that step means (#48).
    static func archetype(failedAt step: DestinationTestStep) -> UserFacingErrorArchetype {
        switch step {
        case .resolveHost, .connect: .hostUnresolvable
        case .tlsHandshake, .confirmCertificate: .tlsTrustFailure
        case .authenticate: .http401
        case .sendCanary, .readResponse, .publishCanary, .receiveEcho, .subscribe: .timeout
        case .openFolder, .writeCanary, .readBack, .confirmBytes: .unexpected
        }
    }
}

/// One destination on the Status screen: what it is, its state in words and glyph,
/// and one line of detail. The same labels and glyphs as the widget.
public struct StatusDestinationRow: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var state: DestinationDisplayState
    public var detail: String
    public var needsAttention: Bool

    public var stateLabel: String { state.label }
    public var glyph: String { state.glyph }
    public var tone: StatusTone { needsAttention && state.tone == .ok ? .attention : state.tone }
}

/// The plain sentence at the top of Status, and the one action it offers.
public struct StatusSummary: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// Open this destination's detail.
        case check(destinationID: String, label: String)
        /// No destination yet: resume setup.
        case setUp
    }

    public var headline: String
    public var detail: String
    public var tone: StatusTone
    public var action: Action?

    public init(headline: String, detail: String, tone: StatusTone, action: Action?) {
        self.headline = headline
        self.detail = detail
        self.tone = tone
        self.action = action
    }
}

/// #46: what Status shows, worked out from the destination snapshots. Times are
/// formatted by the caller, so the words are tested here and localised by the app.
public enum StatusDashboard {
    public static func rows(
        _ snapshots: [DestinationStatusSnapshot],
        nowEpoch: TimeInterval,
        relative: (TimeInterval) -> String
    ) -> [StatusDestinationRow] {
        snapshots.map { snapshot in
            let state = snapshot.state(at: nowEpoch)
            let changed = snapshot.unacknowledgedSecurityEventCount > 0
            return StatusDestinationRow(
                id: snapshot.destinationID,
                label: snapshot.destinationLabel,
                state: state,
                detail: changed
                    ? "Its identity changed. Review it before more data is sent."
                    : detail(snapshot, state: state, relative: relative),
                needsAttention: changed || state.tone == .attention || state.tone == .blocked
            )
        }
    }

    public static func summary(
        _ rows: [StatusDestinationRow],
        lastSuccessEpoch: TimeInterval?,
        relative: (TimeInterval) -> String
    ) -> StatusSummary {
        guard !rows.isEmpty else {
            return StatusSummary(
                headline: "No destinations yet.",
                detail: "Choose where your health data should go, then export.",
                tone: .neutral,
                action: .setUp
            )
        }
        let attention = rows.filter(\.needsAttention)
        if let worst = attention.max(by: { $0.state.severity < $1.state.severity }) {
            let healthy = rows.count - attention.count
            let headline = rows.count == 1
                ? "\(worst.label) needs attention."
                : "\(healthy) of \(rows.count) destinations are up to date."
            return StatusSummary(
                headline: headline,
                detail: "\(worst.label): \(worst.detail)",
                tone: worst.tone,
                action: .check(destinationID: worst.id, label: worst.label)
            )
        }
        if rows.allSatisfy({ $0.state.tone == .ok }) {
            let when = lastSuccessEpoch.map { "Last export \(relative($0))." } ?? ""
            let count = rows.count == 1 ? "1 destination" : "\(rows.count) destinations"
            return StatusSummary(
                headline: "Everything is up to date.",
                detail: [when, "Sending to \(count)."].filter { !$0.isEmpty }.joined(separator: " "),
                tone: .ok,
                action: nil
            )
        }
        return StatusSummary(
            headline: "Nothing needs you right now.",
            detail: "Some destinations are waiting on iOS or haven't exported yet.",
            tone: .neutral,
            action: nil
        )
    }

    /// One sentence a person can act on. Never an enum name or an error class.
    static func detail(
        _ snapshot: DestinationStatusSnapshot,
        state: DestinationDisplayState,
        relative: (TimeInterval) -> String
    ) -> String {
        let last = snapshot.lastSuccessEpoch.map(relative)
        let reason = humanReason(snapshot.errorClass)
        switch state {
        case .healthy:
            return last.map { "Delivered \($0)." } ?? "Delivered."
        case .manualOnly:
            return last.map { "Exports when you tap Export now. Last delivered \($0)." }
                ?? "Exports when you tap Export now."
        case .paused:
            return "Paused. Nothing is sent until you resume it."
        case .notSetUp:
            return "Not set up yet."
        case .noExportsYet:
            return "Waiting for its first export."
        case .quiet:
            return last.map { "No new data since \($0)." } ?? "No new data yet."
        case .sentUnconfirmed:
            return last.map { "Sent \($0), waiting for the destination to confirm." }
                ?? "Sent, waiting for the destination to confirm."
        case .partial:
            return "Some types were delivered and some weren't." + (reason.map { " \($0)" } ?? "")
        case .stale, .overdue:
            return last.map { "Last delivered \($0)." } ?? "Nothing delivered yet."
        case .failing, .blocked:
            return reason ?? "The last export didn't reach it."
        case .waiting, .deferred, .limitedByIOS:
            return reason ?? "Waiting for iOS to allow the next export."
        }
    }

    /// The manifest's sentence for a known error class; nothing for an unknown one,
    /// so a raw class name never reaches the screen.
    static func humanReason(_ raw: String?) -> String? {
        guard let raw, let known = ErrorClass(rawValue: raw), known != .none else { return nil }
        let copy = ErrorClassManifest.record(for: known).userFacingCopy
        return copy.isEmpty ? nil : copy
    }
}
