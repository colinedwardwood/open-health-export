// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Testing

@Test func storedCredentialDescriptorNeverIncludesTheSecret() {
    let captured = StoredCredentialDescriptor.capturing(
        "super-secret-token",
        appearance: .bearerToken,
        addedOnDay: "2026-09-13T21:00:00Z"
    )
    #expect(captured.characterCount == 18)
    #expect(captured.addedOnDay == "2026-09-13")
    #expect(
        captured.summary
            == "•••• 18 characters · bearer token · added 2026-09-13"
    )
    #expect(!captured.summary.contains("super-secret-token"))

    let webhook = StoredCredentialDescriptor.capturing(
        "secret-webhook-id",
        appearance: .webhookID,
        addedOnDay: "2026-09-14"
    )
    #expect(webhook.summary.contains("webhook ID"))
    #expect(!webhook.summary.contains("secret-webhook-id"))

    let empty = StoredCredentialDescriptor.capturing(
        nil,
        appearance: .password,
        addedOnDay: "2026-09-13T21:00:00Z"
    )
    #expect(empty.appearance == .absent)
    #expect(empty.summary == "No saved credential.")
}
