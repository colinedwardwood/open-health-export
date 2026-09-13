// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// UX-25: the one-shot archive is the only HIG-appropriate Live Activity.
/// Dismissal stays inside the 15–30 minute window; the surface never shows health values.
public enum ArchiveLiveActivity {
    public static let dismissalSeconds: TimeInterval = 20 * 60
    public static let title = "Historical archive"
    public static let finishedCopy = "Archive finished"
    public static let glyph = "archivebox"

    public static func parseProgress(_ line: String) -> (
        completedMonths: Int,
        totalMonths: Int,
        type: Int,
        types: Int
    )? {
        guard line.hasPrefix("Archive month ") else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 10,
              parts[0] == "Archive",
              parts[1] == "month",
              let completed = Int(parts[2]),
              parts[3] == "of",
              let total = Int(parts[4]),
              parts[6] == "type",
              let type = Int(parts[7]),
              parts[8] == "of",
              let types = Int(parts[9])
        else {
            return nil
        }
        return (completed, total, type, types)
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

public struct ArchiveLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var completedMonths: Int
        public var totalMonths: Int
        public var type: Int
        public var types: Int

        public init(completedMonths: Int, totalMonths: Int, type: Int, types: Int) {
            self.completedMonths = completedMonths
            self.totalMonths = totalMonths
            self.type = type
            self.types = types
        }

        public var progressLine: String {
            NamedWorkProgress.archive(
                completedMonths: completedMonths,
                totalMonths: totalMonths,
                type: type,
                types: types
            )
        }
    }

    public init() {}
}
#endif
