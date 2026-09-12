// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import NetEgress

public struct OTLPBacklogSelection: Sendable, Equatable {
    public var events: [RunEvent]
    public var dropped: [RunEvent]

    public init(events: [RunEvent], dropped: [RunEvent]) {
        self.events = events
        self.dropped = dropped
    }
}

/// Oldest-first selection of unprojected journal rows. Drops age and count overflow
/// rather than sending them; callers must persist the drop so it is not retried.
public enum OTLPBacklog {
    public static let cap = 5_000
    public static let maxAgeSeconds: TimeInterval = 30 * 24 * 60 * 60

    public static func select(
        events: [RunEvent],
        nowEpoch: TimeInterval,
        cap: Int = cap,
        maxAgeSeconds: TimeInterval = maxAgeSeconds
    ) -> OTLPBacklogSelection {
        let cutoff = nowEpoch - maxAgeSeconds
        let unprojected = events.filter { $0.projectedAtEpoch == nil }
        var dropped: [RunEvent] = []
        var remaining: [RunEvent] = []
        remaining.reserveCapacity(unprojected.count)
        for event in unprojected {
            if event.wallTimeEpoch < cutoff {
                dropped.append(event)
            } else {
                remaining.append(event)
            }
        }
        if remaining.count > cap {
            let overflow = remaining.count - cap
            dropped.append(contentsOf: remaining.prefix(overflow))
            remaining = Array(remaining.suffix(cap))
        }
        return OTLPBacklogSelection(events: remaining, dropped: dropped)
    }
}

public enum OTLPPreview {
    public static func representativeEvents(_ events: [RunEvent]) -> [RunEvent] {
        guard let last = events.last else { return [] }
        return [last]
    }

    public static func payload(events: [RunEvent]) -> Data {
        OTLPProjector.traces(events: representativeEvents(events))
    }

    public static func text(payload: Data) -> String {
        let keys = OTLPProjector.attributeKeys(in: payload).sorted().joined(separator: ", ")
        let hex = payload.map { String(format: "%02x", $0) }.joined()
        var wrapped = ""
        wrapped.reserveCapacity(hex.count + hex.count / 64)
        for (index, character) in hex.enumerated() {
            if index > 0, index.isMultiple(of: 64) {
                wrapped.append("\n")
            }
            wrapped.append(character)
        }
        return """
        OTLP/HTTP protobuf
        bytes: \(payload.count)
        attributes: \(keys)
        hex:
        \(wrapped)

        """
    }
}

public enum OTLPSettingsGate {
    public static func enabledSettings(
        urlString: String,
        allowInsecureHTTP: Bool,
        previewCompleted: Bool
    ) throws -> OTLPExportSettings {
        guard previewCompleted else { throw OTLPExportError.previewRequired }
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else {
            throw OTLPExportError.endpointRequired
        }
        let destination = try HTTPSDestination(
            urlString: urlString,
            allowedHosts: [host],
            allowInsecureHTTP: allowInsecureHTTP
        )
        return OTLPExportSettings(enabled: true, endpoint: destination)
    }
}

public enum OTLPOpportunityContext: Sendable, Equatable {
    case foreground
    case chargingOnWiFi
    case exportBackgroundWake
    case dedicatedTelemetryTask
}

/// R-53 opportunity policy. Projection is deferred until foreground or charging Wi-Fi;
/// it receives no budget inside an export wake and may not create its own schedule.
public enum OTLPOpportunity {
    public static let maximumExportWakeWorkNanoseconds: UInt64 = 0

    public static func allow(_ context: OTLPOpportunityContext) -> Bool {
        switch context {
        case .foreground, .chargingOnWiFi:
            true
        case .exportBackgroundWake, .dedicatedTelemetryTask:
            false
        }
    }

    public static func allow(
        foreground: Bool,
        charging: Bool,
        onWiFi: Bool,
        observerWake: Bool
    ) -> Bool {
        guard !observerWake else { return false }
        if foreground {
            return allow(.foreground)
        }
        if charging && onWiFi {
            return allow(.chargingOnWiFi)
        }
        return false
    }
}
