// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

private let schemaVersion = 1
private let defaultRegressionLimit = 20.0
private let sqliteOK: Int32 = 0
private let sqliteRow: Int32 = 100
private let sqliteDone: Int32 = 101
private let sqliteOpenReadOnly: Int32 = 0x0000_0001
private let sqliteOpenReadWrite: Int32 = 0x0000_0002
private let sqliteOpenCreate: Int32 = 0x0000_0004

// Keep this executable independent of product targets while still timing a
// real SQLite open and indexed read. Package.swift links the system library.
@_silgen_name("sqlite3_open_v2")
private func sqliteOpen(
    _ filename: UnsafePointer<CChar>,
    _ database: UnsafeMutablePointer<OpaquePointer?>,
    _ flags: Int32,
    _ vfs: UnsafePointer<CChar>?
) -> Int32

@_silgen_name("sqlite3_close")
private func sqliteClose(_ database: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_prepare_v2")
private func sqlitePrepare(
    _ database: OpaquePointer?,
    _ sql: UnsafePointer<CChar>,
    _ bytes: Int32,
    _ statement: UnsafeMutablePointer<OpaquePointer?>,
    _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?
) -> Int32

@_silgen_name("sqlite3_step")
private func sqliteStep(_ statement: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_finalize")
private func sqliteFinalize(_ statement: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_column_int64")
private func sqliteColumnInt64(_ statement: OpaquePointer?, _ column: Int32) -> Int64

@_silgen_name("sqlite3_column_text")
private func sqliteColumnText(
    _ statement: OpaquePointer?,
    _ column: Int32
) -> UnsafePointer<UInt8>?

private struct Environment: Codable {
    let platform: String
    let operatingSystem: String
    let architecture: String
    let swiftVersion: String
}

private struct Workload: Codable {
    let iterations: Int
    let operations: [String]
    let excludedOperations: [String]
}

private struct Summary: Codable {
    let sampleCount: Int
    let p50Milliseconds: Double
    let p90Milliseconds: Double
    let maxMilliseconds: Double
}

private struct BenchmarkReport: Codable {
    let schemaVersion: Int
    let reportKind: String
    let requirementIDs: [String]
    let generatedAt: String
    let environment: Environment
    let workload: Workload
    let samplesMilliseconds: [Double]
    let summary: Summary
    let limitations: [String]
}

private struct ComparisonReport: Codable {
    let schemaVersion: Int
    let reportKind: String
    let baselinePath: String
    let candidatePath: String
    let metric: String
    let baseline: Double
    let candidate: Double
    let changePercent: Double
    let failureThresholdPercent: Double
    let passed: Bool
}

private enum HarnessError: Error, CustomStringConvertible {
    case usage(String)
    case operation(String)

    var description: String {
        switch self {
        case .usage(let message), .operation(let message):
            return message
        }
    }
}

@main
struct M0Harness {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("m0harness: \(error)\n".utf8))
            exit(2)
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            throw HarnessError.usage(usage)
        }
        let options = try parseOptions(Array(arguments.dropFirst()))
        switch command {
        case "benchmark-launch":
            try benchmarkLaunch(options)
        case "compare":
            try compare(options)
        case "verify":
            try verifyComparator()
        case "_probe":
            try probe(options)
        case "help", "--help", "-h":
            print(usage)
        default:
            throw HarnessError.usage("unknown command \(command)\n\n\(usage)")
        }
    }

    private static func benchmarkLaunch(_ options: [String: String]) throws {
        let iterations = try integerOption("iterations", options: options, default: 100)
        guard iterations >= 1 else {
            throw HarnessError.usage("--iterations must be at least 1")
        }
        guard let output = options["output"] else {
            throw HarnessError.usage("benchmark-launch requires --output PATH")
        }

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-m0-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let database = temporary.appendingPathComponent("launch.sqlite").path
        try prepareDatabase(at: database)

        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        var samples: [Double] = []
        for _ in 0..<iterations {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["_probe", "--database", database]
            process.standardOutput = pipe
            process.standardError = FileHandle.standardError
            let started = ContinuousClock.now
            try process.run()
            let data = try pipe.fileHandleForReading.read(upToCount: 64) ?? Data()
            let elapsed = started.duration(to: .now).milliseconds
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let text = String(data: data, encoding: .utf8),
                  text.trimmingCharacters(in: .whitespacesAndNewlines) == "query-ready"
            else {
                throw HarnessError.operation("cold-launch probe failed")
            }
            samples.append(elapsed)
        }

        let report = BenchmarkReport(
            schemaVersion: 1,
            reportKind: "automated-host-permitted-launch-proxy",
            requirementIDs: ["R-73", "R-91"],
            generatedAt: iso8601(Date()),
            environment: environment(),
            workload: Workload(
                iterations: iterations,
                operations: [
                    "cold process start",
                    "SQLite open",
                    "schemaVersion integer comparison",
                    "indexed anchor-row read",
                    "query-token construction",
                ],
                excludedOperations: [
                    "HKHealthStore instantiation",
                    "HealthKit query dispatch",
                    "iOS background scheduling",
                ]
            ),
            samplesMilliseconds: samples,
            summary: summarize(samples),
            limitations: [
                "This host proxy is an automated regression signal, not R-73 acceptance evidence.",
                "R-73 still requires at least 100 cold background launches on REF-B and REF-C.",
            ]
        )
        try writeJSON(report, to: output)
        print("wrote \(iterations) launch samples to \(output)")
    }

    private static func probe(_ options: [String: String]) throws {
        guard let path = options["database"] else {
            throw HarnessError.usage("_probe requires --database PATH")
        }
        var database: OpaquePointer?
        guard sqliteOpen(path, &database, sqliteOpenReadOnly, nil) == sqliteOK,
              let database
        else {
            throw HarnessError.operation("could not open launch database")
        }
        defer { _ = sqliteClose(database) }

        guard scalarInt(database, sql: "SELECT value FROM metadata WHERE key = 'schemaVersion'") == schemaVersion else {
            throw HarnessError.operation("schema migration is required; launch must return")
        }
        var statement: OpaquePointer?
        guard sqlitePrepare(
            database,
            "SELECT anchor FROM anchors WHERE type_id IN ('heart_rate', 'step_count') ORDER BY type_id",
            -1,
            &statement,
            nil
        ) == sqliteOK else {
            throw HarnessError.operation("could not prepare anchor query")
        }
        defer { _ = sqliteFinalize(statement) }
        var anchors: [String] = []
        while sqliteStep(statement) == sqliteRow {
            if let text = sqliteColumnText(statement, 0) {
                anchors.append(String(cString: text))
            }
        }
        // This value-only token stands in for query construction. No forbidden
        // destination, network, UI, keychain, catalogue-decoding, or telemetry
        // subsystem is imported or initialized by this executable.
        let queryToken = anchors.joined(separator: ":")
        guard !queryToken.isEmpty else {
            throw HarnessError.operation("anchor slice was empty")
        }
        FileHandle.standardOutput.write(Data("query-ready\n".utf8))
    }

    private static func compare(_ options: [String: String]) throws {
        guard let baselinePath = options["baseline"],
              let candidatePath = options["candidate"]
        else {
            throw HarnessError.usage("compare requires --baseline PATH --candidate PATH")
        }
        let output = options["output"]
        let limit = try doubleOption(
            "failure-threshold-percent",
            options: options,
            default: defaultRegressionLimit
        )
        guard limit >= 0 else {
            throw HarnessError.usage("--failure-threshold-percent cannot be negative")
        }
        let decoder = JSONDecoder()
        let baseline = try decoder.decode(
            BenchmarkReport.self,
            from: Data(contentsOf: URL(fileURLWithPath: baselinePath))
        )
        let candidate = try decoder.decode(
            BenchmarkReport.self,
            from: Data(contentsOf: URL(fileURLWithPath: candidatePath))
        )
        guard baseline.reportKind == candidate.reportKind else {
            throw HarnessError.operation("report kinds differ")
        }
        guard baseline.summary.sampleCount > 0, candidate.summary.sampleCount > 0,
              baseline.summary.p90Milliseconds > 0
        else {
            throw HarnessError.operation("reports require non-empty, positive timing samples")
        }
        let change = (
            candidate.summary.p90Milliseconds / baseline.summary.p90Milliseconds - 1
        ) * 100
        let comparison = ComparisonReport(
            schemaVersion: 1,
            reportKind: "performance-regression-comparison",
            baselinePath: baselinePath,
            candidatePath: candidatePath,
            metric: "p90Milliseconds",
            baseline: baseline.summary.p90Milliseconds,
            candidate: candidate.summary.p90Milliseconds,
            changePercent: change,
            failureThresholdPercent: limit,
            passed: change <= limit
        )
        if let output {
            try writeJSON(comparison, to: output)
        } else {
            let data = try encodedJSON(comparison)
            FileHandle.standardOutput.write(data)
        }
        guard comparison.passed else {
            FileHandle.standardError.write(
                Data(
                    String(
                        format: "p90 regression %.2f%% exceeds %.2f%%\n",
                        change,
                        limit
                    ).utf8
                )
            )
            exit(1)
        }
    }

    private static func verifyComparator() throws {
        let baseline = 100.0
        let exactlyAtLimit = (120.0 / baseline - 1) * 100
        let overLimit = (120.01 / baseline - 1) * 100
        guard exactlyAtLimit <= defaultRegressionLimit, overLimit > defaultRegressionLimit,
              summarize([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]).p90Milliseconds == 9
        else {
            throw HarnessError.operation("comparison boundary or percentile verification failed")
        }
        print("m0harness comparator: 20% passes; >20% fails; nearest-rank p90 verified")
    }

    private static func prepareDatabase(at path: String) throws {
        var database: OpaquePointer?
        guard sqliteOpen(
            path,
            &database,
            sqliteOpenCreate | sqliteOpenReadWrite,
            nil
        ) == sqliteOK, let database
        else {
            throw HarnessError.operation("could not create launch database")
        }
        defer { _ = sqliteClose(database) }
        for sql in [
            "PRAGMA journal_mode=WAL",
            "CREATE TABLE metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL)",
            "INSERT INTO metadata VALUES ('schemaVersion', \(schemaVersion))",
            "CREATE TABLE anchors (type_id TEXT PRIMARY KEY, anchor TEXT NOT NULL)",
            "INSERT INTO anchors VALUES ('heart_rate', 'anchor-a')",
            "INSERT INTO anchors VALUES ('step_count', 'anchor-b')",
        ] {
            try execute(database, sql: sql)
        }
    }

    private static func scalarInt(_ database: OpaquePointer, sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlitePrepare(database, sql, -1, &statement, nil) == sqliteOK,
              let statement
        else {
            return -1
        }
        defer { _ = sqliteFinalize(statement) }
        guard sqliteStep(statement) == sqliteRow else { return -1 }
        return Int(sqliteColumnInt64(statement, 0))
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        guard sqlitePrepare(database, sql, -1, &statement, nil) == sqliteOK,
              let statement
        else {
            throw HarnessError.operation("could not prepare launch fixture SQL")
        }
        defer { _ = sqliteFinalize(statement) }
        guard sqliteStep(statement) == sqliteDone || sql.hasPrefix("PRAGMA") else {
            throw HarnessError.operation("could not seed launch database")
        }
    }

    private static func summarize(_ samples: [Double]) -> Summary {
        let ordered = samples.sorted()
        return Summary(
            sampleCount: ordered.count,
            p50Milliseconds: percentile(ordered, percentile: 0.50),
            p90Milliseconds: percentile(ordered, percentile: 0.90),
            maxMilliseconds: ordered.last ?? 0
        )
    }

    private static func percentile(_ ordered: [Double], percentile: Double) -> Double {
        guard !ordered.isEmpty else { return 0 }
        let rank = max(1, Int(ceil(percentile * Double(ordered.count))))
        return ordered[min(rank - 1, ordered.count - 1)]
    }

    private static func parseOptions(_ arguments: [String]) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw HarnessError.usage("expected --name value, got \(key)")
            }
            result[String(key.dropFirst(2))] = arguments[index + 1]
            index += 2
        }
        return result
    }

    private static func integerOption(
        _ name: String,
        options: [String: String],
        default defaultValue: Int
    ) throws -> Int {
        guard let raw = options[name] else { return defaultValue }
        guard let value = Int(raw) else {
            throw HarnessError.usage("--\(name) must be an integer")
        }
        return value
    }

    private static func doubleOption(
        _ name: String,
        options: [String: String],
        default defaultValue: Double
    ) throws -> Double {
        guard let raw = options[name] else { return defaultValue }
        guard let value = Double(raw), value.isFinite else {
            throw HarnessError.usage("--\(name) must be a finite number")
        }
        return value
    }

    private static func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encodedJSON(value).write(to: url, options: .atomic)
    }

    private static func encodedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    private static func environment() -> Environment {
        #if os(macOS)
        let platform = "macOS"
        #elseif os(Linux)
        let platform = "Linux"
        #else
        let platform = "other"
        #endif
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return Environment(
            platform: platform,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            swiftVersion: swiftVersionString()
        )
    }

    private static func swiftVersionString() -> String {
        #if swift(>=6.3)
        "6.3+"
        #elseif swift(>=6.2)
        "6.2"
        #else
        "older-than-6.2"
        #endif
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static let usage = """
    Usage:
      m0harness benchmark-launch --iterations 100 --output REPORT.json
      m0harness compare --baseline BASELINE.json --candidate REPORT.json [--output RESULT.json] [--failure-threshold-percent 20]
      m0harness verify

    benchmark-launch is a host-only regression proxy for R-73's permitted
    operations. It is not a substitute for physical-device R-70/R-71/R-73 runs.
    """
}

private extension Duration {
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000
            + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}
