// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import EnginePorts
import MetricCatalog

/// What a person can do about a notice, beyond reading it.
public enum StatusNoticeAction: Sendable, Equatable {
    /// QA-17: a held type waits for "send it all again" or "stop exporting it".
    case resolveAnchorHold(metric: MetricID)
}

extension StatusNotices {
    /// The choices an anchor-hold notice offers.
    public static let anchorReexportChoice: LocalizedCopy = "Send it all again"
    public static let anchorStopChoice: LocalizedCopy = "Stop exporting this data"

    /// QA-17 in-app rung: one notice per held type, which stays until the hold is
    /// decided. There is no dismiss, because dismissing would leave a type silently
    /// not exporting, which is the failure the hold exists to prevent.
    public static func anchorHoldNotices(_ holds: [AnchorHold]) -> [StatusNotice] {
        holds.sorted { $0.metric.rawValue < $1.metric.rawValue }.map { hold in
            let name = MetricCatalog.declaration(for: hold.metric)?.displayName ?? hold.metric.rawValue
            let awaiting = hold.decision == nil
            return StatusNotice(
                id: "anchor-hold-\(hold.metric.rawValue)",
                title: LocalizedCopy("Export paused for %@", .text(name)),
                detail: awaiting
                    ? anchorHoldDetail(hold)
                    : "You chose to send this history again. It goes out on the next export.",
                tone: awaiting ? .blocked : .attention,
                action: awaiting ? .resolveAnchorHold(metric: hold.metric) : nil
            )
        }
    }

    private static func anchorHoldDetail(_ hold: AnchorHold) -> LocalizedCopy {
        let sent: LocalizedCopy = hold.lastEmittedDay
            .map { LocalizedCopy("Data through %@ has already been sent.", .text($0)) }
            ?? "Nothing has been sent yet for this data."
        switch hold.reason {
        case .cursorLost:
            return LocalizedCopy(
                "The export lost track of how far it had got. %@ It can start again from the beginning, which sends that history a second time, or you can stop exporting this data.",
                .copy(sent)
            )
        case .replaySuspected:
            return LocalizedCopy(
                "One update returned %lld records, which is far more than an update should contain. %@ Sending it would repeat history already at your server. You can send it anyway, or stop exporting this data.",
                .number(hold.observedSamples),
                .copy(sent)
            )
        }
    }
}
