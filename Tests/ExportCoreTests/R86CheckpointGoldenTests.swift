// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import Testing

private enum R86CheckpointFixture {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("qa").appendingPathComponent(name))
    }
}

@Test func r86Format1CheckpointMatchesCommittedGoldenBytes() throws {
    let envelope = CheckpointEnvelope(
        tzDatabaseVersion: "2024a",
        epoch: 9,
        adapterAnchor: Data([0xAB, 0xCD])
    )
    let golden = try R86CheckpointFixture.data("r86-checkpoint-format1.ohec")
    #expect(envelope.encoded() == golden)
    let restored = try CheckpointEnvelope.decoded(golden)
    #expect(restored == envelope)
}

@Test func r86CorruptCheckpointGoldensFailClosed() throws {
    #expect(throws: CheckpointError.corrupt) {
        _ = try CheckpointEnvelope.decoded(
            try R86CheckpointFixture.data("r86-checkpoint-corrupt.ohec")
        )
    }
    #expect(throws: CheckpointError.corrupt) {
        _ = try CheckpointEnvelope.decoded(
            try R86CheckpointFixture.data("r86-checkpoint-truncated.ohec")
        )
    }
    #expect(throws: CheckpointError.corrupt) {
        _ = try CheckpointEnvelope.decoded(
            try R86CheckpointFixture.data("r86-checkpoint-empty.ohec")
        )
    }
    #expect(throws: CheckpointError.unsupportedFormat) {
        _ = try CheckpointEnvelope.decoded(
            try R86CheckpointFixture.data("r86-checkpoint-bitflip-format.ohec")
        )
    }
}
