// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-12: stored secrets render as a mask plus length, apparent type, and date.
/// The descriptor never includes the secret itself.
public struct StoredCredentialDescriptor: Sendable, Equatable, Codable {
    public enum Appearance: String, Sendable, Equatable, Codable {
        case bearerToken = "bearer token"
        case password
        case pkcs12Password = "PKCS#12 password"
        case absent
    }

    public var characterCount: Int
    public var appearance: Appearance
    public var addedOnDay: String?

    public init(characterCount: Int, appearance: Appearance, addedOnDay: String?) {
        self.characterCount = characterCount
        self.appearance = appearance
        self.addedOnDay = addedOnDay
    }

    public static func capturing(
        _ secret: String?,
        appearance: Appearance,
        addedOnDay: String
    ) -> StoredCredentialDescriptor {
        guard let secret, !secret.isEmpty else {
            return StoredCredentialDescriptor(
                characterCount: 0,
                appearance: .absent,
                addedOnDay: nil
            )
        }
        return StoredCredentialDescriptor(
            characterCount: secret.count,
            appearance: appearance,
            addedOnDay: day(fromISO8601: addedOnDay)
        )
    }

    public var summary: String {
        switch appearance {
        case .absent:
            return "No saved credential."
        case .bearerToken, .password, .pkcs12Password:
            let count = characterCount == 1 ? "1 character" : "\(characterCount) characters"
            if let addedOnDay, !addedOnDay.isEmpty {
                return "•••• \(count) · \(appearance.rawValue) · added \(addedOnDay)"
            }
            return "•••• \(count) · \(appearance.rawValue)"
        }
    }

    public static func day(fromISO8601 timestamp: String) -> String {
        let day = String(timestamp.prefix(10))
        return day.count == 10 ? day : timestamp
    }
}
