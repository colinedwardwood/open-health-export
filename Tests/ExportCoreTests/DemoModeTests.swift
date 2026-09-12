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

@Test func tierTwoCorpusSpansFifteenYearsWithTwentyMillionSingleTypeRecords() {
    let tier = SyntheticCorpusTier.t2
    #expect(tier.dateSpanYears == 15)
    #expect(tier.concentratedMetricRecordCount == 20_000_000)
    for index in [0, 1, 1_000_000, 19_999_999] {
        #expect(DemoCorpus.isConcentratedMetricRecord(at: index, tier: tier))
        #expect(
            DemoCorpus.declaration(at: index, tier: tier).id == MetricCatalog.heartRate.id
        )
    }
    #expect(!DemoCorpus.isConcentratedMetricRecord(at: 20_000_000, tier: tier))

    let years = (0 ..< tier.dateSpanYears).map { offset in
        let index = offset * 12 * 28
        let declaration = DemoCorpus.declaration(at: index, tier: tier)
        return DemoCorpus.sample(
            at: index,
            seed: 1,
            declaration: declaration,
            tier: tier
        ).start.prefix(4)
    }
    #expect(years.first == "2010")
    #expect(years.last == "2024")
    #expect(Set(years).count == 15)
}

@Test func volumeCorpusPairsECGParentsWithVoltageSeries() throws {
    let accounted = NativeWire.volumeStructuralKinds.union(["sample.quantity"])
    var kinds = Set<String>()
    for index in 0 ..< 200 {
        kinds.insert(try volumeKind(at: index, tier: .t0))
    }
    #expect(kinds.isSubset(of: accounted))
    #expect(kinds.contains("sample.ecg"))
    #expect(kinds.contains("series.ecgVoltage"))

    let parent = try volumeObject(at: 4, tier: .t0)
    let chunk = try volumeObject(at: 104, tier: .t0)
    #expect(parent["kind"] as? String == "sample.ecg")
    #expect(chunk["kind"] as? String == "series.ecgVoltage")
    #expect(chunk["parentUuid"] as? String == parent["uuid"] as? String)

    let t2Parent = try volumeKind(at: 20_000_004, tier: .t2)
    let t2Chunk = try volumeKind(at: 20_000_104, tier: .t2)
    #expect(t2Parent == "sample.ecg")
    #expect(t2Chunk == "series.ecgVoltage")
}

private func volumeKind(at index: Int, tier: SyntheticCorpusTier) throws -> String {
    try #require(try volumeObject(at: index, tier: tier)["kind"] as? String)
}

private func volumeObject(at index: Int, tier: SyntheticCorpusTier) throws -> [String: Any] {
    let declaration = DemoCorpus.declaration(at: index, tier: tier)
    let sample = DemoCorpus.sample(
        at: index,
        seed: 1,
        declaration: declaration,
        tier: tier
    )
    let envelope = WireEnvelope(
        exporterId: "00000000-0000-4000-8000-000000000082",
        seq: index + 1,
        emittedAt: sample.observedAt,
        observedAt: sample.observedAt
    )
    let line = try DemoCorpus.encodeRecord(
        index: index,
        sample: sample,
        envelope: envelope,
        tier: tier,
        seed: 1
    )
    return try #require(
        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    )
}
