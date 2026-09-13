// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Watchdog
import WidgetKit

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

struct ArchiveLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ArchiveLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                Label(ArchiveLiveActivity.title, systemImage: ArchiveLiveActivity.glyph)
                    .font(.headline)
                Text(context.state.progressLine)
                    .font(.caption)
            }
            .padding()
            .privacySensitive()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ArchiveLiveActivity.title, systemImage: ArchiveLiveActivity.glyph)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.progressLine)
                }
            } compactLeading: {
                Image(systemName: ArchiveLiveActivity.glyph)
            } compactTrailing: {
                Text("\(context.state.completedMonths)/\(context.state.totalMonths)")
            } minimal: {
                Image(systemName: ArchiveLiveActivity.glyph)
            }
        }
    }
}
#endif
