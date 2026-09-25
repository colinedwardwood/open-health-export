// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation

/// Presentation-only advisory item. No field here may map to export behaviour (R-38 / T-43).
public struct AdvisoryItem: Sendable, Equatable {
    public var id: String
    public var published: String
    public var severity: String
    public var affected: String
    public var description: String
    public var url: String

    public init(
        id: String,
        published: String,
        severity: String,
        affected: String,
        description: String,
        url: String
    ) {
        self.id = id
        self.published = published
        self.severity = severity
        self.affected = affected
        self.description = description
        self.url = url
    }
}

public struct AdvisoryFeed: Sendable, Equatable {
    public var seq: Int
    public var validFrom: String
    public var expiresAt: String
    public var keyID: String
    public var items: [AdvisoryItem]

    public init(
        seq: Int,
        validFrom: String,
        expiresAt: String,
        keyID: String,
        items: [AdvisoryItem]
    ) {
        self.seq = seq
        self.validFrom = validFrom
        self.expiresAt = expiresAt
        self.keyID = keyID
        self.items = items
    }
}

public enum AdvisoryError: Error, Equatable {
    case malformed
    case extraField(String)
    case unknownKey
    case badSignature
    case rollback
    /// #65: a sequence number far beyond the last one seen. Accepting it would freeze
    /// the counter so that no later genuine feed could ever be shown.
    case sequenceJump
    case notYetValid
    case expired
}

/// Compiled Ed25519 public keys (#65). Rotation is an app update; a feed can never
/// introduce a key. The private halves are held offline by the owner, never in this
/// repository or in the app, and signing lives in `Tools/advisory-sign`.
public enum AdvisoryPinnedKeys {
    public static let host = "advisories.openhealthexporter.org"
    public static let path = "/advisories/v1.json"
    public static let urlString = "https://advisories.openhealthexporter.org/advisories/v1.json"
    public static let activeID = "active"
    public static let successorID = "successor"

    public static let activePublicKeyHex = "d27e27c91a4f62e6735f6f07605c20581f7f819e74410f271c69e07d2acf2112"
    public static let successorPublicKeyHex = "e1928a0697f45676aa1bafaf6686796adf05d4ab0eff52926d2285f1f65d3e6f"
}

/// Checks a detached Ed25519 signature over the canonical feed bytes.
public struct AdvisoryVerifier: Sendable {
    /// Raw 32-byte public keys by key ID.
    public var publicKeys: [String: Data]

    public init(publicKeys: [String: Data]) {
        self.publicKeys = publicKeys
    }

    public static let pinned = AdvisoryVerifier(publicKeys: [
        AdvisoryPinnedKeys.activeID: Hex.decode(AdvisoryPinnedKeys.activePublicKeyHex) ?? Data(),
        AdvisoryPinnedKeys.successorID: Hex.decode(AdvisoryPinnedKeys.successorPublicKeyHex) ?? Data(),
    ])

    public func verify(signatureHex: String, keyID: String, message: Data) throws {
        guard let raw = publicKeys[keyID], raw.count == 32 else {
            throw AdvisoryError.unknownKey
        }
        #if canImport(CryptoKit)
        guard
            let signature = Hex.decode(signatureHex.lowercased()),
            signature.count == 64,
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
            key.isValidSignature(signature, for: message)
        else {
            throw AdvisoryError.badSignature
        }
        #else
        // No Ed25519 implementation on this platform, so nothing can be verified.
        throw AdvisoryError.badSignature
        #endif
    }
}

public enum Hex {
    public static func decode(_ hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    public static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

public enum AdvisoryCanonical {
    public static func bytes(_ feed: AdvisoryFeed) -> Data {
        Data(string(feed).utf8)
    }

    public static func string(_ feed: AdvisoryFeed) -> String {
        let items = feed.items
            .sorted { $0.id < $1.id }
            .map(itemJSON)
            .joined(separator: ",")
        return "{"
            + "\"expires_at\":\(jsonString(feed.expiresAt)),"
            + "\"items\":[\(items)],"
            + "\"key_id\":\(jsonString(feed.keyID)),"
            + "\"seq\":\(feed.seq),"
            + "\"valid_from\":\(jsonString(feed.validFrom))"
            + "}"
    }

    /// The published document: the canonical feed and a signature made offline over
    /// `bytes(feed)`. The app never signs.
    public static func envelopeJSON(_ feed: AdvisoryFeed, signatureHex: String) -> Data {
        Data(
            ("{\"feed\":" + string(feed) + ",\"signature\":" + jsonString(signatureHex) + "}")
                .utf8
        )
    }

    private static func itemJSON(_ item: AdvisoryItem) -> String {
        "{"
            + "\"affected\":\(jsonString(item.affected)),"
            + "\"description\":\(jsonString(item.description)),"
            + "\"id\":\(jsonString(item.id)),"
            + "\"published\":\(jsonString(item.published)),"
            + "\"severity\":\(jsonString(item.severity)),"
            + "\"url\":\(jsonString(item.url))"
            + "}"
    }

    static func jsonString(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count + 2)
        escaped.append("\"")
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": escaped.append("\\\"")
            case "\\": escaped.append("\\\\")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            default: escaped.append(Character(scalar))
            }
        }
        escaped.append("\"")
        return escaped
    }
}

public enum AdvisoryDocument {
    private static let feedKeys: Set<String> = [
        "seq", "valid_from", "expires_at", "key_id", "items",
    ]
    private static let itemKeys: Set<String> = [
        "id", "published", "severity", "affected", "description", "url",
    ]
    private static let envelopeKeys: Set<String> = ["feed", "signature"]

    /// The publisher increments `seq` by one per feed. A larger jump than this is
    /// refused rather than trusted, so one feed cannot move the counter out of reach.
    public static let maximumSequenceStep = 1_000

    public static func parse(
        _ data: Data,
        lastSeenSeq: Int,
        now: Date,
        verifier: AdvisoryVerifier = .pinned
    ) throws -> AdvisoryFeed {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw AdvisoryError.malformed
        }
        try rejectUnknown(root.keys, allowed: envelopeKeys)
        guard
            let feedObject = root["feed"] as? [String: Any],
            let signature = root["signature"] as? String
        else {
            throw AdvisoryError.malformed
        }
        try rejectUnknown(feedObject.keys, allowed: feedKeys)
        let feed = try decodeFeed(feedObject)
        try verifier.verify(
            signatureHex: signature,
            keyID: feed.keyID,
            message: AdvisoryCanonical.bytes(feed)
        )
        guard feed.seq > lastSeenSeq else {
            throw AdvisoryError.rollback
        }
        guard feed.seq - lastSeenSeq <= maximumSequenceStep else {
            throw AdvisoryError.sequenceJump
        }
        let validFrom = try parseInstant(feed.validFrom)
        let expiresAt = try parseInstant(feed.expiresAt)
        if now < validFrom { throw AdvisoryError.notYetValid }
        if now >= expiresAt { throw AdvisoryError.expired }
        return feed
    }

    private static func decodeFeed(_ object: [String: Any]) throws -> AdvisoryFeed {
        guard
            let seq = intValue(object["seq"]),
            let validFrom = object["valid_from"] as? String,
            let expiresAt = object["expires_at"] as? String,
            let keyID = object["key_id"] as? String,
            let rawItems = object["items"] as? [Any]
        else {
            throw AdvisoryError.malformed
        }
        let items = try rawItems.map { raw -> AdvisoryItem in
            guard let item = raw as? [String: Any] else {
                throw AdvisoryError.malformed
            }
            try rejectUnknown(item.keys, allowed: itemKeys)
            guard
                let id = item["id"] as? String,
                let published = item["published"] as? String,
                let severity = item["severity"] as? String,
                let affected = item["affected"] as? String,
                let description = item["description"] as? String,
                let url = item["url"] as? String
            else {
                throw AdvisoryError.malformed
            }
            return AdvisoryItem(
                id: id,
                published: published,
                severity: severity,
                affected: affected,
                description: description,
                url: url
            )
        }
        return AdvisoryFeed(
            seq: seq,
            validFrom: validFrom,
            expiresAt: expiresAt,
            keyID: keyID,
            items: items
        )
    }

    private static func rejectUnknown<S: Sequence>(
        _ keys: S,
        allowed: Set<String>
    ) throws where S.Element == String {
        for key in keys where !allowed.contains(key) {
            throw AdvisoryError.extraField(key)
        }
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let value = any as? Int64 { return Int(value) }
        if let value = any as? NSNumber { return value.intValue }
        return nil
    }

    private static func parseInstant(_ raw: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: raw) else {
            throw AdvisoryError.malformed
        }
        return date
    }
}

public enum AdvisoryStaleness {
    public static let freshWindow: TimeInterval = 30 * 24 * 60 * 60
    public static let staleCopy = "security advisories are stale"
    public static let neverCheckedCopy = "security advisories have not been checked yet"
    public static let offCopy = "security advisories are off"

    public static func disabledCopy(lastChecked: String) -> String {
        "\(offCopy) — last checked \(lastChecked)"
    }

    /// Nil while fresh. A feed that has never verified is reported as unchecked, not
    /// stale: nothing was ever current, so "stale" would imply a lapse that did not
    /// happen (#30).
    public static func bannerCopy(lastVerified: Date?, now: Date) -> String? {
        guard let lastVerified else { return neverCheckedCopy }
        return isStale(lastVerified: lastVerified, now: now) ? staleCopy : nil
    }

    public static func isStale(lastVerified: Date?, now: Date) -> Bool {
        guard let lastVerified else { return true }
        return now.timeIntervalSince(lastVerified) >= freshWindow
    }
}

public enum MarketingVersion {
    /// Major.minor only. Build numbers would shrink the anonymity set (R-38).
    public static func coarse(_ raw: String) -> String {
        let pieces = raw.split(separator: ".", omittingEmptySubsequences: false)
        let major = digits(pieces.first.map(String.init) ?? "0")
        let minor = pieces.count > 1 ? digits(String(pieces[1])) : "0"
        return "\(major).\(minor)"
    }

    private static func digits(_ raw: String) -> String {
        let kept = raw.filter(\.isNumber)
        return kept.isEmpty ? "0" : kept
    }
}
