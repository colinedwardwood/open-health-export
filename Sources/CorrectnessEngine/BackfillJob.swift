import CoreDomain
import CoreTemporal
import EnginePorts
import FileWriteKit
import Foundation
import WireFormat

public enum BackfillMode: String, Codable, Sendable {
    case aggregateOnly
    case raw
}

public struct BackfillPlan: Codable, Sendable, Equatable {
    public var windowStartDay: String
    public var windowEndDay: String
    public var order: String
    public var chunkTargetSamples: Int
    public var chunkTargetBytes: Int
    public var mode: BackfillMode
    public var metrics: [MetricID]
    public var destinations: [String]

    public init(
        windowStartDay: String,
        windowEndDay: String,
        order: String = "newestFirst",
        chunkTargetSamples: Int = 5_000,
        chunkTargetBytes: Int = 4 * 1_024 * 1_024,
        mode: BackfillMode = .aggregateOnly,
        metrics: [MetricID],
        destinations: [String]
    ) {
        self.windowStartDay = windowStartDay
        self.windowEndDay = windowEndDay
        self.order = order
        self.chunkTargetSamples = chunkTargetSamples
        self.chunkTargetBytes = chunkTargetBytes
        self.mode = mode
        self.metrics = metrics
        self.destinations = destinations
    }
}

public struct BackfillCompletedRange: Codable, Sendable, Equatable {
    public var metric: MetricID
    public var days: [String]

    public init(metric: MetricID, days: [String] = []) {
        self.metric = metric
        self.days = days
    }
}

public struct BackfillCursor: Codable, Sendable, Equatable {
    public var metricIndex: Int
    public var day: String

    public init(metricIndex: Int, day: String) {
        self.metricIndex = metricIndex
        self.day = day
    }
}

public struct BackfillProgress: Codable, Sendable, Equatable {
    public var completed: [BackfillCompletedRange]
    public var cursor: BackfillCursor?
    public var samplesRead: Int
    public var batchesEnqueued: Int
    public var pausedReason: String?

    public init(
        completed: [BackfillCompletedRange] = [],
        cursor: BackfillCursor? = nil,
        samplesRead: Int = 0,
        batchesEnqueued: Int = 0,
        pausedReason: String? = nil
    ) {
        self.completed = completed
        self.cursor = cursor
        self.samplesRead = samplesRead
        self.batchesEnqueued = batchesEnqueued
        self.pausedReason = pausedReason
    }
}

public struct BackfillIntegrity: Codable, Sendable, Equatable {
    public var algorithm: String
    public var value: String

    public init(algorithm: String = "sha256", value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

public struct BackfillCheckpoint: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var jobID: String
    public var jobKind: String
    public var createdAt: String
    public var updatedAt: String
    public var hostModel: String
    public var plan: BackfillPlan
    public var progress: BackfillProgress
    public var integrity: BackfillIntegrity

    public init(
        jobID: String,
        createdAt: String,
        hostModel: String,
        plan: BackfillPlan
    ) throws {
        schemaVersion = Self.currentSchemaVersion
        self.jobID = jobID
        jobKind = "backfill"
        self.createdAt = createdAt
        updatedAt = createdAt
        self.hostModel = hostModel
        self.plan = plan
        progress = BackfillProgress(
            completed: plan.metrics.map { BackfillCompletedRange(metric: $0) }
        )
        integrity = BackfillIntegrity(value: "")
        try reseal()
    }

    public mutating func reseal() throws {
        integrity = BackfillIntegrity(value: "")
        integrity.value = ContentSHA256.hex(try unsignedBytes())
    }

    public func validated() throws -> BackfillCheckpoint {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw BackfillError.unsupportedSchema(schemaVersion)
        }
        guard jobKind == "backfill", integrity.algorithm == "sha256" else {
            throw BackfillError.corruptCheckpoint
        }
        var unsigned = self
        let expected = unsigned.integrity.value
        unsigned.integrity.value = ""
        guard expected == ContentSHA256.hex(try unsigned.unsignedBytes()) else {
            throw BackfillError.corruptCheckpoint
        }
        _ = try ReconcilePlanner.days(
            from: plan.windowStartDay,
            through: plan.windowEndDay
        )
        guard plan.order == "newestFirst",
              plan.chunkTargetSamples > 0,
              plan.chunkTargetBytes > 0,
              !plan.metrics.isEmpty,
              !plan.destinations.isEmpty
        else {
            throw BackfillError.invalidPlan
        }
        return self
    }

    public static func read(from url: URL) throws -> BackfillCheckpoint {
        let decoded = try JSONDecoder().decode(
            BackfillCheckpoint.self,
            from: Data(contentsOf: url)
        )
        return try decoded.validated()
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    private func unsignedBytes() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct BackfillChunkResult: Sendable, Equatable {
    public var samplesRead: Int
    public var batchesEnqueued: Int

    public init(samplesRead: Int, batchesEnqueued: Int) {
        self.samplesRead = samplesRead
        self.batchesEnqueued = batchesEnqueued
    }
}

public protocol BackfillChunkProcessor: Sendable {
    func process(
        metric: MetricID,
        days: [String],
        mode: BackfillMode
    ) async throws -> BackfillChunkResult
}

public enum BackfillError: Error, Equatable {
    case unsupportedSchema(Int)
    case corruptCheckpoint
    case invalidPlan
}

/// R-11: resumable, newest-first backfill. A day is marked complete only after
/// its processor returns, so abrupt termination can repeat at most one chunk
/// and can never skip a range. This state never reads or advances live anchors.
public struct BackfillJob: Sendable {
    public var checkpointURL: URL
    public var processor: any BackfillChunkProcessor
    public var clock: any Clock
    public var store: (any StateStore)?

    public init(
        checkpointURL: URL,
        processor: any BackfillChunkProcessor,
        clock: any Clock = SystemClock(),
        store: (any StateStore)? = nil
    ) {
        self.checkpointURL = checkpointURL
        self.processor = processor
        self.clock = clock
        self.store = store
    }

    public func create(_ checkpoint: BackfillCheckpoint) async throws {
        guard !FileManager.default.fileExists(atPath: checkpointURL.path) else {
            throw BackfillError.invalidPlan
        }
        try await persist(checkpoint)
    }

    @discardableResult
    public func run() async throws -> BackfillCheckpoint {
        var checkpoint = try await load()
        let days = try ReconcilePlanner.days(
            from: checkpoint.plan.windowStartDay,
            through: checkpoint.plan.windowEndDay
        ).reversed()
        let allDays = Array(days)

        for (metricIndex, metric) in checkpoint.plan.metrics.enumerated() {
            let completed = Set(
                checkpoint.progress.completed.first { $0.metric == metric }?.days ?? []
            )
            for day in allDays where !completed.contains(day) {
                try Task.checkCancellation()
                checkpoint.progress.cursor = BackfillCursor(
                    metricIndex: metricIndex,
                    day: day
                )
                checkpoint.progress.pausedReason = nil
                try await persist(&checkpoint)

                let result: BackfillChunkResult
                do {
                    result = try await processor.process(
                        metric: metric,
                        days: [day],
                        mode: checkpoint.plan.mode
                    )
                } catch is CancellationError {
                    checkpoint.progress.pausedReason = "cancelled"
                    try await persist(&checkpoint)
                    throw CancellationError()
                } catch {
                    checkpoint.progress.pausedReason = "processor_error"
                    try await persist(&checkpoint)
                    throw error
                }

                checkpoint.progress.samplesRead += result.samplesRead
                checkpoint.progress.batchesEnqueued += result.batchesEnqueued
                if let index = checkpoint.progress.completed.firstIndex(
                    where: { $0.metric == metric }
                ) {
                    checkpoint.progress.completed[index].days.append(day)
                    checkpoint.progress.completed[index].days.sort()
                } else {
                    checkpoint.progress.completed.append(
                        BackfillCompletedRange(metric: metric, days: [day])
                    )
                }
                try await persist(&checkpoint)
            }
        }
        checkpoint.progress.cursor = nil
        checkpoint.progress.pausedReason = nil
        try await persist(&checkpoint)
        return checkpoint
    }

    private func load() async throws -> BackfillCheckpoint {
        let file = try BackfillCheckpoint.read(from: checkpointURL)
        guard let store else { return file }
        let mirrored = try await store.transact {
            try $0.loadBackfillCheckpoint(jobID: file.jobID)
        }
        let expected = try file.encoded()
        guard let mirrored, mirrored == expected else {
            throw BackfillError.corruptCheckpoint
        }
        return file
    }

    private func persist(_ checkpoint: inout BackfillCheckpoint) async throws {
        checkpoint.updatedAt = clock.now().ISO8601Format()
        try checkpoint.reseal()
        try await persist(checkpoint)
    }

    private func persist(_ checkpoint: BackfillCheckpoint) async throws {
        let bytes = try checkpoint.encoded()
        try FileWriteKit.writeAtomically(bytes, to: checkpointURL)
        if let store {
            try await store.transact {
                try $0.upsertBackfillCheckpoint(jobID: checkpoint.jobID, bytes: bytes)
            }
        }
    }
}
