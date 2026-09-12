// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Security)
import EnginePorts
import Foundation
import Security
import Testing
@testable import NetEgress

@Test func r33KeychainPSKAddQueryIsDeviceOnlyNonSynchronizingAndAvailableAfterFirstUnlock() throws {
    let service = "app.openhealthexporter.test.\(UUID().uuidString)"
    let handle = SecretHandle(rawValue: "r33")
    let attributes = KeychainSecretStore.storeQuery(
        bytes: [0x33, 0x01],
        handle: handle,
        service: service
    )
    #expect(attributes[kSecClass as String] as? String == kSecClassGenericPassword as String)
    #expect(attributes[kSecAttrService as String] as? String == service)
    #expect(attributes[kSecAttrAccount as String] as? String == handle.rawValue)
    #expect(
        attributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
    )
    #expect(attributes[kSecAttrSynchronizable as String] as? Bool == false)
    #expect(attributes[kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(attributes[kSecValueData as String] as? Data == Data([0x33, 0x01]))
}
#endif
