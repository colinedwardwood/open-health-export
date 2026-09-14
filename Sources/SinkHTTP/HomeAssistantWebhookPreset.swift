// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum HomeAssistantWebhookPresetError: Error, Equatable, LocalizedError {
    case invalidBaseURL
    case invalidWebhookID

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter a valid Home Assistant HTTP or HTTPS base URL without credentials, a query, or a fragment."
        case .invalidWebhookID:
            "Enter the webhook ID from Home Assistant. It may contain letters, numbers, hyphens, and underscores."
        }
    }
}

/// Home Assistant's bounded HTTPS preset: the app sends its complete native
/// NDJSON feed to a webhook automation rather than pretending the state API can
/// import or backdate an archive.
public enum HomeAssistantWebhookPreset {
    public static func endpoint(
        baseURLString: String,
        webhookID: String
    ) throws -> URL {
        guard var components = URLComponents(string: baseURLString),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw HomeAssistantWebhookPresetError.invalidBaseURL
        }
        let id = webhookID.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        guard !id.isEmpty,
              id.unicodeScalars.allSatisfy(allowed.contains)
        else {
            throw HomeAssistantWebhookPresetError.invalidWebhookID
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path + "/api/webhook/" + id
        guard let url = components.url else {
            throw HomeAssistantWebhookPresetError.invalidBaseURL
        }
        return url
    }

    /// Removes the credential-bearing webhook path before configuration export
    /// or persistence.
    public static func baseURL(from endpoint: URL) throws -> URL {
        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw HomeAssistantWebhookPresetError.invalidBaseURL
        }
        var segments = components.percentEncodedPath.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard segments.count >= 3,
              segments[segments.count - 3] == "api",
              segments[segments.count - 2] == "webhook"
        else {
            throw HomeAssistantWebhookPresetError.invalidBaseURL
        }
        segments.removeLast(3)
        components.percentEncodedPath =
            segments.isEmpty ? "" : "/" + segments.joined(separator: "/")
        guard let baseURL = components.url else {
            throw HomeAssistantWebhookPresetError.invalidBaseURL
        }
        return baseURL
    }
}
