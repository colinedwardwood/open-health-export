// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Per-class registry. `record(for:)` is a total `switch` so a new `ErrorClass` case is a compile
/// error until the table grows. The bijection test still asserts unique copy keys (DP-6).
public struct ErrorClassRecord: Sendable, Equatable {
    public var userCopyKey: String
    public var userFacingCopy: String
    public var retryable: Bool
    public var blocksEnablement: Bool
    public var ledgerKind: String
    public var scheduleFailure: Bool
    public var r88P1: Bool
}

public enum ErrorClassManifest {
    public static var records: [ErrorClass: ErrorClassRecord] {
        Dictionary(uniqueKeysWithValues: ErrorClass.allCases.map { ($0, record(for: $0)) })
    }

    public static func record(for errorClass: ErrorClass) -> ErrorClassRecord {
        switch errorClass {
        case .none:
            return ErrorClassRecord(
                userCopyKey: "error.none",
                userFacingCopy: "",
                retryable: false,
                blocksEnablement: false,
                ledgerKind: "none",
                scheduleFailure: false,
                r88P1: false
            )
        case .deviceLocked:
            return ErrorClassRecord(
                userCopyKey: "error.deviceLocked",
                userFacingCopy: "The device is locked, so Health data is temporarily unavailable. Export will retry when it unlocks.",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: false
            )
        case .localNetworkDenied:
            return ErrorClassRecord(
                userCopyKey: "error.localNetworkDenied",
                userFacingCopy: "Local Network access is off for this app, so it cannot find your Mac. That is different from the Mac being asleep or on another network. Allow Local Network in Settings, then test again.",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: false
            )
        case .destinationUnreachable:
            return ErrorClassRecord(
                userCopyKey: "error.destinationUnreachable",
                userFacingCopy: "Couldn't find your Mac on this network. Both devices need to be on the same network, the Mac needs to be awake, and the companion needs to be running on it.",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: true
            )
        case .budgetExhausted:
            return ErrorClassRecord(
                userCopyKey: "error.budgetExhausted",
                userFacingCopy: "The system stopped this export because the background time budget ran out. It will try again later.",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "schedule",
                scheduleFailure: true,
                r88P1: false
            )
        case .cancelledBySystem:
            return ErrorClassRecord(
                userCopyKey: "error.cancelledBySystem",
                userFacingCopy: "The system cancelled this export. It will try again later.",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "schedule",
                scheduleFailure: true,
                r88P1: false
            )
        case .internalFault:
            return ErrorClassRecord(
                userCopyKey: "error.internalFault",
                userFacingCopy: "Export stopped because of an internal fault. Check diagnostics for the recorded error class.",
                retryable: false,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: true
            )
        case .healthDataRestricted:
            return ErrorClassRecord(
                userCopyKey: "error.healthDataRestricted",
                userFacingCopy: "Health data is restricted on this device by a policy such as MDM or Guest User. That is different from a Health permission in Settings.",
                retryable: false,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: false
            )
        case .lowPowerMode:
            return ErrorClassRecord(
                userCopyKey: "error.lowPowerMode",
                userFacingCopy: "Low Power Mode is on, so iOS is holding this export. It will retry when Low Power Mode is off.",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "schedule",
                scheduleFailure: true,
                r88P1: false
            )
        }
    }

    /// Closed user-facing reason for a stored error-class token. Unknown tokens stay as
    /// the raw code so a bug report still has something to paste.
    public static func userFacingReason(forRaw errorClass: String?) -> String? {
        guard let errorClass, !errorClass.isEmpty, errorClass != ErrorClass.none.rawValue else {
            return nil
        }
        guard let classified = ErrorClass(rawValue: errorClass) else {
            return errorClass
        }
        let copy = record(for: classified).userFacingCopy
        return copy.isEmpty ? errorClass : copy
    }
}
