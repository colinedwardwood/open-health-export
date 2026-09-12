// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import CorrectnessEngine
import EnginePorts
import Testing

@Test func wipeInventoryItemisesCountsAndReceivedDateRanges() {
    let pending = [
        PendingBatch(
            id: BatchID(rawValue: "00000000-0000-4000-8000-000000000001"),
            payloadURL: "one.ndjson",
            expectedRecords: 4,
            byteCount: 1_048_576
        ),
        PendingBatch(
            id: BatchID(rawValue: "00000000-0000-4000-8000-000000000002"),
            payloadURL: "two.ndjson",
            expectedRecords: 2,
            byteCount: 1_048_576
        ),
    ]
    let journal = [
        RunEvent(runID: RunID(rawValue: "r1"), outcomeKind: "success", detail: ""),
        RunEvent(runID: RunID(rawValue: "r2"), outcomeKind: "success", detail: ""),
    ]
    let ledger = [
        EgressEntry(
            destination: "homeassistant.local",
            sampleCount: 10,
            outcomeKind: "success",
            wallTimeEpoch: 1_741_737_600
        ),
        EgressEntry(
            destination: "homeassistant.local",
            sampleCount: 3,
            outcomeKind: "success",
            wallTimeEpoch: 1_756_771_200
        ),
        EgressEntry(
            destination: "local-file",
            sampleCount: 1,
            outcomeKind: "success",
            wallTimeEpoch: 1_744_934_400
        ),
        EgressEntry(
            destination: "nas.example.com",
            sampleCount: 0,
            outcomeKind: "attempt",
            wallTimeEpoch: 1_756_771_200
        ),
    ]
    let inventory = WipeInventory.build(
        destinationCount: 3,
        credentialCount: 2,
        pending: pending,
        journal: journal,
        ledger: ledger
    )
    #expect(inventory.queuedRecords == 6)
    #expect(inventory.queuedBytes == 2_097_152)
    #expect(inventory.runCount == 2)
    #expect(inventory.ledgerCount == 4)
    #expect(inventory.received.map(\.destination) == ["homeassistant.local", "local-file"])
    #expect(
        WipeCopy.counts(inventory)
            == "Destinations: 3. Stored credentials: 2. Queued payloads: 6 records, 2.0 MB. Run history: 2. Egress ledger: 4."
    )
    #expect(
        WipeCopy.receivedLine(inventory.received[0])
            == "homeassistant.local received data from 2025-03-12 to 2025-09-02."
    )
    #expect(
        WipeCopy.receivedLine(inventory.received[1])
            == "local-file received data on 2025-04-18."
    )
    #expect(WipeCopy.receivedLimit.contains("already received"))
    #expect(WipeCopy.healthLimit.contains("Health access"))
    #expect(WipeCopy.healthPath.contains("Privacy → Apps"))
}

@Test func wipeInventoryEmptyLedgerHasNoReceivedRanges() {
    let inventory = WipeInventory.build(
        destinationCount: 0,
        credentialCount: 0,
        pending: [],
        journal: [],
        ledger: [
            EgressEntry(
                destination: "local-file",
                sampleCount: 0,
                outcomeKind: "genesis_after_wipe",
                wallTimeEpoch: 0
            )
        ]
    )
    #expect(inventory.received.isEmpty)
    #expect(WipeCopy.noneReceived == "No destination has received data yet.")
}
