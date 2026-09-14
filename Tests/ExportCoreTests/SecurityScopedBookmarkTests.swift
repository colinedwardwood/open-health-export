// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(Darwin)
import FileWriteKit
import Foundation
import Testing

@Test func securityScopedBookmarkRoundTripsASelectedFolder() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ohe-bookmark-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let data = try SecurityScopedBookmark.create(fromAccessibleURL: folder)
    let resolved = try SecurityScopedBookmark.resolve(data)

    #expect(resolved.url.standardizedFileURL == folder.standardizedFileURL)
    #expect(!resolved.isStale)
}

@Test func malformedSecurityScopedBookmarkFailsClosed() {
    #expect(throws: (any Error).self) {
        _ = try SecurityScopedBookmark.resolve(Data("not-a-bookmark".utf8))
    }
}
#endif
