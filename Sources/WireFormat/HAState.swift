// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Non-retained Home Assistant state JSON. Sample UUIDs and HAE `qty` never appear here.
public struct HAStatePoint: Sendable, Equatable {
    public var value: Double
    public var bucketStart: String?
    public var bucketEnd: String?
    public var timeZoneIdentifier: String
    public var sampleCount: Int
    public var state: String
    public var computation: String

    public init(
        value: Double,
        bucketStart: String? = nil,
        bucketEnd: String? = nil,
        timeZoneIdentifier: String,
        sampleCount: Int,
        state: String,
        computation: String
    ) {
        self.value = value
        self.bucketStart = bucketStart
        self.bucketEnd = bucketEnd
        self.timeZoneIdentifier = timeZoneIdentifier
        self.sampleCount = sampleCount
        self.state = state
        self.computation = computation
    }
}

public enum HAState {
    public static func topic(exporterId: String, wireId: String, statistic: String, granularity: String) throws -> String {
        let id = try HADiscovery.sanitizeExporterId(exporterId)
        return "ohe/\(id)/v1/state/\(wireId)/\(statistic)/\(granularity)"
    }

    public static func encode(_ point: HAStatePoint) throws -> Data {
        var fields: [String: CanonicalJSON] = [
            "value": .number(point.value),
            "tz": .string(point.timeZoneIdentifier),
            "sampleCount": .integer(point.sampleCount),
            "state": .string(point.state),
            "computation": .string(point.computation),
        ]
        if let start = point.bucketStart {
            fields["bucketStart"] = .string(start)
        }
        if let end = point.bucketEnd {
            fields["bucketEnd"] = .string(end)
        }
        return Data(try CanonicalJSON.object(fields).serialized().utf8)
    }
}
