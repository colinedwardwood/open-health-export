// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// UX-40: problems-first history plus the field set a run detail must show.
public enum RunHistoryDetail {
    public static let emptyStateCopy =
        "No exports yet. Run one now to check your setup."
    public static let retentionCopy =
        "Keeping 90 days or 1,000 runs, whichever is reached first."
    public static let payloadHiddenCopy =
        "Payload hidden. Reveal to inspect the exact bytes that left the device."
    public static let payloadGoneCopy =
        "Payload file is no longer on this device."

    public static func redactedPayload(
        metric: String,
        records: Int,
        byteCount: Int,
        windowStartDay: String?,
        windowEndDay: String?
    ) -> String {
        let window: String
        if let start = windowStartDay, let end = windowEndDay {
            window = "\(start)/\(end)"
        } else {
            window = "none"
        }
        return "{\"metric\":\"\(metric)\",\"records\":\(records),\"bytes\":\(byteCount),\"window\":\"\(window)\"}"
    }

    public static func lines(for event: RunEvent, revealPayload: Bool = false) -> [String] {
        let facts = event.facts
        var lines: [String] = []
        lines.append(listLine(event))
        lines.append("outcome: \(event.outcomeKind)")
        lines.append("trigger: \(event.trigger.rawValue)")
        if let destination = facts.destinationID, !destination.isEmpty {
            lines.append("destination: \(destination)")
        }
        if let start = facts.windowStartDay, let end = facts.windowEndDay {
            lines.append("window: \(start) → \(end)")
        } else {
            lines.append("window: none")
        }
        if let metric = facts.metric, !metric.isEmpty {
            lines.append("type \(metric): \(event.samplesCommitted) records")
        } else {
            lines.append("records: \(event.samplesCommitted)")
        }
        lines.append("bytes: \(facts.byteCount)")
        lines.append("duration: \(facts.durationMillis) ms")
        if facts.stepTimings.isEmpty {
            lines.append("steps: none")
        } else {
            for step in facts.stepTimings {
                lines.append("step \(step.name): \(step.durationMillis) ms")
            }
        }
        if let errorClass = event.errorClass, !errorClass.isEmpty {
            lines.append("error: \(errorClass)")
            if !event.detail.isEmpty {
                lines.append("error detail: \(event.detail)")
            }
        }
        if revealPayload {
            lines.append("payload: \(revealedPayload(for: event))")
        } else if let redacted = facts.redactedPayload, !redacted.isEmpty {
            lines.append("payload: \(redacted)")
            lines.append(payloadHiddenCopy)
        } else {
            lines.append("payload: none")
        }
        return lines
    }

    public static func listLine(_ event: RunEvent) -> String {
        let error = event.errorClass.flatMap { raw -> String? in
            guard !raw.isEmpty, raw != "none" else { return nil }
            return raw
        }
        let suffix = error.map { " · \($0)" } ?? ""
        return "\(event.outcomeKind)\(suffix) · \(event.trigger.rawValue) · "
            + "\(event.samplesAcked)/\(event.samplesCommitted) acknowledged"
    }

    public static func revealedPayload(for event: RunEvent) -> String {
        guard let path = event.facts.payloadPath, !path.isEmpty else {
            return payloadGoneCopy
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let text = String(data: data, encoding: .utf8)
        else {
            if let digest = event.facts.payloadSHA256 {
                return "\(payloadGoneCopy) SHA-256 \(digest)."
            }
            return payloadGoneCopy
        }
        return text
    }
}
