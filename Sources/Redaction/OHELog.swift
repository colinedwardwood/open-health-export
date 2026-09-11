// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(os)
import os
#endif

/// R-50: first-party logs go through `os.Logger`, never a swift-log facade.
public enum OHELog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "app.openhealthexporter", category: "core")
    #endif

    public static func notice(_ publicText: String) {
        #if canImport(os)
        logger.notice("\(publicText, privacy: .public)")
        #else
        _ = publicText
        #endif
    }

    public static func sensitive(_ publicText: String, privateText: String) {
        #if canImport(os)
        logger.notice("\(publicText, privacy: .public) \(privateText, privacy: .private)")
        #else
        _ = publicText
        _ = privateText
        #endif
    }
}
