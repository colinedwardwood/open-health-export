// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import EnginePorts
import Foundation
import MetricCatalog
import SinkLocalFile
import TestSupport
import Testing
import WireFormat

@Test func demoWireFieldIsOmittedUnlessRequested() throws {
    var envelope = testEnvelope()
    let plain = try NativeWire.encode(heartSample("00000000-0000-4000-8000-0000000000d1"), envelope: envelope)
    #expect(!plain.contains("\"demo\""))
    envelope.demo = true
    let marked = try NativeWire.encode(heartSample("00000000-0000-4000-8000-0000000000d1"), envelope: envelope)
    #expect(marked.contains("\"demo\":true"))
}

@Test func demoExportGateRequiresTheExactDestinationName() throws {
    #expect(throws: DemoExportError.confirmationRequired) {
        try DemoExportGate.confirmSending(to: "local-file", typed: "  ")
    }
    #expect(throws: DemoExportError.confirmationMismatch) {
        try DemoExportGate.confirmSending(to: "local-file", typed: "home-assistant")
    }
    try DemoExportGate.confirmSending(to: "local-file", typed: "local-file")
}

@Test func demoSourceCoversEveryCatalogueMetricAndPrefixesFiles() async throws {
    try DemoExportGate.confirmSending(to: "local-file", typed: "local-file")
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-demo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    let source = DemoSampleSource(seed: 1, samplesPerMetric: 2)
    var envelope = testEnvelope()
    envelope.demo = true
    var exported = Set<MetricID>()
    for declaration in MetricCatalog.all {
        let store = MemoryStateStore()
        let run = ExportRun(
            source: source,
            destination: .testing(LocalFileSink(directory: dest)),
            store: store,
            metric: declaration.id,
            scratchDirectory: dest.appendingPathComponent("scratch-\(declaration.id.rawValue)"),
            destinationName: "local-file",
            envelope: envelope
        )
        let outcome = try await run.run()
        #expect(outcome.kind == .success)
        exported.insert(declaration.id)
        #expect(try store.transaction.loadJournal().last?.detail == "demo")
        #expect(try store.transaction.loadLedger().last?.outcomeKind == "run:success:demo")
    }
    #expect(exported == Set(MetricCatalog.all.map(\.id)))
    let files = try FileManager.default.contentsOfDirectory(atPath: dest.path)
        .filter { $0.hasSuffix(".ndjson") }
    #expect(files.allSatisfy { $0.hasPrefix(NativeWire.demoFilePrefix) })
    #expect(files.count == MetricCatalog.all.count)
    let sample = try Data(contentsOf: dest.appendingPathComponent(files[0]))
    #expect(NativeWire.payloadIsDemo(sample))
}

@Test func demoCorpusMatchesTheShippedGenerator() {
    let declaration = MetricCatalog.heartRate
    let record = DemoCorpus.sample(at: 0, seed: 1, declaration: declaration)
    #expect(record.metric == declaration.id)
    #expect(record.value.isFinite)
    #expect(record.start.hasSuffix("Z"))
}

@Test func tierZeroCorpusCarriesSixSyntheticSourceIdentities() {
    let sources = (0 ..< 200).compactMap { index in
        let declaration = MetricCatalog.all[index % MetricCatalog.all.count]
        return DemoCorpus.sample(at: index, seed: 1, declaration: declaration)
            .source?.bundleIdentifier
    }
    #expect(Set(sources).count == 6)
    #expect(sources.allSatisfy { $0.contains("synthetic") || $0 == "com.apple.Health" })
}

@Test func syntheticCorpusTierScaleContractIsFrozen() {
    #expect(SyntheticCorpusTier.t0.defaultCount == 200)
    #expect(SyntheticCorpusTier.t1.defaultCount == 10_000_000)
    #expect(SyntheticCorpusTier.t2.defaultCount == 50_000_000)
    let generatedTypes = Set(
        MetricCatalog.all.map(\.wireId)
            + DemoCorpus.categoryTypes.map(\.metricID)
            + ["blood_pressure", "workout", "state_of_mind",
               "electrocardiogram", "audiogram", "medication_dose"]
    )
    #expect(generatedTypes.count >= 60)
}
