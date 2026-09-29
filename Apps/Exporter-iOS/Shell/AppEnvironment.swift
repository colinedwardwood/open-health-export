// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import SwiftUI

/// The services product screens use, injected through the environment so a preview
/// or a test can hand a screen something other than the live app (#43).
struct AppEnvironment: Sendable {
    var status: StatusService
    var history: HistoryService
    var destinations: DestinationRepository
    var advisory: AdvisoryService
    var export: ExportService
    var health: HealthService

    static let live = AppEnvironment(
        status: AppStatus.status,
        history: AppStatus.history,
        destinations: AppDestinations.repository,
        advisory: AppAdvisory.service,
        export: AppExport.service,
        health: AppHealth.service
    )
}

extension EnvironmentValues {
    @Entry var services: AppEnvironment = .live
}
