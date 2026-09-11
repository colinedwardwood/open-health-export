// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Security)
import Foundation
import Security

/// A user-supplied PKCS#12 identity for MQTTS client certificates.
/// External keys are **not** Secure Enclave material (SEC-68).
public struct TLSClientIdentity: @unchecked Sendable {
    private static let importLock = NSLock()
    public let identity: SecIdentity

    public init(pkcs12 data: Data, password: String) throws {
        Self.importLock.lock()
        defer { Self.importLock.unlock() }
        var items: CFArray?
        let status = SecPKCS12Import(
            data as CFData,
            [kSecImportExportPassphrase as String: password] as CFDictionary,
            &items
        )
        guard
            status == errSecSuccess,
            let imported = items as? [[String: Any]],
            let raw = imported.first?[kSecImportItemIdentity as String] as AnyObject?
        else {
            throw StreamError.transport("pkcs12 import \(status)")
        }
        identity = raw as! SecIdentity
    }

    public func makeSecIdentity() throws -> sec_identity_t {
        guard let created = sec_identity_create(identity) else {
            throw StreamError.transport("sec_identity_create")
        }
        return created
    }
}
#endif
