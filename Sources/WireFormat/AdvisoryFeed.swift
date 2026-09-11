// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

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
    case notYetValid
    case expired
}

/// Compiled HMAC pins. Rotation is an app update, never a feed-driven key.
public enum AdvisoryPinnedKeys {
    public static let host = "advisories.openhealthexporter.org"
    public static let path = "/advisories/v1.json"
    public static let urlString = "https://advisories.openhealthexporter.org/advisories/v1.json"
    public static let activeID = "active"
    public static let successorID = "successor"

    /// Development pins compiled into the binary. Not Ed25519; same rotation rule.
    public static let active = Data(repeating: 0x0a, count: 32)
    public static let successor = Data(repeating: 0x0b, count: 32)

    public static func key(id: String) -> Data? {
        switch id {
        case activeID: active
        case successorID: successor
        default: nil
        }
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

    public static func sign(_ feed: AdvisoryFeed) throws -> String {
        guard let key = AdvisoryPinnedKeys.key(id: feed.keyID) else {
            throw AdvisoryError.unknownKey
        }
        return HMACSHA256.hex(key: key, message: bytes(feed))
    }

    public static func envelopeJSON(_ feed: AdvisoryFeed) throws -> Data {
        let signature = try sign(feed)
        return Data(
            ("{\"feed\":" + string(feed) + ",\"signature\":" + jsonString(signature) + "}")
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

    public static func parse(_ data: Data, lastSeenSeq: Int, now: Date) throws -> AdvisoryFeed {
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
        guard let key = AdvisoryPinnedKeys.key(id: feed.keyID) else {
            throw AdvisoryError.unknownKey
        }
        let expected = HMACSHA256.hex(key: key, message: AdvisoryCanonical.bytes(feed))
        guard expected == signature.lowercased() else {
            throw AdvisoryError.badSignature
        }
        guard feed.seq > lastSeenSeq else {
            throw AdvisoryError.rollback
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

    public static func disabledCopy(lastChecked: String) -> String {
        "security advisories are off — last checked \(lastChecked)"
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
