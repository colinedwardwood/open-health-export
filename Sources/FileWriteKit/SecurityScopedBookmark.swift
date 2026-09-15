// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Darwin)
import Foundation

public enum SecurityScopedBookmarkError: Error, Equatable {
    case accessDenied
}

public struct ResolvedSecurityScopedBookmark: Sendable {
    public let url: URL
    public let isStale: Bool
}

public final class SecurityScopedAccess: @unchecked Sendable {
    public let url: URL
    private let active: Bool

    public init(url: URL) throws {
        let active = url.startAccessingSecurityScopedResource()
        guard active else {
            throw SecurityScopedBookmarkError.accessDenied
        }
        self.url = url
        self.active = active
    }

    private init(url: URL, active: Bool) {
        self.url = url
        self.active = active
    }

    #if DEBUG
    /// A folder the app already owns has no security scope to start, so the real
    /// initializer refuses it. UI tests cannot drive the Files picker, which is the only
    /// way to obtain a scoped folder, so a seeded archive folder inside the app container
    /// needs this. R-83 keeps it out of release builds.
    public static func unscoped(url: URL) -> SecurityScopedAccess {
        SecurityScopedAccess(url: url, active: false)
    }
    #endif

    deinit {
        if active {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

public enum SecurityScopedBookmark {
    public static func create(from pickedURL: URL) throws -> Data {
        let access = try SecurityScopedAccess(url: pickedURL)
        return try create(fromAccessibleURL: access.url)
    }

    public static func create(fromAccessibleURL url: URL) throws -> Data {
        try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public static func resolve(_ data: Data) throws -> ResolvedSecurityScopedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedSecurityScopedBookmark(url: url, isStale: isStale)
    }
}
#endif
