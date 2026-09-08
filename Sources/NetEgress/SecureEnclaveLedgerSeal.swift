#if canImport(Security)
import Foundation
import RunJournal
import Security

public enum SecureEnclaveLedgerSealError: Error, Equatable {
    case keyUnavailable
    case signingFailed
}

/// P-256 ledger-head signer. Shipping configuration creates a permanent,
/// non-exportable Secure Enclave key; tests can request an ephemeral software key.
public actor SecureEnclaveLedgerSeal: ResettableLedgerHeadSeal {
    public let applicationTag: String
    public let useSecureEnclave: Bool
    public let permanent: Bool
    private var cachedKey: SecKey?

    public init(
        applicationTag: String = "app.openhealthexporter.ledger-head",
        useSecureEnclave: Bool = true,
        permanent: Bool = true
    ) {
        self.applicationTag = applicationTag
        self.useSecureEnclave = useSecureEnclave
        self.permanent = permanent
    }

    public func signedHead(_ head: String) async throws -> String {
        let key = try privateKey(createIfMissing: true)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .ecdsaSignatureMessageX962SHA256,
            message(head),
            &error
        ) as Data? else {
            _ = error?.takeRetainedValue()
            throw SecureEnclaveLedgerSealError.signingFailed
        }
        return signature.base64EncodedString()
    }

    public func matches(head: String, signature: String) async -> Bool {
        guard let signatureData = Data(base64Encoded: signature),
              let key = try? privateKey(createIfMissing: false),
              let publicKey = SecKeyCopyPublicKey(key)
        else {
            return false
        }
        var error: Unmanaged<CFError>?
        let valid = SecKeyVerifySignature(
            publicKey,
            .ecdsaSignatureMessageX962SHA256,
            message(head),
            signatureData as CFData,
            &error
        )
        _ = error?.takeRetainedValue()
        return valid
    }

    public func destroyIdentity() async throws {
        cachedKey = nil
        guard permanent else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: Data(applicationTag.utf8),
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureEnclaveLedgerSealError.keyUnavailable
        }
    }

    private func privateKey(createIfMissing: Bool) throws -> SecKey {
        if let cachedKey {
            return cachedKey
        }
        if permanent, let existing = loadKey() {
            cachedKey = existing
            return existing
        }
        guard createIfMissing else {
            throw SecureEnclaveLedgerSealError.keyUnavailable
        }
        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        if useSecureEnclave {
            attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        }
        if permanent {
            var privateAttributes: [String: Any] = [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: Data(applicationTag.utf8),
            ]
            if useSecureEnclave {
                var accessError: Unmanaged<CFError>?
                guard let access = SecAccessControlCreateWithFlags(
                    nil,
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                    .privateKeyUsage,
                    &accessError
                ) else {
                    _ = accessError?.takeRetainedValue()
                    throw SecureEnclaveLedgerSealError.keyUnavailable
                }
                privateAttributes[kSecAttrAccessControl as String] = access
            } else {
                privateAttributes[kSecAttrAccessible as String] =
                    kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            attributes[kSecPrivateKeyAttrs as String] = privateAttributes
        }
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            _ = error?.takeRetainedValue()
            throw SecureEnclaveLedgerSealError.keyUnavailable
        }
        cachedKey = key
        return key
    }

    private func loadKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: Data(applicationTag.utf8),
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return (item as! SecKey)
    }

    private func message(_ head: String) -> CFData {
        Data("ohe.ledger-head/1\n\(head)".utf8) as CFData
    }
}
#endif
