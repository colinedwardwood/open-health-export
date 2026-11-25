// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import DestinationTrust
import Foundation
import MetricCatalog
import Observation

/// #47: add a Files destination. Pick a folder, run its test with each step shown, and
/// save only once the test has passed. Also used by "Test again" on the detail screen.
@MainActor
@Observable
final class FilesSetupModel {
    private(set) var folderName: String?
    private(set) var checklist = DestinationTestChecklist.localFile
    private(set) var error: UserFacingErrorObject?

    @ObservationIgnored private let services: AppEnvironment

    init(services: AppEnvironment = .live) {
        self.services = services
        folderName = services.destinations.localExportFolderName()
    }

    var canSave: Bool { checklist.passed }
    var testing: Bool { checklist.running }

    func useFolder(_ url: URL) async {
        do {
            folderName = try services.destinations.chooseLocalExportFolder(url)
        } catch {
            self.error = UserFacingFailure.object(for: error, destinationLabel: "the folder")
            return
        }
        await runTest()
    }

    #if DEBUG
    /// UI tests can't drive the Files folder picker; they get a seeded folder.
    func useSeededFolder() async {
        folderName = try? HarnessExport.seedLocalExportFolderForUITests()
        await runTest()
    }
    #endif

    /// Writes a test file, reads it back and checks it. Enabling is the same call: the
    /// folder is only enabled when every step passes.
    func runTest() async {
        error = nil
        checklist.reset()
        checklist.start(.openFolder)
        do {
            try await ensureScope()
            _ = try await AppDestinationSetup.enableLocalFile { _, _, step in
                Task { @MainActor in self.checklist.start(step) }
            }
            checklist.finish(failedAt: nil)
            // The person set this folder up just now; that is not a change to review.
            try? services.status.acknowledgeDestinationChanges()
            AppLifecycleCoordinator.shared.stopObservers()
            try? await AppLifecycleCoordinator.shared.startObserversIfEligible()
        } catch let SetupError.testFailed(step) {
            checklist.finish(failedAt: step)
            error = UserFacingErrorObject.make(archetype: .unexpected, destinationLabel: folderName ?? "the folder")
        } catch {
            let running = checklist.steps.first { $0.state == .running }?.step
            checklist.finish(failedAt: running ?? .openFolder)
            self.error = UserFacingFailure.object(for: error, destinationLabel: folderName ?? "the folder")
        }
    }

    /// A new folder starts with the everyday types from the last seven days, the same
    /// as first run; a folder that already has types keeps them.
    private func ensureScope() async throws {
        let existing = try await services.destinations.scope("local-file")
        guard !existing.isConfigured else { return }
        let scope = try DestinationExportScope(
            destinationID: "local-file",
            metrics: Set(MetricCatalog.coreDaily.map(\.id)),
            startInclusive: OnboardingPlan.defaultScopeStart(now: Date(), calendar: .current)
        )
        try await services.destinations.applyScope(scope, previousMetrics: [])
    }
}
