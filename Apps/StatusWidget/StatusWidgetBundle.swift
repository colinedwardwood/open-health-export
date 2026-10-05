// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import SwiftUI
import WidgetKit

@main
struct StatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        ExportStatusWidget()
        ExportNowControl()
        #if canImport(ActivityKit) && os(iOS)
        ArchiveLiveActivityWidget()
        #endif
    }
}
