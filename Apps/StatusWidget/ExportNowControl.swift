// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppIntents
import SwiftUI
import Watchdog
import WidgetKit

struct ExportNowControl: ControlWidget {
    static let kind = "app.openhealthexporter.exportNow"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(ExportNowRoute().url)) {
                Label("Export now", systemImage: "square.and.arrow.up")
            }
        }
        .displayName("Export now")
        .description("Run one export page to the local archive.")
    }
}
