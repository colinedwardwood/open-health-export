import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog
import WireFormat

/// Release-shipped synthetic source. No HealthKit, no fault seams (QA-38).
public struct DemoSampleSource: SampleSource, Sendable {
    public var seed: UInt64
    public var samplesPerMetric: Int

    public init(seed: UInt64 = 1, samplesPerMetric: Int = 4) {
        self.seed = seed
        self.samplesPerMetric = samplesPerMetric
    }

    public func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        if afterAnchor != nil {
            return SamplePage(
                samples: [],
                tombstones: [],
                metric: metric,
                anchorBlob: afterAnchor ?? Data(),
                observedThrough: Date(timeIntervalSince1970: 0)
            )
        }
        guard let declaration = MetricCatalog.declaration(for: metric) else {
            return SamplePage(
                samples: [],
                tombstones: [],
                metric: metric,
                anchorBlob: Data("demo-unknown".utf8),
                observedThrough: Date(timeIntervalSince1970: 0)
            )
        }
        let metricIndex = MetricCatalog.all.firstIndex { $0.id == metric } ?? 0
        let samples = (0..<samplesPerMetric).map { offset in
            DemoCorpus.sample(
                at: metricIndex * samplesPerMetric + offset,
                seed: seed,
                declaration: declaration
            )
        }
        return SamplePage(
            samples: samples,
            tombstones: [],
            metric: metric,
            anchorBlob: Data("demo-eof".utf8),
            observedThrough: Date(timeIntervalSince1970: 1)
        )
    }
}

public enum DemoExportError: Error, Equatable {
    case confirmationRequired
    case confirmationMismatch
}

public enum DemoExportGate {
    public static func confirmSending(to destinationName: String, typed: String) throws {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DemoExportError.confirmationRequired }
        guard trimmed == destinationName else { throw DemoExportError.confirmationMismatch }
    }
}
