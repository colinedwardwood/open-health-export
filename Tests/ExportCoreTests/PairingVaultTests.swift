import CompanionWire
import EnginePorts
import Foundation
import SinkCompanion
import TestSupport
import Testing

@Test func pairingVaultRoundTripsSecretOutOfBandFromTheRecord() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-vault-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let record = dir.appendingPathComponent("pairing.json")
    let store = MemorySecretStore()
    let vault = PairingVault(store: store, recordFile: record)
    let secret = try PairingSecret(bytes: (0..<32).map { UInt8($0) })
    let session = PairingSession.mac(
        secret: secret,
        localInstallationID: "mac-9F2C",
        serviceName: "OHE Test"
    )
    try await vault.save(session)
    let loaded = try await vault.load()
    #expect(loaded.macInstallationID == "mac-9F2C")
    #expect(loaded.serviceName == "OHE Test")
    #expect(loaded.secret == secret)
    let json = try String(contentsOf: record, encoding: .utf8)
    #expect(!json.contains("secret"))
    #expect(!json.contains("\"key\""))
    #expect(!json.contains(try session.qrPayload().encoded().split(separator: "\n")[2]))
    try await vault.forget()
    await #expect(throws: SecretStoreError.notFound) {
        _ = try await vault.load()
    }
}

@Test func pairingVaultPhoneLoadKeepsImmediateSAS() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-vault-phone-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let vault = PairingVault(
        store: MemorySecretStore(),
        recordFile: dir.appendingPathComponent("pairing.json")
    )
    let secret = try PairingSecret(bytes: (0..<32).map { UInt8(truncatingIfNeeded: $0 * 7 + 3) })
    let payload = try PairingPayload(
        macInstallationID: "mac-9F2C",
        secret: secret,
        serviceName: "OHE Test"
    )
    let phone = PairingSession.phone(payload: payload, localInstallationID: "phone-1A7B")
    try await vault.save(phone)
    let loaded = try await vault.load()
    #expect(loaded.confirmationCode == phone.confirmationCode)
    #expect(loaded.confirmationCode == "RPY5-BRGD")
}