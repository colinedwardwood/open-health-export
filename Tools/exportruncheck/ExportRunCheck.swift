import CoreDomain
import CoreTemporal
import CorrectnessEngine
import EnginePorts
import Foundation
import MetricCatalog
import SinkLocalFile
import TestSupport
import WireFormat

private let memoryLimitMiB = 100

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
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let inputLines = try validateT1Provenance(input)
        let samples = try NativeSidecars.quantitySamples(fromNDJSON: input)
            .filter { $0.metric == MetricCatalog.heartRate.id }
        guard !samples.isEmpty else {
            throw CheckError.noHeartRateSamples
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-exportruncheck-\(UUID().uuidString)")
        let destination = root.appendingPathComponent("destination")
        let scratch = root.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = MemoryStateStore()
        let run = ExportRun(
            source: CorpusSliceSource(samples: samples),
            destination: .testing(LocalFileSink(directory: destination)),
            store: store,
            metric: MetricCatalog.heartRate.id,
            scratchDirectory: scratch,
            envelope: WireEnvelope(
                exporterId: "00000000-0000-4000-8000-000000000024",
                seq: 1,
                emittedAt: "2025-01-01T00:00:00Z",
                observedAt: "2025-01-01T00:00:00Z"
            ),
            clock: FrozenClock(instant: Date(timeIntervalSince1970: 1_735_689_600)),
            trigger: .bgProcessing
        )
        let outcome = try await run.run()
        guard outcome.kind == .success else {
            throw CheckError.outcome(outcome.kind.rawValue)
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
            "exportruncheck outcome=\(outcome.kind.rawValue)"
                + " samples_read=\(event.samplesRead)"
                + " samples_acked=\(event.samplesAcked)"
                + " corpus_samples=\(samples.count)"
                + " input_lines=\(inputLines)"
                + " peak_rss_mib=\(memoryResult)"
                + " limit_mib=\(memoryLimitMiB)"
        )
    }

    private static func validateT1Provenance(_ data: Data) throws -> Int {
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        guard let first = lines.first,
              let header = try JSONSerialization.jsonObject(with: Data(first)) as? [String: Any],
              header["kind"] as? String == "batch.header",
              header["synthetic"] as? Bool == true,
              header["tier"] as? String == "T1"
        else {
            throw CheckError.invalidProvenance
        }
        return lines.count
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

private struct CorpusSliceSource: SampleSource {
    let samples: [SampleRecord]

    func page(metric: MetricID, afterAnchor: Data?) async throws -> SamplePage {
        SamplePage(
            samples: samples,
            tombstones: [],
            metric: metric,
            anchorBlob: Data([0x24]),
            observedThrough: Date(timeIntervalSince1970: 1_735_689_600)
        )
    }
}

private enum CheckError: Error, CustomStringConvertible {
    case invalidProvenance
    case noHeartRateSamples
    case outcome(String)
    case ackEvidence(String)
    case missingJournal
    case countMismatch(read: Int, acked: Int)
    case missingVmHWM
    case memoryExceeded(peakKiB: Int, limitKiB: Int)

    var description: String {
        switch self {
        case .invalidProvenance:
            "stdin is not a synthetic T1 corpusgen stream"
        case .noHeartRateSamples:
            "T1 corpus slice contained no heart-rate quantity samples"
        case .outcome(let outcome):
            "ExportRun closed with \(outcome), expected success"
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
