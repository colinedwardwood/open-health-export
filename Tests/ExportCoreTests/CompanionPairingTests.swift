// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import Foundation
import Testing

private let zeroSecretBytes = [UInt8](repeating: 0, count: 32)
private let mixedSecretBytes = (0..<32).map { UInt8(truncatingIfNeeded: $0 * 7 + 3) }

private func zeroSecret() throws -> PairingSecret {
    try PairingSecret(bytes: zeroSecretBytes)
}

private func mixedSecret() throws -> PairingSecret {
    try PairingSecret(bytes: mixedSecretBytes)
}

private func samplePayload() throws -> PairingPayload {
    try PairingPayload(
        macInstallationID: "mac-9F2C",
        secret: mixedSecret(),
        serviceName: "Colin's Mac._ohe-companion._tcp"
    )
}

@Test func pairingPayloadRoundTripsExactly() throws {
    let payload = try samplePayload()
    let text = payload.encoded()
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(lines.count == 4)
    #expect(lines[0] == "ohe.pair/1")
    #expect(lines[1] == "mac-9F2C")
    #expect(lines[3] == "Colin's Mac._ohe-companion._tcp")
    #expect(!lines[2].contains("="))
    #expect(!lines[2].contains("+"))
    #expect(!lines[2].contains("/"))
    #expect(try PairingPayload.parse(text) == payload)
    #expect(try PairingPayload.parse(text).encoded() == text)
}

@Test func pairingPayloadRejectsBadVersionLine() throws {
    let secretLine = try samplePayload().encoded()
        .split(separator: "\n", omittingEmptySubsequences: false)[2]
    for version in ["ohe.pair/2", "ohe.pair/1 ", "", "OHE.PAIR/1"] {
        let text = "\(version)\nmac\n\(secretLine)\nservice"
        #expect(throws: PairingError.payloadVersion) { try PairingPayload.parse(text) }
    }
}

@Test func pairingPayloadRejectsWrongLineCount() throws {
    let payload = try samplePayload()
    let text = payload.encoded()
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    #expect(throws: PairingError.payloadShape) {
        try PairingPayload.parse(lines.prefix(3).joined(separator: "\n"))
    }
    #expect(throws: PairingError.payloadShape) {
        try PairingPayload.parse(text + "\nextra")
    }
    #expect(throws: PairingError.payloadShape) {
        try PairingPayload.parse(text + "\n")
    }
    #expect(throws: PairingError.payloadShape) {
        try PairingPayload.parse("ohe.pair/1")
    }
}

@Test func pairingPayloadRejectsNonBase64URLSecret() throws {
    let standard = Data(mixedSecretBytes).base64EncodedString()
    #expect(standard.contains("="))
    let plusFlavour = standard.replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "-", with: "+")
    for secretLine in [standard, "+" + plusFlavour.dropFirst(), "a/b", "not base64url!", "…"] {
        let text = "ohe.pair/1\nmac\n\(secretLine)\nservice"
        #expect(throws: PairingError.base64) { try PairingPayload.parse(text) }
    }
}

@Test func pairingPayloadRejectsSecretOfWrongLength() throws {
    for count in [0, 1, 31, 33, 64] {
        let bytes = [UInt8](repeating: 0xAB, count: count)
        let line = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let text = "ohe.pair/1\nmac\n\(line)\nservice"
        #expect(throws: count == 0 ? PairingError.base64 : PairingError.secretLength) {
            try PairingPayload.parse(text)
        }
    }
}

@Test func pairingPayloadRejectsEmptyField() throws {
    let secretLine = try samplePayload().encoded()
        .split(separator: "\n", omittingEmptySubsequences: false)[2]
    #expect(throws: PairingError.emptyField) {
        try PairingPayload.parse("ohe.pair/1\n\n\(secretLine)\nservice")
    }
    #expect(throws: PairingError.emptyField) {
        try PairingPayload.parse("ohe.pair/1\nmac\n\(secretLine)\n")
    }
    #expect(throws: PairingError.emptyField) {
        try PairingPayload(macInstallationID: "", secret: mixedSecret(), serviceName: "service")
    }
}

@Test func pairingPayloadRejectsOverLongField() throws {
    let secretLine = try samplePayload().encoded()
        .split(separator: "\n", omittingEmptySubsequences: false)[2]
    let long = String(repeating: "m", count: 256)
    let atLimit = String(repeating: "m", count: 255)
    #expect(throws: PairingError.fieldTooLong) {
        try PairingPayload.parse("ohe.pair/1\n\(long)\n\(secretLine)\nservice")
    }
    #expect(throws: PairingError.fieldTooLong) {
        try PairingPayload.parse("ohe.pair/1\nmac\n\(secretLine)\n\(long)")
    }
    // 255 UTF-8 bytes is the cap, not 255 Characters.
    #expect(throws: PairingError.fieldTooLong) {
        try PairingPayload.parse("ohe.pair/1\nmac\n\(secretLine)\n\(String(repeating: "é", count: 128))")
    }
    let accepted = try PairingPayload.parse("ohe.pair/1\n\(atLimit)\n\(secretLine)\nservice")
    #expect(accepted.macInstallationID == atLimit)
}

@Test func pairingSecretRejectsWrongLength() throws {
    for count in [0, 1, 16, 31, 33, 64] {
        #expect(throws: PairingError.secretLength) {
            try PairingSecret(bytes: [UInt8](repeating: 1, count: count))
        }
    }
    #expect(try PairingSecret(bytes: zeroSecretBytes) == (try PairingSecret(bytes: zeroSecretBytes)))
    #expect(try PairingSecret(bytes: zeroSecretBytes) != (try mixedSecret()))
}

@Test func pairingSecretGenerateIsDeterministicForFixedByteSource() throws {
    let source: (Int) -> [UInt8] = { count in (0..<count).map { UInt8(truncatingIfNeeded: $0 * 7 + 3) } }
    let first = try PairingSecret.generate(random: source)
    let second = try PairingSecret.generate(random: source)
    #expect(first == second)
    #expect(first == (try mixedSecret()))
    #expect(first.digestHex == (try mixedSecret()).digestHex)
    #expect(first.digestHex.count == 64)
    #expect(throws: PairingError.secretLength) {
        try PairingSecret.generate(random: { count in [UInt8](repeating: 0, count: count - 1) })
    }
}

@Test func pairingSecretNeverPrintsKeyMaterial() throws {
    let secret = try mixedSecret()
    let payload = try PairingPayload(macInstallationID: "mac", secret: secret, serviceName: "service")
    let base64URL = String(payload.encoded().split(separator: "\n", omittingEmptySubsequences: false)[2])
    let rendered = [String(describing: secret), String(reflecting: secret)]
    for text in rendered {
        #expect(text == "PairingSecret(redacted)")
        #expect(!text.contains(base64URL))
        #expect(!text.contains(secret.digestHex))
        for byte in mixedSecretBytes {
            #expect(!text.contains(String(byte)))
        }
        #expect(!text.contains(where: { $0.isNumber }))
    }
    #expect(String(describing: [secret]).contains("PairingSecret(redacted)"))
}

@Test func pairingConfirmationCodeIsGolden() throws {
    let ids = ("mac-9F2C", "phone-1A7B")
    #expect(PairingConfirmation.confirmationCode(secret: try zeroSecret(), installationIDs: ids) == "V8ZY-HNJ0")
    #expect(PairingConfirmation.confirmationCode(secret: try mixedSecret(), installationIDs: ids) == "RPY5-BRGD")
}

@Test func pairingConfirmationCodeIgnoresArgumentOrder() throws {
    let secret = try mixedSecret()
    let forward = PairingConfirmation.confirmationCode(secret: secret, installationIDs: ("mac-9F2C", "phone-1A7B"))
    let reverse = PairingConfirmation.confirmationCode(secret: secret, installationIDs: ("phone-1A7B", "mac-9F2C"))
    #expect(forward == reverse)
}

@Test func pairingConfirmationCodeChangesWithEitherInstallationID() throws {
    let secret = try mixedSecret()
    let base = PairingConfirmation.confirmationCode(secret: secret, installationIDs: ("mac-9F2C", "phone-1A7B"))
    #expect(PairingConfirmation.confirmationCode(secret: secret, installationIDs: ("mac-9F2D", "phone-1A7B")) != base)
    #expect(PairingConfirmation.confirmationCode(secret: secret, installationIDs: ("mac-9F2C", "phone-1A7C")) != base)
    // Length prefixes make concatenation unambiguous.
    #expect(PairingConfirmation.confirmationCode(secret: secret, installationIDs: ("mac-9F2Cp", "hone-1A7B")) != base)
}

@Test func pairingConfirmationCodeChangesWhenOneSecretBitFlips() throws {
    let ids = ("mac-9F2C", "phone-1A7B")
    let base = PairingConfirmation.confirmationCode(secret: try zeroSecret(), installationIDs: ids)
    for index in [0, 7, 31] {
        var bytes = zeroSecretBytes
        bytes[index] ^= 0x01
        let flipped = try PairingSecret(bytes: bytes)
        #expect(PairingConfirmation.confirmationCode(secret: flipped, installationIDs: ids) != base)
    }
}

@Test func pairingConfirmationCodeUsesUnambiguousAlphabet() throws {
    let pattern = try NSRegularExpression(pattern: "^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$")
    for seed in 0..<128 {
        let bytes = (0..<32).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ seed) }
        let code = PairingConfirmation.confirmationCode(
            secret: try PairingSecret(bytes: bytes),
            installationIDs: ("mac-\(seed)", "phone-\(seed)")
        )
        #expect(code.count == 9)
        let range = NSRange(code.startIndex..<code.endIndex, in: code)
        if pattern.firstMatch(in: code, range: range) == nil {
            Issue.record("code \(code) is outside the Crockford base32 alphabet")
        }
        for glyph in ["I", "L", "O", "U"] {
            #expect(!code.contains(glyph))
        }
    }
}

@Test func phoneHasSASImmediatelyAndMacMatchesAfterHello() throws {
    let payload = try samplePayload()
    let phone = PairingSession.phone(payload: payload, localInstallationID: "phone-1A7B")
    #expect(phone.confirmationCode == "RPY5-BRGD")
    var mac = PairingSession.mac(
        secret: payload.secret,
        localInstallationID: "mac-9F2C",
        serviceName: payload.serviceName
    )
    #expect(mac.confirmationCode == nil)
    let shown = mac.notePeer("phone-1A7B")
    #expect(shown == phone.confirmationCode)
    #expect(shown == "RPY5-BRGD")
}

@Test func helloTurnNamesThePeer() throws {
    var receiver = CompanionReceiver(installationID: "mac-9F2C")
    let turn = receiver.process(.hello(
        protocolVersion: 1,
        installationID: "phone-1A7B",
        capabilities: CompanionReceiver.capabilities
    ))
    #expect(turn.peerInstallationID == "phone-1A7B")
    guard case .hello(_, let repliedAs, _) = turn.replies.first else {
        Issue.record("expected hello reply")
        return
    }
    #expect(repliedAs == "mac-9F2C")
}
