// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CoreTemporal
import CorrectnessEngine
import EnginePorts
import Foundation
import MetricCatalog
import TestSupport
import WireFormat

private let memoryLimitMiB = 100
private let defaultPageSize = 500
private let maximumPageSize = 10_000
private let maximumConcurrentMetrics = 4
private let newline = Data([0x0A])
private let volumeStructuralKinds = NativeWire.volumeStructuralKinds

@main
struct ExportRunCheck {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("exportruncheck failed: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func run() async throws {
        let pageSize = try parsePageSize()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-exportruncheck-\(UUID().uuidString)")
        let scratch = root.appendingPathComponent("scratch")
        let spoolRoot = root.appendingPathComponent("spool")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: spoolRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var reader = NDJSONLineReader(handle: .standardInput)
        var spools: [MetricID: MetricSpool] = [:]
        defer {
            for spool in spools.values {
                try? spool.handle.close()
            }
        }
        var declaredRecords: Int?
        var inputLines = 0
        var headerRecords = 0
        var structuralRecords = 0
        var exportableRecords = 0
        var submittedRecords = 0
        var pages = 0
        var totalRead = 0
        var totalAcked = 0

        while let line = try reader.next() {
            guard !line.isEmpty else { continue }
            inputLines += 1
            if inputLines == 1 {
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    throw CheckError.invalidRecord(line: inputLines)
                }
                declaredRecords = try validateCorpusProvenance(object)
                headerRecords = 1
                continue
            }
            let record: KindRecord
            do {
                record = try JSONDecoder().decode(KindRecord.self, from: line)
            } catch {
                throw CheckError.invalidRecord(line: inputLines)
            }
            switch record.kind {
            case "sample.quantity":
                guard let wireId = record.metricId else {
                    throw CheckError.invalidRecord(line: inputLines)
                }
                let metric = MetricCatalog.all.first { $0.wireId == wireId }?.id
                    ?? MetricID(rawValue: wireId)
                let spool: MetricSpool
                if let existing = spools[metric] {
                    spool = existing
                } else {
                    let url = spoolRoot.appendingPathComponent("metric-\(spools.count).ndjson")
                    _ = FileManager.default.createFile(atPath: url.path, contents: nil)
                    let created = MetricSpool(
                        url: url,
                        handle: try FileHandle(forWritingTo: url)
                    )
                    spools[metric] = created
                    spool = created
                }
                try spool.handle.write(contentsOf: line)
                try spool.handle.write(contentsOf: newline)
                exportableRecords += 1
            case let structural where volumeStructuralKinds.contains(structural):
                structuralRecords += 1
            default:
                throw CheckError.unaccountedKind(kind: record.kind, line: inputLines)
            }
        }

        for spool in spools.values {
            try spool.handle.close()
        }
        let work = spools.keys.sorted(by: { $0.rawValue < $1.rawValue }).enumerated().compactMap {
            ordinal, metric -> MetricWork? in
            spools[metric].map { MetricWork(ordinal: ordinal, metric: metric, url: $0.url) }
        }
        var nextWork = work.makeIterator()
        try await withThrowingTaskGroup(of: MetricWorkResult.self) { group in
            for _ in 0 ..< min(maximumConcurrentMetrics, work.count) {
                if let item = nextWork.next() {
                    group.addTask {
                        try await process(
                            item,
                            pageSize: pageSize,
                            scratchRoot: scratch
                        )
                    }
                }
            }
            while let result = try await group.next() {
                pages += result.pages
                submittedRecords += result.submitted
                totalRead += result.read
                totalAcked += result.acked
                if let item = nextWork.next() {
                    group.addTask {
                        try await process(
                            item,
                            pageSize: pageSize,
                            scratchRoot: scratch
                        )
                    }
                }
            }
        }

        guard headerRecords == 1, let declaredRecords else {
            throw CheckError.invalidProvenance
        }
        guard exportableRecords > 0 else {
            throw CheckError.noSamples
        }
        guard declaredRecords == exportableRecords + structuralRecords else {
            throw CheckError.declaredCountMismatch(
                declared: declaredRecords,
                accounted: exportableRecords + structuralRecords
            )
        }
        guard submittedRecords == exportableRecords else {
            throw CheckError.skippedExportable(
                parsed: exportableRecords,
                submitted: submittedRecords
            )
        }
        #if os(Linux)
        let peakKiB = try peakResidentMemoryKiB()
        // R-74 in docs/02-design/08-reliability-design.md declares a 100 MB maximum.
        let limitKiB = memoryLimitMiB * 1_024
        guard peakKiB <= limitKiB else {
            throw CheckError.memoryExceeded(peakKiB: peakKiB, limitKiB: limitKiB)
        }
        let memoryResult = String(format: "%.1f", Double(peakKiB) / 1_024)
        #else
        let memoryResult = "unsupported"
        #endif

        print(
            "exportruncheck outcome=success"
                + " metrics=\(spools.count)"
                + " pages=\(pages)"
                + " page_size=\(pageSize)"
                + " exportable_records=\(exportableRecords)"
                + " submitted_records=\(submittedRecords)"
                + " structural_records=\(structuralRecords)"
                + " header_records=\(headerRecords)"
                + " declared_records=\(declaredRecords)"
                + " samples_read=\(totalRead)"
                + " samples_acked=\(totalAcked)"
                + " input_lines=\(inputLines)"
                + " peak_rss_mib=\(memoryResult)"
                + " limit_mib=\(memoryLimitMiB)"
                + " formats=native-ndjson,native-json,native-json-pretty,csv,hae"
        )
    }

    private static func parsePageSize() throws -> Int {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else { return defaultPageSize }
        guard arguments.count == 2, arguments[0] == "--page-size",
              let size = Int(arguments[1]), (1...maximumPageSize).contains(size)
        else {
            throw CheckError.invalidPageSize(maximum: maximumPageSize)
        }
        return size
    }

    private static func validateCorpusProvenance(_ header: [String: Any]) throws -> Int {
        guard header["kind"] as? String == "batch.header",
              header["synthetic"] as? Bool == true,
              let tier = header["tier"] as? String,
              ["T0", "T1", "T2"].contains(tier),
              let recordCount = (header["recordCount"] as? NSNumber)?.intValue,
              recordCount >= 0
        else {
            throw CheckError.invalidProvenance
        }
        return recordCount
    }

    private static func exercise(
        samples: [SampleRecord],
        metric: MetricID,
        sequence: Int,
        scratchRoot: URL,
        exerciseSidecars: Bool
    ) async throws -> (read: Int, acked: Int) {
        let pageScratch = scratchRoot.appendingPathComponent("page-\(sequence)")
        try FileManager.default.createDirectory(at: pageScratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: pageScratch) }
        let store = MemoryStateStore()
        let run = ExportRun(
            source: CorpusSliceSource(samples: samples, sequence: sequence),
            destination: .testing(
                AuditingSink(
                    expectedQuantityRecords: samples.count,
                    exerciseSidecars: exerciseSidecars
                )
            ),
            store: store,
            metric: metric,
            scratchDirectory: pageScratch,
            envelope: WireEnvelope(
                exporterId: "00000000-0000-4000-8000-000000000024",
                seq: sequence,
                emittedAt: "2025-01-01T00:00:00Z",
                observedAt: "2025-01-01T00:00:00Z"
            ),
            clock: FrozenClock(instant: Date(timeIntervalSince1970: 1_735_689_600)),
            trigger: .bgProcessing
        )
        let outcome = try await run.run()
        guard outcome.kind == .success else {
            throw CheckError.outcome(metric: metric.rawValue, outcome: outcome.kind.rawValue)
        }
        guard outcome.ackEvidence == .receiptFull else {
            throw CheckError.ackEvidence(outcome.ackEvidence.rawValue)
        }
        guard let event = store.transaction.journal.last else {
            throw CheckError.missingJournal
        }
        guard event.samplesRead == event.samplesAcked else {
            throw CheckError.countMismatch(read: event.samplesRead, acked: event.samplesAcked)
        }
        return (event.samplesRead, event.samplesAcked)
    }

    private static func process(
        _ work: MetricWork,
        pageSize: Int,
        scratchRoot: URL
    ) async throws -> MetricWorkResult {
        let handle = try FileHandle(forReadingFrom: work.url)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: work.url)
        }
        var reader = NDJSONLineReader(handle: handle)
        var page: [SampleRecord] = []
        page.reserveCapacity(pageSize)
        var result = MetricWorkResult()

        func submit(_ samples: [SampleRecord], pageNumber: Int) async throws -> (Int, Int) {
            let counts = try await exercise(
                samples: samples,
                metric: work.metric,
                sequence: (work.ordinal + 1) * 1_000_000 + pageNumber,
                scratchRoot: scratchRoot,
                exerciseSidecars: pageNumber == 1
            )
            return (counts.read, counts.acked)
        }

        while let line = try reader.next() {
            page.append(try NativeSidecars.quantitySample(fromNDJSONLine: line))
            guard page.count == pageSize else { continue }
            let counts = try await submit(page, pageNumber: result.pages + 1)
            result.pages += 1
            result.submitted += page.count
            result.read += counts.0
            result.acked += counts.1
            page.removeAll(keepingCapacity: true)
        }
        if !page.isEmpty {
            let counts = try await submit(page, pageNumber: result.pages + 1)
            result.pages += 1
            result.submitted += page.count
            result.read += counts.0
            result.acked += counts.1
        }
        return result
    }

    #if os(Linux)
    private static func peakResidentMemoryKiB() throws -> Int {
        let status = try String(contentsOfFile: "/proc/self/status", encoding: .utf8)
        guard let line = status.split(separator: "\n").first(where: { $0.hasPrefix("VmHWM:") }),
              let value = line.split(whereSeparator: \.isWhitespace).dropFirst().first,
              let peakKiB = Int(value)
        else {
            throw CheckError.missingVmHWM
        }
        return peakKiB
    }
    #endif
}

private struct KindRecord: Decodable {
    let kind: String
    let metricId: String?
}

private struct MetricSpool {
    let url: URL
    let handle: FileHandle
}

private struct MetricWork: Sendable {
    let ordinal: Int
    let metric: MetricID
    let url: URL
}

private struct MetricWorkResult: Sendable {
    var pages = 0
    var submitted = 0
    var read = 0
    var acked = 0
}

private struct CorpusSliceSource: SampleSource {
    let samples: [SampleRecord]
    let sequence: Int

    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        if afterAnchor != nil {
            return SamplePage(
                samples: [],
                tombstones: [],
                metric: metric,
                anchorBlob: afterAnchor ?? Data(),
                observedThrough: Date(timeIntervalSince1970: 1_735_689_600)
            )
        }
        return SamplePage(
            samples: samples,
            tombstones: [],
            metric: metric,
            anchorBlob: withUnsafeBytes(of: UInt64(sequence).bigEndian) { Data($0) },
            observedThrough: Date(timeIntervalSince1970: 1_735_689_600)
        )
    }
}

private struct AuditingSink: DestinationSink {
    let expectedQuantityRecords: Int
    let exerciseSidecars: Bool

    func send(fileHandle: String, idempotencyKey: BatchID) async throws -> DeliveryReceipt {
        let payloadURL = URL(fileURLWithPath: fileHandle)
        let data = try Data(contentsOf: payloadURL)
        let text = String(decoding: data, as: UTF8.self)
        let quantityRecords = text.split(whereSeparator: \.isNewline)
            .filter { $0.contains("\"kind\":\"sample.quantity\"") }
            .count
        guard quantityRecords == expectedQuantityRecords else {
            throw CheckError.payloadQuantityMismatch(
                expected: expectedQuantityRecords,
                emitted: quantityRecords
            )
        }
        if exerciseSidecars {
            try NativeSidecars.write(fromNDJSON: data, beside: payloadURL)
            let encodings = payloadURL.deletingPathExtension().appendingPathExtension("encodings")
            let names = Set(
                try FileManager.default.contentsOfDirectory(atPath: encodings.path)
            )
            let required = Set([
                "_meta.json",
                "batch.hae.json",
                "batch.json",
                "batch.pretty.json",
            ])
            guard required.isSubset(of: names),
                  names.contains(where: { $0.hasSuffix(".csv") })
            else {
                throw CheckError.missingSidecars(names.sorted())
            }
        }
        return DeliveryReceipt(
            batchID: idempotencyKey,
            accepted: NativeWire.countRecords(in: text),
            statusOnly: false
        )
    }
}

private enum CheckError: Error, CustomStringConvertible {
    case invalidProvenance
    case invalidRecord(line: Int)
    case unaccountedKind(kind: String, line: Int)
    case declaredCountMismatch(declared: Int, accounted: Int)
    case skippedExportable(parsed: Int, submitted: Int)
    case payloadQuantityMismatch(expected: Int, emitted: Int)
    case missingSidecars([String])
    case invalidPageSize(maximum: Int)
    case noSamples
    case outcome(metric: String, outcome: String)
    case ackEvidence(String)
    case missingJournal
    case countMismatch(read: Int, acked: Int)
    case missingVmHWM
    case memoryExceeded(peakKiB: Int, limitKiB: Int)

    var description: String {
        switch self {
        case .invalidProvenance:
            "stdin is not a synthetic T0/T1/T2 corpusgen stream"
        case .invalidRecord(let line):
            "stdin line \(line) is not a kind-bearing JSON record"
        case .unaccountedKind(let kind, let line):
            "stdin line \(line) has unaccounted record kind \(kind)"
        case .declaredCountMismatch(let declared, let accounted):
            "header declares \(declared) records but \(accounted) data records were accounted"
        case .skippedExportable(let parsed, let submitted):
            "parsed \(parsed) exportable records but submitted \(submitted) to ExportRun"
        case .payloadQuantityMismatch(let expected, let emitted):
            "ExportRun payload contains \(emitted) quantity records, expected \(expected)"
        case .missingSidecars(let names):
            "bounded page did not produce every sidecar format: \(names)"
        case .invalidPageSize(let maximum):
            "--page-size must be an integer from 1 through \(maximum)"
        case .noSamples:
            "corpus stream contained no quantity samples"
        case .outcome(let metric, let outcome):
            "ExportRun for \(metric) closed with \(outcome), expected success"
        case .ackEvidence(let evidence):
            "ExportRun acknowledgement evidence was \(evidence), expected receiptFull"
        case .missingJournal:
            "ExportRun did not record a journal event"
        case .countMismatch(let read, let acked):
            "sample count mismatch: read=\(read) acknowledged=\(acked)"
        case .missingVmHWM:
            "could not read VmHWM from /proc/self/status"
        case .memoryExceeded(let peakKiB, let limitKiB):
            "peak resident memory \(peakKiB) KiB exceeded \(limitKiB) KiB ceiling"
        }
    }
}
