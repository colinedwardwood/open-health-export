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
        guard let declaration = MetricCatalog.declaration(for: metric) else { return nil }
        let identifier = HKQuantityTypeIdentifier(rawValue: declaration.hkIdentifier)
        return HKQuantityType.quantityType(forIdentifier: identifier)
    }

    static func unit(for metric: MetricID) -> HKUnit {
        switch metric {
        case MetricCatalog.heartRate.id,
             MetricCatalog.respiratoryRate.id,
             MetricCatalog.restingHeartRate.id,
             MetricCatalog.walkingHeartRateAverage.id:
            return HKUnit.count().unitDivided(by: .minute())
        case MetricCatalog.activeEnergy.id, MetricCatalog.basalEnergy.id:
            return .kilocalorie()
        case MetricCatalog.bodyMass.id, MetricCatalog.leanBodyMass.id:
            return .gramUnit(with: .kilo)
        case MetricCatalog.oxygenSaturation.id:
            return .percent()
        case MetricCatalog.walkingRunningDistance.id, MetricCatalog.cyclingDistance.id:
            return .meter()
        case MetricCatalog.vo2Max.id:
            return HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        case MetricCatalog.bloodGlucose.id:
            return HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case MetricCatalog.exerciseTime.id, MetricCatalog.standTime.id:
            return .minute()
        case MetricCatalog.heartRateVariabilitySDNN.id:
            return .secondUnit(with: .milli)
        case MetricCatalog.bodyTemperature.id, MetricCatalog.basalBodyTemperature.id:
            return .degreeCelsius()
        case MetricCatalog.dietaryWater.id:
            return .literUnit(with: .milli)
        case MetricCatalog.bloodPressureSystolic.id, MetricCatalog.bloodPressureDiastolic.id:
            return .millimeterOfMercury()
        default:
            return .count()
        }
    }

    static func canonicalValue(_ hkValue: Double, metric: MetricID) -> Double {
        switch metric {
        case MetricCatalog.oxygenSaturation.id:
            return hkValue * 100
        case MetricCatalog.walkingRunningDistance.id, MetricCatalog.cyclingDistance.id:
            return hkValue / 1000
        default:
            return hkValue
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
        let canonical = MetricCatalog.declaration(for: metric)?.canonicalUnit
            ?? CanonicalUnit(symbol: unit.unitString)
        return SampleRecord(
            key: RecordKey(uuid: sample.uuid.uuidString),
            metric: metric,
            start: formatUTC(sample.startDate),
            end: formatUTC(sample.endDate),
            timeZoneOffsetMinutes: offset,
            timeZoneSource: .deviceCurrent,
            value: canonicalValue(sample.quantity.doubleValue(for: unit), metric: metric),
            unit: canonical,
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
        for declaration in MetricCatalog.all {
            if let type = SampleConversion.quantityType(for: declaration.id) {
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

/// Date-ranged R-08 source. Sweep anchors are throwaway values and never escape this adapter.
public final class HealthKitDayObservationSource: DayObservationSource, @unchecked Sendable {
    private let store: HKHealthStore
    private let context: TemporalContext
    private let limit: Int

    public init(store: HKHealthStore = HKHealthStore(), context: TemporalContext, limit: Int = 1000) {
        self.store = store
        self.context = context
        self.limit = limit
    }

    public func samples(metric: MetricID, day: String) async throws -> [SampleRecord] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitSourceError.unavailable
        }
        guard let type = SampleConversion.quantityType(for: metric) else {
            throw HealthKitSourceError.unknownMetric(metric)
        }
        guard let bounds = BucketKey.boundsP1D(day: day, context: context),
              let start = SampleConversion.parseUTC(bounds.bucketStart),
              let end = SampleConversion.parseUTC(bounds.bucketEnd)
        else {
            throw HealthKitSourceError.queryFailed("invalid day")
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        var anchor: HKQueryAnchor?
        var records: [SampleRecord] = []
        while true {
            let page = try await queryPage(
                type: type,
                predicate: predicate,
                anchor: anchor,
                metric: metric
            )
            records.append(contentsOf: page.records)
            anchor = page.anchor
            if page.count < limit || page.anchor == nil {
                return records
            }
        }
    }

    private func queryPage(
        type: HKQuantityType,
        predicate: NSPredicate,
        anchor: HKQueryAnchor?,
        metric: MetricID
    ) async throws -> (records: [SampleRecord], anchor: HKQueryAnchor?, count: Int) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: limit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(
                        throwing: HealthKitSourceError.queryFailed(error.localizedDescription)
                    )
                    return
                }
                let converted = (samples ?? []).compactMap { sample -> SampleRecord? in
                    guard let quantity = sample as? HKQuantitySample else { return nil }
                    return SampleConversion.record(
                        from: quantity,
                        metric: metric,
                        context: self.context
                    )
                }
                continuation.resume(
                    returning: (converted, newAnchor, samples?.count ?? 0)
                )
            }
            self.store.execute(query)
        }
    }
}

enum StatisticsConversion {
    static func record(
        metric: MetricID,
        day: String,
        value: Double?,
        context: TemporalContext,
        computedAt: String,
        observedAt: String
    ) -> AggregateRecord? {
        guard let declaration = MetricCatalog.declaration(for: metric),
              declaration.usesHealthKitStatistics,
              let bounds = BucketKey.boundsP1D(day: day, context: context)
        else { return nil }
        let key = BucketKey.render(
            metricWireId: declaration.wireId,
            statistic: AggregateStatistic.sum.rawValue,
            granularity: "P1D",
            bucketStart: bounds.bucketStart,
            timeZoneIdentifier: context.timeZoneIdentifier,
            sourceScope: AggregateSourceScope.all.rawValue
        )
        return AggregateRecord(
            bucketKey: key,
            metric: metric,
            statistic: .sum,
            computation: .healthKitStatisticsCollectionQuery,
            sourceScope: .all,
            granularity: "P1D",
            bucketStart: bounds.bucketStart,
            bucketEnd: bounds.bucketEnd,
            bucketDurationSeconds: bounds.bucketDurationSeconds,
            timeZoneIdentifier: context.timeZoneIdentifier,
            localStart: bounds.localStart,
            value: value,
            unit: declaration.canonicalUnit,
            sampleCount: 0,
            state: .open,
            emitSeq: 1,
            computedAt: computedAt,
            observedAt: observedAt
        )
    }
}

/// Canonical de-duplicated daily totals for the catalogue's R-80 exception list.
public final class HealthKitStatisticsSource: StatisticsSource, @unchecked Sendable {
    private let store: HKHealthStore
    private let context: TemporalContext

    public init(store: HKHealthStore = HKHealthStore(), context: TemporalContext) {
        self.store = store
        self.context = context
    }

    public func dailyBucket(metric: MetricID, day: String) async throws -> AggregateRecord? {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitSourceError.unavailable
        }
        guard let declaration = MetricCatalog.declaration(for: metric),
              declaration.usesHealthKitStatistics,
              let type = SampleConversion.quantityType(for: metric)
        else {
            throw HealthKitSourceError.unknownMetric(metric)
        }
        guard let bounds = BucketKey.boundsP1D(day: day, context: context),
              let start = SampleConversion.parseUTC(bounds.bucketStart),
              let end = SampleConversion.parseUTC(bounds.bucketEnd)
        else {
            throw HealthKitSourceError.queryFailed("invalid day")
        }
        let value = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Double?, Error>) in
            let interval = DateComponents(day: 1)
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(
                    withStart: start,
                    end: end,
                    options: .strictStartDate
                ),
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(
                        throwing: HealthKitSourceError.queryFailed(error.localizedDescription)
                    )
                    return
                }
                let statistic = collection?.statistics().first
                let quantity = statistic?.sumQuantity()
                let raw = quantity?.doubleValue(for: SampleConversion.unit(for: metric))
                continuation.resume(
                    returning: raw.map { SampleConversion.canonicalValue($0, metric: metric) }
                )
            }
            self.store.execute(query)
        }
        let now = SampleConversion.formatUTC(Date())
        return StatisticsConversion.record(
            metric: declaration.id,
            day: day,
            value: value,
            context: context,
            computedAt: now,
            observedAt: now
        )
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
