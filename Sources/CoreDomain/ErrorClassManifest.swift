/// Per-class registry. `record(for:)` is a total `switch` so a new `ErrorClass` case is a compile
/// error until the table grows. The bijection test still asserts unique copy keys (DP-6).
public struct ErrorClassRecord: Sendable, Equatable {
    public var userCopyKey: String
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
                retryable: false,
                blocksEnablement: false,
                ledgerKind: "none",
                scheduleFailure: false,
                r88P1: false
            )
        case .deviceLocked:
            return ErrorClassRecord(
                userCopyKey: "error.deviceLocked",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: false
            )
        case .localNetworkDenied:
            return ErrorClassRecord(
                userCopyKey: "error.localNetworkDenied",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: false
            )
        case .destinationUnreachable:
            return ErrorClassRecord(
                userCopyKey: "error.destinationUnreachable",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: true
            )
        case .budgetExhausted:
            return ErrorClassRecord(
                userCopyKey: "error.budgetExhausted",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "schedule",
                scheduleFailure: true,
                r88P1: false
            )
        case .cancelledBySystem:
            return ErrorClassRecord(
                userCopyKey: "error.cancelledBySystem",
                retryable: true,
                blocksEnablement: false,
                ledgerKind: "schedule",
                scheduleFailure: true,
                r88P1: false
            )
        case .internalFault:
            return ErrorClassRecord(
                userCopyKey: "error.internalFault",
                retryable: false,
                blocksEnablement: false,
                ledgerKind: "execute",
                scheduleFailure: false,
                r88P1: true
            )
        }
    }
}
