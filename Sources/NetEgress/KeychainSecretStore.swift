// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Security)
import EnginePorts
import Foundation
import Security

/// Keychain-backed PSK store. Data-protection keychain, not iCloud, accessible after first
/// unlock on this device only (R-33). Biometry is deliberately *not* required: a Face ID prompt
/// would block background export. `deleteAll` is R-43.
public struct KeychainSecretStore: SecretStore, Sendable {
    public var service: String

    public init(service: String = "app.openhealthexporter.psk") {
        self.service = service
    }

    public func store(_ bytes: [UInt8], handle: SecretHandle) async throws {
        guard !handle.rawValue.isEmpty else { throw SecretStoreError.emptyHandle }
        guard !bytes.isEmpty else { throw SecretStoreError.emptySecret }
        try deleteIgnoringNotFound(handle)
        let query = Self.storeQuery(bytes: bytes, handle: handle, service: service)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Self.mapAddStatus(status)
        }
    }

    static func mapAddStatus(_ status: OSStatus) -> SecretStoreError {
        status == errSecMissingEntitlement ? .unavailable : .notFound
    }

    static func storeQuery(
        bytes: [UInt8],
        handle: SecretHandle,
        service: String
    ) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: handle.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: Data(bytes),
        ]
    }

    public func load(_ handle: SecretHandle) async throws -> [UInt8] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: handle.rawValue,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, !data.isEmpty else {
            throw SecretStoreError.notFound
        }
        return [UInt8](data)
    }

    public func delete(_ handle: SecretHandle) async throws {
        try deleteIgnoringNotFound(handle)
    }

    public func deleteAll() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.notFound
        }
    }

    private func deleteIgnoringNotFound(_ handle: SecretHandle) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: handle.rawValue,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.notFound
        }
    }
}
#endif
