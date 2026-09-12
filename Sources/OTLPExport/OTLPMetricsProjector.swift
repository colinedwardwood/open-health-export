// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct OTLPMetricsDestination: Sendable, Equatable {
    /// A locally generated opaque identifier. Never pass a user-authored label.
    public var destinationID: String
    public var lastSuccessEpoch: TimeInterval

    public init(destinationID: String, lastSuccessEpoch: TimeInterval) {
        self.destinationID = destinationID
        self.lastSuccessEpoch = lastSuccessEpoch
    }
}

public enum OTLPMetricsProjector {
    public static let lastSuccessMetric = "ohe.destination.last_success.timestamp"
    public static let stalenessMetric = "ohe.destination.staleness"
    public static let destinationIDAttribute = "ohe.destination.id"

    public static func metrics(
        destinations: [OTLPMetricsDestination],
        nowEpoch: TimeInterval
    ) -> Data {
        let bounded = boundedDestinationIDs(destinations)
        let lastSuccessPoints = bounded.map {
            numberDataPoint(
                destinationID: $0.destinationID,
                value: max(0, $0.lastSuccessEpoch),
                nowEpoch: nowEpoch
            )
        }
        let stalenessPoints = bounded.map {
            numberDataPoint(
                destinationID: $0.destinationID,
                value: max(0, nowEpoch - $0.lastSuccessEpoch),
                nowEpoch: nowEpoch
            )
        }
        let metrics = gaugeMetric(name: lastSuccessMetric, points: lastSuccessPoints)
            + gaugeMetric(name: stalenessMetric, points: stalenessPoints)
        let scopeMetrics = ProtoWriter.field(2, bytes: metrics)
        let resource = ProtoWriter.field(
            1,
            bytes: ProtoWriter.field(
                1,
                bytes: OTLPProjector.stringAttribute("service.name", OTLPProjector.serviceName)
            )
        )
        return ProtoWriter.field(1, bytes: resource + scopeMetrics)
    }

    private static func boundedDestinationIDs(
        _ destinations: [OTLPMetricsDestination]
    ) -> [OTLPMetricsDestination] {
        let sorted = destinations.sorted {
            ($0.destinationID, $0.lastSuccessEpoch) < ($1.destinationID, $1.lastSuccessEpoch)
        }
        let allowedIDs = Set(
            sorted.map(\.destinationID).uniqued()
                .prefix(TelemetryCardinalityBudget.destinationSlots - 1)
        )
        var latest: [String: TimeInterval] = [:]
        for destination in sorted {
            let id = allowedIDs.contains(destination.destinationID)
                ? destination.destinationID
                : TelemetryDestinationKind.other.rawValue
            latest[id] = max(latest[id] ?? 0, destination.lastSuccessEpoch)
        }
        return latest.map {
            OTLPMetricsDestination(destinationID: $0.key, lastSuccessEpoch: $0.value)
        }.sorted { $0.destinationID < $1.destinationID }
    }

    private static func gaugeMetric(name: String, points: [Data]) -> Data {
        let gauge = points.reduce(into: Data()) { $0.append(ProtoWriter.field(1, bytes: $1)) }
        return ProtoWriter.field(
            2,
            bytes: ProtoWriter.field(1, string: name) + ProtoWriter.field(5, bytes: gauge)
        )
    }

    private static func numberDataPoint(
        destinationID: String,
        value: Double,
        nowEpoch: TimeInterval
    ) -> Data {
        let attribute = OTLPProjector.stringAttribute(destinationIDAttribute, destinationID)
        let timestamp = UInt64(max(0, nowEpoch) * 1_000_000_000)
        return ProtoWriter.field(7, bytes: attribute)
            + ProtoWriter.fieldFixed64(3, value: timestamp)
            + ProtoWriter.fieldFixed64(4, value: value.bitPattern)
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
