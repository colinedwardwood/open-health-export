import CoreDomain
import Foundation
import MetricCatalog

/// Token that a call site must construct to emit HAE JSON. A boolean would be too easy to pass
/// without reading the loss table (no UUID, no tombstones — ineligible for R-23/R-24/R-27).
public struct HAELossAccepted: Sendable, Equatable {
    public init() {}
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
        let points: [CanonicalJSON] = samples.map { sample in
            .object([
                "qty": .number(sample.value),
                "date": .string(haeDate(sample.start)),
                "source": .string("iPhone"),
            ])
        }
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
