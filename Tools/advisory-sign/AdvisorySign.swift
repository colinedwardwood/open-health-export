// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

// #65: the only place advisory feeds are signed. Runs on the owner's machine with a
// private key held offline; nothing here is linked into the app.
//
//   advisory-sign keygen <directory>
//   advisory-sign sign --key <private key file> --key-id active|successor --feed <feed.json> [--out <envelope.json>]
//   advisory-sign verify <envelope.json>
//
// feed.json holds seq, valid_from, expires_at and items; key_id comes from --key-id.
// `sign` refuses to write an envelope the app's compiled public keys would reject.

import CryptoKit
import Foundation
import WireFormat

@main
enum AdvisorySign {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("advisory-sign: \(error)\n".utf8))
            exit(1)
        }
    }

    private enum Failure: Error, CustomStringConvertible {
        case usage
        case message(String)

        var description: String {
            switch self {
            case .usage:
                "usage: advisory-sign keygen <dir> | sign --key <file> --key-id <id> --feed <feed.json> [--out <file>] | verify <envelope.json>"
            case .message(let text):
                text
            }
        }
    }

    private static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else { throw Failure.usage }
        let rest = Array(arguments.dropFirst())
        switch command {
        case "keygen":
            guard let directory = rest.first else { throw Failure.usage }
            try keygen(into: URL(fileURLWithPath: directory))
        case "sign":
            let options = try parse(rest)
            guard let keyPath = options["--key"], let keyID = options["--key-id"],
                  let feedPath = options["--feed"]
            else { throw Failure.usage }
            try sign(keyPath: keyPath, keyID: keyID, feedPath: feedPath, outPath: options["--out"])
        case "verify":
            guard let path = rest.first else { throw Failure.usage }
            let feed = try AdvisoryDocument.parse(
                try Data(contentsOf: URL(fileURLWithPath: path)),
                lastSeenSeq: 0,
                now: Date()
            )
            print("verified: seq \(feed.seq), key \(feed.keyID), \(feed.items.count) item(s)")
        default:
            throw Failure.usage
        }
    }

    private static func parse(_ arguments: [String]) throws -> [String: String] {
        guard arguments.count.isMultiple(of: 2) else { throw Failure.usage }
        var options: [String: String] = [:]
        for index in stride(from: 0, to: arguments.count, by: 2) {
            options[arguments[index]] = arguments[index + 1]
        }
        return options
    }

    private static func keygen(into directory: URL) throws {
        let file = directory.appendingPathComponent("advisory.ed25519.key")
        guard !FileManager.default.fileExists(atPath: file.path) else {
            throw Failure.message("\(file.path) exists; refusing to overwrite a signing key")
        }
        let key = Curve25519.Signing.PrivateKey()
        try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        print("private key: \(file.path) (move it offline)")
        print("public key:  \(Hex.encode(key.publicKey.rawRepresentation))")
    }

    private static func sign(keyPath: String, keyID: String, feedPath: String, outPath: String?) throws {
        let encoded = try String(contentsOfFile: keyPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: encoded) else {
            throw Failure.message("\(keyPath) is not a base64 Ed25519 private key")
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
        let feed = try readFeed(URL(fileURLWithPath: feedPath), keyID: keyID)
        let signature = try key.signature(for: AdvisoryCanonical.bytes(feed))
        let envelope = AdvisoryCanonical.envelopeJSON(feed, signatureHex: Hex.encode(signature))
        // The app must accept what is published: check against its compiled keys.
        _ = try AdvisoryDocument.parse(envelope, lastSeenSeq: feed.seq - 1, now: Date())
        if let outPath {
            try envelope.write(to: URL(fileURLWithPath: outPath))
            print("wrote \(outPath): seq \(feed.seq), key \(keyID)")
        } else {
            FileHandle.standardOutput.write(envelope)
        }
    }

    private static func readFeed(_ url: URL, keyID: String) throws -> AdvisoryFeed {
        guard
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
            let seq = (object["seq"] as? NSNumber)?.intValue,
            let validFrom = object["valid_from"] as? String,
            let expiresAt = object["expires_at"] as? String,
            let rawItems = object["items"] as? [[String: String]]
        else {
            throw Failure.message("\(url.path) needs seq, valid_from, expires_at and items")
        }
        let items = try rawItems.map { item -> AdvisoryItem in
            guard let id = item["id"], let published = item["published"], let severity = item["severity"],
                  let affected = item["affected"], let description = item["description"],
                  let link = item["url"]
            else {
                throw Failure.message("each item needs id, published, severity, affected, description and url")
            }
            return AdvisoryItem(
                id: id, published: published, severity: severity,
                affected: affected, description: description, url: link
            )
        }
        return AdvisoryFeed(seq: seq, validFrom: validFrom, expiresAt: expiresAt, keyID: keyID, items: items)
    }
}
