import CoreDomain
import DiagnosticBundle
import EnginePorts
import Foundation
import MetricCatalog
import Redaction
import Testing
import WireFormat

@Test func redactionSinkRegistryMatchesTheCommittedCanaryList() {
    #expect(RedactionSink.allCases.map(\.rawValue).sorted() == CanarySinkRegistry.expected)
}

@Test func diagnosticBundleCanaryStaysGreen() throws {
    let canary = RedactionCanary.tokens.joined(separator: " ")
    let data = try BundleAssembler(maxRuns: 2).assemble(
        header: DiagnosticHeader(
            appVersion: "0.1.0",
            osVersion: "test",
            deviceModel: "test-device",
            localeIdentifier: "en_US",
            utcOffsetMinutes: 0,
            generatedAt: "2024-01-01T00:00:00Z"
        ),
        events: [
            RunEvent(
                runID: RunID(rawValue: canary),
                outcomeKind: "failed",
                detail: canary,
                samplesRead: 1
            )
        ]
    )
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(RedactionCanary.isClean(text), "production assembler leaked \(RedactionCanary.leaks(in: text))")
}

@Test(arguments: LeakMutant.allCases)
func leakMutantTurnsTheCanaryRed(_ mutant: LeakMutant) {
    let leaked = mutant.emit()
    #expect(
        !RedactionCanary.leaks(in: leaked).isEmpty,
        "the canary test no longer detects \(mutant.rawValue)"
    )
}

enum LeakMutant: String, CaseIterable {
    case sampleValueInterpolation
    case verbatimDetail
    case hostnameInLog
    case undeclaredAttribute
    case localizedError

    func emit() -> String {
        let event = RunEvent(
            runID: RunID(rawValue: "run"),
            outcomeKind: "failed",
            detail: RedactionCanary.tokens.joined(separator: " ")
        )
        switch self {
        case .sampleValueInterpolation:
            return "hr=\(RedactionCanary.sampleValue) bpm"
        case .verbatimDetail:
            return event.detail
        case .hostnameInLog:
            return "resolved \(RedactionCanary.hostname)"
        case .undeclaredAttribute:
            return "{\"source\":\"\(RedactionCanary.sourceName)\"}"
        case .localizedError:
            return RedactionCanary.secret
        }
    }
}

@Test func dataBrowserNeverClaimsDenialAndDemoFillsEveryRow() {
    let empty = DataBrowser.rows(latest: [:], exported: [MetricCatalog.heartRate.id])
    #expect(empty.count == MetricCatalog.selectable.count)
    #expect(empty.allSatisfy { $0.subtitle == DataBrowser.noDataCopy })
    #expect(!empty.contains { $0.subtitle.lowercased().contains("denied") })
    #expect(empty.first { $0.metric == MetricCatalog.heartRate.id }?.exported == true)

    let latest = Dictionary(uniqueKeysWithValues: MetricCatalog.selectable.enumerated().map { index, declaration in
        (declaration.id, DemoCorpus.sample(at: index, seed: 1, declaration: declaration))
    })
    let filled = DataBrowser.rows(latest: latest, search: "stepCount")
    #expect(filled.count == 1)
    #expect(filled[0].metric == MetricCatalog.stepCount.id)
    #expect(filled[0].hasData)
    #expect(filled[0].subtitle != DataBrowser.noDataCopy)

    let sensitive = DataBrowser.rows(latest: latest).filter(\.sensitive)
    #expect(!sensitive.isEmpty)
    #expect(DataBrowser.rows(latest: [:], onlyWithData: true).isEmpty)
}

@Test func healthAuthorizationIsTiedToEnabledTypesNotTheFullCatalogue() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let harness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessView.swift"),
        encoding: .utf8
    )
    #expect(harness.contains("metrics: HarnessExport.selectedMetrics()"))
    #expect(harness.contains("metrics: adding.sorted"))
    #expect(!harness.contains("requestReadAccess(\n                    metrics: MetricCatalog.all"))
    #expect(!harness.contains("requestReadAccess(metrics: MetricCatalog.all"))
    #expect(!harness.contains("requestReadAccess(metrics: MetricCatalog.selectable"))
}
