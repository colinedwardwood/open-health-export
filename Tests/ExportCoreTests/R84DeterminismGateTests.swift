// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import WireFormat

private enum R84DeterminismFixture {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func data(_ relative: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(relative))
    }

    static func text(_ relative: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
    }
}

@Test func r84ScriptSelfTestAcceptsCommittedUTCDigests() throws {
    let script = R84DeterminismFixture.root.appendingPathComponent(
        "scripts/check-r84-determinism.sh"
    )
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path, "--self-test"]
    process.currentDirectoryURL = R84DeterminismFixture.root
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(process.terminationStatus == 0, "self-test failed: \(err)\(out)")
    #expect(out.contains("r84-determinism self-test: ok"))
}

@Test func p8R84G1UtcFixtureIsByteStableAcrossOneHundredEncodes() throws {
    let input = try R84DeterminismFixture.data(
        "spec/v1.0.0/fixtures/g1/logical-input.json"
    )
    let expected = try R84DeterminismFixture.data(
        "spec/v1.0.0/fixtures/g1/expected.ndjson"
    )
    var first: Data?
    for run in 1 ... 100 {
        let artifacts = try FrozenEncoder.artifacts(fromLogicalInput: input)
        #expect(artifacts.ndjson == expected, "G1 encode \(run) drifted from committed bytes")
        if let first {
            #expect(artifacts.ndjson == first, "G1 encode \(run) drifted from run 1")
        } else {
            first = artifacts.ndjson
        }
    }
}

@Test func r84GateDoesNotClaimUnavailableDarwinX86() throws {
    let script = try R84DeterminismFixture.text("scripts/check-r84-determinism.sh")
    let workflow = try R84DeterminismFixture.text(".github/workflows/r84-determinism.yml")
    #expect(script.contains("OHE_DETERMINISM_RUNS"))
    #expect(script.contains("does not claim Darwin x86_64"))
    #expect(workflow.contains("ubuntu-latest"))
    #expect(workflow.contains("ubuntu-24.04-arm"))
    #expect(workflow.contains("macos-26"))
    #expect(workflow.contains("actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"))
    #expect(workflow.contains("swift-actions/setup-swift@d8e84bc3a450686a95474d7d6fa4a3301498debc"))
    #expect(workflow.contains("contents: read"))
    #expect(!workflow.contains("macos-13"))
    #expect(!workflow.contains("pull_request_target"))
    #expect(!workflow.contains("self-hosted"))
    #expect(!workflow.contains("nightly-volume"))
}

@Test func r84CommittedDigestsCoverUTCFixtures() throws {
    let spec = try JSONSerialization.jsonObject(
        with: R84DeterminismFixture.data("spec/v1.0.0/README.md")
    ) as? [String: Any]
    let fixtures = spec?["fixtures"] as? [String: Any]
    let t0 = fixtures?["tier0.ndjson"] as? [String: Any]
    let g1 = fixtures?["g1"] as? [String: Any]
    #expect(t0?["sha256"] as? String == ContentSHA256.hex(
        try R84DeterminismFixture.data("spec/v1.0.0/fixtures/tier0.ndjson")
    ))
    #expect(g1?["sha256"] as? String == ContentSHA256.hex(
        try R84DeterminismFixture.data("spec/v1.0.0/fixtures/g1/expected.ndjson")
    ))
    let input = try JSONSerialization.jsonObject(
        with: R84DeterminismFixture.data("spec/v1.0.0/fixtures/g1/logical-input.json")
    ) as? [String: Any]
    let samples = try #require(input?["samples"] as? [[String: Any]])
    for sample in samples {
        #expect((sample["tzOffsetMinutes"] as? NSNumber)?.intValue == 0)
    }
}
