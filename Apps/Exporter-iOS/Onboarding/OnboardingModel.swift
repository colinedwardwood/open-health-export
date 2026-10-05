// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import EnginePorts
import Foundation
import HealthKitSource
import MetricCatalog
import Observation

/// First run (#45): types, a tested Files destination, the disclosure, Apple's Health
/// sheet and a first export. Each step's work is here; the screens only call it.
@MainActor
@Observable
final class OnboardingModel {
    enum Work: Equatable {
        case idle
        case running(String)
        case failed(String)
    }

    private(set) var step: OnboardingStep
    var selected: Set<MetricID>
    private(set) var folderName: String?
    private(set) var destinationReady = false
    private(set) var work: Work = .idle
    private(set) var exportProgress: Double = 0
    private(set) var exportSummary: String?
    /// The first export ran but Health returned nothing for the chosen types.
    private(set) var nothingCameBack = false
    /// Back on the types screen from an empty first export; continuing saves the new
    /// types and runs the export again.
    private var retyping = false

    let resuming: Bool
    let types: [MetricDeclaration] = MetricCatalog.coreDaily

    @ObservationIgnored private let services: AppEnvironment
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let finish: () -> Void

    init(
        resuming: Bool,
        services: AppEnvironment = .live,
        defaults: UserDefaults = .standard,
        finish: @escaping () -> Void
    ) {
        self.resuming = resuming
        self.services = services
        self.defaults = defaults
        self.finish = finish
        step = OnboardingPlan.steps(resuming: resuming)[0]
        selected = Set(MetricCatalog.coreDaily.map(\.id))
        folderName = services.destinations.localExportFolderName()
    }

    var isWorking: Bool {
        if case .running = work { return true }
        return false
    }

    // MARK: Navigation

    func advance() {
        work = .idle
        if retyping {
            retyping = false
            Task { await saveTypesAndExportAgain() }
            return
        }
        if let next = OnboardingPlan.next(
            after: step,
            resuming: resuming,
            destinationReady: destinationReady
        ) {
            step = next
        } else {
            finish()
        }
    }

    // MARK: Destination

    /// Saves the chosen types as the archive's scope, then runs its write, read and
    /// confirm test. The archive is only enabled once that passes.
    func useFolder(_ url: URL) async {
        do {
            folderName = try services.destinations.chooseLocalExportFolder(url)
        } catch {
            work = .failed("That folder can't be used. Choose another one.")
            return
        }
        await enableArchive()
    }

    func enableArchive() async {
        work = .running("Testing the folder…")
        do {
            let scope = try DestinationExportScope(
                destinationID: "local-file",
                metrics: selected,
                startInclusive: OnboardingPlan.defaultScopeStart(now: Date(), calendar: .current)
            )
            try await services.destinations.applyScope(scope, previousMetrics: [])
            _ = try await AppDestinationSetup.enableLocalFile(onProgress: nil)
            // The person set this destination up just now; it is not a change for them
            // to review, so Status doesn't open with "its identity changed".
            try? services.status.acknowledgeDestinationChanges()
            destinationReady = true
            advance()
        } catch {
            work = .failed("We couldn't write to that folder, read the file back and confirm it. Choose another folder or try again.")
        }
    }

    #if DEBUG
    /// UI tests can't drive the Files folder picker; they get a seeded folder instead.
    func useSeededFolder() async {
        folderName = try? HarnessExport.seedLocalExportFolderForUITests()
        await enableArchive()
    }
    #endif

    func setUpLater() {
        destinationReady = false
        advance()
    }

    // MARK: Disclosure and Health

    func acknowledgeDisclosure() {
        defaults.set(true, forKey: SettingKey.disclosureAcknowledged.rawValue)
        advance()
    }

    func requestHealthAccess() async {
        work = .running("Waiting for Apple Health…")
        do {
            try await HealthKitAuthorization.requestReadAccess(
                metrics: selected.sorted { $0.rawValue < $1.rawValue }
            )
            _ = try await services.health.observeAuthorizationChanges()
            try await services.health.reenableAfterAuthorizationRequest()
            try? await AppLifecycleCoordinator.shared.startObserversIfEligible()
            advance()
        } catch {
            work = .failed("Apple Health didn't open. You can try again, or continue and allow access later in Settings.")
        }
    }

    // MARK: First export

    func runFirstExport() async {
        work = .running("Exporting…")
        exportProgress = 0
        do {
            let lines = try await HarnessExport.runOnePageEachMetric(trigger: .manual) { current, total in
                await MainActor.run {
                    self.exportProgress = total > 0 ? Double(current) / Double(total) : 0
                }
            }
            exportProgress = 1
            let summary = lines.first ?? "Your first export is in the folder."
            nothingCameBack = summary == CombinedExportSummary.copy([.successNothingDue])
            exportSummary = nothingCameBack ? nil : summary
            work = .idle
        } catch {
            let label = await HarnessExport.notifyRunFailure(trigger: .manual)
            let object = UserFacingFailure.object(for: error, destinationLabel: label ?? folderName ?? "your folder")
            work = .failed("\(object.title). \(object.fix)")
        }
    }

    func chooseDifferentTypes() {
        retyping = true
        nothingCameBack = false
        step = .types
    }

    private func saveTypesAndExportAgain() async {
        work = .running("Saving your types…")
        do {
            let previous = try await services.destinations.scope("local-file").metrics
            let scope = try DestinationExportScope(
                destinationID: "local-file",
                metrics: selected,
                startInclusive: OnboardingPlan.defaultScopeStart(now: Date(), calendar: .current)
            )
            try await services.destinations.applyScope(scope, previousMetrics: previous)
            try await HealthKitAuthorization.requestReadAccess(
                metrics: selected.sorted { $0.rawValue < $1.rawValue }
            )
            work = .idle
            step = .firstExport
        } catch {
            work = .failed("Those types couldn't be saved. Try again.")
        }
    }

    func done() {
        finish()
    }
}
