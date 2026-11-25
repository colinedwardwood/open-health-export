// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CompanionWire
import CoreDomain
import CorrectnessEngine
import FileWriteKit
import NetEgress
import Foundation
import RunJournal
import SinkCompanion
import UIKit

/// Where the app keeps its state on disk, and the identity and keys tied to it.
/// Every service reaches them here.
enum AppFiles {
    static func installationID() throws -> String {
        let root = try applicationSupportRoot()
        let exporterURL = root.appendingPathComponent("exporter-id")
        if let existing = try? String(contentsOf: exporterURL, encoding: .utf8), !existing.isEmpty {
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let id = UUID().uuidString.lowercased()
        try id.write(to: exporterURL, atomically: true, encoding: .utf8)
        return id
    }

    static func applicationSupportRoot() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("OpenHealthExporter", isDirectory: true)
        try fm.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        // createDirectory does not update attributes when the directory already
        // exists, so re-apply the SEC-32 floor for upgrades as well as fresh installs.
        try fm.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: root.path
        )
        // SEC-30: everything the engine keeps — state, journal, queued payloads — lives
        // under here, and none of it may reach a backup.
        try FileWriteKit.excludeFromBackup(root)
        return root
    }

    static func protectedPayloadDirectory(
        named name: String,
        under root: URL
    ) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        let protection = FileProtectionType.completeUnlessOpen
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: protection]
        )
        // Apply the accepted ADR-0002 Class B split to pre-existing directories too.
        try FileManager.default.setAttributes(
            [.protectionKey: protection],
            ofItemAtPath: directory.path
        )
        return directory
    }

    static func ledgerHeadSeal() -> any LedgerHeadSeal {
        resettableLedgerHeadSeal()
    }

    static func resettableLedgerHeadSeal() -> any ResettableLedgerHeadSeal {
        #if targetEnvironment(simulator)
        SecureEnclaveLedgerSeal(useSecureEnclave: false, permanent: true)
        #else
        SecureEnclaveLedgerSeal()
        #endif
    }

    static func vault() throws -> PairingVault {
        let root = try applicationSupportRoot()
        return PairingVault(
            store: KeychainSecretStore(service: IdentifierRoot.qualified("ios.psk")),
            recordFile: root.appendingPathComponent("pairing.json")
        )
    }
}
