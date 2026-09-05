import Foundation
import NetEgress
import Testing
import WireFormat

// MARK: - Test-only DER builder

private enum SPKIFixture {
    static func element(_ tag: UInt8, _ content: Data) -> Data {
        var out = Data([tag])
        let count = content.count
        if count < 0x80 {
            out.append(UInt8(count))
        } else if count <= 0xff {
            out.append(0x81)
            out.append(UInt8(count))
        } else {
            out.append(0x82)
            out.append(UInt8((count >> 8) & 0xff))
            out.append(UInt8(count & 0xff))
        }
        out.append(content)
        return out
    }

    static func sequence(_ parts: [Data]) -> Data {
        element(0x30, parts.reduce(into: Data()) { $0.append($1) })
    }

    static func integer(_ bytes: [UInt8]) -> Data { element(0x02, Data(bytes)) }
    static func bitString(_ bytes: [UInt8]) -> Data { element(0x03, Data([0x00] + bytes)) }
    static func oid(_ bytes: [UInt8]) -> Data { element(0x06, Data(bytes)) }
    static func utcTime(_ text: String) -> Data { element(0x17, Data(text.utf8)) }

    static let ecPublicKey: [UInt8] = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]
    static let prime256v1: [UInt8] = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]
    static let ecdsaWithSHA256: [UInt8] = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02]

    static let defaultKeyBits: [UInt8] = Array(repeating: 0xab, count: 64)

    static func spki(keyBits: [UInt8] = defaultKeyBits) -> Data {
        sequence([
            sequence([oid(ecPublicKey), oid(prime256v1)]),
            bitString(keyBits),
        ])
    }

    static func name(_ commonName: String) -> Data {
        sequence([
            element(0x31, sequence([oid([0x55, 0x04, 0x03]), element(0x0c, Data(commonName.utf8))])),
        ])
    }

    static func validity(notBefore: String = "240101000000Z", notAfter: String = "250101000000Z") -> Data {
        sequence([utcTime(notBefore), utcTime(notAfter)])
    }

    /// Builds a certificate. `includeVersion` selects the v3 shape (explicit `[0]` element)
    /// versus the v1 shape where that element is absent.
    static func certificate(
        includeVersion: Bool = true,
        serial: [UInt8] = [0x01],
        validity validityElement: Data = validity(),
        spki spkiElement: Data = spki(),
        includeSPKI: Bool = true
    ) -> Data {
        var fields: [Data] = []
        if includeVersion {
            fields.append(element(0xa0, integer([0x02])))
        }
        fields.append(integer(serial))
        fields.append(sequence([oid(ecdsaWithSHA256)]))
        fields.append(name("Example CA"))
        fields.append(validityElement)
        fields.append(name("ha.example"))
        if includeSPKI {
            fields.append(spkiElement)
            fields.append(element(0xa3, sequence([sequence([oid([0x55, 0x1d, 0x13]), element(0x04, Data([0x30, 0x00]))])])))
        }
        return sequence([
            sequence(fields),
            sequence([oid(ecdsaWithSHA256)]),
            bitString(Array(repeating: 0x5a, count: 70)),
        ])
    }
}

private func isLowercaseHex(_ text: String) -> Bool {
    text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
}

// MARK: - Happy paths

@Test func v3CertificateYieldsExactSPKIElementBytes() throws {
    let spki = SPKIFixture.spki()
    let certificate = SPKIFixture.certificate(spki: spki)

    let extracted = try SPKIDigest.subjectPublicKeyInfo(certificateDER: certificate)
    #expect(extracted == spki)
    #expect(extracted.first == 0x30)
}

@Test func sha256HexMatchesContentSHA256OfSPKI() throws {
    let spki = SPKIFixture.spki()
    let certificate = SPKIFixture.certificate(spki: spki)

    let hex = try SPKIDigest.sha256Hex(certificateDER: certificate)
    #expect(hex == ContentSHA256.hex(spki))
    #expect(hex.count == 64)
    #expect(isLowercaseHex(hex))
    #expect(!hex.hasPrefix("sha256:"))
}

@Test func v1CertificateWithoutVersionElementYieldsSPKI() throws {
    let spki = SPKIFixture.spki(keyBits: Array(repeating: 0x11, count: 64))
    let certificate = SPKIFixture.certificate(includeVersion: false, spki: spki)

    #expect(try SPKIDigest.subjectPublicKeyInfo(certificateDER: certificate) == spki)
    #expect(try SPKIDigest.sha256Hex(certificateDER: certificate) == ContentSHA256.hex(spki))
}

@Test func differentKeyBitsProduceDifferentDigest() throws {
    let a = SPKIFixture.certificate(spki: SPKIFixture.spki(keyBits: Array(repeating: 0x01, count: 64)))
    let b = SPKIFixture.certificate(spki: SPKIFixture.spki(keyBits: Array(repeating: 0x02, count: 64)))

    #expect(try SPKIDigest.sha256Hex(certificateDER: a) != SPKIDigest.sha256Hex(certificateDER: b))
}

@Test func renewalWithNewSerialAndValidityKeepsSameDigest() throws {
    let key = SPKIFixture.spki(keyBits: Array(repeating: 0x7e, count: 64))
    let original = SPKIFixture.certificate(
        serial: [0x01],
        validity: SPKIFixture.validity(notBefore: "240101000000Z", notAfter: "250101000000Z"),
        spki: key
    )
    let renewed = SPKIFixture.certificate(
        serial: [0x0a, 0xbc, 0xde],
        validity: SPKIFixture.validity(notBefore: "250101000000Z", notAfter: "260101000000Z"),
        spki: key
    )

    #expect(original != renewed)
    #expect(try SPKIDigest.sha256Hex(certificateDER: original) == SPKIDigest.sha256Hex(certificateDER: renewed))
}

@Test func trailingBytesAfterCertificateAreIgnored() throws {
    let spki = SPKIFixture.spki()
    var certificate = SPKIFixture.certificate(spki: spki)
    certificate.append(contentsOf: [0xde, 0xad, 0xbe, 0xef])

    #expect(try SPKIDigest.subjectPublicKeyInfo(certificateDER: certificate) == spki)
}

// MARK: - Rejection paths

@Test func emptyInputIsTruncated() {
    #expect(throws: SPKIDigestError.truncated) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: Data())
    }
}

@Test func singleByteInputIsTruncated() {
    #expect(throws: SPKIDigestError.truncated) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: Data([0x30]))
    }
}

@Test func truncatedOuterSequenceIsMalformed() {
    #expect(throws: SPKIDigestError.malformedDER) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: Data([0x30, 0x82, 0x01, 0x00, 0x30, 0x02]))
    }
}

@Test func indefiniteLengthOuterSequenceIsRejected() {
    #expect(throws: SPKIDigestError.indefiniteLength) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: Data([0x30, 0x80, 0x30, 0x00, 0x00, 0x00]))
    }
}

@Test func fourByteMaxLengthIsMalformed() {
    #expect(throws: SPKIDigestError.malformedDER) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: Data([0x30, 0x84, 0xff, 0xff, 0xff, 0xff, 0x00]))
    }
}

@Test func fiveByteLengthFieldIsMalformed() {
    #expect(throws: SPKIDigestError.malformedDER) {
        _ = try SPKIDigest.subjectPublicKeyInfo(
            certificateDER: Data([0x30, 0x85, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00])
        )
    }
}

@Test func declaredLengthFarBeyondBufferThrowsWithoutAllocating() {
    // Eight bytes claiming two gigabytes of content.
    #expect(throws: SPKIDigestError.malformedDER) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: Data([0x30, 0x84, 0x7f, 0xff, 0xff, 0xff, 0x30, 0x03]))
    }
}

@Test func nonSequenceTopLevelTagIsReported() {
    #expect(throws: SPKIDigestError.unexpectedTag(0x31)) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: Data([0x31, 0x03, 0x02, 0x01, 0x00]))
    }
}

@Test func nonSequenceTBSTagIsReported() {
    let bogus = SPKIFixture.sequence([SPKIFixture.integer([0x01])])
    #expect(throws: SPKIDigestError.unexpectedTag(0x02)) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: bogus)
    }
}

@Test func tbsMissingSeventhElementIsTruncated() {
    let certificate = SPKIFixture.certificate(includeSPKI: false)
    #expect(throws: SPKIDigestError.truncated) {
        _ = try SPKIDigest.subjectPublicKeyInfo(certificateDER: certificate)
    }
}
