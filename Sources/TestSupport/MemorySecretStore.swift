import EnginePorts
import Foundation

/// In-memory secret store for tests. Not for production PSK.
public actor MemorySecretStore: SecretStore {
    private var secrets: [String: [UInt8]] = [:]

    public init() {}

    public func store(_ bytes: [UInt8], handle: SecretHandle) async throws {
        guard !handle.rawValue.isEmpty else { throw SecretStoreError.emptyHandle }
        guard !bytes.isEmpty else { throw SecretStoreError.emptySecret }
        secrets[handle.rawValue] = bytes
    }

    public func load(_ handle: SecretHandle) async throws -> [UInt8] {
        guard let bytes = secrets[handle.rawValue] else { throw SecretStoreError.notFound }
        return bytes
    }

    public func delete(_ handle: SecretHandle) async throws {
        secrets.removeValue(forKey: handle.rawValue)
    }

    public func deleteAll() async throws {
        secrets.removeAll()
    }
}
