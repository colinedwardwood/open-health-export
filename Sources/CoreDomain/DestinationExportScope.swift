// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum DestinationScopeError: Error, Equatable, LocalizedError {
    case invalidDateRange

    public var errorDescription: String? {
        "The export date range is invalid."
    }
}

/// SEC-16: the complete health-data grant for one destination. Absence is deny, not
/// "use the global default": a new destination has neither types nor a start date and
/// therefore cannot receive a health record until both are chosen interactively.
public struct DestinationExportScope: Sendable, Codable, Equatable {
    public var destinationID: String
    public var metrics: Set<MetricID>
    public var startInclusive: Date?
    public var endExclusive: Date?

    public init(
        destinationID: String,
        metrics: Set<MetricID> = [],
        startInclusive: Date? = nil,
        endExclusive: Date? = nil
    ) throws {
        if let startInclusive, let endExclusive, endExclusive <= startInclusive {
            throw DestinationScopeError.invalidDateRange
        }
        self.destinationID = destinationID
        self.metrics = metrics
        self.startInclusive = startInclusive
        self.endExclusive = endExclusive
    }

    public var isConfigured: Bool {
        !metrics.isEmpty && startInclusive != nil
    }

    public func allows(metric: MetricID, sampleStart: Date) -> Bool {
        guard metrics.contains(metric), let startInclusive, sampleStart >= startInclusive else {
            return false
        }
        return endExclusive.map { sampleStart < $0 } ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case destinationID
        case metrics
        case startInclusive
        case endExclusive
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            destinationID: values.decode(String.self, forKey: .destinationID),
            metrics: Set(values.decode([MetricID].self, forKey: .metrics)),
            startInclusive: values.decodeIfPresent(Date.self, forKey: .startInclusive),
            endExclusive: values.decodeIfPresent(Date.self, forKey: .endExclusive)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(destinationID, forKey: .destinationID)
        try values.encode(
            metrics.sorted { $0.rawValue < $1.rawValue },
            forKey: .metrics
        )
        try values.encodeIfPresent(startInclusive, forKey: .startInclusive)
        try values.encodeIfPresent(endExclusive, forKey: .endExclusive)
    }
}

/// Versioned as one document so updating a destination's types and dates is one atomic
/// preference write. Decoding failure is fail-closed at the app boundary.
public struct DestinationScopeDocument: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var scopes: [String: DestinationExportScope]

    public init(scopes: [String: DestinationExportScope] = [:]) {
        schemaVersion = 1
        self.scopes = scopes
    }

    public func scope(for destinationID: String) throws -> DestinationExportScope {
        if let scope = scopes[destinationID] { return scope }
        return try DestinationExportScope(destinationID: destinationID)
    }

    public mutating func set(_ scope: DestinationExportScope) {
        scopes[scope.destinationID] = scope
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decoded(_ data: Data) throws -> DestinationScopeDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let document = try decoder.decode(DestinationScopeDocument.self, from: data)
        guard document.schemaVersion == 1 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "unsupported destination-scope schema")
            )
        }
        return document
    }
}
