// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation

public struct WakeRecord: Sendable, Equatable {
    public var trigger: RunTrigger
    public var atEpoch: TimeInterval

    public init(trigger: RunTrigger, atEpoch: TimeInterval) {
        self.trigger = trigger
        self.atEpoch = atEpoch
    }
}

/// Append-only wake file (R-22). Written before any work that can fail.
public struct WakeLedger: Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }

    public func append(_ record: WakeRecord) throws {
        let line = "\(record.trigger.rawValue) \(record.atEpoch)\n"
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        handle.write(Data(line.utf8))
    }

    public func records() throws -> [WakeRecord] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: " ")
            guard parts.count == 2,
                  let trigger = RunTrigger(rawValue: String(parts[0])),
                  let at = TimeInterval(parts[1])
            else { return nil }
            return WakeRecord(trigger: trigger, atEpoch: at)
        }
    }
}

public enum AttributionKind: String, Sendable, Equatable, CaseIterable {
    case none
    case scheduling
    case execution

    /// R-22 is only satisfied if a person can tell the two failures apart, so the copy
    /// belongs with the classification rather than at each call site. RK-4: when iOS
    /// never woke us, say so — do not let the user read it as the export failing.
    public var userFacingCopy: String {
        switch self {
        case .none:
            return "No overdue scheduling or execution failure."
        case .scheduling:
            return "iOS did not wake the app by the measured deadline. Nothing ran, so nothing failed to send."
        case .execution:
            return "The app woke on time and the export did not finish. This one is ours."
        }
    }
}

/// R-22: a missing wake in an overdue window is scheduling; a wake without a clean journal is execution.
public enum WakeAttribution {
    public static func classify(
        wakes: [WakeRecord],
        lastJournal: RunEvent?,
        nowEpoch: TimeInterval,
        expectedWakeByEpoch: TimeInterval
    ) -> AttributionKind {
        if nowEpoch < expectedWakeByEpoch {
            return .none
        }
        let covering = wakes.filter { $0.atEpoch >= expectedWakeByEpoch }
        if covering.isEmpty {
            return .scheduling
        }
        guard let lastJournal else {
            return .execution
        }
        if lastJournal.outcomeKind == "success"
            || lastJournal.outcomeKind == "successNothingDue"
            || lastJournal.outcomeKind == "blockedDeviceLocked"
            || lastJournal.outcomeKind == "blockedLowPower"
        {
            return .none
        }
        return .execution
    }
}
