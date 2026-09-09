#if canImport(Network)
import Foundation
import NetEgress
import Security

enum LoopbackTLS {
    private static let lock = NSLock()

    struct Material {
        var identity: SecIdentity
        var certificateDER: Data
        var pin: PinRecord
    }

    static func material(commonName: String = "127.0.0.1") throws -> Material {
        lock.lock()
        defer { lock.unlock() }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-tls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = dir.appendingPathComponent("key.pem")
        let cert = dir.appendingPathComponent("cert.pem")
        let p12 = dir.appendingPathComponent("id.p12")
        try runOpenSSL([
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "1", "-nodes",
            "-keyout", key.path, "-out", cert.path, "-subj", "/CN=\(commonName)",
            "-addext", "subjectAltName=IP:127.0.0.1,DNS:localhost,DNS:127.0.0.1",
        ])
        try runOpenSSL([
            "pkcs12", "-export", "-inkey", key.path, "-in", cert.path, "-out", p12.path,
            "-passout", "pass:test",
        ])
        let p12Data = try Data(contentsOf: p12)
        var items: CFArray?
        let status = SecPKCS12Import(
            p12Data as CFData,
            [kSecImportExportPassphrase as String: "test"] as CFDictionary,
            &items
        )
        guard status == errSecSuccess, let imported = items as? [[String: Any]],
              let identity = imported.first?[kSecImportItemIdentity as String]
        else {
            throw StreamError.transport("pkcs12 import \(status)")
        }
        let secIdentity = identity as! SecIdentity
        var certificate: SecCertificate?
        let certStatus = SecIdentityCopyCertificate(secIdentity, &certificate)
        guard certStatus == errSecSuccess, let certificate else {
            throw StreamError.transport("identity certificate \(certStatus)")
        }
        let der = SecCertificateCopyData(certificate) as Data
        let digest = try SPKIDigest.sha256Hex(certificateDER: der)
        let pin = PinRecord(
            leafSPKISha256: digest,
            issuerSPKISha256: digest,
            firstSeen: "2024-01-01T00:00:00Z",
            policy: .leaf
        )
        return Material(identity: secIdentity, certificateDER: der, pin: pin)
    }

    private static func runOpenSSL(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw StreamError.transport("openssl \(arguments.first ?? "") failed: \(message)")
        }
    }
}
#endif
