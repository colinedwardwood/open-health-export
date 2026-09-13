// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Testing

@Test func credentialFieldHygieneStripsPaddingAndParsesURLPieces() {
    let padded = CredentialFieldHygiene.url(" https://collector.example:8443/upload ")
    #expect(padded.normalized == "https://collector.example:8443/upload")
    #expect(padded.strippedWhitespace)
    #expect(!padded.replacedSmartPunctuation)
    #expect(padded.parseBack == "scheme https · host collector.example · port 8443 · path /upload")

    let smart = CredentialFieldHygiene.url(
        "\u{201C}https://collector.example/upload\u{201D}"
    )
    #expect(smart.replacedSmartPunctuation)
    #expect(smart.normalized == "\"https://collector.example/upload\"")
    #expect(smart.parseBack == "Not a usable URL yet.")

    let secret = CredentialFieldHygiene.secret(" token\n")
    #expect(secret.normalized == "token")
    #expect(secret.strippedWhitespace)
    #expect(secret.parseBack == nil)
}

@Test func credentialFieldHygieneLeavesACleanURLQuiet() {
    let clean = CredentialFieldHygiene.url("https://example.test/v1")
    #expect(!clean.strippedWhitespace)
    #expect(!clean.replacedSmartPunctuation)
    #expect(clean.parseBack == "scheme https · host example.test · path /v1")
}
