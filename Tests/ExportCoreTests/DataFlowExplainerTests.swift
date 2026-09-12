// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import DestinationTrust
import Testing

@Test func dataFlowExplainerNamesHostsProtocolsAndCredentialKindsFromLiveConfig() {
    let hops = [
        DataFlowHop(
            id: "local",
            host: "Files on this iPhone",
            transport: "Local files",
            credential: DataFlowHop.noNetwork
        ),
        DataFlowHop(
            id: "https",
            host: "homeassistant.local:8123",
            transport: "HTTPS",
            credential: DataFlowHop.bearerToken
        ),
        DataFlowHop(
            id: "mqtt",
            host: "nas.example.com:8883",
            transport: "MQTTS",
            credential: DataFlowHop.usernamePassword
        ),
        DataFlowHop(
            id: "otlp",
            host: "collector.example.com",
            transport: "OTLP HTTP",
            credential: DataFlowHop.noCredential
        ),
    ]
    #expect(DataFlowExplainer.typeCountCopy(41) == "We read 41 types you chose.")
    #expect(DataFlowExplainer.typeCountCopy(1) == "We read 1 type you chose.")
    #expect(DataFlowExplainer.typeCountCopy(0) == "No types selected yet.")
    #expect(
        hops.map(DataFlowExplainer.hopLine) == [
            "Files on this iPhone · Local files · no network",
            "homeassistant.local:8123 · HTTPS · bearer token",
            "nas.example.com:8883 · MQTTS · username + password",
            "collector.example.com · OTLP HTTP · no credential",
        ]
    )
    let joined = hops.map(DataFlowExplainer.hopLine).joined(separator: " ")
        + DataFlowExplainer.nowhereElse
        + DataFlowExplainer.empty
    for secretShaped in ["sk_live", "password=", "Bearer ey"] {
        #expect(!joined.contains(secretShaped))
    }
}
