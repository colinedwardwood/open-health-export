import CompanionWire
import EnginePorts
import FileWriteKit
import Foundation

/// Metadata only — the PSK lives in `SecretStore`, never in this file.
public struct PairingRecord: Sendable, Equatable, Codable {
    public var macInstallationID: String
    public var localInstallationID: String
    public var serviceName: String
    public var handle: String
    public var peerInstallationID: String?

    public init(
        macInstallationID: String,
        localInstallationID: String,
        serviceName: String,
        handle: String,
        peerInstallationID: String? = nil
    ) {
        self.macInstallationID = macInstallationID
        self.localInstallationID = localInstallationID
        self.serviceName = serviceName
        self.handle = handle
        self.peerInstallationID = peerInstallationID
    }
}

/// Persists one companion pairing: Keychain (or test double) for the PSK, a JSON sidecar for names.
public struct PairingVault: Sendable {
    public static let primaryHandle = SecretHandle(rawValue: "companion.primary")

    public var store: any SecretStore
    public var recordFile: URL

    public init(store: any SecretStore, recordFile: URL) {
        self.store = store
        self.recordFile = recordFile
    }

    public func save(_ session: PairingSession, handle: SecretHandle = primaryHandle) async throws {
        let bytes = session.secret.withKeyBytes { $0 }
        try await store.store(bytes, handle: handle)
        let record = PairingRecord(
            macInstallationID: session.macInstallationID,
            localInstallationID: session.localInstallationID,
            serviceName: session.serviceName,
            handle: handle.rawValue,
            peerInstallationID: session.peerInstallationID
        )
        let data = try JSONEncoder().encode(record)
        try FileWriteKit.writeAtomically(data, to: recordFile)
    }

    public func load(handle: SecretHandle = primaryHandle) async throws -> PairingSession {
        guard FileManager.default.fileExists(atPath: recordFile.path) else {
            throw SecretStoreError.notFound
        }
        let record = try JSONDecoder().decode(PairingRecord.self, from: Data(contentsOf: recordFile))
        let bytes = try await store.load(handle)
        let secret = try PairingSecret(bytes: bytes)
        var session = PairingSession(
            secret: secret,
            localInstallationID: record.localInstallationID,
            macInstallationID: record.macInstallationID,
            serviceName: record.serviceName,
            peerInstallationID: record.peerInstallationID
        )
        if session.peerInstallationID == nil, record.localInstallationID != record.macInstallationID {
            session.peerInstallationID = record.macInstallationID
        }
        return session
    }

    public func forget(handle: SecretHandle = primaryHandle) async throws {
        try await store.delete(handle)
        if FileManager.default.fileExists(atPath: recordFile.path) {
            try FileManager.default.removeItem(at: recordFile)
        }
    }
}

extension PairingSession {
    public func qrPayload() throws -> PairingPayload {
        try PairingPayload(
            macInstallationID: macInstallationID,
            secret: secret,
            serviceName: serviceName
        )
    }
}
