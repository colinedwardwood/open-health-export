// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Network)
import Foundation
import NetEgress
import Security

/// Ephemeral test CA, server cert (SAN 127.0.0.1), and client PKCS#12 for real Mosquitto.
struct MosquittoTLSMaterial {
    var directory: URL
    var caCert: URL
    var serverCert: URL
    var serverKey: URL
    var clientPKCS12: Data
    var roguePKCS12: Data
    var pin: PinRecord

    static func generate() throws -> MosquittoTLSMaterial {
        let openssl = URL(fileURLWithPath: "/usr/bin/openssl")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ohe-mosq-tls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let caKey = dir.appendingPathComponent("ca.key")
        let caCert = dir.appendingPathComponent("ca.crt")
        let serverKey = dir.appendingPathComponent("server.key")
        let serverCsr = dir.appendingPathComponent("server.csr")
        let serverCert = dir.appendingPathComponent("server.crt")
        let serverExt = dir.appendingPathComponent("server.ext")
        let serverDer = dir.appendingPathComponent("server.der")
        let clientKey = dir.appendingPathComponent("client.key")
        let clientCsr = dir.appendingPathComponent("client.csr")
        let clientCert = dir.appendingPathComponent("client.crt")
        let clientP12 = dir.appendingPathComponent("client.p12")
        let rogueKey = dir.appendingPathComponent("rogue.key")
        let rogueCert = dir.appendingPathComponent("rogue.crt")
        let rogueP12 = dir.appendingPathComponent("rogue.p12")
        try run(openssl, [
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "2", "-nodes",
            "-keyout", caKey.path, "-out", caCert.path, "-subj", "/CN=OHE Test CA",
        ])
        try run(openssl, [
            "req", "-newkey", "rsa:2048", "-nodes",
            "-keyout", serverKey.path, "-out", serverCsr.path, "-subj", "/CN=127.0.0.1",
        ])
        try "subjectAltName=IP:127.0.0.1\n".write(to: serverExt, atomically: true, encoding: .utf8)
        try run(openssl, [
            "x509", "-req", "-in", serverCsr.path, "-CA", caCert.path, "-CAkey", caKey.path,
            "-CAcreateserial", "-out", serverCert.path, "-days", "2", "-extfile", serverExt.path,
        ])
        try run(openssl, [
            "x509", "-in", serverCert.path, "-outform", "der", "-out", serverDer.path,
        ])
        try run(openssl, [
            "req", "-newkey", "rsa:2048", "-nodes",
            "-keyout", clientKey.path, "-out", clientCsr.path, "-subj", "/CN=ohe-client",
        ])
        try run(openssl, [
            "x509", "-req", "-in", clientCsr.path, "-CA", caCert.path, "-CAkey", caKey.path,
            "-CAcreateserial", "-out", clientCert.path, "-days", "2",
        ])
        try run(openssl, [
            "pkcs12", "-export", "-inkey", clientKey.path, "-in", clientCert.path,
            "-certfile", caCert.path, "-out", clientP12.path, "-passout", "pass:test",
        ])
        try run(openssl, [
            "req", "-x509", "-newkey", "rsa:2048", "-sha256", "-days", "2", "-nodes",
            "-keyout", rogueKey.path, "-out", rogueCert.path, "-subj", "/CN=rogue",
        ])
        try run(openssl, [
            "pkcs12", "-export", "-inkey", rogueKey.path, "-in", rogueCert.path,
            "-out", rogueP12.path, "-passout", "pass:test",
        ])
        let der = try Data(contentsOf: serverDer)
        let digest = try SPKIDigest.sha256Hex(certificateDER: der)
        let pin = PinRecord(
            leafSPKISha256: digest,
            issuerSPKISha256: digest,
            firstSeen: "2024-01-01T00:00:00Z",
            policy: .leaf
        )
        return MosquittoTLSMaterial(
            directory: dir,
            caCert: caCert,
            serverCert: serverCert,
            serverKey: serverKey,
            clientPKCS12: try Data(contentsOf: clientP12),
            roguePKCS12: try Data(contentsOf: rogueP12),
            pin: pin
        )
    }

    private static func run(_ openssl: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = openssl
        process.arguments = arguments
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw StreamError.transport("openssl failed: \(message)")
        }
    }
}
#endif
