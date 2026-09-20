// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionWire
import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import DiagnosticBundle
import EnginePorts
import HealthKitSource
import MetricCatalog
import NetEgress
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Watchdog
import WireFormat

struct HarnessView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("ohe.appPrivacyGateEnabled")
    private var appPrivacyGateEnabled = false
    @State private var appPrivacyGate: AppPrivacyGate

    private enum Phase {
        case disclosure
        case ready
        case working
    }

    private enum PendingConfirmationKind {
        case https
        case homeAssistant
        case mqtt
    }

    @State private var phase: Phase = .disclosure
    @State private var rootTab = AppRootTabs.status
    @State private var showSettings = false
    @State private var showHealthPriming = false
    @State private var primingTypeCount = 0
    @AppStorage("ohe.disclosureAcknowledged")
    private var disclosureAcknowledged = false
    @State private var status = "Waiting for disclosure acknowledgement."
    @State private var results: [String] = []
    @State private var timeToFirstFrameMS: Double = 0
    @State private var pairingPaste = ""
    @State private var pairing: PairingSession?
    @State private var sas = ""
    @State private var httpsURL = ""
    @State private var httpsBearer = ""
    @State private var httpsBearerDescriptor: String?
    @State private var homeAssistantBaseURL = ""
    @State private var homeAssistantWebhookID = ""
    @State private var homeAssistantWebhookDescriptor: String?
    @State private var allowInsecureHomeAssistant = false
    @State private var homeAssistantTestLines: [String] = []
    @State private var mqttPasswordDescriptor: String?
    @State private var mqttPKCS12PasswordDescriptor: String?
    @State private var allowInsecureHTTP = false
    @AppStorage("ohe.https.allowsMeteredNetwork")
    private var allowMeteredHTTPS = false
    @AppStorage("ohe.home-assistant.allowsMeteredNetwork")
    private var allowMeteredHomeAssistant = false
    @AppStorage("ohe.mqtt.allowsMeteredNetwork")
    private var allowMeteredMQTT = false
    @AppStorage("ohe.companion.allowsMeteredNetwork")
    private var allowMeteredCompanion = false
    @AppStorage("ohe.otlp.allowsMeteredNetwork")
    private var allowMeteredOTLP = false
    @State private var propagateTraceparent = false
    @State private var companionTraceparent = false
    @State private var httpsTestLines: [String] = []
    @State private var mqttURL = ""
    @State private var mqttClientID = "ohe-iphone"
    @State private var mqttTopic = "ohe/health"
    @State private var mqttQoS: UInt8 = 1
    @State private var userFacingError: UserFacingErrorObject?
    @State private var seededUserFacingErrors: [UserFacingErrorObject] = []
    @AppStorage("ohe.exportWindowHours")
    private var exportWindowHours = 24
    @AppStorage("ohe.freshnessIntervalMinutes")
    private var freshnessIntervalMinutes = 15
    @State private var mqttUsername = ""
    @State private var mqttPassword = ""
    @State private var allowInsecureMQTT = false
    @State private var mqttPKCS12Name = "No client certificate"
    @State private var mqttPKCS12Data: Data?
    @State private var mqttPKCS12Password = ""
    @State private var pickingMQTTPKCS12 = false
    @State private var mqttTestLines: [String] = []
    @State private var localFileTestLines: [String] = []
    @State private var pickingLocalExportFolder = false
    @State private var localExportFolderName: String?
    @State private var importedDestinationDraft: ImportedDestinationDraftRecord?
    @State private var importedDraftRefreshToken = 0
    @State private var pairingImportMismatch = false
    @State private var configurationExportURL: URL?
    #if !OHE_OBS25_SIZE_BASELINE
    @State private var otlpURL = ""
    @State private var allowInsecureOTLP = false
    @State private var otlpPreview = ""
    @State private var otlpPayload: Data?
    @State private var otlpGate = DiagnosticPreviewGate()
    @State private var otlpLines: [String] = []
    #endif
    @State private var showScanner = false
    @State private var diagnosticPreview = ""
    @State private var diagnosticPayload: Data?
    @State private var diagnosticGate = DiagnosticPreviewGate()
    @State private var diagnosticShareURL: URL?
    @AppStorage("ohe.diagnosticMinimumRuns")
    private var diagnosticMinimumRuns = 30
    @AppStorage("ohe.diagnosticWindowHours")
    private var diagnosticWindowHours = 24
    @State private var destinationStatusLines: [String] = []
    @State private var destinationSnapshots: [DestinationStatusSnapshot] = []
    @State private var dataFlowHops: [DataFlowHop] = []
    @State private var dataFlowTypeCount = 0
    @State private var ledgerLines: [String] = []
    @State private var networkActivityLines: [String] = []
    @State private var provenanceLines: [String] = []
    @State private var historyLines: [String] = []
    @State private var historyEvents: [RunEvent] = []
    @State private var revealedHistoryIDs: Set<String> = []
    @State private var ledgerWarning = ""
    @State private var wakeAttribution = ""
    @State private var queueEvictionGaps: [GapRecord] = []
    @State private var wipeArmed = false
    @State private var wipeInventory = WipeInventory()
    @State private var stopHeartRateArmed = false
    @State private var demoConfirmName = ""
    @State private var browserSearch = ""
    @State private var browserSelecting = false
    @State private var browserReviewVisible = false
    @State private var browserBaseline = Set<MetricID>()
    @State private var authorizedForReview = Set<MetricID>()
    @State private var browserSelection = Set<MetricID>()
    @State private var scopeDestinationID = "local-file"
    @State private var scopeStartDate = Date()
    @State private var scopeEndEnabled = false
    @State private var scopeEndDate = Date().addingTimeInterval(365 * 24 * 60 * 60)
    @State private var selectedBrowserMetric: MetricID?
    @State private var pendingSensitiveMetric: MetricID?
    @State private var sensitiveDestinationConfirmation = ""
    @State private var liveBrowserSamples: [MetricID: [SampleRecord]] = [:]
    @State private var browserAuthorizedDays: [MetricID: String] = [:]
    @State private var coverageProbeObservations: [MetricID: CoverageObservation] = [:]
    @State private var coverageLastDataDays: [MetricID: String] = [:]
    @State private var browserSentThroughDay: [MetricID: String] = [:]
    @State private var browserIndexHorizonDay: String?
    @State private var browserLoadingHealth = false
    @State private var foregroundCatchUpStarted = false
    @AppStorage("ohe.browserOnlyWithData")
    private var browserOnlyWithData = true
    @AppStorage("ohe.preset.coreDaily.appliedVersion")
    private var coreDailyAppliedVersion = 0
    @State private var coreDailyUpgrade: MetricPresetDiff?
    /// SEC-45: one-time, so it persists past the run that acknowledged it.
    @AppStorage("ohe.shareProtectionAcknowledged")
    private var shareProtectionAcknowledged = false
    @AppStorage("ohe.browserDemoMode")
    private var browserDemoMode = false
    @AppStorage("ohe.displayUnitPreference")
    private var displayUnitPreference: DisplayUnitPreference = .automatic
    @AppStorage("ohe.clockDisplay")
    private var clockDisplay: ClockDisplay = .system
    @State private var healthKitUnitPolicy: UnitDisplayPolicy?

    /// Automatic follows Health preferred units when HealthKit answers; otherwise the
    /// region. Explicit picker values never consult Health (UX-44).
    private var displayUnitPolicy: UnitDisplayPolicy {
        if displayUnitPreference == .automatic, let healthKitUnitPolicy {
            return healthKitUnitPolicy
        }
        return displayUnitPreference.policy(locale: Locale.current)
    }

    private var acknowledgementsText: String {
        guard let url = Bundle.main.url(forResource: "NOTICE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "NOTICE is missing from this build."
        }
        return text
    }
    @AppStorage("ohe.advisoryEnabled")
    private var advisoryEnabled = true
    @State private var advisoryBanner: String?
    @State private var advisoryItems: [AdvisoryItem] = []
    @State private var destinationChangeBanner: String?
    @State private var overdueBanner: String?
    @State private var anchorHolds: [AnchorHold] = []
    @State private var confirmationCard: DestinationConfirmationCard?
    @State private var confirmationKind: PendingConfirmationKind?
    @State private var publicAddressConfirmation = ""

    init(authenticator: any UserPresenceAuthenticating = LocalAuthenticationAdapter()) {
        _appPrivacyGate = State(initialValue: AppPrivacyGate(authenticator: authenticator))
    }

    private var isPrivacyLocked: Bool {
        appPrivacyGateEnabled && appPrivacyGate.state != .unlocked
    }

    private var healthKitAvailable: Bool {
        HealthKitAvailability.isAvailable()
    }

    private var showsIPadOnlyExporterNotice: Bool {
        IPadExporterNotice.isVisible(
            idiomIsPad: UIDevice.current.userInterfaceIdiom == .pad,
            environment: ProcessInfo.processInfo.environment
        )
    }

    var body: some View {
        ZStack {
            if !healthKitAvailable {
                healthKitUnavailable
            } else if isPrivacyLocked {
                privacyLock
            } else if phase == .disclosure {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            statusAttention
                            disclosure
                        }
                        .padding()
                    }
                    .navigationTitle("M0 harness")
                }
            } else {
                TabView(selection: $rootTab) {
                    ForEach(AppRootTabs.allCases, id: \.self) { tab in
                        rootTabPage(tab)
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .onChange(of: userFacingError) { _, error in
                    guard error != nil else { return }
                    rootTab = .status
                }
                .sheet(isPresented: $showSettings) {
                    NavigationStack {
                        ScrollView {
                            statusSettings
                                .padding()
                        }
                        .accessibilityIdentifier("settings-scroll")
                        .navigationTitle("Settings")
                        .toolbar {
                            Button("Close settings") {
                                showSettings = false
                            }
                            .accessibilityIdentifier("settings-close")
                        }
                    }
                }
            }
        }
        .tint(.primary)
        .fullScreenCover(isPresented: $showHealthPriming) {
            healthPriming
                .interactiveDismissDisabled()
        }
        .safeAreaInset(edge: .top) {
            if !isPrivacyLocked, let overdueBanner {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export overdue")
                        .wrappingFillCaption()
                        .fontWeight(.semibold)
                    Text(overdueBanner)
                        .wrappingFillCaption()
                }
                .attentionBanner()
                .accessibilityIdentifier("export-overdue-banner")
            }
        }
        .safeAreaInset(edge: .top) {
            if !isPrivacyLocked, let destinationChangeBanner {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unacknowledged destination change")
                        .wrappingFillCaption()
                        .fontWeight(.semibold)
                    Text(destinationChangeBanner)
                        .wrappingFillCaption()
                }
                .attentionBanner()
                .accessibilityIdentifier("destination-change-banner")
            }
        }
        .safeAreaInset(edge: .top) {
            if !isPrivacyLocked, AnchorHoldBanner.isVisible(anchorHolds) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AnchorHoldBanner.title)
                        .wrappingFillCaption()
                        .fontWeight(.semibold)
                    Text(AnchorHoldBanner.detail(anchorHolds))
                        .wrappingFillCaption()
                }
                .attentionBanner()
                .accessibilityIdentifier("anchor-hold-banner")
            }
        }
        .sheet(isPresented: Binding(
            get: { confirmationCard != nil },
            set: { presented in
                if !presented {
                    cancelDestinationConfirmation()
                }
            }
        )) {
            if let confirmationCard {
                destinationConfirmation(confirmationCard)
            }
        }
        .onAppear {
            appPrivacyGate.prepare(enabled: appPrivacyGateEnabled)
            timeToFirstFrameMS = LaunchMark.millisecondsToNow()
            #if DEBUG
            if ProcessInfo.processInfo.environment["OHE_RESET_SEEDED_SURFACES"] == "1" {
                try? HarnessExport.resetSeededSurfacesForUITests()
            }
            if let scenario = ProcessInfo.processInfo
                .environment["OHE_SEED_DESTINATION_STATUS"]
            {
                try? HarnessExport.seedDestinationStatusForUITests(scenario: scenario)
            }
            seedUserFacingErrorsFromLaunchEnvironment()
            // Ordered after the reset, which deletes the bookmark, and before the folder
            // name is read below.
            if ProcessInfo.processInfo.environment["OHE_SEED_LOCAL_EXPORT_FOLDER"] == "1" {
                _ = try? HarnessExport.seedLocalExportFolderForUITests()
            }
            #endif
            localExportFolderName = HarnessExport.localExportFolderName()
            refreshDestinationSurfaces()
            HealthKitPreferredDisplayUnits.startObserving()
            Task { await refreshHealthKitDisplayUnits() }
            #if !OHE_OBS25_SIZE_BASELINE
            if otlpURL.isEmpty {
                otlpURL = HarnessExport.storedOTLPURL()
            }
            #endif
            propagateTraceparent = HarnessExport.storedHTTPSTraceparent()
            companionTraceparent = HarnessExport.storedCompanionTraceparent()
            provenanceLines = HarnessExport.buildProvenanceLines()
            networkActivityLines = HarnessExport.networkActivityLines()
            if disclosureAcknowledged {
                phase = .ready
                status = "Ready."
            }
            #if DEBUG
            let seedHold = ProcessInfo.processInfo.environment["OHE_SEED_ANCHOR_HOLD"]
            if let held = seedHold {
                anchorHolds = [
                    AnchorHold(
                        metric: MetricID(rawValue: held),
                        reason: .cursorLost,
                        detectedAtEpoch: 0,
                        lastEmittedDay: "2026-09-08"
                    )
                ]
            }
            #endif
            Task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["OHE_RESET_SEEDED_SURFACES"] == "1",
                   seedHold == nil
                {
                    try? await HarnessExport.clearAnchorHoldsForUITests()
                }
                if let held = seedHold {
                    try? await HarnessExport.seedAnchorHoldForUITests(
                        metric: MetricID(rawValue: held)
                    )
                    if let loaded = try? await HarnessExport.anchorHolds(),
                       !loaded.isEmpty
                    {
                        anchorHolds = loaded
                    }
                }
                #endif
                await appPrivacyGate.authenticateIfNeeded(enabled: appPrivacyGateEnabled)
                await loadDestinationScope(scopeDestinationID)
                do {
                    let expired = try await HarnessExport.expireQueuesAndNotify()
                    if expired.expiredBatches > 0 {
                        status = "Ready. Deleted \(expired.expiredBatches) queued export(s) older than seven days."
                    }
                    if let interrupted = try await HarnessExport.recoverInterruptedExports() {
                        status = interrupted
                    }
                } catch {
                    status = "Failed to enforce queue expiry: \(error.localizedDescription)"
                }
                try? await HarnessExport.recordNotificationSuppressionIfNeeded()
                await restorePairing()
                await refreshLedgerIntegrity()
                await refreshWakeAttribution()
                await refreshSecurityAdvisory()
                #if DEBUG
                refreshDestinationSurfaces()
                if let raw = ProcessInfo.processInfo.environment["OHE_OPEN_URL"],
                   let url = URL(string: raw)
                {
                    applyOpenURL(url)
                }
                if let pending = AppLifecycleCoordinator.shared.consumePendingDeepLink() {
                    applyOpenURL(pending)
                }
                // SEC-45 is a one-time warning, so exercising it needs the
                // acknowledgement cleared rather than overridden: a launch argument
                // lands in the read-only argument domain, where the app's own write
                // could never take effect and the warning could never be dismissed.
                if ProcessInfo.processInfo.environment["OHE_SEED_SHARE_ACK"] == "clear" {
                    UserDefaults.standard.removeObject(forKey: "ohe.shareProtectionAcknowledged")
                }
                if ProcessInfo.processInfo.environment["OHE_SEED_HISTORY_PAYLOAD"] == "1" {
                    try? await HarnessExport.prepareHistoryPayloadSeedForUITests()
                }
                if ProcessInfo.processInfo.environment["OHE_SEED_PUBLIC_CONFIRMATION"] == "true" {
                    confirmationCard = DestinationConfirmationCard(
                        host: "collector.example.com",
                        identity: TLSIdentity(
                            leafSPKISha256: "aaaa",
                            issuerSPKISha256: "bbbb",
                            tlsVersion: "TLS 1.3",
                            cipherSuite: "test",
                            leafSubject: "collector.example.com",
                            leafIssuer: "Test CA",
                            notBefore: "2026-01-01",
                            notAfter: "2027-01-01",
                            resolvedAddress: "203.0.113.10",
                            addressClass: .publicUnicast,
                            trustAnchorKind: "test"
                        ),
                        preview: Data("{\"kind\":\"canary\"}\n".utf8),
                        insecureWithoutTLS: false
                    )
                    confirmationKind = .https
                }
                if ProcessInfo.processInfo.environment["OHE_SEED_MQTT_QOS0"] == "1" {
                    mqttQoS = 0
                    let error = UserFacingErrorObject.make(
                        archetype: .mqttQoS0,
                        destinationLabel: "broker.example"
                    )
                    userFacingError = error
                    status = error.title
                    results = error.lines
                }
                if ProcessInfo.processInfo.environment["OHE_SEED_HTTP413"] == "1" {
                    exportWindowHours = 24
                    let error = UserFacingErrorObject.make(
                        archetype: .http413,
                        destinationLabel: "nas",
                        evidence: UserFacingErrorEvidence(bytesSent: 3_600_000)
                    )
                    userFacingError = error
                    status = error.title
                    results = error.lines
                }
                if ProcessInfo.processInfo.environment["OHE_SEED_HTTP429"] == "1" {
                    freshnessIntervalMinutes = 15
                    let error = UserFacingErrorObject.make(
                        archetype: .http429,
                        destinationLabel: "nas",
                        evidence: UserFacingErrorEvidence(retryAfterSeconds: 30)
                    )
                    userFacingError = error
                    status = error.title
                    results = error.lines
                }
                if let raw = ProcessInfo.processInfo.environment["OHE_SEED_HTTPS_TEST_FAIL"],
                   let step = DestinationTestStep(rawValue: raw),
                   let summary = DestinationTestReport.failed(at: step).failureSummary
                {
                    httpsTestLines = [summary]
                }
                if let raw = ProcessInfo.processInfo.environment["OHE_SEED_MQTT_TEST_FAIL"],
                   let step = DestinationTestStep(rawValue: raw),
                   let summary = DestinationTestReport.failed(at: step).failureSummary
                {
                    mqttTestLines = [summary]
                }
                if let raw = ProcessInfo.processInfo.environment["OHE_SEED_LOCAL_FILE_TEST_FAIL"],
                   let step = DestinationTestStep(rawValue: raw),
                   let summary = DestinationTestReport.failed(at: step).failureSummary
                {
                    localFileTestLines = [summary]
                }
                if ProcessInfo.processInfo.environment["OHE_SEED_PAIRING_PASTE"] == "1",
                   let secret = try? PairingSecret(bytes: (0 ..< 32).map {
                       UInt8(truncatingIfNeeded: $0 * 7 + 3)
                   }),
                   let payload = try? PairingPayload(
                       macInstallationID: "mac-ui",
                       secret: secret,
                       serviceName: "UI Mac._ohe-companion._tcp"
                   )
                {
                    pairingPaste = " \(payload.encoded()) "
                }
                #endif
                await refreshQueueGaps()
                #if DEBUG
                reapplySeededAnchorHoldIfNeeded()
                #endif
                await refreshCoverageWindows()
                if disclosureAcknowledged,
                   !foregroundCatchUpStarted,
                   HarnessExport.hasAutomaticExport(trigger: .appForeground) {
                    foregroundCatchUpStarted = true
                    await runLocalExport(trigger: .appForeground)
                }
            }
        }
        .onOpenURL { url in
            applyOpenURL(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: HealthKitPreferredDisplayUnits.didChange)) { _ in
            Task { await refreshHealthKitDisplayUnits() }
        }
        .onChange(of: displayUnitPreference) { _, _ in
            Task { await refreshHealthKitDisplayUnits() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .oheOpenDeepLink)) { note in
            guard let url = note.object as? URL else { return }
            applyOpenURL(url)
        }
        .onChange(of: scenePhase) { _, next in
            guard next == .active else {
                appPrivacyGate.lockIfEnabled(appPrivacyGateEnabled)
                showScanner = false
                pickingMQTTPKCS12 = false
                if confirmationCard != nil {
                    cancelDestinationConfirmation()
                }
                return
            }
            AppLifecycleCoordinator.shared.recordWake(.appForeground)
            Task {
                await appPrivacyGate.authenticateIfNeeded(enabled: appPrivacyGateEnabled)
                try? await HarnessExport.recordNotificationSuppressionIfNeeded()
                await startHealthObserversIfEligible()
                await refreshSecurityAdvisory()
                await refreshCoverageWindows()
            }
        }
        .onChange(of: advisoryEnabled) {
            Task { await refreshSecurityAdvisory() }
        }
        .task(id: disclosureAcknowledged) {
            await startHealthObserversIfEligible()
        }
        .sheet(isPresented: $showScanner) {
            PairingScanner(
                onPayload: { text in
                    pairingPaste = text
                    parsePairing()
                },
                onFailure: { message in
                    status = "Failed: \(message). Paste the pairing payload instead."
                }
            )
        }
        .fileImporter(
            isPresented: $pickingLocalExportFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            do {
                localExportFolderName = try HarnessExport.chooseLocalExportFolder(url)
                localFileTestLines = []
                status = "Ready. Test the selected archive folder before exporting."
                refreshDestinationSurfaces()
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $pickingMQTTPKCS12,
            allowedContentTypes: mqttPKCS12Types,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                mqttPKCS12Data = try Data(contentsOf: url)
                mqttPKCS12Name = url.lastPathComponent
            } catch {
                status = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private var healthKitUnavailable: some View {
        VStack(spacing: 16) {
            Text(HealthAvailability.unavailableTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(HealthAvailability.unavailableBody)
                .font(.body)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("healthkit-unavailable")
    }

    private var privacyLock: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .accessibilityHidden(true)
            Text("Open Health Exporter is locked")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("privacy-gate-locked-title")
            Text("Unlocking protects this screen only. Background exports and destination delivery continue without a prompt.")
                .wrappingFillCaption()
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("privacy-gate-background-scope")
            if appPrivacyGate.authenticationFailed {
                Text("Authentication was not completed.")
                    .wrappingFillCaption()
                    .accessibilityIdentifier("privacy-gate-failure")
            }
            Button(
                appPrivacyGate.state == .authenticating ? "Authenticating…" : "Unlock"
            ) {
                Task {
                    await appPrivacyGate.authenticateIfNeeded(enabled: appPrivacyGateEnabled)
                }
            }
            .buttonStyle(HarnessButtonStyle())
            .disabled(appPrivacyGate.state == .authenticating)
            .accessibilityIdentifier("privacy-gate-unlock")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("privacy-gate")
    }

    private var dataFlowExplainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DataFlowExplainer.title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(DataFlowExplainer.source)
                .wrappingFillCaption()
            Text(DataFlowExplainer.typeCountCopy(dataFlowTypeCount))
                .wrappingFillCaption()
            Text(DataFlowExplainer.transform)
                .wrappingFillCaption()
            if dataFlowHops.isEmpty {
                Text(DataFlowExplainer.empty)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("data-flow-empty")
            } else {
                ForEach(Array(dataFlowHops.enumerated()), id: \.element.id) { index, hop in
                    Text(DataFlowExplainer.hopLine(hop))
                        .wrappingFillCaption()
                        .accessibilityIdentifier("data-flow-hop-\(index)")
                }
            }
            Text(DataFlowExplainer.nowhereElse)
                .wrappingFillCaption()
                .accessibilityIdentifier("data-flow-nowhere-else")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("data-flow-explainer")
    }

    private var schedulingHonesty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SchedulingHonesty.title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Text(SchedulingHonesty.body)
                .wrappingPrimaryCaption()
            Text(SchedulingHonesty.noSchedulePromise)
                .wrappingPrimaryCaption()
                .accessibilityIdentifier("scheduling-honesty-promise")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduling-honesty")
    }

    private var mqttPKCS12Types: [UTType] {
        ["p12", "pfx"].compactMap { UTType(filenameExtension: $0) } + [.data]
    }

    private var statusAttention: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(status)
                .wrappingFillCaption()
                .multilineTextAlignment(.leading)
                .accessibilityLabel("Status: \(status)")
                .accessibilityIdentifier("status-line")
                .id("status-line")

            if showsIPadOnlyExporterNotice {
                VStack(alignment: .leading, spacing: 4) {
                    Text(IPadExporterNotice.title)
                        .wrappingFillCaption()
                        .fontWeight(.semibold)
                    Text(IPadExporterNotice.body)
                        .wrappingFillCaption()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("ipad-only-exporter")
            }

            if userFacingError == nil, let drop = coverageDropEvents.first {
                VStack(alignment: .leading, spacing: 4) {
                    Text(CoverageDrop.attentionHeadline(for: drop))
                        .wrappingFillCaption()
                        .fontWeight(.semibold)
                    Text(CoverageDrop.attentionDetail)
                        .wrappingFillCaption()
                    Button(CoverageDrop.reviewAction) {
                        rootTab = .data
                    }
                    .buttonStyle(HarnessButtonStyle())
                    .accessibilityIdentifier("coverage-drop-review")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("coverage-drop-attention")
            }

            if !seededUserFacingErrors.isEmpty {
                ForEach(seededUserFacingErrors, id: \.archetype) { error in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(error.lines.enumerated()), id: \.offset) { index, line in
                            selectableMonospaceLine(
                                line,
                                identifier: "error-\(error.archetype.rawValue)-part-\(index)"
                            )
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("error-\(error.archetype.rawValue)")
                }
            } else if let userFacingError {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(userFacingError.lines.enumerated()), id: \.offset) { index, line in
                        selectableMonospaceLine(
                            line,
                            identifier: "error-part-\(index)"
                        )
                    }
                    ForEach(userFacingError.actions, id: \.rawValue) { action in
                        Button(action.label) {
                            applyUserFacingFix(action)
                        }
                        .buttonStyle(HarnessButtonStyle())
                        .disabled(phase == .working)
                        .accessibilityIdentifier("error-fix-\(action.rawValue)")
                    }
                }
                .accessibilityElement(children: .contain)
                .id("user-facing-error")
            }

            Text("Time to first screen: \(timeToFirstFrameMS, specifier: "%.0f") ms (foreground; R-73 is a background-launch budget).")
                .wrappingPrimaryCaption()
        }
    }

    private var measurements: some View {
        Group {
            if !results.isEmpty {
                Text("Measurements")
                    .font(.headline)
                ForEach(Array(results.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func rootTabPage(_ tab: AppRootTabs) -> some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch tab {
                        case .status:
                            statusAttention
                            destinationStatusCards
                            Button("Where your data goes") {
                                rootTab = .destinations
                            }
                            .buttonStyle(HarnessButtonStyle())
                            .accessibilityIdentifier("status-open-destinations")
                            Button("Settings") {
                                showSettings = true
                            }
                            .buttonStyle(HarnessButtonStyle())
                            .accessibilityIdentifier("status-open-settings")
                            statusOperations
                            measurements
                        case .data:
                            dataBrowser
                        case .destinations:
                            destinationsPane
                        case .history:
                            historyPane
                        }
                    }
                    .padding()
                    .padding(.bottom, 56)
                }
                .accessibilityIdentifier("root-scroll-\(tab.rawValue)")
                .navigationTitle(rootTabTitle(tab))
                .toolbar {
                    if tab == .status {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                            .accessibilityIdentifier("status-settings")
                        }
                    }
                }
                .onChange(of: userFacingError) { _, error in
                    guard tab == .status, error != nil else { return }
                    proxy.scrollTo("user-facing-error", anchor: .top)
                }
            }
        }
        .tabItem {
            switch tab {
            case .status:
                Label("Status", systemImage: tab.systemImage)
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
            case .data:
                Label("Data", systemImage: tab.systemImage)
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
            case .destinations:
                Label("Destinations", systemImage: tab.systemImage)
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
            case .history:
                Label("History", systemImage: tab.systemImage)
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .tag(tab)
    }

    private func rootTabTitle(_ tab: AppRootTabs) -> String {
        switch tab {
        case .status: "Status"
        case .data: "Data"
        case .destinations: "Destinations"
        case .history: "History"
        }
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before Health access")
                .font(.headline)
            Text("This is not a medical device. It does not diagnose or treat anything.")
                .wrappingFillCaption()
                .accessibilityIdentifier("first-run-disclaimer")
            schedulingHonesty
            Text("You choose what is read. We do not hide destinations, and we do not send telemetry to the maintainers.")
                .wrappingFillCaption()
            dataFlowExplainer
            Button("I understand — continue") {
                disclosureAcknowledged = true
                phase = .ready
                status = "Ready. Next: request Health read access, then measure."
            }
            .buttonStyle(HarnessButtonStyle())
            .accessibilityIdentifier("disclosure-continue")
            .accessibilityHint("Shows Health permission and measurement controls.")
        }
    }

    private var healthPriming: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(HealthAuthorizationPriming.title)
                .wrappingFillCaption()
                .fontWeight(.semibold)
                .accessibilityIdentifier("health-priming-title")
            Text(HealthAuthorizationPriming.typeCountCopy(primingTypeCount))
                .wrappingFillCaption()
                .accessibilityIdentifier("health-priming-types")
            Text(HealthAuthorizationPriming.sheetFollows)
                .wrappingFillCaption()
            Text(HealthAuthorizationPriming.invisibility)
                .wrappingFillCaption()
                .accessibilityIdentifier("health-priming-invisibility")
            Button(HealthAuthorizationPriming.continueTitle) {
                showHealthPriming = false
                Task { await requestAccess() }
            }
            .buttonStyle(HarnessButtonStyle())
            .accessibilityIdentifier("health-priming-continue")
            .accessibilityHint("Opens Apple's Health permission sheet.")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemBackground))
        .toolbar(.hidden, for: .navigationBar)
    }

    private var statusOperations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Request Health read access for selected types") {
                Task { await presentHealthPriming() }
            }
            .buttonStyle(HarnessButtonStyle())
            .accessibilityIdentifier("health-request")
            .accessibilityHint("Asks Apple for read permission only for types currently selected in Data.")
            .disabled(phase == .working)

            Text("This is not a medical device. It does not diagnose or treat anything.")
                .wrappingPrimaryCaption()
                .accessibilityIdentifier("about-disclaimer")

            Text("HealthKit provides no deletion callback. Tombstones are best-effort when iOS next reports a deletion; a full reconcile repairs deletions that were not reported.")
                .wrappingPrimaryCaption()
                .accessibilityIdentifier("deletion-behaviour")

            Button("Run R-70 (one anchored page per type)") {
                Task { await runR70() }
            }
            .buttonStyle(HarnessButtonStyle())
            .disabled(phase == .working)
            .accessibilityIdentifier("r70-run")
            Button("Export one page") {
                Task { await runLocalExport() }
            }
            .buttonStyle(HarnessButtonStyle())
            .disabled(phase == .working || !HarnessExport.hasAutomaticExport(trigger: .manual))
            .accessibilityIdentifier("local-file-export")
            .accessibilityHint("Writes NDJSON to the archive folder you chose in Files.")
            Text(SchedulingHonesty.shortcutsLine)
                .wrappingPrimaryCaption()
                .accessibilityIdentifier("shortcut-export")
            schedulingHonesty
            Text("Backfill runs newest-first and resumes from an inspectable checkpoint. On iOS 26 or later it continues unattended after you leave the app. On iOS 18 through 25, keep this screen open; the app prevents idle sleep while it works.")
                .wrappingFillCaption()
                .accessibilityIdentifier("backfill-os-disclosure")
            Button("Backfill all history (aggregates)") {
                Task { await runBackfill(mode: .aggregateOnly) }
            }
            .buttonStyle(HarnessButtonStyle())
            .disabled(phase == .working || !HarnessExport.isLocalFileEnabled())
            .accessibilityIdentifier("backfill-aggregate")
            Button("Backfill raw history (explicit action)") {
                Task { await runBackfill(mode: .raw) }
            }
            .buttonStyle(HarnessButtonStyle())
            .disabled(phase == .working || !HarnessExport.isLocalFileEnabled())
            .accessibilityIdentifier("backfill-raw")
            Button("Reconcile all available Health history") {
                Task { await runFullReconcile() }
            }
            .buttonStyle(HarnessButtonStyle())
            .disabled(phase == .working || !HarnessExport.isLocalFileEnabled())
            .accessibilityIdentifier("full-reconcile")
            .accessibilityHint("Compares every available day without advancing HealthKit anchors.")
            if !anchorHolds.isEmpty {
                Text("Paused data")
                    .font(.headline)
                ForEach(Array(anchorHolds.enumerated()), id: \.offset) { index, hold in
                    Text(AnchorHoldBanner.explanation(hold))
                        .wrappingFillCaption()
                        .accessibilityIdentifier("anchor-hold-explanation-\(index)")
                    Button(AnchorHoldBanner.reexportChoice) {
                        Task { await decideAnchorHold(hold, reexport: true) }
                    }
                    .buttonStyle(HarnessButtonStyle())
                    .disabled(phase == .working)
                    .accessibilityIdentifier("anchor-hold-reexport-\(index)")
                    Button(AnchorHoldBanner.stopChoice) {
                        Task { await decideAnchorHold(hold, reexport: false) }
                    }
                    .buttonStyle(HarnessButtonStyle())
                    .disabled(phase == .working)
                    .accessibilityIdentifier("anchor-hold-stop-\(index)")
                }
            }
            if !queueEvictionGaps.isEmpty {
                Text("Data gaps")
                    .font(.headline)
                Text("These queued date ranges were evicted to keep storage bounded.")
                    .wrappingFillCaption()
                ForEach(Array(queueEvictionGaps.enumerated()), id: \.offset) { index, gap in
                    Button(
                        "Re-export \(gap.metric.rawValue) "
                            + "\(gap.rangeStartDay ?? "unknown")–\(gap.rangeEndDay ?? "unknown")"
                    ) {
                        Task { await reExportQueueGap(gap) }
                    }
                    .buttonStyle(HarnessButtonStyle())
                    .disabled(phase == .working)
                    .accessibilityIdentifier("gap-reexport-\(index)")
                }
            }
            Text("DEMO MODE — synthetic data")
                .wrappingPrimaryCaption()
                .accessibilityIdentifier("demo-mode-label")
            Text("Demo export never reads HealthKit. Type the destination name local-file to confirm you are not sending this into a live archive.")
                .wrappingFillCaption()
            TextField("Type local-file to confirm demo export", text: $demoConfirmName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .frame(minHeight: 44)
                .accessibilityIdentifier("demo-confirm")
            secretFieldHygiene(demoConfirmName, identifierPrefix: "demo-confirm")
            Button("Export demo dataset (every catalogue metric)") {
                Task { await runDemoExport() }
            }
            .buttonStyle(HarnessButtonStyle())
            .disabled(
                phase == .working
                    || CredentialFieldHygiene.secret(demoConfirmName).normalized != "local-file"
            )
            .accessibilityIdentifier("demo-export")
            .accessibilityHint("Exports synthetic samples marked demo:true into a DEMO- prefixed local folder.")
            Button("Send sample destination-enabled notice") {
                Task { await sendSampleNotice() }
            }
            .buttonStyle(HarnessButtonStyle())
            .disabled(phase == .working)
            .accessibilityIdentifier("destination-enabled-notice")
            .accessibilityHint("Asks for notification permission and posts one R-40 notice with copy from the registry.")

            Text("Security advisories")
                .font(.headline)
            Text(AdvisoryPinnedKeys.urlString)
                .wrappingFillCaption()
                .accessibilityLabel("Security advisory endpoint")
            Text("This is the sole built-in host. The app never sends Health data there. Fetch happens only on a visible foreground launch, never during export.")
                .wrappingFillCaption()
            Toggle("Fetch security advisories", isOn: $advisoryEnabled)
                .frame(minHeight: 44)
                .accessibilityIdentifier("advisory-fetch")
            if let advisoryBanner {
                Text(advisoryBanner)
                    .wrappingFillCaption()
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("advisory-banner")
            }
            ForEach(advisoryItems, id: \.id) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.severity.uppercased()): \(item.id)")
                        .font(.subheadline)
                    Text(item.description)
                        .wrappingFillCaption()
                    Text(item.url)
                        .wrappingFillCaption()
                        .accessibilityLabel("Security advisory web link")
                }
                .accessibilityIdentifier("advisory-\(item.id)")
            }

        }
        .buttonStyle(HarnessButtonStyle())
        .controlSize(.large)
    }

    private var destinationStatusCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Refresh destination status") {
                refreshDestinationSurfaces()
            }
            .buttonStyle(HarnessButtonStyle())
            .accessibilityIdentifier("destination-refresh")
            if destinationSnapshots.isEmpty {
                Text(destinationStatusLines.first ?? DestinationStatusLine.emptyCopy)
                    .wrappingFillCaption()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("destination-empty")
            } else {
                ForEach(Array(destinationSnapshots.enumerated()), id: \.element.destinationID) { index, snapshot in
                    let line = destinationStatusLines[index]
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            presentErrorFromStatus(snapshot)
                        } label: {
                            Text(line)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("destination-status-\(index)")
                        .accessibilityHint("Shows the error cause and fix when this destination needs attention.")

                        if snapshot.enabled,
                           HarnessExport.healthDestinationIDs.contains(snapshot.destinationID) {
                            // A menu picker is a UIKit control that does not take the
                            // accessibility content-size category, so the hosted audit
                            // reports Dynamic Type as partially unsupported. Two wrapping
                            // buttons keep the same choice without that chrome.
                            let role = HarnessExport.destinationExportRole(
                                snapshot.destinationID
                            )
                            Text("Exports from this device")
                                .wrappingFillCaption()
                                .accessibilityIdentifier(
                                    "destination-export-role-\(snapshot.destinationID)"
                                )
                            Button {
                                try? HarnessExport.setDestinationExportRole(
                                    .designated,
                                    destinationID: snapshot.destinationID
                                )
                                refreshDestinationSurfaces()
                                Task { await reevaluateAutomaticExport() }
                            } label: {
                                Text("Automatic and manual")
                                    .fontWeight(role == .designated ? .semibold : .regular)
                                    .wrappingActionLabel()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "destination-export-role-designated-\(snapshot.destinationID)"
                            )
                            Button {
                                try? HarnessExport.setDestinationExportRole(
                                    .manualOnly,
                                    destinationID: snapshot.destinationID
                                )
                                refreshDestinationSurfaces()
                                Task { await reevaluateAutomaticExport() }
                            } label: {
                                Text("Manual only")
                                    .fontWeight(role == .manualOnly ? .semibold : .regular)
                                    .wrappingActionLabel()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(
                                "destination-export-role-manual-\(snapshot.destinationID)"
                            )
                            Text(
                                HarnessExport.destinationExportRole(snapshot.destinationID)
                                    == .manualOnly
                                    ? "This device exports here only when you ask. Keep exactly one other device automatic for this destination."
                                    : "This is the designated automatic exporter. Set every other device using this destination to Manual only."
                            )
                                .wrappingFillCaption()
                                .accessibilityIdentifier(
                                    "destination-export-role-copy-\(snapshot.destinationID)"
                                )
                        }
                    }
                }
            }
        }
        .buttonStyle(HarnessButtonStyle())
        .controlSize(.large)
    }

    private var destinationsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where your data goes")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("destination-title")
            dataFlowExplainer
            Text("Export window: \(exportWindowHours) hours")
                .wrappingFillCaption()
                .accessibilityIdentifier("export-window-hours")
            Text("Freshness interval: \(freshnessIntervalMinutes) minutes")
                .wrappingFillCaption()
                .accessibilityIdentifier("freshness-interval-minutes")
            Text(FreshnessTarget.provisionalDisclosure)
                .wrappingFillCaption()
                .accessibilityIdentifier("freshness-target")
            ForEach(HarnessExport.freshnessDisclosureLines(), id: \.id) { disclosure in
                Text(disclosure.text)
                    .wrappingFillCaption()
                    .accessibilityIdentifier(disclosure.id)
            }
            if !wakeAttribution.isEmpty {
                Text(wakeAttribution)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("wake-attribution")
            }
            if !ledgerWarning.isEmpty {
                Text(ledgerWarning)
                    .wrappingFillCaption()
                    .fontWeight(ledgerWarning.hasPrefix("WARNING") ? .semibold : .regular)
                    .accessibilityLabel("Ledger status: \(ledgerWarning)")
            }
            Text("Your health data is sent only to destinations listed here. This is what the app records about its own use, not independent proof.")
                .wrappingFillCaption()
                .accessibilityIdentifier("destination-ledger-honesty")
            ConfigurationImportView(
                refreshToken: importedDraftRefreshToken
            ) { draft in
                importedDestinationDraft = draft
                loadImportedDestinationDraft(draft)
            }
            if let importedName = importedCompanionServiceName {
                Text("Imported Mac name")
                    .wrappingFillCaption()
                Text(importedName)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("pairing-imported-service-name")
            }
            companionPairingSection
            Button {
                Task { await prepareConfigurationExport() }
            } label: {
                Text("Prepare credential-free configuration export")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("configuration-export-prepare")
            if let configurationExportURL {
                ShareLink(item: configurationExportURL) {
                    Text("Share .tributary configuration")
                }
                .accessibilityIdentifier("configuration-export-share")
            }
            Button {
                pickingLocalExportFolder = true
            } label: {
                Text(
                    localExportFolderName == nil
                        ? "Choose archive folder"
                        : "Choose archive folder again"
                )
                .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("local-file-choose-folder")
            .accessibilityHint("Opens the system folder picker. The app remembers access to that folder.")
            Text(
                localExportFolderName.map { "Archive folder: \($0)" }
                    ?? "No archive folder selected."
            )
            .wrappingFillCaption()
            .accessibilityIdentifier("local-file-folder")
            Button {
                Task { await enableLocalFile() }
            } label: {
                Text("Test and enable archive folder")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working || localExportFolderName == nil)
            .accessibilityIdentifier("local-file-enable")
            .accessibilityHint("Writes a canary file, reads it back, then enables the local-file destination.")
            ForEach(Array(localFileTestLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("local-file-test-line-\(index)")
            }
            Text(ExportProfile.haeCompatibility.label)
                .wrappingFillCaption()
                .accessibilityIdentifier("hae-compatibility-label")
            TextField("HTTPS destination URL", text: $httpsURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-url")
            urlFieldHygiene(httpsURL, identifierPrefix: "https-url")
            Text(CredentialDisclosure.copy)
                .wrappingFillCaption()
                .accessibilityIdentifier("credential-disclosure-https")
            SecureField("Bearer token (optional)", text: $httpsBearer)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-bearer")
            secretFieldHygiene(httpsBearer, identifierPrefix: "https-bearer")
            if let httpsBearerDescriptor {
                Text(httpsBearerDescriptor)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("https-bearer-descriptor")
            }
            Toggle("Allow plain HTTP (unsafe)", isOn: $allowInsecureHTTP)
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-insecure")
            Toggle("Allow cellular and other metered networks", isOn: $allowMeteredHTTPS)
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-metered")
            Text("Off by default. Exports wait for Wi-Fi unless you turn this on.")
                .wrappingFillCaption()
            if allowInsecureHTTP {
                Text("Plain HTTP exposes health exports to anyone able to observe this network.")
                    .wrappingFillCaption()
                    .fontWeight(.semibold)
            }
            Toggle("Send traceparent header (opt-in)", isOn: $propagateTraceparent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-traceparent")
                .onChange(of: propagateTraceparent) { _, enabled in
                    try? HarnessExport.setHTTPSTraceparent(enabled)
                }
            Text("Off by default. Never sends tracestate or baggage.")
                .wrappingFillCaption()
            Button {
                Task { await testHTTPS() }
            } label: {
                Text("Test HTTPS destination")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working || httpsURL.isEmpty)
            .accessibilityIdentifier("https-enable")
            Button {
                Task { await runHTTPSExport() }
            } label: {
                Text("Export one page (HTTPS destination)")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("https-export")
            ForEach(Array(httpsTestLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("https-test-line-\(index)")
            }
            Text("Home Assistant webhook")
                .font(.headline)
                .accessibilityIdentifier("home-assistant-title")
            Text("Sends the complete native NDJSON feed to an automation webhook. Home Assistant does not import historical sensor states from this feed by itself.")
                .wrappingFillCaption()
                .accessibilityIdentifier("home-assistant-semantics")
            TextField("Home Assistant base URL", text: $homeAssistantBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("home-assistant-url")
            urlFieldHygiene(
                homeAssistantBaseURL,
                identifierPrefix: "home-assistant-url"
            )
            SecureField("Webhook ID", text: $homeAssistantWebhookID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("home-assistant-webhook-id")
            secretFieldHygiene(
                homeAssistantWebhookID,
                identifierPrefix: "home-assistant-webhook-id"
            )
            if let homeAssistantWebhookDescriptor {
                Text(homeAssistantWebhookDescriptor)
                    .wrappingFillCaption()
                    .accessibilityIdentifier(
                        "home-assistant-webhook-descriptor"
                    )
            }
            Toggle(
                "Allow plain HTTP to Home Assistant (unsafe)",
                isOn: $allowInsecureHomeAssistant
            )
            .frame(minHeight: 44)
            .accessibilityIdentifier("home-assistant-insecure")
            Toggle(
                "Allow cellular and other metered networks",
                isOn: $allowMeteredHomeAssistant
            )
            .frame(minHeight: 44)
            .accessibilityIdentifier("home-assistant-metered")
            Text("Off by default. Exports wait for Wi-Fi unless you turn this on.")
                .wrappingFillCaption()
            Button {
                Task { await testHomeAssistantWebhook() }
            } label: {
                Text("Test Home Assistant webhook")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(
                phase == .working
                    || homeAssistantBaseURL.isEmpty
                    || homeAssistantWebhookID.isEmpty
            )
            .accessibilityIdentifier("home-assistant-enable")
            Button {
                Task { await runHomeAssistantExport() }
            } label: {
                Text("Export one page (Home Assistant webhook)")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(
                phase == .working
                    || !HarnessExport.isDestinationEnabled("home-assistant")
            )
            .accessibilityIdentifier("home-assistant-export")
            ForEach(
                Array(homeAssistantTestLines.enumerated()),
                id: \.offset
            ) { index, line in
                Text(line)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("home-assistant-test-line-\(index)")
            }
            TextField("MQTT broker URL", text: $mqttURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-url")
            urlFieldHygiene(mqttURL, identifierPrefix: "mqtt-url")
            TextField("MQTT client ID", text: $mqttClientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-client-id")
            secretFieldHygiene(mqttClientID, identifierPrefix: "mqtt-client-id")
            TextField("MQTT topic template", text: $mqttTopic)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-topic")
            secretFieldHygiene(mqttTopic, identifierPrefix: "mqtt-topic")
            Text("Use {{exporterId|raw}} and {{batchId|raw}} if the broker needs a templated topic.")
                .wrappingFillCaption()
            Text(mqttQoS == 0 ? "At most once (0)" : "At least once (1)")
                .wrappingFillCaption()
                .frame(minHeight: 44)
                .accessibilityLabel(
                    mqttQoS == 0 ? "MQTT QoS, At most once (0)" : "MQTT QoS, At least once (1)"
                )
                .accessibilityIdentifier("mqtt-qos")
            Button { mqttQoS = 0 } label: {
                Text("At most once (0)")
                    .wrappingActionLabel()
                    .fontWeight(mqttQoS == 0 ? .semibold : .regular)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mqtt-qos-0")
            Button { mqttQoS = 1 } label: {
                Text("At least once (1)")
                    .wrappingActionLabel()
                    .fontWeight(mqttQoS == 1 ? .semibold : .regular)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mqtt-qos-1")
            Button {
                pickingMQTTPKCS12 = true
            } label: {
                Text("Choose MQTT client PKCS#12")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mqtt-pkcs12")
            Text(mqttPKCS12Name)
                .wrappingFillCaption()
                .accessibilityIdentifier("mqtt-pkcs12-name")
            SecureField("PKCS#12 password", text: $mqttPKCS12Password)
                .textContentType(.password)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-pkcs12-password")
            secretFieldHygiene(mqttPKCS12Password, identifierPrefix: "mqtt-pkcs12-password")
            if mqttPKCS12Data != nil {
                Button {
                    mqttPKCS12Data = nil
                    mqttPKCS12Name = "No client certificate"
                    mqttPKCS12Password = ""
                } label: {
                    Text("Clear client certificate")
                        .wrappingActionLabel()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mqtt-pkcs12-clear")
            }
            TextField("MQTT username", text: $mqttUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-username")
            secretFieldHygiene(mqttUsername, identifierPrefix: "mqtt-username")
            Text(CredentialDisclosure.copy)
                .wrappingFillCaption()
                .accessibilityIdentifier("credential-disclosure-mqtt")
            SecureField("MQTT password", text: $mqttPassword)
                .textContentType(.password)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-password")
            secretFieldHygiene(mqttPassword, identifierPrefix: "mqtt-password")
            if let mqttPasswordDescriptor {
                Text(mqttPasswordDescriptor)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("mqtt-password-descriptor")
            }
            if let mqttPKCS12PasswordDescriptor {
                Text(mqttPKCS12PasswordDescriptor)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("mqtt-pkcs12-password-descriptor")
            }
            Toggle("Allow plain MQTT (unsafe)", isOn: $allowInsecureMQTT)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-insecure")
            Toggle("Allow cellular and other metered networks", isOn: $allowMeteredMQTT)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-metered")
            Text("Off by default. Exports wait for Wi-Fi unless you turn this on.")
                .wrappingFillCaption()
            if allowInsecureMQTT {
                Text("Plain MQTT exposes health exports to anyone able to observe this network.")
                    .wrappingFillCaption()
                    .fontWeight(.semibold)
            }
            Button {
                Task { await testMQTT() }
            } label: {
                Text("Test MQTT destination")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working || mqttURL.isEmpty || mqttClientID.isEmpty || mqttTopic.isEmpty)
            .accessibilityIdentifier("mqtt-enable")
            Button {
                Task { await runMQTTExport() }
            } label: {
                Text("Export one page (MQTT destination)")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("mqtt-export")
            ForEach(Array(mqttTestLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .wrappingFillCaption()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("mqtt-test-line-\(index)")
            }
            #if !OHE_OBS25_SIZE_BASELINE
            TextField("OTLP collector URL", text: $otlpURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("otlp-url")
            urlFieldHygiene(otlpURL, identifierPrefix: "otlp-url")
            Toggle("Allow plain HTTP for OTLP (unsafe)", isOn: $allowInsecureOTLP)
                .frame(minHeight: 44)
                .accessibilityIdentifier("otlp-insecure")
            Toggle("Allow cellular and other metered networks", isOn: $allowMeteredOTLP)
                .frame(minHeight: 44)
                .accessibilityIdentifier("otlp-metered")
            Text("Off by default. Exports wait for Wi-Fi unless you turn this on.")
                .wrappingFillCaption()
            if allowInsecureOTLP {
                Text("Plain HTTP exposes traces to anyone able to observe this network.")
                    .wrappingFillCaption()
                    .fontWeight(.semibold)
            }
            Text("This preview is traces only. It does not include health values.")
                .wrappingFillCaption()
            Button {
                Task { await previewOTLP() }
            } label: {
                Text("Preview OTLP payload")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("otlp-preview")
            if !otlpPreview.isEmpty {
                Text(otlpPreview)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("otlp-preview-body")
                Text("End of OTLP preview")
                    .wrappingFillCaption()
                    .accessibilityIdentifier("otlp-preview-end")
                    .onScrollVisibilityChange(threshold: 0.1) { visible in
                        if visible { revealOTLPEnable() }
                    }
            }
            Button {
                Task { await enableOTLP() }
            } label: {
                Text("Enable OTLP collector")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working || otlpURL.isEmpty || otlpGate.sharePayload == nil)
            .accessibilityIdentifier("otlp-enable")
            Button {
                Task { await projectOTLP() }
            } label: {
                Text("Project unprojected runs")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("otlp-project")
            Button {
                disableOTLP()
            } label: {
                Text("Disable OTLP collector")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("otlp-disable")
            ForEach(Array(otlpLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .wrappingFillCaption()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("otlp-line-\(index)")
            }
            #endif
            Button {
                do {
                    try HarnessExport.acknowledgeDestinationChanges()
                    refreshDestinationSurfaces()
                    status = "Ready. Unacknowledged destination changes were cleared."
                } catch {
                    status = "Failed: \(error.localizedDescription)"
                }
            } label: {
                Text("Acknowledge destination changes")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("destination-acknowledge-changes")
            Button {
                Task { await loadLedger() }
            } label: {
                Text("Verify and show egress ledger")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("destination-ledger-verify")
            .accessibilityHint("Verifies the append-only hash chain and shows up to 50 recent transmission records.")
            ForEach(Array(ledgerLines.enumerated()), id: \.offset) { index, line in
                selectableMonospaceLine(
                    line,
                    identifier: "destination-ledger-line-\(index)"
                )
            }
            Text(EgressAttemptLog.sectionTitle)
                .font(.headline)
                .accessibilityIdentifier("network-activity-title")
            ForEach(Array(networkActivityLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .wrappingFillCaption()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("network-activity-\(index)")
            }
            ForEach(Array(provenanceLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .wrappingFillCaption()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("build-provenance-\(index)")
            }
            Text("Acknowledgements")
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("acknowledgements-title")
            Text(acknowledgementsText)
                .wrappingFillCaption()
                .textSelection(.enabled)
                .accessibilityIdentifier("acknowledgements-body")
        }
        .buttonStyle(HarnessButtonStyle())
        .controlSize(.large)
    }

    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task { await loadHistory() }
            } label: {
                Text("Show export history (problems first)")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("history-load")
            if historyEvents.isEmpty {
                ForEach(Array(historyLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .wrappingFillCaption()
                        .lineLimit(nil)
                        .accessibilityIdentifier("history-row-\(index)")
                }
            } else {
                Text(RunHistoryDetail.retentionCopy)
                    .wrappingFillCaption()
                ForEach(Array(historyEvents.enumerated()), id: \.offset) { eventIndex, event in
                    let rowID = historyRowID(event)
                    let revealed = revealedHistoryIDs.contains(rowID)
                    let lines = RunHistoryDetail.lines(for: event, revealPayload: revealed)
                    ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                        selectableMonospaceLine(
                            line,
                            identifier: "history-row-\(eventIndex)-\(lineIndex)"
                        )
                    }
                    if event.facts.payloadPath != nil, !revealed {
                        Button("Reveal exact payload") {
                            Task { await revealHistoryPayload(rowID) }
                        }
                        .buttonStyle(HarnessButtonStyle())
                        .accessibilityIdentifier("history-reveal-payload-\(eventIndex)")
                    }
                }
            }
        }
        .buttonStyle(HarnessButtonStyle())
        .controlSize(.large)
    }

    private var statusSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Where your data goes") {
                showSettings = false
                rootTab = .destinations
            }
            .buttonStyle(HarnessButtonStyle())
            .accessibilityIdentifier("settings-open-destinations")
            dataFlowExplainer
            ForEach(Array(provenanceLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .wrappingFillCaption()
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings-build-provenance-\(index)")
            }
            Text("App privacy")
                .font(.headline)
                .accessibilityIdentifier("app-privacy-heading")
            Toggle(
                "Require Face ID, Touch ID, or device passcode to open the app",
                isOn: Binding(
                    get: { appPrivacyGateEnabled },
                    set: { enabled in
                        if enabled {
                            Task {
                                if await appPrivacyGate.authenticateIfNeeded(enabled: true) {
                                    appPrivacyGateEnabled = true
                                    status = "Ready. The app screen will lock whenever you leave it."
                                } else {
                                    status = "App privacy was not enabled because authentication did not complete."
                                }
                            }
                        } else {
                            appPrivacyGateEnabled = false
                            appPrivacyGate.prepare(enabled: false)
                            status = "Ready. The optional app privacy gate is off."
                        }
                    }
                )
            )
            .frame(minHeight: 44)
            .accessibilityIdentifier("privacy-gate-enabled")
            Text("This protects the foreground screen only. It never gates background tasks or destination delivery.")
                .wrappingFillCaption()
                .accessibilityIdentifier("privacy-gate-scope")
            Text(CredentialPresentationPolicy.copy)
                .wrappingFillCaption()
                .accessibilityIdentifier("credential-no-reveal-policy")
            Text("If someone else set this up")
                .font(.headline)
                .accessibilityIdentifier("hide-lock-heading")
            Text("iOS can hide this app. We cannot prevent that, and we do not offer stealth mode, alternate icons, or a second name. Check Settings → Apps → Hidden Apps, Screen Time, Battery, and App Store purchase history. Apple's Personal Safety guide: https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web")
                .wrappingFillCaption()
                .accessibilityIdentifier("hide-lock-body")

            Text("Stop and delete")
                .font(.headline)
                .accessibilityIdentifier("wipe-section-heading")
            Text(WipeCopy.counts(wipeInventory))
                .wrappingFillCaption()
                .accessibilityIdentifier("wipe-counts")
            Text(WipeCopy.receivedLimit)
                .wrappingFillCaption()
                .accessibilityIdentifier("wipe-received-limit")
            if wipeInventory.received.isEmpty {
                Text(WipeCopy.noneReceived)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("wipe-none-received")
            } else {
                ForEach(Array(wipeInventory.received.enumerated()), id: \.offset) { index, range in
                    Text(WipeCopy.receivedLine(range))
                        .wrappingFillCaption()
                        .accessibilityIdentifier("wipe-received-\(index)")
                }
            }
            Text(WipeCopy.healthLimit)
                .wrappingFillCaption()
                .accessibilityIdentifier("wipe-health-limit")
            Text(WipeCopy.healthPath)
                .wrappingFillCaption()
                .accessibilityIdentifier("wipe-health-path")
            Text(WipeCopy.macLimit)
                .wrappingFillCaption()
                .accessibilityIdentifier("wipe-mac-limit")
            Button(stopHeartRateArmed ? "Confirm: stop exporting heart rate" : "Stop exporting heart rate") {
                if stopHeartRateArmed {
                    Task { await stopHeartRate() }
                } else {
                    stopHeartRateArmed = true
                    status = "Ready. Tap again to purge queued heart-rate payloads and disable that type."
                }
            }
            .buttonStyle(HarnessButtonStyle())
            .accessibilityIdentifier("stop-heart-rate")
            .disabled(phase == .working)
            Button(wipeArmed ? WipeCopy.confirmTitle : WipeCopy.title) {
                if wipeArmed {
                    Task { await wipeDevice() }
                } else {
                    wipeArmed = true
                    status = "Ready. Tap again to destroy credentials, pairing, and the ledger signing identity."
                }
            }
            .buttonStyle(HarnessButtonStyle())
            .accessibilityIdentifier("wipe-everything")
            .disabled(phase == .working)

            Text("Diagnostics")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("diagnostic-section-heading")
            Stepper(
                "Include at least \(diagnosticMinimumRuns) recent runs",
                value: $diagnosticMinimumRuns,
                in: 1 ... 100
            )
            .frame(minHeight: 44)
            .accessibilityIdentifier("diagnostic-minimum-runs")
            Stepper(
                "Include runs from \(diagnosticWindowHours) hours",
                value: $diagnosticWindowHours,
                in: 1 ... 168
            )
            .frame(minHeight: 44)
            .accessibilityIdentifier("diagnostic-window-hours")
            Button("Build diagnostic bundle") {
                buildDiagnostic()
            }
            .buttonStyle(HarnessButtonStyle())
            .accessibilityIdentifier("diagnostic-build")
            .disabled(phase == .working)
            .accessibilityHint("Assembles a redacted ohe.diagnostic/1 JSON preview. Sharing exists only below the bundle's last line.")
            if !diagnosticPreview.isEmpty {
                let previewParts = diagnosticPreview.components(separatedBy: "\n\n")
                let summary = previewParts.first ?? diagnosticPreview
                let json = previewParts.dropFirst().joined(separator: "\n\n")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(
                        Array(summary.split(separator: "\n", omittingEmptySubsequences: false).enumerated()),
                        id: \.offset
                    ) { index, line in
                        let trimmed = String(line).trimmingCharacters(in: .whitespaces)
                        selectableMonospaceLine(
                            trimmed.isEmpty ? " " : trimmed,
                            identifier: index == 0 ? "diagnostic-preview" : "diagnostic-preview-\(index)"
                        )
                    }
                    if !json.isEmpty {
                        // One line per view so the clip audit does not see a 600-point
                        // UILabel. The lines stay in the accessibility tree: hiding them
                        // left visible text the audit then reported as inaccessible.
                        Text("Redacted diagnostic JSON")
                            .font(.body)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("diagnostic-preview-json")
                        ForEach(
                            Array(DiagnosticPreviewLayout.displayLines(json).enumerated()),
                            id: \.offset
                        ) { index, line in
                            Text(line)
                                .font(.body)
                                .foregroundStyle(.black)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(Color.white)
                                .contentShape(Rectangle())
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(line)
                                .accessibilityIdentifier("diagnostic-json-\(index)")
                        }
                    }
                }
                // S9: the share affordance exists only past the last line of content, so
                // it cannot be reached without traversing the bundle by scroll, VoiceOver
                // or Full Keyboard Access. Visibility, not an onAppear, is the evidence:
                // a ScrollView builds every child eagerly whether it is on screen or not.
                Text("End of diagnostic bundle")
                    .wrappingPrimaryCaption()
                    .accessibilityIdentifier("diagnostic-end")
                    // A low threshold is the honest one: the marker sits below every line
                    // of the bundle, so any part of it entering the viewport already
                    // means the content above it was traversed.
                    .onScrollVisibilityChange(threshold: 0.1) { visible in
                        if visible { revealDiagnosticShare() }
                    }
                if let diagnosticShareURL {
                    // SEC-45: the warning is shown once, and acknowledging it is what
                    // reveals the share control. R-26 still governs where this sits —
                    // below the bundle's last line — so the two gates compose rather
                    // than one replacing the other.
                    if shareProtectionAcknowledged {
                        ShareLink(item: diagnosticShareURL) {
                            Text("Share diagnostic")
                        }
                        .accessibilityIdentifier("diagnostic-share")
                    } else {
                        Text(ShareDisclosure.copy)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .attentionBanner()
                            .accessibilityIdentifier("share-protection-warning")
                        Button("I understand — show sharing") {
                            shareProtectionAcknowledged = true
                        }
                        .buttonStyle(HarnessButtonStyle())
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("share-protection-continue")
                    }
                }
            }
        }
        .controlSize(.large)
    }

    private var companionPairingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Companion pairing")
                .font(.headline)
            if pairingImportMismatch {
                Text("The pairing names a different Mac than the imported configuration.")
                    .wrappingFillCaption()
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("pairing-import-name-mismatch")
            }
            if PairingCamera.canPresentScanner {
                Button {
                    Task { await openScanner() }
                } label: {
                    Text("Scan pairing QR")
                        .wrappingActionLabel()
                }
                .buttonStyle(.plain)
                .disabled(phase == .working)
                .accessibilityIdentifier("pairing-scan")
            } else {
                Text(PairingCamera.unavailableReason)
                    .wrappingFillCaption()
                    .accessibilityIdentifier("pairing-scan-unavailable")
            }
            TextEditor(text: $pairingPaste)
                .frame(minHeight: 88)
                .font(.system(.footnote, design: .monospaced))
                .accessibilityLabel("Pairing payload from the Mac")
                .accessibilityIdentifier("pairing-paste")
            secretFieldHygiene(pairingPaste, identifierPrefix: "pairing-paste")
            Button {
                parsePairing()
            } label: {
                Text("Parse pairing payload")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("pairing-parse")
            if !sas.isEmpty {
                Text("Confirmation: \(sas)")
                    .font(.title2)
                    .accessibilityLabel("Confirmation code \(sas)")
                    .accessibilityIdentifier("pairing-confirmation")
                Text("This must match the Mac after the phone connects.")
                    .wrappingFillCaption()
            }
            Button {
                Task { await runCompanionExport() }
            } label: {
                Text("Export one page to companion")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working || pairing == nil)
            .accessibilityIdentifier("pairing-export")
            .accessibilityHint("Browses for the paired Mac name and pushes one page over TLS-PSK.")
            Button {
                Task { await forgetPairing() }
            } label: {
                Text("Forget companion pairing")
                    .wrappingActionLabel()
            }
            .buttonStyle(.plain)
            .disabled(phase == .working)
            .accessibilityIdentifier("pairing-forget")
            Toggle("Send traceparent to Mac companion (opt-in)", isOn: $companionTraceparent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("companion-traceparent")
                .onChange(of: companionTraceparent) { _, enabled in
                    try? HarnessExport.setCompanionTraceparent(enabled)
                }
            Toggle("Allow cellular and other metered networks", isOn: $allowMeteredCompanion)
                .frame(minHeight: 44)
                .accessibilityIdentifier("companion-metered")
            Text("Off by default. Exports wait for Wi-Fi unless you turn this on.")
                .wrappingFillCaption()
        }
    }

    private func buildDiagnostic() {
        diagnosticShareURL = nil
        diagnosticGate = DiagnosticPreviewGate()
        do {
            let built = try HarnessExport.diagnosticBundle(
                minimumRuns: diagnosticMinimumRuns,
                windowHours: diagnosticWindowHours
            )
            diagnosticPreview = built.preview
            diagnosticPayload = built.payload
            status = "Ready. Sharing exists only below the bundle's last line."
        } catch {
            diagnosticPreview = ""
            diagnosticPayload = nil
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func revealDiagnosticShare() {
        guard diagnosticShareURL == nil, let diagnosticPayload else { return }
        diagnosticGate.reachedEnd(of: diagnosticPayload)
        guard let payload = diagnosticGate.sharePayload else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-diagnostic.json")
        do {
            try payload.write(to: url, options: .atomic)
            diagnosticShareURL = url
            status = "Ready. You reached the end of the bundle, so sharing it is available."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    #if !OHE_OBS25_SIZE_BASELINE
    private func revealOTLPEnable() {
        guard let otlpPayload else { return }
        otlpGate.reachedEnd(of: otlpPayload)
        status = "Ready. You reached the end of the OTLP preview, so enabling is available."
    }

    @MainActor
    private func previewOTLP() async {
        phase = .working
        otlpGate = DiagnosticPreviewGate()
        do {
            let built = try await HarnessExport.previewOTLP()
            otlpPreview = built.preview
            otlpPayload = built.payload
            status = "Ready. Enabling exists only below the preview's last line."
        } catch {
            otlpPreview = ""
            otlpPayload = nil
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func enableOTLP() async {
        phase = .working
        guard let preview = otlpGate.sharePayload else {
            status = "Failed: preview the payload before enabling."
            phase = .ready
            return
        }
        do {
            otlpLines = try await HarnessExport.enableOTLPCollector(
                urlString: CredentialFieldHygiene.url(otlpURL).normalized,
                allowInsecureHTTP: allowInsecureOTLP,
                previewPayload: preview
            )
            refreshDestinationSurfaces()
            status = "Ready. OTLP collector is enabled and off the health export path."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func projectOTLP() async {
        phase = .working
        do {
            let result = try await HarnessExport.projectOTLP()
            otlpLines = [result]
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            status = "Ready. \(result)"
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    private func disableOTLP() {
        do {
            try HarnessExport.disableOTLPCollector()
            otlpGate = DiagnosticPreviewGate()
            otlpPreview = ""
            otlpPayload = nil
            refreshDestinationSurfaces()
            status = "Ready. OTLP collector is disabled."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }
    #endif

    @MainActor
    private func loadLedger() async {
        phase = .working
        status = NamedWorkProgress.verifyingLedger
        do {
            ledgerLines = try await HarnessExport.ledgerLines()
            ledgerWarning = ledgerLines.first ?? ""
            networkActivityLines = HarnessExport.networkActivityLines()
            provenanceLines = HarnessExport.buildProvenanceLines()
            status = "Ready. The ledger includes attempts and failures; it contains counts, not health values."
        } catch {
            ledgerLines = []
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func loadHistory() async {
        phase = .working
        do {
            historyEvents = try await HarnessExport.historyEvents()
            revealedHistoryIDs = []
            if historyEvents.isEmpty {
                historyLines = [
                    RunHistoryDetail.emptyStateCopy,
                    RunHistoryDetail.retentionCopy,
                ]
                status = RunHistoryDetail.emptyStateCopy
            } else {
                historyLines = []
                status = "Ready. Problems are listed before successful runs."
            }
        } catch {
            historyEvents = []
            historyLines = []
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    private func historyRowID(_ event: RunEvent) -> String {
        "\(event.runID.rawValue)-\(Int(event.wallTimeEpoch))"
    }

    @MainActor
    private func revealHistoryPayload(_ rowID: String) async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OHE_HISTORY_PAYLOAD_AUTH"] == "skip" {
            revealedHistoryIDs.insert(rowID)
            return
        }
        #endif
        let unlocked = await LocalAuthenticationAdapter().authenticate(
            reason: "Reveal the exact export payload stored on \(DeviceNoun.thisDevice)."
        )
        if unlocked {
            revealedHistoryIDs.insert(rowID)
        } else {
            status = "Payload stayed hidden because authentication did not complete."
        }
    }

    @MainActor
    private func loadDestinationScope(_ destinationID: String) async {
        do {
            let scope = try await HarnessExport.destinationScope(destinationID)
            scopeDestinationID = destinationID
            browserBaseline = scope.metrics
            browserSelection = scope.metrics
            scopeStartDate = scope.startInclusive ?? Date()
            scopeEndEnabled = scope.endExclusive != nil
            scopeEndDate = scope.endExclusive
                ?? max(Date().addingTimeInterval(24 * 60 * 60), scopeStartDate.addingTimeInterval(24 * 60 * 60))
            browserReviewVisible = false
            browserSelecting = false
        } catch {
            browserBaseline = []
            browserSelection = []
            status = "Failed to load \(destinationID) scope: \(error.localizedDescription)"
        }
    }

    private func applyCoreDailyPreset() {
        let shipped = CoreDailyPreset.current
        let applied = coreDailyAppliedVersion == 0 ? nil : coreDailyAppliedVersion
        switch MetricPresetAdoption.nextAction(
            shipped: shipped,
            appliedVersion: applied,
            snapshots: CoreDailyPreset.snapshots
        ) {
        case .applyNow:
            browserSelection = shipped.metricIDs
            coreDailyAppliedVersion = shipped.version
            coreDailyUpgrade = nil
        case .offerDiff(let diff):
            coreDailyUpgrade = diff
        }
    }

    @MainActor
    private func applyBrowserSelection() async {
        phase = .working
        do {
            let priorUnion = Set(try await HarnessExport.selectedMetrics())
            let scope = try DestinationExportScope(
                destinationID: scopeDestinationID,
                metrics: browserSelection,
                startInclusive: scopeStartDate,
                endExclusive: scopeEndEnabled ? scopeEndDate : nil
            )
            let adding = HarnessExport.isDestinationEnabled(scopeDestinationID)
                ? scope.metrics.subtracting(priorUnion)
                : []
            if !adding.isEmpty {
                try await HealthKitAuthorization.requestReadAccess(
                    metrics: adding.sorted { $0.rawValue < $1.rawValue }
                )
            }
            try await HarnessExport.applyDestinationScope(
                scope,
                previousMetrics: browserBaseline
            )
            browserBaseline = browserSelection
            browserReviewVisible = false
            AppLifecycleCoordinator.shared.stopObservers()
            await startHealthObserversIfEligible()
            status = "Ready. \(scopeDestinationID) export scope updated."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    private var scopeDestinationLabel: String {
        switch scopeDestinationID {
        case "local-file": "Archive folder"
        case "https": "HTTPS"
        case "home-assistant": "Home Assistant webhook"
        case "mqtt": "MQTT"
        case "companion": "Mac companion"
        default: scopeDestinationID
        }
    }

    @MainActor
    private func refreshAuthorizedMetricsForReview() async {
        let union = Set((try? await HarnessExport.selectedMetrics()) ?? [])
        authorizedForReview = union.union(browserBaseline)
    }

    @ViewBuilder
    private func urlFieldHygiene(_ raw: String, identifierPrefix: String) -> some View {
        let hygiene = CredentialFieldHygiene.url(raw)
        if hygiene.strippedWhitespace {
            Text(CredentialFieldHygiene.whitespaceNote)
                .wrappingFillCaption()
                .accessibilityIdentifier("\(identifierPrefix)-whitespace")
        }
        if hygiene.replacedSmartPunctuation {
            Text(CredentialFieldHygiene.smartPunctuationNote)
                .wrappingFillCaption()
                .accessibilityIdentifier("\(identifierPrefix)-smartquotes")
        }
        if let parseBack = hygiene.parseBack {
            Text(parseBack)
                .wrappingFillCaption()
                .accessibilityIdentifier("\(identifierPrefix)-parseback")
        }
    }

    #if DEBUG
    private func seedUserFacingErrorsFromLaunchEnvironment() {
        guard let raw = ProcessInfo.processInfo.environment["OHE_SEED_USER_FACING_ERROR"]
        else {
            return
        }
        if raw == "all" {
            seededUserFacingErrors = UserFacingErrorArchetype.allCases.map { archetype in
                UserFacingErrorObject.make(
                    archetype: archetype,
                    destinationLabel: "nas"
                )
            }
        } else if let archetype = UserFacingErrorArchetype(rawValue: raw) {
            let error = UserFacingErrorObject.make(
                archetype: archetype,
                destinationLabel: "nas"
            )
            userFacingError = error
            status = error.title
            results = error.lines
        }
    }
    #endif

    @ViewBuilder
    private func selectableMonospaceLine(_ line: String, identifier: String) -> some View {
        Text(line)
            .font(.body)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func secretFieldHygiene(_ raw: String, identifierPrefix: String) -> some View {
        let hygiene = CredentialFieldHygiene.secret(raw)
        if hygiene.strippedWhitespace {
            Text(CredentialFieldHygiene.whitespaceNote)
                .wrappingFillCaption()
                .accessibilityIdentifier("\(identifierPrefix)-whitespace")
        }
        if hygiene.replacedSmartPunctuation {
            Text(CredentialFieldHygiene.smartPunctuationNote)
                .wrappingFillCaption()
                .accessibilityIdentifier("\(identifierPrefix)-smartquotes")
        }
    }

    @MainActor
    private func presentHealthPriming() async {
        do {
            let metrics = try await HarnessExport.selectedMetrics()
            guard !metrics.isEmpty else {
                status = "Configure and enable a destination scope before requesting Health access."
                return
            }
            primingTypeCount = metrics.count
            showHealthPriming = true
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func requestAccess() async {
        phase = .working
        status = NamedWorkProgress.requestingHealthAccess
        do {
            let metrics = try await HarnessExport.selectedMetrics()
            guard !metrics.isEmpty else {
                status = "Configure and enable a destination scope before requesting Health access."
                phase = .ready
                return
            }
            try await HealthKitAuthorization.requestReadAccess(
                metrics: metrics
            )
            try await HarnessExport.observeAuthorizationChanges()
            try await HarnessExport.reenableCoreActivityAfterAuthorizationRequest()
            await startHealthObserversIfEligible()
            status = "Ready. Health authorisation finished. Apple does not tell us whether you allowed or denied a type."
            phase = .ready
        } catch {
            status = "Failed: \(error.localizedDescription)"
            phase = .ready
        }
    }

    @MainActor
    private func runR70() async {
        phase = .working
        status = NamedWorkProgress.measure(current: 0, total: 2)
        results = []
        let context = TemporalContext.utcHost
        let source = HealthKitSampleSource(context: context, limit: 10_000)
        var lines: [String] = []
        let metrics = [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id]
        for (index, metric) in metrics.enumerated() {
            status = NamedWorkProgress.measure(current: index + 1, total: metrics.count)
            do {
                let sample = try await HealthKitThroughput.measure(source: source, metric: metric)
                lines.append(
                    "\(metric.rawValue): \(sample.samples) samples in \(sample.seconds) s → \(sample.samplesPerSecond) samples/s"
                )
            } catch {
                lines.append("\(metric.rawValue): failed — \(error.localizedDescription)")
            }
        }
        results = lines
        status = "Ready. R-70 finished. Copy the lines below into the findings doc. Simulator stores are often empty; use REF-B or the XR for a real number."
        phase = .ready
    }

    @MainActor
    private func refreshSecurityAdvisory() async {
        do {
            let presentation = try await HarnessExport.fetchSecurityAdvisory(
                enabled: advisoryEnabled
            )
            advisoryBanner = presentation.banner
            advisoryItems = presentation.items
        } catch {
            advisoryBanner = AdvisoryStaleness.staleCopy
            advisoryItems = []
        }
    }

    private var dataBrowser: some View {
        let samples = MetricCatalog.selectable.enumerated().map { index, declaration in
            DemoCorpus.sample(at: index, seed: 1, declaration: declaration)
        }
        let demoLatest = Dictionary(
            uniqueKeysWithValues: samples.map { ($0.metric, $0) }
        )
        let liveLatest = Dictionary(
            uniqueKeysWithValues: liveBrowserSamples.compactMap { metric, samples in
                samples.sorted { $0.start > $1.start }.first.map { (metric, $0) }
            }
        )
        let latest = browserDemoMode ? demoLatest : liveLatest
        let coverage = browserDemoMode ? [:] : browserCoverageObservations()
        let rows = DataBrowser.rows(
            latest: latest,
            exported: browserSelection,
            search: browserSearch,
            onlyWithData: browserOnlyWithData && !browserSelecting,
            displayUnits: displayUnitPolicy,
            coverage: coverage,
            coverageLastDataDays: coverageLastDataDays
        )
        let selectedDetail = selectedBrowserMetric.flatMap { metric in
            let live = liveBrowserSamples[metric]
            let detailSamples = live
                ?? (browserDemoMode ? samples.filter { $0.metric == metric } : [])
            let detailNow = live == nil && browserDemoMode
                ? detailSamples.first.flatMap { ISO8601DateFormatter().date(from: $0.start) }
                    ?? Date(timeIntervalSince1970: 0)
                : Date()
            return DataBrowser.detail(
                metric: metric,
                samples: detailSamples,
                destinations: browserSentThroughDay[metric].map {
                    [DataBrowserDestination(name: "Archive folder", sentThroughDay: $0)]
                } ?? [],
                displayUnits: displayUnitPolicy,
                now: detailNow,
                indexHorizonDay: browserIndexHorizonDay
            )
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDetail?.title ?? "Data")
                    .font(.headline)
                    .accessibilityIdentifier("browser-title")
                Spacer()
                if selectedDetail != nil {
                    Button("Back") { selectedBrowserMetric = nil }
                        .buttonStyle(.plain)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Back")
                        .accessibilityIdentifier("browser-back")
                } else if browserSelecting {
                    Button("Review changes") {
                        browserSelecting = false
                        browserReviewVisible = true
                        Task { await refreshAuthorizedMetricsForReview() }
                    }
                    .buttonStyle(.plain)
                    .wrappingPrimaryCaption()
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("browser-review")
                } else {
                    Button("Select") {
                        browserBaseline = browserSelection
                        browserSelecting = true
                        browserReviewVisible = false
                    }
                    .buttonStyle(.plain)
                    .wrappingPrimaryCaption()
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("browser-select")
                }
            }
            Text(
                browserDemoMode
                    ? "Demo values. This is what App Review sees without HealthKit history."
                    : "Health values read on \(DeviceNoun.thisDevice)."
            )
                .wrappingFillCaption()
                .fontWeight(browserDemoMode ? .semibold : .regular)

            if selectedDetail == nil, !browserSearchIsFiltering {
                Text("Export destination")
                    .wrappingFillCaption()
                    .accessibilityIdentifier("scope-destination")
                ForEach(
                    [
                        ("local-file", "Archive folder"),
                        ("https", "HTTPS"),
                        ("home-assistant", "Home Assistant"),
                        ("mqtt", "MQTT"),
                        ("companion", "Mac companion"),
                    ],
                    id: \.0
                ) { id, title in
                    Button(title) {
                        scopeDestinationID = id
                        Task { await loadDestinationScope(id) }
                    }
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .fontWeight(scopeDestinationID == id ? .semibold : .regular)
                    .buttonStyle(HarnessButtonStyle())
                    .accessibilityIdentifier("scope-destination-\(id)")
                }
                Text("Each destination starts with zero types. Choose a destination, types, and the earliest date it may receive.")
                    .wrappingFillCaption()
                    .accessibilityIdentifier("scope-zero-default")
                if browserSelection.isEmpty {
                    Text("Scope required: this destination cannot export until at least one type is selected.")
                        .wrappingFillCaption()
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("scope-required")
                }
                DatePicker(
                    "Send samples starting",
                    selection: $scopeStartDate,
                    displayedComponents: .date
                )
                .font(.body)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("scope-start-date")
                dataTabToggle(
                    "Stop sending after a date",
                    isOn: $scopeEndEnabled,
                    identifier: "scope-end-enabled"
                )
                if scopeEndEnabled {
                    DatePicker(
                        "Stop before",
                        selection: $scopeEndDate,
                        in: scopeStartDate.addingTimeInterval(24 * 60 * 60)...,
                        displayedComponents: .date
                    )
                    .accessibilityIdentifier("scope-end-date")
                }
            }

            if let detail = selectedDetail {
                Button {
                    Task { await loadBrowserSamples(metric: detail.metric) }
                } label: {
                    Text(browserLoadingHealth ? "Loading Health data…" : "Load 30 days from Health")
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(browserLoadingHealth)
                .accessibilityIdentifier("browser-load-health")
                dataBrowserDetail(detail)
            } else {
                if browserSelecting {
                    HStack {
                        Button("Use Core Daily") {
                            applyCoreDailyPreset()
                        }
                        .buttonStyle(.plain)
                        .wrappingPrimaryCaption()
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("browser-core-daily")
                        Button("Invert routine") {
                            var draft = DataSelectionDraft(baseline: browserSelection)
                            draft.invertRoutine(MetricCatalog.selectable.map(\.id))
                            browserSelection = draft.selected
                        }
                        .buttonStyle(.plain)
                        .wrappingPrimaryCaption()
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("browser-invert-routine")
                        Button("Clear all") { browserSelection.removeAll() }
                            .buttonStyle(.plain)
                            .wrappingPrimaryCaption()
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("browser-clear-all")
                    }
                    if let upgrade = coreDailyUpgrade {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Review Core Daily update")
                                .font(.headline)
                                .accessibilityIdentifier("preset-upgrade-title")
                            Text(upgrade.summary)
                                .accessibilityIdentifier("preset-upgrade-summary")
                            HStack {
                                Button("Apply Core Daily update") {
                                    let shipped = CoreDailyPreset.current
                                    browserSelection = shipped.metricIDs
                                    coreDailyAppliedVersion = shipped.version
                                    coreDailyUpgrade = nil
                                }
                                .buttonStyle(.plain)
                                .wrappingPrimaryCaption()
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("preset-upgrade-apply")
                                Button("Keep current types") {
                                    coreDailyUpgrade = nil
                                }
                                .buttonStyle(.plain)
                                .wrappingPrimaryCaption()
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("preset-upgrade-keep")
                            }
                        }
                    }
                }
                if browserReviewVisible {
                    let review = DataSelectionReview.comparing(
                        selected: browserSelection,
                        baseline: browserBaseline,
                        authorized: authorizedForReview,
                        destinationName: scopeDestinationLabel
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review changes")
                            .font(.headline)
                            .accessibilityIdentifier("browser-review-title")
                        Text("Adding \(review.adding.count) types")
                            .accessibilityIdentifier("browser-review-adding")
                        Text("Removing \(review.removing.count) types")
                            .accessibilityIdentifier("browser-review-removing")
                        if let permission = review.permissionConsequence {
                            Text(permission)
                                .wrappingFillCaption()
                                .fontWeight(.semibold)
                                .accessibilityIdentifier("browser-review-permission")
                        }
                        if let warning = review.removalWarning {
                            Text(warning)
                                .wrappingFillCaption()
                                .fontWeight(.semibold)
                        }
                        Button("Continue") {
                            Task { await applyBrowserSelection() }
                        }
                        .buttonStyle(HarnessButtonStyle())
                        .accessibilityIdentifier("browser-review-continue")
                    }
                }
                if let pendingSensitiveMetric {
                    Text("Sensitive type — type \(scopeDestinationID) to add it individually.")
                        .wrappingFillCaption()
                        .accessibilityIdentifier("sensitive-type-prompt")
                    TextField(scopeDestinationID, text: $sensitiveDestinationConfirmation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("sensitive-destination-confirmation")
                    secretFieldHygiene(
                        sensitiveDestinationConfirmation,
                        identifierPrefix: "sensitive-destination-confirmation"
                    )
                    Button("Confirm sensitive type") {
                        if CredentialFieldHygiene.secret(sensitiveDestinationConfirmation)
                            .normalized == scopeDestinationID
                        {
                            browserSelection.insert(pendingSensitiveMetric)
                            self.pendingSensitiveMetric = nil
                            sensitiveDestinationConfirmation = ""
                        }
                    }
                    .buttonStyle(HarnessButtonStyle())
                    .disabled(
                        CredentialFieldHygiene.secret(sensitiveDestinationConfirmation)
                            .normalized != scopeDestinationID
                    )
                    .accessibilityIdentifier("sensitive-destination-confirm")
                }
                dataTabToggle(
                    "Only types with data",
                    isOn: $browserOnlyWithData,
                    identifier: "browser-only-with-data"
                )
                dataTabToggle(
                    "Show demo values",
                    isOn: $browserDemoMode,
                    identifier: "browser-demo-mode"
                )
                if !browserSearchIsFiltering {
                Text("Display units")
                    .wrappingFillCaption()
                    .accessibilityLabel("Display units")
                    .accessibilityIdentifier("browser-display-units")
                ForEach(DisplayUnitPreference.allCases, id: \.self) { preference in
                    Button {
                        displayUnitPreference = preference
                    } label: {
                        Text(preference.label)
                            .wrappingActionLabel()
                            .fontWeight(displayUnitPreference == preference ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(preference.label)
                    .accessibilityIdentifier("browser-display-units-\(preference.rawValue)")
                }
                Text("Time format")
                    .wrappingFillCaption()
                    .accessibilityLabel("Time format")
                    .accessibilityIdentifier("browser-time-format")
                ForEach(ClockDisplay.allCases, id: \.self) { choice in
                    Button {
                        clockDisplay = choice
                    } label: {
                        Text(choice.label)
                            .wrappingActionLabel()
                            .fontWeight(clockDisplay == choice ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(choice.label)
                    .accessibilityIdentifier("browser-time-format-\(choice.rawValue)")
                }
                Text("Sample times read as \(clockDisplay.timeString(Date(), locale: Locale.current, timeZone: .current)).")
                    .wrappingFillCaption()
                    .accessibilityIdentifier("browser-time-example")
                }
                TextField("Search types", text: $browserSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search types")
                    .accessibilityIdentifier("browser-search")
                if rows.isEmpty {
                    Text("No data types match your search.")
                        .wrappingFillCaption()
                        .accessibilityLabel("No data types match your search.")
                        .accessibilityIdentifier("browser-empty")
                }
                ForEach(rows) { row in
                    Button {
                        if browserSelecting {
                            if browserSelection.contains(row.metric) {
                                browserSelection.remove(row.metric)
                            } else if row.sensitive {
                                pendingSensitiveMetric = row.metric
                            } else {
                                browserSelection.insert(row.metric)
                            }
                        } else {
                            selectedBrowserMetric = row.metric
                            Task { await loadBrowserSamples(metric: row.metric) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                if browserSelecting {
                                    Image(systemName: browserSelection.contains(row.metric)
                                        ? "checkmark.circle.fill"
                                        : "circle")
                                        .font(.body)
                                        .accessibilityHidden(true)
                                }
                                Text(row.title)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                if row.reidentifying {
                                    Text(DataBrowser.reidentifyingBadge)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .foregroundStyle(.primary)
                                } else if row.sensitive {
                                    Text("sensitive")
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .foregroundStyle(.primary)
                                }
                            }
                            Text(row.subtitle)
                                .wrappingFillCaption()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.title), \(row.subtitle)")
                    .accessibilityIdentifier("browser-row-\(row.metric.rawValue)")
                }
            }
        }
    }

    private var browserSearchIsFiltering: Bool {
        !browserSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A titled SwiftUI Toggle exposes that title twice to the hosted contrast
    /// audit (empty identifier, duplicated label). Hide the switch's own title
    /// and keep the visible copy out of the accessibility tree.
    @ViewBuilder
    private func dataTabToggle(
        _ title: String,
        isOn: Binding<Bool>,
        identifier: String
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .wrappingFillCaption()
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.primary)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    @ViewBuilder
    private func dataBrowserDetail(_ detail: DataBrowserDetail) -> some View {
        if let latest = detail.latest {
            Text("Latest")
                .wrappingFillCaption()
            Text(
                "\(DataBrowser.formatValue(detail.displayValue ?? latest.value)) "
                    + detail.displayUnit
            )
                .wrappingFillCaption()
                .accessibilityIdentifier("browser-detail-latest")
            if detail.displayUnit != detail.exportUnit {
                Text("Export remains \(detail.exportUnit).")
                    .wrappingFillCaption()
            }
            Text(latest.start)
                .wrappingFillCaption()
            Text("Source: \(latest.source?.name ?? "Unknown")")
                .wrappingFillCaption()
        } else {
            Text(DataBrowser.emptyDetailCopy)
                .wrappingFillCaption()
                .accessibilityIdentifier("browser-detail-empty")
        }
        Text("Exported to")
            .wrappingFillCaption()
        if detail.destinations.isEmpty {
            Text("Not included in any export.")
                .wrappingFillCaption()
        } else {
            ForEach(detail.destinations, id: \.name) { destination in
                Text("\(destination.name) · data through \(destination.sentThroughDay ?? "no day yet") has been sent")
                    .wrappingFillCaption()
            }
        }
        Text("Export unit: \(detail.exportUnit)")
            .wrappingFillCaption()
        if let horizon = detail.indexHorizonDay {
            Text(DataBrowser.horizonCopy(day: horizon))
                .wrappingFillCaption()
                .accessibilityIdentifier("browser-index-horizon")
        }
        if let explanation = detail.aggregationExplanation {
            Text("Daily buckets (this is what we export)")
                .wrappingFillCaption()
            Text("Computed as: \(explanation)")
                .wrappingFillCaption()
        }
        Text("Samples")
            .wrappingFillCaption()
            .accessibilityIdentifier("browser-detail-samples")
        ForEach(detail.samples, id: \.key.uuid) { sample in
            Text("\(DataBrowser.formatValue(sample.value)) \(detail.exportUnit) · \(sample.start)")
                .wrappingFillCaption()
        }
    }

    private func browserRecords(from page: SamplePage) -> [SampleRecord] {
        let unit = MetricCatalog.declaration(for: page.metric)?.canonicalUnit
            ?? CanonicalUnit(symbol: "s")
        var records = page.samples
        records.append(contentsOf: page.categories.map { category in
            SampleRecord(
                key: category.key,
                metric: category.metric,
                start: category.start,
                end: category.end,
                timeZoneOffsetMinutes: category.timeZoneOffsetMinutes,
                timeZoneSource: category.timeZoneSource,
                value: category.durationSeconds ?? Double(category.categoryValue),
                unit: unit,
                observedAt: category.observedAt,
                source: category.source,
                device: category.device,
                wasUserEntered: category.wasUserEntered
            )
        })
        records.append(contentsOf: page.workouts.map { workout in
            SampleRecord(
                key: workout.key,
                metric: workout.metric,
                start: workout.start,
                end: workout.end,
                timeZoneOffsetMinutes: workout.timeZoneOffsetMinutes,
                timeZoneSource: workout.timeZoneSource,
                value: workout.durationSeconds,
                unit: unit,
                observedAt: workout.observedAt,
                source: workout.source,
                device: workout.device,
                wasUserEntered: workout.wasUserEntered
            )
        })
        return records
    }

    private var coverageDropEvents: [CoverageDropEvent] {
        let current = Dictionary(
            uniqueKeysWithValues: browserCoverageObservations().map {
                ($0.key, CoverageClassification.classify($0.value))
            }
        )
        return CoverageDrop.events(
            lastDataDays: coverageLastDataDays,
            current: current,
            selected: browserSelection
        )
    }

    private func browserCoverageObservations() -> [MetricID: CoverageObservation] {
        var observations = coverageProbeObservations
        for (metric, samples) in liveBrowserSamples where !samples.isEmpty {
            let latest = samples.max { $0.start < $1.start }
            observations[metric] = CoverageObservation(
                sampleCount: samples.count,
                latestStart: latest?.start,
                earliestAuthorizedDay: browserAuthorizedDays[metric]
                    ?? observations[metric]?.earliestAuthorizedDay
            )
        }
        for metric in browserSelection where observations[metric] == nil {
            observations[metric] = CoverageObservation(
                earliestAuthorizedDay: browserAuthorizedDays[metric]
            )
        }
        return observations
    }

    private func exporterTemporalContext() -> TemporalContext {
        let timeZone = TimeZone.current
        return TemporalContext(
            timeZoneIdentifier: timeZone.identifier,
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: TemporalContext.hostTzDatabaseVersion
        )
    }

    @MainActor
    private func refreshCoverageWindows(metrics: [MetricID]? = nil) async {
        let probed = metrics ?? Array(browserSelection.union(Set(liveBrowserSamples.keys)))
        guard !probed.isEmpty else { return }
        if coverageLastDataDays.isEmpty {
            coverageLastDataDays = CoverageDrop.decodeLastDataDays(
                UserDefaults.standard.data(forKey: CoverageDrop.storageKey)
            )
        }
        if let days = try? await HealthKitAuthorization.earliestAuthorizedDays(for: probed) {
            for metric in probed {
                browserAuthorizedDays[metric] = days[metric]
            }
        }
        let probedObservations = await HealthKitCoverageProbe.observations(
            for: probed,
            context: exporterTemporalContext()
        )
        for (metric, observation) in probedObservations {
            var merged = observation
            if merged.earliestAuthorizedDay == nil {
                merged.earliestAuthorizedDay = browserAuthorizedDays[metric]
            }
            coverageProbeObservations[metric] = merged
        }
        let current = Dictionary(
            uniqueKeysWithValues: coverageProbeObservations.map {
                ($0.key, CoverageClassification.classify($0.value))
            }
        )
        coverageLastDataDays = CoverageDrop.nextLastDataDays(
            previous: coverageLastDataDays,
            current: current
        )
        if let data = CoverageDrop.encodeLastDataDays(coverageLastDataDays) {
            UserDefaults.standard.set(data, forKey: CoverageDrop.storageKey)
        }
    }

    @MainActor
    private func loadBrowserSamples(metric: MetricID) async {
        browserLoadingHealth = true
        defer { browserLoadingHealth = false }
        let timeZone = TimeZone.current
        let context = exporterTemporalContext()
        var loaded: [SampleRecord] = []
        do {
            if MetricCatalog.declaration(for: metric)?.kind == "sample.quantity" {
                let source = HealthKitDayObservationSource(context: context, limit: 1000)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                for offset in 0 ..< DataBrowserPeriod.month.rawValue {
                    guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                        continue
                    }
                    loaded.append(contentsOf: try await source.samples(
                        metric: metric,
                        day: formatter.string(from: date)
                    ))
                }
            } else {
                let page = try await HealthKitAnchoredSource(context: context, limit: 1000)
                    .page(metric: metric, afterAnchor: nil)
                loaded = browserRecords(from: page)
            }
            liveBrowserSamples[metric] = loaded
            await refreshSentThroughDay(metric)
            await refreshCoverageWindows(metrics: [metric])
            let state = CoverageClassification.classify(
                browserCoverageObservations()[metric] ?? CoverageObservation(sampleCount: loaded.count)
            )
            status = loaded.isEmpty
                ? DataBrowser.emptyDetailCopy
                : CoverageClassification.subtitle(state)
        } catch {
            status = "Couldn't read this type. Health data may be locked; this usually resolves on its own."
        }
    }

    @MainActor
    private func runDemoExport() async {
        phase = .working
        status = "Exporting demo dataset…"
        do {
            results = try await HarnessExport.runDemoDataset(
                typedDestinationName: CredentialFieldHygiene.secret(demoConfirmName).normalized
            )
            refreshDestinationSurfaces()
            status = "Demo export finished. Files are DEMO- prefixed."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    private func runLocalExport(trigger: RunTrigger = .manual) async {
        phase = .working
        status = CombinedExportSummary.progress(current: 0, total: 1)
        results = []
        await refreshCoverageWindows()
        do {
            results = try await HarnessExport.runOnePageEachMetric(trigger: trigger) { current, total in
                await MainActor.run {
                    status = CombinedExportSummary.progress(current: current, total: total)
                }
            }
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            await refreshWakeAttribution()
            await refreshQueueGaps()
            status = results.first ?? "Ready. Local export finished."
        } catch {
            let label = await HarnessExport.notifyRunFailure(trigger: trigger)
            presentUserFacingFailure(error, destinationLabel: label ?? "Archive folder")
        }
        phase = .ready
    }

    @MainActor
    private func runFullReconcile() async {
        phase = .working
        status = NamedWorkProgress.reconcile(current: 0, total: 1)
        results = []
        do {
            results = try await HarnessExport.runFullReconcile { current, total in
                await MainActor.run {
                    status = NamedWorkProgress.reconcile(current: current, total: total)
                }
            }
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            status = "Ready. Full reconciliation finished without advancing anchored cursors."
        } catch {
            await HarnessExport.notifyRunFailure(trigger: .manual)
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func runBackfill(mode: BackfillMode) async {
        phase = .working
        status = NamedWorkProgress.archive(completedMonths: 0, totalMonths: 1, type: 0, types: 1)
        results = []
        do {
            if try ContinuedBackfillCoordinator.submit(mode: mode) {
                status = "Ready. iOS accepted the unattended backfill; progress is available in the system UI."
                phase = .ready
                return
            }
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            ArchiveLiveActivitySession.start()
            do {
                results = try await HarnessExport.runBackfill(mode: mode) { line in
                    await MainActor.run {
                        status = line
                    }
                    await ArchiveLiveActivitySession.update(progressLine: line)
                }
                await ArchiveLiveActivitySession.finish()
            } catch {
                await ArchiveLiveActivitySession.finish()
                throw error
            }
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            status = backfillFinishedStatus(results)
        } catch {
            await HarnessExport.notifyRunFailure(trigger: .manual)
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    private func backfillFinishedStatus(_ results: [String]) -> String {
        if results.contains(where: { $0.hasSuffix("backfill parked") }) {
            if results.contains(CatchUpAdmission.lowPowerParkedJournalDetail) {
                return "Ready. Backfill is paused while Low Power Mode is on."
            }
            if results.contains(CatchUpAdmission.thermalParkedJournalDetail) {
                return "Ready. Backfill is paused while your \(DeviceNoun.current) cools down."
            }
            if results.contains(CatchUpAdmission.parkedJournalDetail) {
                return "Ready. Backfill is paused until queued work drains."
            }
            if results.contains(CatchUpAdmission.destinationParkedJournalDetail) {
                return "Ready. Backfill is paused until the destination recovers."
            }
            return "Ready. Backfill is paused."
        }
        return "Ready. Foreground backfill completed."
    }

    @MainActor
    private func refreshQueueGaps() async {
        queueEvictionGaps = (try? await HarnessExport.queueEvictionGaps()) ?? []
        let loaded = (try? await HarnessExport.anchorHolds()) ?? []
        #if DEBUG
        if loaded.isEmpty, ProcessInfo.processInfo.environment["OHE_SEED_ANCHOR_HOLD"] != nil {
            reapplySeededAnchorHoldIfNeeded()
            return
        }
        #endif
        anchorHolds = loaded
    }

    #if DEBUG
    /// `refreshQueueGaps` reads SQLite. A UI-test seed can still be in memory
    /// when that read returns empty. Do not blank the banner the test asserts.
    @MainActor
    private func reapplySeededAnchorHoldIfNeeded() {
        guard let held = ProcessInfo.processInfo.environment["OHE_SEED_ANCHOR_HOLD"],
              anchorHolds.isEmpty
        else { return }
        anchorHolds = [
            AnchorHold(
                metric: MetricID(rawValue: held),
                reason: .cursorLost,
                detectedAtEpoch: 0,
                lastEmittedDay: "2026-09-08"
            )
        ]
    }
    #endif

    /// QA-17: both answers are explicit and both are recorded. Neither is a retry.
    @MainActor
    private func decideAnchorHold(_ hold: AnchorHold, reexport: Bool) async {
        do {
            if reexport {
                try await HarnessExport.authoriseAnchorReexport(metric: hold.metric)
                status = "\(hold.metric.rawValue) will send its history again on the next export."
            } else {
                try await HarnessExport.stopExportingHeldType(metric: hold.metric)
                status = "\(hold.metric.rawValue) is no longer being exported."
            }
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        anchorHolds = (try? await HarnessExport.anchorHolds()) ?? []
    }

    /// R-69: the browser reports what the export recorded emitting, so a type that is
    /// selected but never sent shows no destination at all.
    @MainActor
    private func refreshSentThroughDay(_ metric: MetricID) async {
        guard let day = try? await HarnessExport.sentThroughDay(metric: metric) else {
            browserSentThroughDay[metric] = nil
            browserIndexHorizonDay = try? await HarnessExport.indexHorizonDay()
            return
        }
        browserSentThroughDay[metric] = day
        browserIndexHorizonDay = try? await HarnessExport.indexHorizonDay()
    }

    @MainActor
    private func refreshWakeAttribution() async {
        wakeAttribution = (try? await HarnessExport.wakeAttributionLine()) ?? ""
    }

    @MainActor
    private func reExportQueueGap(_ gap: GapRecord) async {
        phase = .working
        status = NamedWorkProgress.reexport(current: 1, total: 1)
        do {
            let kind = try await HarnessExport.reExportQueueGap(gap)
            await refreshLedgerIntegrity()
            status = "Ready. Gap re-export finished: \(kind.rawValue)."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func enableLocalFile() async {
        phase = .working
        status = NamedWorkProgress.test(
            current: 0,
            total: DestinationTestPlan.localFile.total,
            step: DestinationTestPlan.localFile.first.progressLabel
        )
        wipeArmed = false
        do {
            _ = try await HarnessExport.enableLocalFileDestination { current, total, step in
                Task { @MainActor in
                    status = NamedWorkProgress.test(
                        current: current,
                        total: total,
                        step: step.progressLabel
                    )
                }
            }
            refreshDestinationSurfaces()
            await startHealthObserversIfEligible()
            await refreshLedgerIntegrity()
            localFileTestLines = []
            status = "Ready. Local archive passed write/read/confirm and is enabled."
        } catch {
            if case SetupError.testFailed(let step) = error {
                localFileTestLines = [DestinationTestReport.failed(at: step).failureSummary]
                    .compactMap { $0 }
            } else {
                localFileTestLines = []
            }
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func prepareConfigurationExport() async {
        configurationExportURL = nil
        do {
            configurationExportURL =
                try await HarnessExport.portableConfigurationExport()
            status = "Ready. The .tributary file contains destination settings and scope, but no credentials."
        } catch {
            status = "Configuration export failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func loadImportedDestinationDraft(
        _ draft: ImportedDestinationDraftRecord
    ) {
        let inputs: PortableDestinationSetupInputs
        do {
            inputs = try PortableDestinationMaterializer.materialize(
                draft.configuration
            )
        } catch {
            status = "Import refused: \(error.localizedDescription)"
            return
        }
        let slot = inputs.slotIdentifier
        importedDestinationDraft = draft
        guard !HarnessExport.hasDestinationConfiguration(slot) else {
            status = "Import refused: the \(slot) destination slot already has a configuration. Disable and remove it before importing another."
            return
        }
        scopeDestinationID = slot
        browserBaseline = []
        browserSelection = Set(draft.configuration.exportScope.metrics)
        scopeStartDate =
            draft.configuration.exportScope.startInclusive ?? Date()
        scopeEndEnabled =
            draft.configuration.exportScope.endExclusive != nil
        scopeEndDate =
            draft.configuration.exportScope.endExclusive
                ?? scopeStartDate.addingTimeInterval(365 * 24 * 60 * 60)
        switch draft.configuration.kind {
        case .https:
            httpsURL = inputs.endpoint
            allowInsecureHTTP = inputs.allowInsecure
            status = "Ready. HTTPS fields loaded from the disabled draft. Add the omitted credential, then run the destination test."
        case .homeAssistant:
            homeAssistantBaseURL = inputs.endpoint
            allowInsecureHomeAssistant = inputs.allowInsecure
            status = "Ready. Home Assistant fields loaded from the disabled draft. Add the omitted webhook ID, then run the destination test."
        case .mqtt:
            mqttURL = inputs.endpoint
            mqttClientID = inputs.clientID ?? mqttClientID
            mqttTopic = inputs.topic ?? mqttTopic
            mqttQoS = inputs.qos ?? 1
            allowInsecureMQTT = inputs.allowInsecure
            status = "Ready. MQTT fields loaded from the disabled draft. Add omitted credentials, then run the destination test."
        case .companion:
            pairingImportMismatch = false
            status = "Ready. Companion Mac name loaded from the disabled draft. Paste or scan pairing, then run the destination test."
        default:
            importedDestinationDraft = nil
            status = "Import refused: this destination kind does not have a setup path."
        }
    }

    @MainActor
    private func testHTTPS() async {
        phase = .working
        let httpsURLNormalized = CredentialFieldHygiene.url(httpsURL).normalized
        let httpsScheme = URL(string: httpsURLNormalized)?.scheme?.lowercased() == "https"
        let httpsPlan = DestinationTestPlan.https(hasPin: httpsScheme)
        status = NamedWorkProgress.test(
            current: 0,
            total: httpsPlan.total,
            step: httpsPlan.first.progressLabel
        )
        do {
            confirmationKind = .https
            confirmationCard = try await HarnessExport.prepareHTTPSDestination(
                urlString: CredentialFieldHygiene.url(httpsURL).normalized,
                allowInsecureHTTP: allowInsecureHTTP,
                bearer: {
                    let token = CredentialFieldHygiene.secret(httpsBearer).normalized
                    return token.isEmpty ? nil : token
                }(),
                importedLocalIdentifier:
                    importedDestinationDraft?.configuration.kind == .https
                        ? importedDestinationDraft?.localIdentifier : nil
            ) { current, total, step in
                Task { @MainActor in
                    status = NamedWorkProgress.test(
                        current: current,
                        total: total,
                        step: step.progressLabel
                    )
                }
            }
            httpsTestLines = confirmationCard?.lines ?? []
            userFacingError = nil
            status = "Ready. Confirm this server before any Health data moves."
        } catch {
            confirmationCard = nil
            confirmationKind = nil
            if case SetupError.testFailed(let step) = error {
                httpsTestLines = [DestinationTestReport.failed(at: step).failureSummary].compactMap { $0 }
            } else {
                httpsTestLines = []
            }
            presentUserFacingFailure(error, destinationLabel: httpsURL)
        }
        phase = .ready
    }

    @MainActor
    private func testHomeAssistantWebhook() async {
        phase = .working
        let base = CredentialFieldHygiene.url(
            homeAssistantBaseURL
        ).normalized
        let hasPin = URL(string: base)?.scheme?.lowercased() == "https"
        let plan = DestinationTestPlan.https(hasPin: hasPin)
        status = NamedWorkProgress.test(
            current: 0,
            total: plan.total,
            step: plan.first.progressLabel
        )
        do {
            confirmationKind = .homeAssistant
            confirmationCard = try await HarnessExport.prepareHomeAssistantWebhook(
                baseURLString: base,
                webhookID: CredentialFieldHygiene.secret(
                    homeAssistantWebhookID
                ).normalized,
                allowInsecureHTTP: allowInsecureHomeAssistant,
                importedLocalIdentifier:
                    importedDestinationDraft?.configuration.kind
                        == .homeAssistant
                        ? importedDestinationDraft?.localIdentifier : nil
            ) { current, total, step in
                Task { @MainActor in
                    status = NamedWorkProgress.test(
                        current: current,
                        total: total,
                        step: step.progressLabel
                    )
                }
            }
            homeAssistantTestLines = confirmationCard?.lines ?? []
            userFacingError = nil
            status = "Ready. Confirm this Home Assistant webhook before any Health data moves."
        } catch {
            confirmationCard = nil
            confirmationKind = nil
            if case SetupError.testFailed(let step) = error {
                homeAssistantTestLines = [
                    DestinationTestReport.failed(at: step).failureSummary
                ].compactMap { $0 }
            } else {
                homeAssistantTestLines = []
            }
            presentUserFacingFailure(
                error,
                destinationLabel: "Home Assistant webhook"
            )
        }
        phase = .ready
    }

    @MainActor
    private func testMQTT() async {
        phase = .working
        let mqttURLNormalized = CredentialFieldHygiene.url(mqttURL).normalized
        let mqttScheme = URL(string: mqttURLNormalized)?.scheme
        let mqtts = mqttScheme?.lowercased() == "mqtts"
        let mqttPlan = DestinationTestPlan.mqtt(
            scheme: mqttScheme,
            confirmsDelivery: mqttQoS != 0,
            hasPin: mqtts
        )
        status = NamedWorkProgress.test(
            current: 0,
            total: mqttPlan.total,
            step: mqttPlan.first.progressLabel
        )
        do {
            confirmationKind = .mqtt
            confirmationCard = try await HarnessExport.prepareMQTTDestination(
                urlString: CredentialFieldHygiene.url(mqttURL).normalized,
                allowInsecure: allowInsecureMQTT,
                clientID: CredentialFieldHygiene.secret(mqttClientID).normalized,
                topic: CredentialFieldHygiene.secret(mqttTopic).normalized,
                clientPKCS12: mqttPKCS12Data,
                clientPKCS12Password: {
                    let password = CredentialFieldHygiene.secret(mqttPKCS12Password).normalized
                    return password.isEmpty ? nil : password
                }(),
                username: {
                    let name = CredentialFieldHygiene.secret(mqttUsername).normalized
                    return name.isEmpty ? nil : name
                }(),
                password: {
                    let password = CredentialFieldHygiene.secret(mqttPassword).normalized
                    return password.isEmpty ? nil : password
                }(),
                qos: mqttQoS,
                importedLocalIdentifier:
                    importedDestinationDraft?.configuration.kind == .mqtt
                        ? importedDestinationDraft?.localIdentifier : nil
            ) { current, total, step in
                Task { @MainActor in
                    status = NamedWorkProgress.test(
                        current: current,
                        total: total,
                        step: step.progressLabel
                    )
                }
            }
            mqttTestLines = confirmationCard?.lines ?? []
            if mqttQoS == 0 {
                let error = UserFacingErrorObject.make(
                    archetype: .mqttQoS0,
                    destinationLabel: mqttURL
                )
                userFacingError = error
                status = error.title
                results = error.lines
            } else {
                userFacingError = nil
                status = "Ready. Confirm this server before any Health data moves."
            }
        } catch {
            confirmationCard = nil
            confirmationKind = nil
            if case SetupError.testFailed(let step) = error {
                mqttTestLines = [DestinationTestReport.failed(at: step).failureSummary].compactMap { $0 }
            } else {
                mqttTestLines = []
            }
            presentUserFacingFailure(error, destinationLabel: mqttURL)
        }
        phase = .ready
    }

    @MainActor
    private func confirmPendingDestination() async {
        phase = .working
        status = NamedWorkProgress.enablingDestination
        do {
            let activatingDraft = importedDestinationDraft.flatMap { draft in
                let kind = draft.configuration.kind
                return (confirmationKind == .https && kind == .https)
                    || (confirmationKind == .homeAssistant && kind == .homeAssistant)
                    || (confirmationKind == .mqtt && kind == .mqtt)
                    ? draft : nil
            }
            if let draft = activatingDraft {
                let destinationID: String
                switch draft.configuration.kind {
                case .https:
                    destinationID = "https"
                case .homeAssistant:
                    destinationID = "home-assistant"
                default:
                    destinationID = "mqtt"
                }
                try await HarnessExport.saveDestinationScope(
                    try DestinationExportScope(
                        destinationID: destinationID,
                        metrics: browserSelection,
                        startInclusive: scopeStartDate,
                        endExclusive: scopeEndEnabled ? scopeEndDate : nil
                    )
                )
            }
            switch confirmationKind {
            case .https:
                httpsTestLines = try await HarnessExport.confirmPendingHTTPSDestination(
                    propagateTraceparent: propagateTraceparent
                )
                httpsBearer = ""
                status = "Ready. Network destination passed its real-path test and is enabled."
            case .homeAssistant:
                homeAssistantTestLines =
                    try await HarnessExport.confirmPendingHTTPSDestination()
                homeAssistantWebhookID = ""
                status = "Ready. Home Assistant webhook passed its real-path test and is enabled."
            case .mqtt:
                mqttTestLines = try await HarnessExport.confirmPendingMQTTDestination()
                status = "Ready. MQTT destination passed its real-path test and is enabled."
            case nil:
                status = "Failed: nothing to confirm."
            }
            if let draft = activatingDraft {
                do {
                    try ImportedDestinationDraftStore.remove(
                        localIdentifier: draft.localIdentifier
                    )
                    importedDestinationDraft = nil
                    importedDraftRefreshToken += 1
                    status += " Imported scope applied and the disabled draft was consumed."
                } catch {
                    status += " The destination is enabled, but its inert draft could not be removed; discard that draft manually."
                }
            }
            confirmationCard = nil
            confirmationKind = nil
            publicAddressConfirmation = ""
            refreshDestinationSurfaces()
            await reevaluateAutomaticExport()
            await refreshLedgerIntegrity()
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    private func cancelDestinationConfirmation() {
        HarnessExport.cancelPendingHTTPSDestination()
        HarnessExport.cancelPendingMQTTDestination()
        confirmationCard = nil
        confirmationKind = nil
        publicAddressConfirmation = ""
    }

    private func applyOpenURL(_ url: URL) {
        if AppLifecycleCoordinator.shared.pendingDeepLink == url {
            _ = AppLifecycleCoordinator.shared.consumePendingDeepLink()
        }
        if let route = UserFacingErrorRoute(url: url) {
            applyErrorRoute(route)
            return
        }
        if ExportNowRoute(url: url) != nil {
            applyExportNowRoute()
            return
        }
        applyWidgetStatusURL(url)
    }

    private func applyErrorRoute(_ route: UserFacingErrorRoute) {
        refreshDestinationSurfaces()
        let snapshot = destinationSnapshots.first { $0.destinationID == route.destinationID }
        let now = Date().timeIntervalSince1970
        guard let object = UserFacingErrorPresentation.object(
            route: route,
            snapshot: snapshot,
            nowEpoch: now
        ) else {
            status = disclosureAcknowledged
                ? "Ready. Opened destination status for \(route.destinationID) from a notification."
                : "Review the disclosure before opening destination status."
            return
        }
        userFacingError = object
        results = object.lines
        if disclosureAcknowledged {
            phase = .ready
            rootTab = .status
            status = object.title
        } else {
            status = "Review the disclosure before opening destination status."
        }
    }

    private func presentErrorFromStatus(_ snapshot: DestinationStatusSnapshot) {
        refreshDestinationSurfaces()
        let now = Date().timeIntervalSince1970
        if let object = UserFacingErrorPresentation.object(for: snapshot, nowEpoch: now) {
            userFacingError = object
            results = object.lines
            status = object.title
            return
        }
        status = "Ready. Opened destination status for \(snapshot.destinationID)."
    }

    private func applyExportNowRoute() {
        guard disclosureAcknowledged, HarnessExport.hasAutomaticExport(trigger: .widgetControl) else {
            status = disclosureAcknowledged
                ? "Enable a destination before exporting from Control Centre."
                : "Review the disclosure before exporting from Control Centre."
            return
        }
        rootTab = .status
        Task { await runLocalExport(trigger: .widgetControl) }
    }

    private func applyWidgetStatusURL(_ url: URL) {
        guard let route = WidgetStatusRoute(url: url) else { return }
        refreshDestinationSurfaces()
        if disclosureAcknowledged {
            phase = .ready
            rootTab = .status
            status = route.destinationID.map {
                "Ready. Opened destination status for \($0) from the widget."
            } ?? "Ready. Opened destination status from the widget."
        } else {
            status = "Review the disclosure before opening destination status."
        }
    }

    private func refreshHealthKitDisplayUnits() async {
        let fallback = displayUnitPreference.policy(locale: Locale.current)
        guard displayUnitPreference == .automatic else {
            healthKitUnitPolicy = nil
            return
        }
        healthKitUnitPolicy = await HealthKitPreferredDisplayUnits.policy(fallback: fallback)
    }

    private func refreshDestinationSurfaces() {
        HarnessExport.synchronizeDestinationExportRoles()
        destinationSnapshots = StatusSnapshotLocation.readAll()
        let now = Date().timeIntervalSince1970
        destinationStatusLines = destinationSnapshots.isEmpty
            ? [DestinationStatusLine.emptyCopy]
            : destinationSnapshots.map { snapshot in
                DestinationStatusLine.render(snapshot, nowEpoch: now) {
                    Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened)
                }
            }
        destinationChangeBanner = HarnessExport.destinationChangeBannerDetail()
        overdueBanner = HarnessExport.overdueBannerDetail()
        dataFlowHops = HarnessExport.dataFlowHops()
        let credentials = HarnessExport.storedCredentialSummaries()
        httpsBearerDescriptor = credentials.httpsBearer
        homeAssistantWebhookDescriptor = credentials.homeAssistantWebhook
        mqttPasswordDescriptor = credentials.mqttPassword
        mqttPKCS12PasswordDescriptor = credentials.mqttPKCS12Password
        Task {
            dataFlowTypeCount = await HarnessExport.dataFlowTypeCount()
            wipeInventory = await HarnessExport.wipeInventory()
        }
    }

    @ViewBuilder
    private func destinationConfirmation(_ card: DestinationConfirmationCard) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Confirm this server")
                        .wrappingFillCaption()
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("destination-confirm-title")
                    ForEach(Array(card.lines.dropFirst().enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .wrappingFillCaption()
                            .accessibilityIdentifier("destination-confirm-line-\(index)")
                    }
                    if card.requiresPublicAddressConfirmation {
                        Text(ConfirmationCopy.publicAddressWarning)
                            .attentionBanner()
                            .accessibilityIdentifier("public-destination-warning")
                        TextField(
                            ConfirmationCopy.publicAddressPhrase,
                            text: $publicAddressConfirmation
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("public-destination-confirmation")
                        secretFieldHygiene(
                            publicAddressConfirmation,
                            identifierPrefix: "public-destination-confirmation"
                        )
                    }
                    Button {
                        Task { await confirmPendingDestination() }
                    } label: {
                        Text("This is my server")
                            .wrappingActionLabel()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        card.requiresPublicAddressConfirmation
                            && CredentialFieldHygiene.secret(publicAddressConfirmation)
                                .normalized != ConfirmationCopy.publicAddressPhrase
                    )
                    .accessibilityIdentifier("destination-confirm")
                    Button("Cancel") {
                        cancelDestinationConfirmation()
                    }
                    .buttonStyle(HarnessButtonStyle())
                    .accessibilityIdentifier("destination-confirm-cancel")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.colorScheme, .light)
                .foregroundStyle(.black)
                .background(Color.white)
            }
            .background(Color.white)
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
    }

    @MainActor
    private func runMQTTExport() async {
        phase = .working
        status = NamedWorkProgress.types(current: 0, total: 1)
        do {
            results = try await HarnessExport.runMQTTDestination { current, total in
                await MainActor.run {
                    status = NamedWorkProgress.types(current: current, total: total)
                }
            }
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            await refreshWakeAttribution()
            status = "Ready. MQTT export finished."
        } catch {
            await HarnessExport.notifyDestinationFailure(
                destinationID: "mqtt",
                destinationLabel: "MQTT destination"
            )
            presentUserFacingFailure(error, destinationLabel: "MQTT destination")
        }
        phase = .ready
    }

    @MainActor
    private func runHTTPSExport() async {
        phase = .working
        status = NamedWorkProgress.types(current: 0, total: 1)
        do {
            results = try await HarnessExport.runHTTPSDestination { current, total in
                await MainActor.run {
                    status = NamedWorkProgress.types(current: current, total: total)
                }
            }
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            await refreshWakeAttribution()
            status = "Ready. HTTPS export finished."
        } catch {
            await HarnessExport.notifyDestinationFailure(
                destinationID: "https",
                destinationLabel: "HTTPS destination"
            )
            presentUserFacingFailure(error, destinationLabel: "HTTPS destination")
        }
        phase = .ready
    }

    @MainActor
    private func runHomeAssistantExport() async {
        phase = .working
        status = NamedWorkProgress.types(current: 0, total: 1)
        do {
            results = try await HarnessExport.runHTTPSDestination(
                destinationID: "home-assistant",
                destinationLabel: "Home Assistant webhook"
            ) { current, total in
                await MainActor.run {
                    status = NamedWorkProgress.types(
                        current: current,
                        total: total
                    )
                }
            }
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            await refreshWakeAttribution()
            status = "Ready. Home Assistant webhook export finished."
        } catch {
            await HarnessExport.notifyDestinationFailure(
                destinationID: "home-assistant",
                destinationLabel: "Home Assistant webhook"
            )
            presentUserFacingFailure(
                error,
                destinationLabel: "Home Assistant webhook"
            )
        }
        phase = .ready
    }

    @MainActor
    private func stopHeartRate() async {
        phase = .working
        status = NamedWorkProgress.purge(current: 1, total: 1)
        do {
            try await HarnessExport.stopExportingHeartRate()
            stopHeartRateArmed = false
            await refreshLedgerIntegrity()
            status = "Ready. Heart rate is disabled and queued payloads for that type were purged."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func wipeDevice() async {
        phase = .working
        status = NamedWorkProgress.wipe(current: 1, total: 1)
        do {
            try await HarnessExport.wipeEverything()
            wipeArmed = false
            stopHeartRateArmed = false
            pairing = nil
            sas = ""
            pairingPaste = ""
            disclosureAcknowledged = false
            foregroundCatchUpStarted = false
            AppLifecycleCoordinator.shared.stopObservers()
            refreshDestinationSurfaces()
            ledgerLines = []
            await refreshLedgerIntegrity()
            phase = .disclosure
            status = "Credentials and the previous ledger identity were destroyed."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        if disclosureAcknowledged {
            phase = .ready
        }
    }

    @MainActor
    private func refreshLedgerIntegrity() async {
        do {
            ledgerWarning = try await HarnessExport.ledgerIntegrityLine()
        } catch {
            ledgerWarning = "WARNING: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendSampleNotice() async {
        phase = .working
        status = NamedWorkProgress.notify(current: 1, total: 1)
        do {
            let delivery = try await LocalUserNotifier().notify(
                UserNotice(kind: .destinationEnabled, destination: "local-file")
            )
            switch delivery {
            case .posted:
                status = "Ready. The copy came from NoticeCopy, not this screen."
            case .skippedAuthorizationDenied:
                status = "Ready. Notifications are off — the widget still escalates when export is overdue."
            case .skippedRateLimited:
                status = "Ready. A recent failure notification already covers this destination."
            case .notRequired:
                status = "Ready."
            }
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func openScanner() async {
        let allowed = await PairingCamera.requestAccess()
        guard allowed, PairingCamera.canPresentScanner else {
            status = PairingCamera.unavailableReason
            return
        }
        showScanner = true
    }

    private var importedCompanionServiceName: String? {
        guard importedDestinationDraft?.configuration.kind == .companion,
              let draft = importedDestinationDraft,
              let name = try? PortableDestinationMaterializer.materialize(
                  draft.configuration
              ).serviceName
        else {
            return nil
        }
        return name
    }

    private func parsePairing() {
        pairingImportMismatch = false
        do {
            let payload = try PairingPayload.parse(
                CredentialFieldHygiene.secret(pairingPaste).normalized
            )
            if let expected = importedCompanionServiceName,
               payload.serviceName != expected {
                pairingImportMismatch = true
                pairing = nil
                sas = ""
                status = "Import refused: the pairing names a different Mac than the imported configuration."
                return
            }
            let local = try HarnessExport.installationID()
            let session = PairingSession.phone(payload: payload, localInstallationID: local)
            pairing = session
            sas = session.confirmationCode ?? ""
            Task { try? await HarnessExport.vault().save(session) }
            status = "Ready. Confirmation is on screen. Open the Mac receive window, then export."
        } catch {
            status = "Failed: \(error.localizedDescription)"
            pairing = nil
            sas = ""
        }
    }

    @MainActor
    private func runCompanionExport() async {
        guard let pairing else { return }
        phase = .working
        let companionPlan = DestinationTestPlan.companion
        status = NamedWorkProgress.test(
            current: 0,
            total: companionPlan.total,
            step: companionPlan.first.progressLabel
        )
        results = []
        do {
            results = try await HarnessExport.runCompanion(
                session: pairing,
                onTestProgress: { current, total, step in
                    Task { @MainActor in
                        status = NamedWorkProgress.test(
                            current: current,
                            total: total,
                            step: step.progressLabel
                        )
                    }
                }
            ) { current, total in
                await MainActor.run {
                    status = NamedWorkProgress.types(current: current, total: total)
                }
            }
            refreshDestinationSurfaces()
            await reevaluateAutomaticExport()
            if let draft = importedDestinationDraft,
               draft.configuration.kind == .companion,
               pairing.serviceName == importedCompanionServiceName {
                try await HarnessExport.saveDestinationScope(
                    try DestinationExportScope(
                        destinationID: "companion",
                        metrics: browserSelection,
                        startInclusive: scopeStartDate,
                        endExclusive: scopeEndEnabled ? scopeEndDate : nil
                    )
                )
                try ImportedDestinationDraftStore.remove(
                    localIdentifier: draft.localIdentifier
                )
                importedDestinationDraft = nil
                importedDraftRefreshToken += 1
                status =
                    "Ready. Companion export finished. Compare confirmation \(sas) with the Mac. Imported scope applied and the disabled draft was consumed."
            } else {
                status = "Ready. Companion export finished. Compare confirmation \(sas) with the Mac."
            }
        } catch {
            await HarnessExport.notifyDestinationFailure(
                destinationID: "companion",
                destinationLabel: "Mac companion"
            )
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func restorePairing() async {
        guard let session = try? await HarnessExport.vault().load() else { return }
        pairing = session
        sas = session.confirmationCode ?? ""
        pairingPaste = (try? session.qrPayload().encoded()) ?? pairingPaste
        status = "Ready. Restored the stored companion pairing."
    }

    @MainActor
    private func forgetPairing() async {
        do {
            try await HarnessExport.forgetCompanion()
            pairing = nil
            sas = ""
            pairingPaste = ""
            refreshDestinationSurfaces()
            await reevaluateAutomaticExport()
            status = "Ready. Companion pairing forgotten and its destination disabled."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func presentUserFacingFailure(_ error: Error, destinationLabel: String) {
        let object: UserFacingErrorObject?
        if let egress = error as? EgressError {
            switch egress {
            case .httpStatus(let status):
                object = UserFacingErrorArchetype.fromHTTPStatus(status).map {
                    UserFacingErrorObject.make(
                        archetype: $0,
                        destinationLabel: destinationLabel,
                        evidence: UserFacingErrorEvidence(statusCode: status)
                    )
                }
            case .httpRetryAfter(let status, let seconds):
                object = UserFacingErrorObject.make(
                    archetype: .http429,
                    destinationLabel: destinationLabel,
                    evidence: UserFacingErrorEvidence(
                        statusCode: status,
                        retryAfterSeconds: Int(seconds)
                    )
                )
            case .transport:
                object = UserFacingErrorObject.make(
                    archetype: .timeout,
                    destinationLabel: destinationLabel
                )
            default:
                object = nil
            }
        } else if let send = error as? DestinationSendError,
                  let archetype = UserFacingErrorArchetype.fromErrorClass(send.errorClass) {
            object = UserFacingErrorObject.make(
                archetype: archetype,
                destinationLabel: destinationLabel
            )
        } else {
            object = nil
        }
        userFacingError = object
        if let object {
            status = object.title
            results = object.lines
        } else {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func applyUserFacingFix(_ action: UserFacingFixAction) {
        var settings = OwnedExportSettings(
            windowHours: exportWindowHours,
            freshnessIntervalMinutes: freshnessIntervalMinutes,
            mqttQoS: mqttQoS
        )
        UserFacingFixApplier.apply(action, to: &settings)
        exportWindowHours = settings.windowHours
        freshnessIntervalMinutes = settings.freshnessIntervalMinutes
        mqttQoS = settings.mqttQoS
        userFacingError = nil
        status = UserFacingErrorCopy.applied(action)
        switch action {
        case .testAgain:
            if confirmationKind == .mqtt || !mqttURL.isEmpty && httpsURL.isEmpty {
                Task { await testMQTT() }
            } else if !httpsURL.isEmpty {
                Task { await testHTTPS() }
            }
        case .setQoS1:
            if !mqttURL.isEmpty, !mqttClientID.isEmpty, !mqttTopic.isEmpty {
                Task { await testMQTT() }
            }
        default:
            break
        }
    }

    @MainActor
    private func startHealthObserversIfEligible() async {
        do {
            try await AppLifecycleCoordinator.shared.startObserversIfEligible()
        } catch {
            status = "Background Health delivery registration failed: \(error.localizedDescription)"
        }
    }

    /// Whether automatic export is possible at all depends on the whole set of
    /// destinations, so enabling or disabling any one of them re-decides the
    /// observers. Only the archive folder used to do this, which left a user whose
    /// single destination was HTTPS, MQTT, Home Assistant or the Mac companion with
    /// no wake source until the next launch.
    @MainActor
    private func reevaluateAutomaticExport() async {
        AppLifecycleCoordinator.shared.stopObservers()
        await startHealthObserversIfEligible()
    }
}

private struct HarnessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    /// Body type, primary contrast, and wrap. Do not force a 44-point minimum at
    /// the default size: that pushed Status copy into the iPad tab fade.
    func wrappingPrimaryCaption() -> some View {
        self
            .font(.body)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Same as wrappingPrimaryCaption, but occupies the proposed width so RTL
    /// Data-tab detail copy wraps instead of compressing to one unreadably
    /// narrow line (hosted iPad `testBrowserDetailInRTL`).
    func wrappingFillCaption() -> some View {
        wrappingPrimaryCaption()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Control titles that must reflow at accessibility Dynamic Type sizes.
    func wrappingActionLabel() -> some View {
        wrappingPrimaryCaption()
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// Black on a deliberately light yellow. The banner has to clear the contrast
    /// audit while still reading as a warning, and `.yellow` with default label
    /// colour does not. Pin light scheme so `.primary` cannot bleach the copy in
    /// Dark Mode. Children stay individually addressable: the banners are
    /// asserted by their inner copy, not only by the container identifier.
    func attentionBanner() -> some View {
        self
            .environment(\.colorScheme, .light)
            .foregroundStyle(Color(red: 0, green: 0, blue: 0))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(red: 1, green: 0.82, blue: 0.12))
            .fixedSize(horizontal: false, vertical: true)
    }
}
