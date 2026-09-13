// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// QA-26 / QA-14: destination surfaces a UI test cannot reach with a real clock,
/// network, or second device. The same snapshots feed Status, the widget, and
/// accessibility audits.
public enum DestinationStatusUIFixtures {
    public static let allStatesScenario = "all-states"
    public static let homeAssistantID = "home-assistant"
    public static let homeAssistantLabel = "Home Assistant"

    public static func snapshots(
        scenario: String,
        nowEpoch: TimeInterval
    ) -> [DestinationStatusSnapshot] {
        let day: TimeInterval = 86_400
        switch scenario {
        case allStatesScenario:
            return DestinationDisplayState.allCases.map {
                displayState($0, nowEpoch: nowEpoch)
            }
        case "stale":
            return [
                homeAssistant(
                    nowEpoch: nowEpoch,
                    lastOutcome: "success",
                    lastSuccessEpoch: nowEpoch - (3 * day)
                ),
            ]
        case "overdue":
            return [
                homeAssistant(
                    nowEpoch: nowEpoch,
                    lastOutcome: "success",
                    lastSuccessEpoch: nowEpoch - (8 * day)
                ),
            ]
        case "failed":
            return [
                homeAssistant(
                    nowEpoch: nowEpoch,
                    lastOutcome: "failed",
                    lastSuccessEpoch: nowEpoch - (2 * day),
                    errorClass: ErrorClass.destinationUnreachable.rawValue
                ),
            ]
        case "deferred":
            return [
                homeAssistant(
                    nowEpoch: nowEpoch,
                    lastOutcome: "blockedDeviceLocked",
                    lastSuccessEpoch: nowEpoch - 60,
                    errorClass: ErrorClass.deviceLocked.rawValue
                ),
            ]
        case "changed":
            return [
                homeAssistant(
                    nowEpoch: nowEpoch,
                    lastOutcome: "success",
                    lastSuccessEpoch: nowEpoch - 60,
                    errorClass: ErrorClass.none.rawValue,
                    unacknowledgedSecurityEventCount: 2
                ),
            ]
        default:
            return [
                homeAssistant(
                    nowEpoch: nowEpoch,
                    lastOutcome: "success",
                    lastSuccessEpoch: nowEpoch - 60,
                    errorClass: ErrorClass.none.rawValue
                ),
            ]
        }
    }

    public static func displayState(
        _ state: DestinationDisplayState,
        nowEpoch: TimeInterval
    ) -> DestinationStatusSnapshot {
        let day: TimeInterval = 86_400
        var enabled = true
        var lastOutcome: String? = "success"
        var lastSuccess: TimeInterval? = nowEpoch - 60
        var errorClass: String? = ErrorClass.none.rawValue
        switch state {
        case .paused:
            enabled = false
            lastOutcome = nil
            lastSuccess = nil
            errorClass = nil
        case .notSetUp, .noExportsYet, .manualOnly:
            lastOutcome = nil
            lastSuccess = nil
            errorClass = nil
        case .stale:
            lastSuccess = nowEpoch - (3 * day)
        case .overdue:
            lastSuccess = nowEpoch - (8 * day)
        case .failing:
            lastOutcome = "failed"
            errorClass = ErrorClass.destinationUnreachable.rawValue
        case .deferred:
            lastOutcome = "blockedDeviceLocked"
            errorClass = ErrorClass.deviceLocked.rawValue
        case .blocked:
            lastOutcome = "localNetworkDenied"
            errorClass = ErrorClass.localNetworkDenied.rawValue
        case .sentUnconfirmed:
            lastOutcome = "unknownAck"
        case .partial:
            lastOutcome = "partial"
        case .waiting:
            lastOutcome = "queued"
        case .limitedByIOS:
            lastOutcome = "cancelledBySystem"
            errorClass = ErrorClass.cancelledBySystem.rawValue
        case .quiet, .healthy:
            break
        }
        return DestinationStatusSnapshot(
            destinationID: "seed-\(state.rawValue)",
            destinationLabel: state.label,
            enabled: enabled,
            state: state,
            lastOutcome: lastOutcome,
            lastSuccessEpoch: lastSuccess,
            errorClass: errorClass,
            staleThresholdSeconds: day,
            overdueThresholdSeconds: 7 * day,
            writtenAtEpoch: nowEpoch
        )
    }

    private static func homeAssistant(
        nowEpoch: TimeInterval,
        lastOutcome: String,
        lastSuccessEpoch: TimeInterval,
        errorClass: String? = nil,
        unacknowledgedSecurityEventCount: Int = 0
    ) -> DestinationStatusSnapshot {
        let day: TimeInterval = 86_400
        return DestinationStatusSnapshot(
            destinationID: homeAssistantID,
            destinationLabel: homeAssistantLabel,
            enabled: true,
            lastOutcome: lastOutcome,
            lastSuccessEpoch: lastSuccessEpoch,
            errorClass: errorClass,
            staleThresholdSeconds: day,
            overdueThresholdSeconds: 7 * day,
            unacknowledgedSecurityEventCount: unacknowledgedSecurityEventCount,
            writtenAtEpoch: nowEpoch
        )
    }
}
