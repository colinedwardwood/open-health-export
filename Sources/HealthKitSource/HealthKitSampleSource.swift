#if canImport(HealthKit)
@preconcurrency import HealthKit
import CoreDomain
import CoreTemporal
import EnginePorts
import Foundation
import MetricCatalog

enum AnchorCoding {
    static func encode(_ anchor: HKQueryAnchor) throws -> Data {
        let bytes = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        return AnchorToken(format: AnchorToken.currentFormat, bytes: bytes).envelope()
    }

    static func decode(_ data: Data) throws -> HKQueryAnchor? {
        if data.isEmpty { return nil }
        let token = try AnchorToken.fromEnvelope(data)
        guard token.format == AnchorToken.currentFormat else {
            throw AnchorTokenError.unsupportedFormat
        }
        if token.bytes.isEmpty { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: token.bytes)
    }
}

enum SampleConversion {
    static func formatUTC(_ date: Date) -> String {
        date.ISO8601Format()
    }

    static func parseUTC(_ string: String) -> Date? {
        try? Date(string, strategy: .iso8601)
    }

    static func quantityType(for metric: MetricID) -> HKQuantityType? {
        switch metric.rawValue {
        case "stepCount": return HKQuantityType(.stepCount)
        case "heartRate": return HKQuantityType(.heartRate)
        default: return nil
        }
    }

    static func unit(for metric: MetricID) -> HKUnit {
        switch metric.rawValue {
        case "heartRate": return HKUnit.count().unitDivided(by: .minute())
        default: return .count()
        }
    }

    /// Must run inside the HealthKit query callback, before any continuation resumes.
    static func record(
        from sample: HKQuantitySample,
        metric: MetricID,
        context: TemporalContext
    ) -> SampleRecord {
        let unit = unit(for: metric)
        let offset = context.timeZone().secondsFromGMT(for: sample.startDate) / 60
        return SampleRecord(
            key: RecordKey(uuid: sample.uuid.uuidString),
            metric: metric,
            start: formatUTC(sample.startDate),
            end: formatUTC(sample.endDate),
            timeZoneOffsetMinutes: offset,
            timeZoneSource: .deviceCurrent,
            value: sample.quantity.doubleValue(for: unit),
            unit: CanonicalUnit(symbol: unit.unitString),
            observedAt: formatUTC(Date())
        )
    }

    static func tombstone(from deleted: HKDeletedObject, metric: MetricID) -> TombstoneRecord {
        TombstoneRecord(key: RecordKey(uuid: deleted.uuid.uuidString), metric: metric)
    }
}

public enum HealthKitSourceError: Error, Sendable {
    case unavailable
    case unknownMetric(MetricID)
    case queryFailed(String)
}

public enum HealthKitAuthorization {
    public static func readTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for metric in [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id] {
            if let type = SampleConversion.quantityType(for: metric) {
                types.insert(type)
            }
        }
        return types
    }

    public static func requestReadAccess(store: HKHealthStore = HKHealthStore()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitSourceError.unavailable
        }
        try await store.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes())
    }
}

public final class HealthKitSampleSource: SampleSource, @unchecked Sendable {
    private let store: HKHealthStore
    private let context: TemporalContext
    private let limit: Int

    public init(store: HKHealthStore = HKHealthStore(), context: TemporalContext, limit: Int = 1000) {
        self.store = store
        self.context = context
        self.limit = limit
    }

    public func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitSourceError.unavailable
        }
        guard let type = SampleConversion.quantityType(for: metric) else {
            throw HealthKitSourceError.unknownMetric(metric)
        }
        let anchor = try afterAnchor.flatMap(AnchorCoding.decode)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: limit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: HealthKitSourceError.queryFailed(error.localizedDescription))
                    return
                }
                // Convert before the continuation resumes — no HK* leaves this callback.
                let records = (samples ?? []).compactMap { sample -> SampleRecord? in
                    guard let quantity = sample as? HKQuantitySample else { return nil }
                    return SampleConversion.record(from: quantity, metric: metric, context: self.context)
                }
                let tombs = (deleted ?? []).map { SampleConversion.tombstone(from: $0, metric: metric) }
                let blob: Data
                do {
                    blob = try newAnchor.map(AnchorCoding.encode) ?? Data()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let latest = records.last.flatMap { SampleConversion.parseUTC($0.end) }
                    ?? Date(timeIntervalSince1970: 0)
                continuation.resume(
                    returning: SamplePage(
                        samples: records,
                        tombstones: tombs,
                        metric: metric,
                        anchorBlob: blob,
                        observedThrough: latest
                    )
                )
            }
            self.store.execute(query)
        }
    }
}

/// R-70: time a single anchored page. Call from a device build with a populated store.
public enum HealthKitThroughput {
    public static func measure(
        source: HealthKitSampleSource,
        metric: MetricID,
        afterAnchor: Data? = nil
    ) async throws -> ThroughputSample {
        let started = ContinuousClock.now
        let page = try await source.page(metric: metric, afterAnchor: afterAnchor)
        let elapsed = started.duration(to: ContinuousClock.now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let count = page.samples.count
        return ThroughputSample(
            samples: count,
            seconds: seconds,
            samplesPerSecond: seconds > 0 ? Double(count) / seconds : 0
        )
    }
}

public struct ThroughputSample: Sendable {
    public var samples: Int
    public var seconds: Double
    public var samplesPerSecond: Double
}
#endif
