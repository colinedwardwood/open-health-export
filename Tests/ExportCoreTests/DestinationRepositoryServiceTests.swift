// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import EnginePorts
import Foundation
import MetricCatalog
import Testing
import Watchdog

private final class MemoryDestinationState: @unchecked Sendable {
    let lock = NSLock()
    var verifications: [String: DestinationVerificationSummary] = [:]
    var sidecars: Set<DestinationSidecar> = []
    var removed: [DestinationSidecar] = []
    var traceparentWrites: [String: Bool] = [:]
    var roles: [String: String] = [:]
    var metered: Set<String> = []
    var companionTraceparent = false
    var snapshotRoles: [String: DestinationExportRole] = [:]
    var snapshotWrites: [(String, DestinationExportRole, Date)] = []
    var scopes: [String: DestinationExportScope] = [:]
    var reenabled: [(MetricID, String)] = []
    var folderName: String?
    var savedFolders: [URL] = []

    func with<T>(_ body: (MemoryDestinationState) throws -> T) rethrows -> T {
        try lock.withLock { try body(self) }
    }
}

private struct MemoryRecords: DestinationRecordStorage {
    let state: MemoryDestinationState
    func verification(_ destinationID: String) -> DestinationVerificationSummary? {
        state.with { $0.verifications[destinationID] }
    }
    func setPropagateTraceparent(_ enabled: Bool, destinationID: String) throws {
        state.with {
            $0.traceparentWrites[destinationID] = enabled
            $0.verifications[destinationID]?.propagateTraceparent = enabled
        }
    }
    func exists(_ sidecar: DestinationSidecar) -> Bool { state.with { $0.sidecars.contains(sidecar) } }
    func remove(_ sidecar: DestinationSidecar) {
        state.with {
            $0.sidecars.remove(sidecar)
            $0.removed.append(sidecar)
            if sidecar == .localFileTestReport { $0.verifications["local-file"] = nil }
        }
    }
}

private struct MemoryPreferences: DestinationPreferenceStorage {
    let state: MemoryDestinationState
    func exportRole(_ destinationID: String) -> String? { state.with { $0.roles[destinationID] } }
    func setExportRole(_ rawValue: String, destinationID: String) {
        state.with { $0.roles[destinationID] = rawValue }
    }
    func allowsMeteredNetwork(_ destinationID: String) -> Bool {
        state.with { $0.metered.contains(destinationID) }
    }
    func companionPropagatesTraceparent() -> Bool { state.with { $0.companionTraceparent } }
    func setCompanionPropagatesTraceparent(_ enabled: Bool) {
        state.with { $0.companionTraceparent = enabled }
    }
}

private struct MemorySnapshots: DestinationSnapshotStorage {
    let state: MemoryDestinationState
    func exportRole(_ destinationID: String) -> DestinationExportRole? {
        state.with { $0.snapshotRoles[destinationID] }
    }
    func applyExportRole(_ role: DestinationExportRole, destinationID: String, at now: Date) throws {
        state.with {
            guard $0.snapshotRoles[destinationID] != nil else { return }
            $0.snapshotRoles[destinationID] = role
            $0.snapshotWrites.append((destinationID, role, now))
        }
    }
}

private struct MemoryScopes: DestinationScopeStorage {
    let state: MemoryDestinationState
    func loadScope(_ destinationID: String) async throws -> DestinationExportScope? {
        state.with { $0.scopes[destinationID] }
    }
    func saveScope(_ scope: DestinationExportScope) async throws {
        state.with { $0.scopes[scope.destinationID] = scope }
    }
    func reenable(_ metric: MetricID, reason: String) async throws {
        state.with { $0.reenabled.append((metric, reason)) }
    }
}

private struct MemoryFolder: LocalExportFolderStorage {
    let state: MemoryDestinationState
    func saveFolder(_ url: URL) throws {
        state.with {
            $0.savedFolders.append(url)
            $0.folderName = url.lastPathComponent
        }
    }
    func accessibleFolderName() -> String? { state.with { $0.folderName } }
}

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

private func makeRepository(unlock: UnlockState = .sourceBuild) -> (DestinationRepository, MemoryDestinationState) {
    let state = MemoryDestinationState()
    let repository = DestinationRepository(
        records: MemoryRecords(state: state),
        preferences: MemoryPreferences(state: state),
        snapshots: MemorySnapshots(state: state),
        scopes: MemoryScopes(state: state),
        folder: MemoryFolder(state: state),
        now: { fixedNow },
        unlockState: { unlock }
    )
    return (repository, state)
}

/// D-08b (#68): without the unlock an enabled destination still exports when the
/// person asks, and never on its own.
@Test func destinationRepositoryGatesOnlyAutomaticRunsOnTheUnlock() {
    for unlock in [UnlockState.locked, .revoked] {
        let (repository, state) = makeRepository(unlock: unlock)
        state.with { $0.verifications["mqtt"] = DestinationVerificationSummary(allowsEnablement: true) }
        #expect(repository.allowsExport("mqtt", trigger: .manual))
        #expect(repository.hasAutomaticExport(trigger: .widgetControl))
        #expect(!repository.hasAutomaticExport(trigger: .observerQuery))
        #expect(!repository.hasAutomaticExport(trigger: .bgAppRefresh))
        #expect(!repository.allowsExport("mqtt", trigger: .shortcut))
    }
    let (unlocked, state) = makeRepository(unlock: .unlocked)
    state.with { $0.verifications["mqtt"] = DestinationVerificationSummary(allowsEnablement: true) }
    #expect(unlocked.hasAutomaticExport(trigger: .observerQuery))
}

private let heartRate = MetricCatalog.heartRate.id
private let stepCount = MetricCatalog.stepCount.id

@Test func destinationRepositoryEnablesOnlyVerifiedDestinations() {
    let (repository, state) = makeRepository()
    state.with {
        $0.verifications["https"] = DestinationVerificationSummary(allowsEnablement: true)
        $0.verifications["mqtt"] = DestinationVerificationSummary(allowsEnablement: false)
        $0.verifications["unknown"] = DestinationVerificationSummary(allowsEnablement: true)
    }
    #expect(repository.isEnabled("https"))
    #expect(!repository.isEnabled("mqtt"))
    #expect(!repository.isEnabled("companion"))
    #expect(!repository.isEnabled("unknown"))
}

@Test func destinationRepositoryLocalFileNeedsAnAccessibleFolderAndAPassedTest() throws {
    let (repository, state) = makeRepository()
    state.with { $0.verifications["local-file"] = DestinationVerificationSummary(allowsEnablement: true) }
    #expect(!repository.isEnabled("local-file"), "a passed test without a reachable folder is off")

    state.with { $0.folderName = "Archive" }
    #expect(repository.isEnabled("local-file"))
    #expect(repository.localExportFolderName() == "Archive")

    let name = try repository.chooseLocalExportFolder(URL(fileURLWithPath: "/tmp/New Folder"))
    #expect(name == "New Folder")
    #expect(state.with { $0.removed } == [.localFileTestReport])
    #expect(!repository.isLocalFileEnabled(), "a newly chosen folder must be tested again")
}

@Test func destinationRepositoryResolvesRolesPreferenceThenSnapshotThenDesignated() throws {
    let (repository, state) = makeRepository()
    #expect(repository.exportRole("https") == .designated)

    state.with { $0.snapshotRoles["https"] = .manualOnly }
    #expect(repository.exportRole("https") == .manualOnly)

    state.with { $0.roles["https"] = "designated" }
    #expect(repository.exportRole("https") == .designated)

    state.with { $0.roles["https"] = "garbage" }
    #expect(repository.exportRole("https") == .manualOnly, "an unreadable preference falls through")

    try repository.setExportRole(.designated, destinationID: "https")
    #expect(state.with { $0.roles["https"] } == "designated")
    let writes = state.with { $0.snapshotWrites }
    #expect(writes.count == 1)
    #expect(writes.first?.0 == "https")
    #expect(writes.first?.2 == fixedNow)
}

@Test func destinationRepositorySynchronizesEveryHealthDestinationRole() {
    let (repository, state) = makeRepository()
    state.with { $0.snapshotRoles["mqtt"] = .manualOnly }
    repository.synchronizeExportRoles()
    let roles = state.with { $0.roles }
    #expect(Set(roles.keys) == Set(DestinationRepository.healthDestinationIDs))
    #expect(roles["mqtt"] == "manual_only")
    #expect(roles["https"] == "designated")
}

@Test func destinationRepositoryAutomaticExportNeedsAnEnabledDestinationWhoseRoleAllowsTheTrigger() {
    let (repository, state) = makeRepository()
    #expect(!repository.hasAutomaticExport(trigger: .manual))

    state.with {
        $0.verifications["mqtt"] = DestinationVerificationSummary(allowsEnablement: true)
        $0.roles["mqtt"] = DestinationExportRole.manualOnly.rawValue
    }
    #expect(repository.hasAutomaticExport(trigger: .manual))
    #expect(!repository.hasAutomaticExport(trigger: .bgAppRefresh))
    #expect(!repository.allowsExport("mqtt", trigger: .observerQuery))

    state.with { $0.verifications["https"] = DestinationVerificationSummary(allowsEnablement: true) }
    #expect(repository.hasAutomaticExport(trigger: .bgAppRefresh))
}

@Test func destinationRepositoryScopeDefaultsToDenyAndSanitizesOnSave() async throws {
    let (repository, state) = makeRepository()
    let empty = try await repository.scope("https")
    #expect(empty.destinationID == "https")
    #expect(!empty.isConfigured)
    #expect(try await repository.allScopes().map(\.destinationID) == DestinationRepository.healthDestinationIDs)

    let start = Date(timeIntervalSince1970: 1_700_000_000)
    try await repository.saveScope(
        DestinationExportScope(
            destinationID: "https",
            metrics: [heartRate, MetricID(rawValue: "not_a_catalogue_type")],
            startInclusive: start
        )
    )
    let saved = state.with { $0.scopes["https"] }
    #expect(saved?.metrics == [heartRate])
    #expect(saved?.startInclusive == start)
}

@Test func destinationRepositoryApplyScopeReenablesOnlyNewlyAddedTypes() async throws {
    let (repository, state) = makeRepository()
    let scope = try DestinationExportScope(
        destinationID: "mqtt",
        metrics: [heartRate, stepCount],
        startInclusive: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try await repository.applyScope(scope, previousMetrics: [heartRate])
    let reenabled = state.with { $0.reenabled }
    #expect(reenabled.map(\.0) == [stepCount])
    #expect(reenabled.map(\.1) == ["user_selected"])
    #expect(state.with { $0.scopes["mqtt"] } == scope)
}

@Test func destinationRepositorySelectedMetricsIsTheUnionOfEnabledScopes() async throws {
    let (repository, state) = makeRepository()
    state.with {
        $0.scopes["https"] = try? DestinationExportScope(destinationID: "https", metrics: [stepCount])
        $0.scopes["mqtt"] = try? DestinationExportScope(destinationID: "mqtt", metrics: [heartRate])
        $0.verifications["mqtt"] = DestinationVerificationSummary(allowsEnablement: true)
    }
    #expect(try await repository.selectedMetrics() == [heartRate])

    state.with { $0.verifications["https"] = DestinationVerificationSummary(allowsEnablement: true) }
    let both = try await repository.selectedMetrics()
    #expect(both == [heartRate, stepCount].sorted { $0.rawValue < $1.rawValue })
}

@Test func destinationRepositoryConfigurationFollowsTheSidecarFiles() {
    let (repository, state) = makeRepository()
    #expect(!repository.hasConfiguration("companion"))
    state.with { $0.sidecars = [.pairing, .httpsRecord(destinationID: "home-assistant")] }
    #expect(repository.hasConfiguration("companion"))
    #expect(repository.hasConfiguration("home-assistant"))
    #expect(!repository.hasConfiguration("https"))
    #expect(!repository.hasConfiguration("local-file"))
    #expect(DestinationSidecar.httpsRecord(destinationID: "https").filename == "https-destination.json")
    #expect(DestinationSidecar.localFolderBookmark.filename == "local-export-folder.bookmark")
}

@Test func destinationRepositoryMeteredIsOffUnlessChosen() {
    let (repository, state) = makeRepository()
    #expect(!repository.allowsMeteredNetwork("https"))
    state.with { $0.metered = ["https"] }
    #expect(repository.allowsMeteredNetwork("https"))
    #expect(!repository.allowsMeteredNetwork("mqtt"))
}

@Test func destinationRepositoryTraceparentSwitches() throws {
    let (repository, state) = makeRepository()
    #expect(!repository.httpsTraceparent())
    state.with {
        $0.verifications["https"] = DestinationVerificationSummary(allowsEnablement: true)
    }
    try repository.setHTTPSTraceparent(true)
    #expect(repository.httpsTraceparent())

    try repository.setCompanionTraceparent(true)
    #expect(repository.companionTraceparent())
    #expect(state.with { $0.traceparentWrites["companion"] } == true)
}

@Test func destinationRepositoryCredentialSummariesHideAbsentCredentials() {
    let (repository, state) = makeRepository()
    let bearer = StoredCredentialDescriptor(characterCount: 12, appearance: .bearerToken, addedOnDay: "2026-09-01")
    let absent = StoredCredentialDescriptor(characterCount: 0, appearance: .absent, addedOnDay: nil)
    state.with {
        $0.verifications["https"] = DestinationVerificationSummary(allowsEnablement: true, bearer: bearer)
        $0.verifications["home-assistant"] = DestinationVerificationSummary(allowsEnablement: true, webhook: absent)
        $0.verifications["mqtt"] = DestinationVerificationSummary(
            allowsEnablement: true,
            password: StoredCredentialDescriptor(characterCount: 1, appearance: .password, addedOnDay: nil)
        )
    }
    let summaries = repository.credentialSummaries()
    #expect(summaries.httpsBearer == bearer.summary)
    #expect(summaries.homeAssistantWebhook == nil)
    #expect(summaries.mqttPassword == "•••• 1 character · password")
    #expect(summaries.mqttPKCS12Password == nil)
}

@Test func destinationRepositoryLabelsAndKeychainServices() {
    #expect(DestinationRepository.label("local-file") == "Archive folder")
    #expect(DestinationRepository.label("companion") == "Mac companion")
    #expect(DestinationRepository.label("otlp") == "otlp")
    #expect(DestinationRepository.keychainService("https") == IdentifierRoot.qualified("ios.https"))
}
