// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import DestinationTrust
import DiagnosticBundle
import EnginePorts
import Foundation
import MetricCatalog
import Redaction
import SinkLocalFile
import StorageSQLite
import Testing
import TestSupport
import WireFormat

@Test func redactionSinkRegistryMatchesTheCommittedCanaryList() {
    #expect(RedactionSink.allCases.map(\.rawValue).sorted() == CanarySinkRegistry.expected)
}

/// SEC-27: a notification is Lock Screen content, so it carries an outcome and nothing
/// else — no health value, no type name, no destination address. Enumerating `Kind`
/// means a notice added later cannot ship unchecked, and feeding the renderer addresses
/// it should never print proves the copy cannot be talked into leaking one.
@Test func p11NotificationBodiesNameNoAddressAndNoHealthType() {
    let addresses = [
        "ha.example.com",
        "https://ha.example.com:8123",
        "192.168.1.50",
        "fe80::1",
        "homeassistant.local:1883",
        "/var/mobile/Containers/archive",
    ]
    for kind in UserNotice.Kind.allCases {
        for address in addresses {
            let rendered = NoticeCopy.render(
                UserNotice(
                    kind: kind,
                    destination: address,
                    fingerprint: "AA:BB:CC",
                    previousFingerprint: "DD:EE:FF"
                )
            )
            let text = rendered.title + " " + rendered.body
            #expect(!text.contains(address), "\(kind) printed \(address): \(text)")
            // Fragments matter too: a split address is still an address.
            for fragment in ["example.com", "192.168", "fe80", "homeassistant", "/var/"] {
                #expect(!text.contains(fragment), "\(kind) printed \(fragment): \(text)")
            }
        }

        let labelled = NoticeCopy.render(
            UserNotice(kind: kind, destination: "Home Assistant", fingerprint: "AA:BB")
        )
        let text = labelled.title + " " + labelled.body
        #expect(!labelled.title.isEmpty)
        #expect(!labelled.body.isEmpty)
        // A notice may say an export paused; it may not say which type paused.
        for declaration in MetricCatalog.selectable {
            #expect(!text.contains(declaration.wireId), "\(kind) named \(declaration.wireId)")
            #expect(
                !text.contains(declaration.hkIdentifier),
                "\(kind) named \(declaration.hkIdentifier)"
            )
        }
    }
}

/// SEC-27 again, from the other side: a label a person chose still reads back, or the
/// notification stops being useful.
@Test func notificationBodiesKeepAPlainDestinationLabel() {
    let rendered = NoticeCopy.render(
        UserNotice(kind: .destinationEnabled, destination: "Archive folder")
    )
    #expect(rendered.body.contains("Archive folder"))
}

@Test func p11RedactionCanaryStaysGreenInDiagnosticProjection() throws {
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

@Test func p12CheckpointAndJournalOmitSampleCanaries() async throws {
    let metric = MetricCatalog.heartRate.id
    var sample = heartSample("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa51")
    sample.value = 72.123456
    sample.source = SampleSourceIdentity(name: RedactionCanary.sourceName)
    sample.device = SampleDevice(name: RedactionCanary.hostname)
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-p12-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let database = root.appendingPathComponent("state.sqlite")
    let store = try SQLiteStateStore(path: database.path)
    let outcome = try await ExportRun(
        source: FixtureSource(
            pages: [
                SamplePage(
                    samples: [sample],
                    tombstones: [],
                    metric: metric,
                    anchorBlob: Data("hk-anchor".utf8),
                    observedThrough: Date(timeIntervalSince1970: 0)
                )
            ]
        ),
        destination: .testing(LocalFileSink(directory: destination)),
        store: store,
        metric: metric,
        scratchDirectory: root.appendingPathComponent("scratch"),
        envelope: testEnvelope()
    ).run()
    #expect(outcome.kind == .success)

    let cursor = try #require(try await store.transact { try $0.loadCursor(metric: metric) })
    let anchorText = String(decoding: cursor.anchorBlob, as: UTF8.self)
    #expect(RedactionCanary.isClean(anchorText))
    #expect(!anchorText.contains(sample.key.uuid))

    var sqliteBytes = Data()
    for suffix in ["", "-wal", "-shm"] {
        let url = URL(fileURLWithPath: database.path + suffix)
        if FileManager.default.fileExists(atPath: url.path) {
            sqliteBytes.append(try Data(contentsOf: url))
        }
    }
    let sqliteText = String(decoding: sqliteBytes, as: UTF8.self)
    #expect(
        RedactionCanary.isClean(sqliteText),
        "managed SQLite leaked \(RedactionCanary.leaks(in: sqliteText))"
    )

    let journal = try await store.transact { try $0.loadJournal() }
    #expect(!journal.isEmpty)
    for event in journal {
        #expect(RedactionCanary.isClean(event.detail))
        #expect(RedactionCanary.isClean(event.outcomeKind))
        #expect(RedactionCanary.isClean(event.errorClass ?? ""))
    }
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
    #expect(empty.allSatisfy { row in
        if MetricCatalog.isCharacteristic(row.metric) {
            row.subtitle == DataBrowser.characteristicCopy
        } else {
            row.subtitle == DataBrowser.noDataCopy
        }
    })
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
    #expect(harness.contains("let metrics = try await HarnessExport.selectedMetrics()"))
    #expect(harness.contains("HarnessExport.destinationScope(destinationID)"))
    #expect(harness.contains("metrics: adding.sorted"))
    #expect(!harness.contains("requestReadAccess(\n                    metrics: MetricCatalog.all"))
    #expect(!harness.contains("requestReadAccess(metrics: MetricCatalog.all"))
    #expect(!harness.contains("requestReadAccess(metrics: MetricCatalog.selectable"))
}

@Test func sec16AppRoutesEveryHealthDestinationThroughItsOwnScope() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let exportHarness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessExport.swift"),
        encoding: .utf8
    )
    let viewHarness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessView.swift"),
        encoding: .utf8
    )

    for destinationID in ["local-file", "https", "mqtt", "companion"] {
        #expect(exportHarness.contains("destinationScope(\"\(destinationID)\")"))
        #expect(exportHarness.contains(
            "requestScopeAuthorizationIfConfigured(\"\(destinationID)\")"
        ))
    }
    #expect(exportHarness.contains("guard isDestinationEnabled($1.destinationID)"))
    #expect(exportHarness.contains("window: HealthKitQueryWindow(scope: scope)"))
    #expect(exportHarness.contains("try ExportScopeGate.requireConfigured(scope)"))
    #expect(exportHarness.contains(
        #"try ExportScopeGate.requireConfigured(try await destinationScope("https"))"#
    ))
    #expect(exportHarness.contains(
        #"try ExportScopeGate.requireConfigured(try await destinationScope("mqtt"))"#
    ))
    #expect(exportHarness.contains(
        #"try ExportScopeGate.requireConfigured(try await destinationScope("local-file"))"#
    ))
    #expect(!exportHarness.contains(
        "for metric in [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id]"
    ))
    #expect(!exportHarness.contains("metrics ?? selectedMetrics()"))
    #expect(viewHarness.contains("@State private var browserSelection = Set<MetricID>()"))
    #expect(viewHarness.contains("Button(\"Use Core Daily\")"))
    #expect(viewHarness.contains("applyCoreDailyPreset()"))
    #expect(viewHarness.contains("ohe.preset.coreDaily.appliedVersion"))
    #expect(viewHarness.contains("HarnessExport.isDestinationEnabled(scopeDestinationID)"))
    #expect(viewHarness.contains("? scope.metrics.subtracting(priorUnion)"))
    #expect(viewHarness.contains("startInclusive: scopeStartDate"))
    #expect(viewHarness.contains("endExclusive: scopeEndEnabled ? scopeEndDate : nil"))
}
