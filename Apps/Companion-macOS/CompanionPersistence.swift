// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import CompanionWire
import Foundation
import NetEgress
import SinkCompanion

enum CompanionPersistence {
    static func vault() throws -> PairingVault {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("OpenHealthExporterCompanion", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return PairingVault(
            store: KeychainSecretStore(service: IdentifierRoot.qualified("mac.psk")),
            recordFile: root.appendingPathComponent("pairing.json")
        )
    }
}
