// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import WidgetKit

@main
struct StatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExportStatusWidget()
        ExportNowControl()
    }
}
