// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import CoreDomain
import CorrectnessEngine
import DestinationTrust
import EnginePorts
import Foundation
import NetEgress
import Testing

@Test func configurationAndEgressErrorsOmitHostsAndSecrets() throws {
    let host = "clinic.example"
    let allowlist = try #require(EgressError.notAllowlisted(host).errorDescription)
    #expect(!allowlist.contains(host))
    #expect(!allowlist.contains("password"))

    let field = try #require(
        DestinationConfigurationPortabilityError.unsupportedField("password").errorDescription
    )
    #expect(!field.contains("password"))
    #expect(
        DestinationConfigurationPortabilityError.confirmationMismatch.errorDescription?
            .contains("confirmation phrase") == true
    )

    let pin = try #require(PinError.mismatch.errorDescription)
    #expect(pin.contains("stopped before sending data"))
    #expect(!pin.contains(host))

    #expect(PairingError.payloadShape.errorDescription == "This pairing code is not valid.")
    #expect(
        DestinationSendError.deviceLocked.errorDescription
            == ErrorClassManifest.record(for: .deviceLocked).userFacingCopy
    )
    #expect(
        DestinationSendError.internalFault("clinic.example/secret").errorDescription?
            .contains("clinic.example") == false
    )
}

@Test func harnessImportSurfacesLocalizedConfigurationErrors() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let harness = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/HarnessView.swift"),
        encoding: .utf8
    )
    let importer = try String(
        contentsOf: root.appendingPathComponent("Apps/Exporter-iOS/ConfigurationImportView.swift"),
        encoding: .utf8
    )
    #expect(harness.contains("Import refused: \\(error.localizedDescription)"))
    #expect(importer.contains("Configuration refused: \\(error.localizedDescription)"))
    #expect(!harness.contains("Import refused: \\(error)."))
    #expect(!importer.contains("Configuration refused: \\(error)\""))
}
