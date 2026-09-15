// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import MetricCatalog

/// Token that a call site must construct to emit HAE JSON. A boolean would be too easy to pass
/// without reading the loss table (no UUID, no tombstones — ineligible for R-23/R-24/R-27).
public struct HAELossAccepted: Sendable, Equatable {
    public init() {}
}

public enum ExportProfile: String, Sendable, Hashable, CaseIterable {
    case native
    case haeCompatibility

    public var label: String {
        switch self {
        case .native:
            "ohe.wire/1"
        case .haeCompatibility:
            "compatibility export — correctness claims do not apply"
        }
    }

    /// HAE has no UUID/tombstone/receipt contract, so it cannot arm R-23/R-24/R-27.
    public var eligibleForHonestySurfaces: Bool {
        self == .native
    }
}

public enum ExportProfileSelection {
    /// Selecting HAE always co-enables native output; compatibility is never the sole archive.
    public static func enabled(requested: Set<ExportProfile>) -> Set<ExportProfile> {
        requested.contains(.haeCompatibility)
            ? requested.union([.native])
            : requested
    }
}

public enum HAEError: Error, Equatable {
    case tombstonesNotRepresentable
    case unknownMetric
}

/// Lossy Health Auto Export compatibility JSON. Native `ohe.wire/1` remains the default encoder.
public enum HAEWire {
    public static func encode(
        samples: [SampleRecord],
        tombstones: [TombstoneRecord],
        metric: MetricID,
        acknowledgingLoss: HAELossAccepted
    ) throws -> Data {
        _ = acknowledgingLoss
        if !tombstones.isEmpty { throw HAEError.tombstonesNotRepresentable }
        guard let declaration = MetricCatalog.declaration(for: metric) else {
            throw HAEError.unknownMetric
        }
        let points: [CanonicalJSON] = samples.map { point(for: $0) }
        let metricObject: CanonicalJSON = .object([
            "name": .string(declaration.wireId),
            "units": .string(declaration.wireUnit),
            "data": .array(points),
        ])
        let root: CanonicalJSON = .object([
            "data": .object([
                "metrics": .array([metricObject]),
                "workouts": .array([]),
                "stateOfMind": .array([]),
                "medications": .array([]),
                "symptoms": .array([]),
                "cycleTracking": .array([]),
                "ecg": .array([]),
                "heartRateNotifications": .array([]),
            ])
        ])
        return Data(try root.serialized().utf8)
    }

    /// Streams the bytes `encode` returns, reading samples from the NDJSON on disk one
    /// at a time. `CanonicalJSON` serializes object keys in sorted order, so the fixed
    /// skeleton below is the same byte sequence the in-memory tree produced; each point
    /// still goes through `CanonicalJSON` so number and escape handling is unchanged.
    static func write(
        readingSamplesFrom url: URL,
        metric: MetricID,
        to destination: URL,
        acknowledgingLoss: HAELossAccepted
    ) throws {
        _ = acknowledgingLoss
        guard let declaration = MetricCatalog.declaration(for: metric) else {
            throw HAEError.unknownMetric
        }
        try Data().write(to: destination)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(flushBytes + 1_024)

        func append(_ text: String) throws {
            buffer.append(contentsOf: text.utf8)
            if buffer.count >= flushBytes {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        try append(
            "{\"data\":{\"cycleTracking\":[],\"ecg\":[],\"heartRateNotifications\":[],"
                + "\"medications\":[],\"metrics\":[{\"data\":["
        )
        var wrotePoint = false
        try NativeSidecars.forEachQuantitySample(at: url) { sample in
            if wrotePoint { try append(",") }
            wrotePoint = true
            try append(try point(for: sample).serialized())
        }
        try append(
            "],\"name\":" + (try CanonicalJSON.string(declaration.wireId).serialized())
                + ",\"units\":" + (try CanonicalJSON.string(declaration.wireUnit).serialized())
                + "}],\"stateOfMind\":[],\"symptoms\":[],\"workouts\":[]}}"
        )
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
    }

    private static let flushBytes = 64 * 1_024

    private static func point(for sample: SampleRecord) -> CanonicalJSON {
        .object([
            "qty": .number(sample.value),
            "date": .string(haeDate(sample.start)),
            "source": .string("iPhone"),
        ])
    }

    /// HAE's locale-dependent clock is a known hazard. We emit a fixed 24-hour `+0000` form so
    /// two encoder runs still match (R-84) even though a HAE receiver may parse several layouts.
    static func haeDate(_ rfc3339: String) -> String {
        let spaced = rfc3339.replacingOccurrences(of: "T", with: " ")
        if spaced.hasSuffix("Z") {
            return String(spaced.dropLast()) + " +0000"
        }
        return spaced
    }
}
