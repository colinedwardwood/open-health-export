// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SinkHTTP
import Testing

@Test func homeAssistantWebhookPresetBuildsTheNativeFeedEndpoint() throws {
    let endpoint = try HomeAssistantWebhookPreset.endpoint(
        baseURLString: "https://home.example/",
        webhookID: "ohe_123-abc"
    )
    #expect(endpoint.absoluteString == "https://home.example/api/webhook/ohe_123-abc")
}

@Test func homeAssistantWebhookPresetKeepsReverseProxyBasePaths() throws {
    let endpoint = try HomeAssistantWebhookPreset.endpoint(
        baseURLString: "https://example.test/home-assistant",
        webhookID: "feed"
    )
    #expect(
        endpoint.absoluteString
            == "https://example.test/home-assistant/api/webhook/feed"
    )
    let persisted = try HomeAssistantWebhookPreset.baseURL(from: endpoint)
    #expect(persisted.absoluteString == "https://example.test/home-assistant")
    #expect(!persisted.absoluteString.contains("feed"))
}

@Test func homeAssistantWebhookPresetRejectsCredentialsAndPathEscapes() {
    #expect(throws: HomeAssistantWebhookPresetError.invalidBaseURL) {
        _ = try HomeAssistantWebhookPreset.endpoint(
            baseURLString: "https://token@example.test",
            webhookID: "feed"
        )
    }
    #expect(throws: HomeAssistantWebhookPresetError.invalidWebhookID) {
        _ = try HomeAssistantWebhookPreset.endpoint(
            baseURLString: "https://example.test",
            webhookID: "../feed"
        )
    }
}
