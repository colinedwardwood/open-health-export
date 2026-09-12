// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation
import Testing

private func portableMQTT(
    id: String = "mqtt-home",
    metrics: [MetricID] = [
        MetricID(rawValue: "step_count"),
        MetricID(rawValue: "heart_rate"),
    ]
) throws -> PortableDestinationConfiguration {
    try PortableDestinationConfiguration(
        sourceIdentifier: id,
        displayName: "Home MQTT",
        kind: .mqtt,
        endpoint: "mqtts://nas.example:8883",
        settings: [
            "topic": "health/{{exporterId|raw}}",
            "qos": "1",
            "retain": "false",
        ],
        exportScope: PortableDestinationExportScope(
            metrics: metrics,
            startInclusive: Date(timeIntervalSince1970: 100),
            endExclusive: Date(timeIntervalSince1970: 200)
        )
    )
}

@Test func destinationConfigurationExportIsDeterministicAndCredentialFree() throws {
    let first = try DestinationConfigurationDocument(
        destinations: [
            portableMQTT(id: "z"),
            portableMQTT(
                id: "a",
                metrics: [
                    MetricID(rawValue: "heart_rate"),
                    MetricID(rawValue: "step_count"),
                ]
            ),
        ]
    ).encoded()
    let second = try DestinationConfigurationDocument(
        destinations: [
            portableMQTT(
                id: "a",
                metrics: [
                    MetricID(rawValue: "step_count"),
                    MetricID(rawValue: "heart_rate"),
                ]
            ),
            portableMQTT(id: "z"),
        ]
    ).encoded()

    #expect(first == second)
    let text = String(decoding: first, as: UTF8.self)
    #expect(text.contains(#""schemaVersion":1"#))
    #expect(text.contains(#""credentials":"omitted""#))
    #expect(!text.lowercased().contains("password"))
    #expect(!text.lowercased().contains("token"))
}

@Test func importedConfigurationRequiresReviewAndCreatesDisabledDraftsOnly() throws {
    let data = try DestinationConfigurationDocument(
        destinations: [portableMQTT()]
    ).encoded()

    let review = try DestinationConfigurationDocument.reviewImport(data)
    #expect(review.destinations.count == 1)
    #expect(throws: DestinationConfigurationPortabilityError.confirmationMismatch) {
        try review.confirm(typedConfirmation: "import")
    }

    let confirmed = try review.confirm(
        typedConfirmation: DestinationConfigurationImportReview.confirmationPhrase
    )
    #expect(confirmed.drafts.count == 1)
    #expect(confirmed.drafts[0].state == .disabledRequiresTest)
    #expect(confirmed.drafts[0].configuration.sourceIdentifier == "mqtt-home")
}

@Test func destinationConfigurationImportRejectsCredentialFields() throws {
    let data = Data(
        """
        {
          "format": "org.open-health-exporter.destination-config",
          "schemaVersion": 1,
          "destinations": [{
            "sourceIdentifier": "mqtt-home",
            "displayName": "Home MQTT",
            "kind": "mqtt",
            "endpoint": "mqtts://nas.example:8883",
            "settings": {},
            "exportScope": {"metrics": []},
            "credentials": "omitted",
            "password": "must-not-import"
          }]
        }
        """.utf8
    )

    #expect(throws: DestinationConfigurationPortabilityError.unsupportedField("password")) {
        try DestinationConfigurationDocument.reviewImport(data)
    }
}

@Test func portableConfigurationRejectsSecretBearingEndpointShapesAndSettings() {
    #expect(throws: DestinationConfigurationPortabilityError.credentialsInEndpoint) {
        try PortableDestinationConfiguration(
            sourceIdentifier: "https",
            displayName: "HTTPS",
            kind: .https,
            endpoint: "https://user:secret@example.test/upload"
        )
    }
    #expect(throws: DestinationConfigurationPortabilityError.credentialsInEndpoint) {
        try PortableDestinationConfiguration(
            sourceIdentifier: "https",
            displayName: "HTTPS",
            kind: .https,
            endpoint: "https://example.test/upload?token=secret"
        )
    }
    #expect(
        throws: DestinationConfigurationPortabilityError.unsupportedSetting(
            kind: .mqtt,
            key: "password"
        )
    ) {
        try PortableDestinationConfiguration(
            sourceIdentifier: "mqtt",
            displayName: "MQTT",
            kind: .mqtt,
            endpoint: "mqtts://example.test",
            settings: ["password": "secret"]
        )
    }
}

@Test func destinationConfigurationImportRejectsVersionAndIdentifierCollisions() throws {
    let valid = try DestinationConfigurationDocument(
        destinations: [portableMQTT()]
    ).encoded()
    let newer = Data(
        String(decoding: valid, as: UTF8.self)
            .replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":2"#)
            .utf8
    )
    #expect(throws: DestinationConfigurationPortabilityError.unsupportedSchemaVersion(2)) {
        try DestinationConfigurationDocument.reviewImport(newer)
    }

    #expect(throws: DestinationConfigurationPortabilityError.duplicateIdentifier("same")) {
        try DestinationConfigurationDocument(
            destinations: [
                portableMQTT(id: "same"),
                portableMQTT(id: "same"),
            ]
        )
    }
}

@Test func importedNetworkDraftsMaterializeOnlySettingsRuntimeCanPreserve() throws {
    let mqtt = try PortableDestinationConfiguration(
        sourceIdentifier: "mqtt",
        displayName: "MQTT",
        kind: .mqtt,
        endpoint: "mqtts://nas.example:8883",
        settings: [
            "allowInsecure": "false",
            "clientID": "phone",
            "qos": "1",
            "topic": "health/export",
        ]
    )
    let inputs = try PortableDestinationMaterializer.materialize(mqtt)
    #expect(inputs.slotIdentifier == "mqtt")
    #expect(inputs.endpoint == "mqtts://nas.example:8883")
    #expect(inputs.clientID == "phone")
    #expect(inputs.topic == "health/export")
    #expect(inputs.qos == 1)
    #expect(!inputs.allowInsecure)

    #expect(
        throws: DestinationConfigurationPortabilityError.unsupportedSetting(
            kind: .mqtt,
            key: "retain"
        )
    ) {
        try PortableDestinationMaterializer.materialize(portableMQTT())
    }
}

@Test func importedDraftMaterializationRejectsUnsupportedKindsAndMethods() throws {
    let local = try PortableDestinationConfiguration(
        sourceIdentifier: "local",
        displayName: "Local",
        kind: .localFile,
        endpoint: "archive"
    )
    #expect(
        throws: DestinationConfigurationPortabilityError
            .unsupportedDestinationKind(.localFile)
    ) {
        try PortableDestinationMaterializer.materialize(local)
    }
    let https = try PortableDestinationConfiguration(
        sourceIdentifier: "https",
        displayName: "HTTPS",
        kind: .https,
        endpoint: "https://example.test/upload",
        settings: ["method": "PUT"]
    )
    #expect(
        throws: DestinationConfigurationPortabilityError.unsupportedSetting(
            kind: .https,
            key: "method"
        )
    ) {
        try PortableDestinationMaterializer.materialize(https)
    }
}
