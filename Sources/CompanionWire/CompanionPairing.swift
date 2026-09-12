// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import WireFormat

public enum PairingError: Error, Equatable, LocalizedError {
    case secretLength
    case payloadVersion
    case payloadShape
    case emptyField
    case fieldTooLong
    case base64

    public var errorDescription: String? {
        switch self {
        case .secretLength, .payloadVersion, .payloadShape, .emptyField, .fieldTooLong, .base64:
            "This pairing code is not valid."
        }
    }
}

/// Pre-shared 32-byte key material for the companion TLS-PSK handshake.
public struct PairingSecret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let byteCount = 32

    private let key: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else { throw PairingError.secretLength }
        key = bytes
    }

    /// Randomness is injected so the core stays deterministic (DP-7).
    public static func generate(random: (Int) -> [UInt8]) throws -> PairingSecret {
        try PairingSecret(bytes: random(byteCount))
    }

    public static func generateFromSystemRandomness() throws -> PairingSecret {
        var generator = SystemRandomNumberGenerator()
        return try generate(random: { count in
            (0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        })
    }

    public var digestHex: String {
        ContentSHA256.hex(Data(key))
    }

    /// Scoped access for the one caller that needs the raw key: building the TLS-PSK.
    /// There is deliberately no stored-copy accessor and no string form of the key.
    public func withKeyBytes<T>(_ body: ([UInt8]) throws -> T) rethrows -> T {
        try body(key)
    }

    public var description: String { "PairingSecret(redacted)" }

    public var debugDescription: String { "PairingSecret(redacted)" }

    var keyBytes: [UInt8] { key }

    var base64URL: String { PairingBase64URL.encode(key) }
}

/// Newline-delimited QR text. Deliberately not a URL so no URL parser is in the trust path.
public struct PairingPayload: Sendable, Equatable {
    public static let version = "ohe.pair/1"
    public static let maxFieldBytes = 255

    public let macInstallationID: String
    public let secret: PairingSecret
    public let serviceName: String

    public init(macInstallationID: String, secret: PairingSecret, serviceName: String) throws {
        self.macInstallationID = try Self.validated(macInstallationID)
        self.secret = secret
        self.serviceName = try Self.validated(serviceName)
    }

    public func encoded() -> String {
        [Self.version, macInstallationID, secret.base64URL, serviceName].joined(separator: "\n")
    }

    public static func parse(_ text: String) throws -> PairingPayload {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count == 4 else { throw PairingError.payloadShape }
        guard lines[0] == version else { throw PairingError.payloadVersion }
        let macInstallationID = try validated(lines[1])
        let serviceName = try validated(lines[3])
        let bytes = try PairingBase64URL.decode(lines[2])
        guard bytes.count == PairingSecret.byteCount else { throw PairingError.secretLength }
        return try PairingPayload(
            macInstallationID: macInstallationID,
            secret: PairingSecret(bytes: bytes),
            serviceName: serviceName
        )
    }

    private static func validated(_ field: String) throws -> String {
        guard !field.isEmpty else { throw PairingError.emptyField }
        guard field.utf8.count <= maxFieldBytes else { throw PairingError.fieldTooLong }
        guard !field.contains("\n") else { throw PairingError.payloadShape }
        return field
    }
}

/// Short authentication string the user compares across both screens.
public enum PairingConfirmation {
    public static let domainTag = "ohe.pair/1 sas"
    public static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func confirmationCode(secret: PairingSecret, installationIDs: (String, String)) -> String {
        var input = Data(domainTag.utf8)
        input.append(contentsOf: secret.keyBytes)
        // Ordered by UTF-8 bytes rather than String `<` so both platforms agree on the pair order.
        let first = Array(installationIDs.0.utf8)
        let second = Array(installationIDs.1.utf8)
        let ordered = first.lexicographicallyPrecedes(second) ? [first, second] : [second, first]
        for id in ordered {
            input.append(contentsOf: CompanionBinary.u32(UInt32(id.count)))
            input.append(contentsOf: id)
        }
        // 32 divides 256, so masking the low 5 bits is uniform over the alphabet.
        let glyphs = ContentSHA256.bytes(input).prefix(8).map { alphabet[Int($0 & 0x1F)] }
        return String(glyphs.prefix(4)) + "-" + String(glyphs.suffix(4))
    }
}

enum PairingBase64URL {
    static func encode(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) throws -> [UInt8] {
        guard !text.isEmpty else { throw PairingError.base64 }
        for scalar in text.unicodeScalars {
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "-", "_": continue
            default: throw PairingError.base64
            }
        }
        var standard = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while standard.utf8.count % 4 != 0 {
            standard.append("=")
        }
        guard let data = Data(base64Encoded: standard) else { throw PairingError.base64 }
        return [UInt8](data)
    }
}
