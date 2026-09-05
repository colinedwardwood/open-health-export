import Foundation
import WireFormat

public enum SPKIDigestError: Error, Equatable {
    case malformedDER
    case unexpectedTag(UInt8)
    case truncated
    case indefiniteLength
    case tooDeep
}

/// Extracts the `SubjectPublicKeyInfo` element from an X.509 certificate and hashes it,
/// so a renewal that keeps the same key keeps the same pin.
public enum SPKIDigest {
    /// The full DER encoding (tag + length + content) of the certificate's SubjectPublicKeyInfo.
    public static func subjectPublicKeyInfo(certificateDER: Data) throws -> Data {
        let bytes = [UInt8](certificateDER)
        var top = DERCursor(bytes: bytes, index: 0, end: bytes.count, depth: 0)
        let certificate = try top.readElement(expecting: DERTag.sequence)

        var certificateBody = try top.descend(into: certificate)
        let tbsCertificate = try certificateBody.readElement(expecting: DERTag.sequence)

        var fields = try certificateBody.descend(into: tbsCertificate)
        if fields.peekTag() == DERTag.contextExplicitZero {
            _ = try fields.readElement()
        }
        _ = try fields.readElement(expecting: DERTag.integer)   // serialNumber
        _ = try fields.readElement(expecting: DERTag.sequence)  // signature
        _ = try fields.readElement(expecting: DERTag.sequence)  // issuer
        _ = try fields.readElement(expecting: DERTag.sequence)  // validity
        _ = try fields.readElement(expecting: DERTag.sequence)  // subject
        let spki = try fields.readElement(expecting: DERTag.sequence)

        return Data(bytes[spki.range])
    }

    /// Lowercase hex SHA-256 of `subjectPublicKeyInfo`, with no "sha256:" prefix.
    public static func sha256Hex(certificateDER: Data) throws -> String {
        ContentSHA256.hex(try subjectPublicKeyInfo(certificateDER: certificateDER))
    }
}

extension SPKIDigest: Sendable {}

private enum DERTag {
    static let integer: UInt8 = 0x02
    static let sequence: UInt8 = 0x30
    static let contextExplicitZero: UInt8 = 0xa0
}

private struct DERElement {
    let tag: UInt8
    let range: Range<Int>
    let contentRange: Range<Int>
}

/// Definite-length-only walker over a fixed byte buffer. Every read is bounds checked against
/// `end`, which is the real buffer extent, never a length declared by the input.
private struct DERCursor {
    static let maxDepth = 16

    let bytes: [UInt8]
    var index: Int
    let end: Int
    let depth: Int

    func peekTag() -> UInt8? {
        index < end ? bytes[index] : nil
    }

    func descend(into element: DERElement) throws -> DERCursor {
        guard depth < Self.maxDepth else { throw SPKIDigestError.tooDeep }
        return DERCursor(
            bytes: bytes,
            index: element.contentRange.lowerBound,
            end: element.contentRange.upperBound,
            depth: depth + 1
        )
    }

    mutating func readElement(expecting expected: UInt8? = nil) throws -> DERElement {
        let start = index
        guard index < end else { throw SPKIDigestError.truncated }
        let tag = bytes[index]
        if let expected, tag != expected { throw SPKIDigestError.unexpectedTag(tag) }
        index += 1

        let length = try readLength()
        guard length <= end - index else { throw SPKIDigestError.malformedDER }
        let contentStart = index
        index += length
        return DERElement(tag: tag, range: start..<index, contentRange: contentStart..<index)
    }

    private mutating func readLength() throws -> Int {
        guard index < end else { throw SPKIDigestError.truncated }
        let first = bytes[index]
        index += 1
        guard first & 0x80 != 0 else { return Int(first) }

        let byteCount = Int(first & 0x7f)
        guard byteCount != 0 else { throw SPKIDigestError.indefiniteLength }
        guard byteCount <= 4 else { throw SPKIDigestError.malformedDER }
        guard end - index >= byteCount else { throw SPKIDigestError.truncated }

        // Accumulate wide: a four-byte length exceeds Int on a 32-bit target, and a malicious
        // certificate must throw rather than trap.
        var value: UInt64 = 0
        for _ in 0..<byteCount {
            value = (value << 8) | UInt64(bytes[index])
            index += 1
        }
        guard value <= UInt64(end - index) else { throw SPKIDigestError.malformedDER }
        return Int(value)
    }
}
