// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// UX-11: URL and secret fields strip padding, flatten curly quotes, and show a
/// live parse-back of URL pieces before a destination test runs.
public struct CredentialFieldHygiene: Sendable, Equatable {
    public var normalized: String
    public var strippedWhitespace: Bool
    public var replacedSmartPunctuation: Bool
    public var parseBack: String?

    public static let whitespaceNote = "Leading or trailing spaces were removed."
    public static let smartPunctuationNote =
        "Curly quotes were replaced with plain quotes."

    public static func url(_ raw: String) -> CredentialFieldHygiene {
        let parts = normalize(raw)
        return CredentialFieldHygiene(
            normalized: parts.text,
            strippedWhitespace: parts.strippedWhitespace,
            replacedSmartPunctuation: parts.replacedSmartPunctuation,
            parseBack: parseBack(for: parts.text)
        )
    }

    public static func secret(_ raw: String) -> CredentialFieldHygiene {
        let parts = normalize(raw)
        return CredentialFieldHygiene(
            normalized: parts.text,
            strippedWhitespace: parts.strippedWhitespace,
            replacedSmartPunctuation: parts.replacedSmartPunctuation,
            parseBack: nil
        )
    }

    private static func normalize(_ raw: String) -> (
        text: String,
        strippedWhitespace: Bool,
        replacedSmartPunctuation: Bool
    ) {
        let withoutSmartQuotes = raw
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
        let replacedSmartPunctuation = withoutSmartQuotes != raw
        let spaced = withoutSmartQuotes.replacingOccurrences(of: "\u{00A0}", with: " ")
        let trimmed = spaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            text: trimmed,
            strippedWhitespace: trimmed != withoutSmartQuotes,
            replacedSmartPunctuation: replacedSmartPunctuation
        )
    }

    private static func parseBack(for text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let components = URLComponents(string: text),
              let scheme = components.scheme,
              let host = components.host,
              !scheme.isEmpty,
              !host.isEmpty
        else {
            return "Not a usable URL yet."
        }
        var parts = ["scheme \(scheme)", "host \(host)"]
        if let port = components.port {
            parts.append("port \(port)")
        }
        if !components.path.isEmpty {
            parts.append("path \(components.path)")
        }
        return parts.joined(separator: " · ")
    }
}
