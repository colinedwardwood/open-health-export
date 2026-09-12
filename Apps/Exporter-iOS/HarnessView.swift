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
        case mqtt
    }

    @State private var phase: Phase = .disclosure
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
    @State private var allowInsecureHTTP = false
    @State private var propagateTraceparent = false
    @State private var companionTraceparent = false
    @State private var httpsTestLines: [String] = []
    @State private var mqttURL = ""
    @State private var mqttClientID = "ohe-iphone"
    @State private var mqttTopic = "ohe/health"
    @State private var mqttQoS: UInt8 = 1
    @State private var userFacingError: UserFacingErrorObject?
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
    @State private var importedDestinationDraft: ImportedDestinationDraftRecord?
    @State private var importedDraftRefreshToken = 0
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
    @State private var historyLines: [String] = []
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
    @State private var browserSentThroughDay: [MetricID: String] = [:]
    @State private var browserIndexHorizonDay: String?
    @State private var browserLoadingHealth = false
    @State private var foregroundCatchUpStarted = false
    @AppStorage("ohe.browserOnlyWithData")
    private var browserOnlyWithData = true
    /// SEC-45: one-time, so it persists past the run that acknowledged it.
    @AppStorage("ohe.shareProtectionAcknowledged")
    private var shareProtectionAcknowledged = false
    @AppStorage("ohe.browserDemoMode")
    private var browserDemoMode = false
    @AppStorage("ohe.displayUnitPreference")
    private var displayUnitPreference: DisplayUnitPreference = .automatic
    @AppStorage("ohe.clockDisplay")
    private var clockDisplay: ClockDisplay = .system

    /// The device locale enters here and nowhere deeper: every reading path below takes
    /// an explicit policy, so a locale matrix test can drive them all (R-65).
    private var displayUnitPolicy: UnitDisplayPolicy {
        displayUnitPreference.policy(locale: Locale.current)
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

    var body: some View {
        ZStack {
            if !healthKitAvailable {
                healthKitUnavailable
            } else if isPrivacyLocked {
                privacyLock
            } else {
                NavigationStack {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(status)
                                    .font(.body)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityLabel("Status: \(status)")
                                    .accessibilityIdentifier("status-line")
                                    .id("status-line")

                                if let userFacingError {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(Array(userFacingError.lines.enumerated()), id: \.offset) { index, line in
                                            Text(line)
                                                .font(.system(.footnote, design: .monospaced))
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .accessibilityIdentifier("error-part-\(index)")
                                        }
                                        ForEach(userFacingError.actions, id: \.rawValue) { action in
                                            Button(action.label) {
                                                applyUserFacingFix(action)
                                            }
                                            .disabled(phase == .working)
                                            .accessibilityIdentifier("error-fix-\(action.rawValue)")
                                        }
                                    }
                                    .id("user-facing-error")
                                }

                                Text("Time to first screen: \(timeToFirstFrameMS, specifier: "%.0f") ms (foreground; R-73 is a background-launch budget).")
                                    .font(.footnote)
                                    .fixedSize(horizontal: false, vertical: true)

                                if phase == .disclosure {
                                    disclosure
                                } else {
                                    dataBrowser
                                    controls
                                }

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
                            .padding()
                        }
                        .navigationTitle("M0 harness")
                        .onChange(of: userFacingError) { _, error in
                            guard error != nil else { return }
                            proxy.scrollTo("user-facing-error", anchor: .top)
                        }
                    }
                }
            }
        }
        .tint(.primary)
        .safeAreaInset(edge: .top) {
            if !isPrivacyLocked, let overdueBanner {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Export overdue")
                        .font(.headline)
                    Text(overdueBanner)
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.yellow)
                .accessibilityIdentifier("export-overdue-banner")
            }
        }
        .safeAreaInset(edge: .top) {
            if !isPrivacyLocked, let destinationChangeBanner {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unacknowledged destination change")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(destinationChangeBanner)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.yellow)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("destination-change-banner")
            }
        }
        .safeAreaInset(edge: .top) {
            if !isPrivacyLocked, AnchorHoldBanner.isVisible(anchorHolds) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AnchorHoldBanner.title)
                        .font(.headline)
                    Text(AnchorHoldBanner.detail(anchorHolds))
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.yellow)
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
            refreshDestinationSurfaces()
            #if !OHE_OBS25_SIZE_BASELINE
            if otlpURL.isEmpty {
                otlpURL = HarnessExport.storedOTLPURL()
            }
            #endif
            propagateTraceparent = HarnessExport.storedHTTPSTraceparent()
            companionTraceparent = HarnessExport.storedCompanionTraceparent()
            if disclosureAcknowledged {
                phase = .ready
                status = "Ready."
            }
            Task {
                await appPrivacyGate.authenticateIfNeeded(enabled: appPrivacyGateEnabled)
                await loadDestinationScope(scopeDestinationID)
                do {
                    let expired = try await HarnessExport.expireQueuesAndNotify()
                    if expired.expiredBatches > 0 {
                        status = "Ready. Deleted \(expired.expiredBatches) queued export(s) older than seven days."
                    }
                } catch {
                    status = "Failed to enforce queue expiry: \(error.localizedDescription)"
                }
                #if DEBUG
                if let scenario = ProcessInfo.processInfo
                    .environment["OHE_SEED_DESTINATION_STATUS"]
                {
                    try? HarnessExport.seedDestinationStatusForUITests(scenario: scenario)
                }
                #endif
                try? await HarnessExport.recordNotificationSuppressionIfNeeded()
                await restorePairing()
                await refreshLedgerIntegrity()
                await refreshWakeAttribution()
                await refreshSecurityAdvisory()
                #if DEBUG
                refreshDestinationSurfaces()
                if let held = ProcessInfo.processInfo.environment["OHE_SEED_ANCHOR_HOLD"] {
                    try? await HarnessExport.seedAnchorHoldForUITests(
                        metric: MetricID(rawValue: held)
                    )
                }
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
                #endif
                await refreshQueueGaps()
                await refreshCoverageWindows()
                if disclosureAcknowledged,
                   !foregroundCatchUpStarted,
                   HarnessExport.isLocalFileEnabled() {
                    foregroundCatchUpStarted = true
                    await runLocalExport(trigger: .appForeground)
                }
            }
        }
        .onOpenURL { url in
            applyOpenURL(url)
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
            Text("Unlocking protects this screen only. Background exports and destination delivery continue without a prompt.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if appPrivacyGate.authenticationFailed {
                Text("Authentication was not completed.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("privacy-gate-failure")
            }
            Button(
                appPrivacyGate.state == .authenticating ? "Authenticating…" : "Unlock"
            ) {
                Task {
                    await appPrivacyGate.authenticateIfNeeded(enabled: appPrivacyGateEnabled)
                }
            }
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
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Text(DataFlowExplainer.typeCountCopy(dataFlowTypeCount))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Text(DataFlowExplainer.transform)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            if dataFlowHops.isEmpty {
                Text(DataFlowExplainer.empty)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(dataFlowHops.enumerated()), id: \.element.id) { index, hop in
                    Text(DataFlowExplainer.hopLine(hop))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("data-flow-hop-\(index)")
                }
            }
            Text(DataFlowExplainer.nowhereElse)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("data-flow-explainer")
    }

    private var schedulingHonesty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SchedulingHonesty.title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(SchedulingHonesty.body)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Text(SchedulingHonesty.noSchedulePromise)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scheduling-honesty")
    }

    private var mqttPKCS12Types: [UTType] {
        ["p12", "pfx"].compactMap { UTType(filenameExtension: $0) } + [.data]
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before Health access")
                .font(.headline)
            Text("This is not a medical device. It does not diagnose or treat anything.")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("first-run-disclaimer")
            schedulingHonesty
            Text("You choose what is read. We do not hide destinations, and we do not send telemetry to the maintainers.")
                .fixedSize(horizontal: false, vertical: true)
            dataFlowExplainer
            Button("I understand — continue") {
                disclosureAcknowledged = true
                phase = .ready
                status = "Ready. Next: request Health read access, then measure."
            }
            .accessibilityIdentifier("disclosure-continue")
            .accessibilityHint("Shows Health permission and measurement controls.")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Request Health read access for selected types") {
                Task { await requestAccess() }
            }
            .accessibilityIdentifier("health-request")
            .accessibilityHint("Asks Apple for read permission only for types currently selected in Data.")
            .disabled(phase == .working)

            Text("This is not a medical device. It does not diagnose or treat anything.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("about-disclaimer")

            Text("App privacy")
                .font(.headline)
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
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("privacy-gate-scope")
            Text(CredentialPresentationPolicy.copy)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("credential-no-reveal-policy")

            Text("HealthKit provides no deletion callback. Tombstones are best-effort when iOS next reports a deletion; a full reconcile repairs deletions that were not reported.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("deletion-behaviour")

            Button("Run R-70 (one anchored page per type)") {
                Task { await runR70() }
            }
            .disabled(phase == .working)
            Button("Export one page (local file)") {
                Task { await runLocalExport() }
            }
            .disabled(phase == .working)
            .accessibilityHint("Writes NDJSON under Application Support using the engine and local-file sink.")
            Text(SchedulingHonesty.shortcutsLine)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shortcut-export")
            schedulingHonesty
            Text("Backfill runs newest-first and resumes from an inspectable checkpoint. On iOS 26 or later it continues unattended after you leave the app. On iOS 18 through 25, keep this screen open; the app prevents idle sleep while it works.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("backfill-os-disclosure")
            Button("Backfill all history (aggregates)") {
                Task { await runBackfill(mode: .aggregateOnly) }
            }
            .disabled(phase == .working || !HarnessExport.isLocalFileEnabled())
            .accessibilityIdentifier("backfill-aggregate")
            Button("Backfill raw history (explicit action)") {
                Task { await runBackfill(mode: .raw) }
            }
            .disabled(phase == .working || !HarnessExport.isLocalFileEnabled())
            .accessibilityIdentifier("backfill-raw")
            Button("Reconcile all available Health history") {
                Task { await runFullReconcile() }
            }
            .disabled(phase == .working || !HarnessExport.isLocalFileEnabled())
            .accessibilityIdentifier("full-reconcile")
            .accessibilityHint("Compares every available day without advancing HealthKit anchors.")
            if !anchorHolds.isEmpty {
                Text("Paused data")
                    .font(.headline)
                ForEach(Array(anchorHolds.enumerated()), id: \.offset) { index, hold in
                    Text(AnchorHoldBanner.explanation(hold))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("anchor-hold-explanation-\(index)")
                    Button(AnchorHoldBanner.reexportChoice) {
                        Task { await decideAnchorHold(hold, reexport: true) }
                    }
                    .disabled(phase == .working)
                    .accessibilityIdentifier("anchor-hold-reexport-\(index)")
                    Button(AnchorHoldBanner.stopChoice) {
                        Task { await decideAnchorHold(hold, reexport: false) }
                    }
                    .disabled(phase == .working)
                    .accessibilityIdentifier("anchor-hold-stop-\(index)")
                }
            }
            if !queueEvictionGaps.isEmpty {
                Text("Data gaps")
                    .font(.headline)
                Text("These queued date ranges were evicted to keep storage bounded.")
                    .font(.footnote)
                ForEach(Array(queueEvictionGaps.enumerated()), id: \.offset) { index, gap in
                    Button(
                        "Re-export \(gap.metric.rawValue) "
                            + "\(gap.rangeStartDay ?? "unknown")–\(gap.rangeEndDay ?? "unknown")"
                    ) {
                        Task { await reExportQueueGap(gap) }
                    }
                    .disabled(phase == .working)
                    .accessibilityIdentifier("gap-reexport-\(index)")
                }
            }
            Text("DEMO MODE — synthetic data")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Demo export never reads HealthKit. Type the destination name local-file to confirm you are not sending this into a live archive.")
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Type local-file to confirm demo export", text: $demoConfirmName, axis: .vertical)
                .lineLimit(1...6)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("demo-confirm")
            Button("Export demo dataset (every catalogue metric)") {
                Task { await runDemoExport() }
            }
            .disabled(phase == .working || demoConfirmName != "local-file")
            .accessibilityIdentifier("demo-export")
            .accessibilityHint("Exports synthetic samples marked demo:true into a DEMO- prefixed local folder.")
            Button("Send sample destination-enabled notice") {
                Task { await sendSampleNotice() }
            }
            .disabled(phase == .working)
            .accessibilityHint("Asks for notification permission and posts one R-40 notice with copy from the registry.")

            Text("Security advisories")
                .font(.headline)
            Text(AdvisoryPinnedKeys.urlString)
                .font(.footnote)
                .accessibilityLabel("Security advisory endpoint")
            Text("This is the sole built-in host. The app never sends Health data there. Fetch happens only on a visible foreground launch, never during export.")
                .font(.footnote)
            Toggle("Fetch security advisories", isOn: $advisoryEnabled)
                .frame(minHeight: 44)
            if let advisoryBanner {
                Text(advisoryBanner)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("advisory-banner")
            }
            ForEach(advisoryItems, id: \.id) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.severity.uppercased()): \(item.id)")
                        .font(.subheadline)
                    Text(item.description)
                        .font(.footnote)
                    Text(item.url)
                        .font(.footnote)
                        .accessibilityLabel("Security advisory web link")
                }
                .accessibilityIdentifier("advisory-\(item.id)")
            }

            Text("Where your data goes")
                .font(.headline)
                .accessibilityIdentifier("destination-title")
            dataFlowExplainer
            Text(FreshnessTarget.provisionalDisclosure)
                .font(.footnote)
                .accessibilityIdentifier("freshness-target")
            ForEach(HarnessExport.freshnessDisclosureLines(), id: \.id) { disclosure in
                Text(disclosure.text)
                    .font(.footnote)
                    .accessibilityIdentifier(disclosure.id)
            }
            if !wakeAttribution.isEmpty {
                Text(wakeAttribution)
                    .font(.footnote)
                    .accessibilityIdentifier("wake-attribution")
            }
            if !ledgerWarning.isEmpty {
                Text(ledgerWarning)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.primary)
                    .fontWeight(ledgerWarning.hasPrefix("WARNING") ? .semibold : .regular)
                    .accessibilityLabel("Ledger status: \(ledgerWarning)")
            }
            Text("Your health data is sent only to destinations listed here. This is what the app records about its own use, not independent proof.")
                .font(.footnote)
            ConfigurationImportView(
                refreshToken: importedDraftRefreshToken
            ) { loadImportedDestinationDraft($0) }
            Button("Prepare credential-free configuration export") {
                Task { await prepareConfigurationExport() }
            }
            .accessibilityIdentifier("configuration-export-prepare")
            if let configurationExportURL {
                ShareLink(item: configurationExportURL) {
                    Text("Share .tributary configuration")
                }
                .accessibilityIdentifier("configuration-export-share")
            }
            Button("Enable local archive folder (R-25 test)") {
                Task { await enableLocalFile() }
            }
            .disabled(phase == .working)
            .accessibilityHint("Writes a canary file, reads it back, then enables the local-file destination.")
            Text(ExportProfile.haeCompatibility.label)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("hae-compatibility-label")
            TextField("HTTPS destination URL", text: $httpsURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-url")
            Text(CredentialDisclosure.copy)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("credential-disclosure-https")
            SecureField("Bearer token (optional)", text: $httpsBearer)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-bearer")
            Toggle("Allow plain HTTP (unsafe)", isOn: $allowInsecureHTTP)
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-insecure")
            if allowInsecureHTTP {
                Text("Plain HTTP exposes health exports to anyone able to observe this network.")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
            }
            Toggle("Send traceparent header (opt-in)", isOn: $propagateTraceparent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("https-traceparent")
                .onChange(of: propagateTraceparent) { _, enabled in
                    try? HarnessExport.setHTTPSTraceparent(enabled)
                }
            Text("Off by default. Never sends tracestate or baggage.")
                .font(.footnote)
            Button("Test HTTPS destination") {
                Task { await testHTTPS() }
            }
            .disabled(phase == .working || httpsURL.isEmpty)
            .accessibilityIdentifier("https-enable")
            Button("Export one page (HTTPS destination)") {
                Task { await runHTTPSExport() }
            }
            .disabled(phase == .working)
            .accessibilityIdentifier("https-export")
            ForEach(Array(httpsTestLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 44,
                        alignment: .leading
                    )
            }
            TextField("MQTT broker URL", text: $mqttURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-url")
            TextField("MQTT client ID", text: $mqttClientID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-client-id")
            TextField("MQTT topic template", text: $mqttTopic)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-topic")
            Text("Use {{exporterId|raw}} and {{batchId|raw}} if the broker needs a templated topic.")
                .font(.footnote)
                .foregroundStyle(.primary)
            Picker("MQTT QoS", selection: $mqttQoS) {
                Text("At most once (0)").tag(UInt8(0))
                Text("At least once (1)").tag(UInt8(1))
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("mqtt-qos")
            Button("Choose MQTT client PKCS#12") {
                pickingMQTTPKCS12 = true
            }
            .accessibilityIdentifier("mqtt-pkcs12")
            Text(mqttPKCS12Name)
                .font(.footnote)
                .accessibilityIdentifier("mqtt-pkcs12-name")
            SecureField("PKCS#12 password", text: $mqttPKCS12Password)
                .textContentType(.password)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-pkcs12-password")
            if mqttPKCS12Data != nil {
                Button("Clear client certificate") {
                    mqttPKCS12Data = nil
                    mqttPKCS12Name = "No client certificate"
                    mqttPKCS12Password = ""
                }
                .accessibilityIdentifier("mqtt-pkcs12-clear")
            }
            TextField("MQTT username", text: $mqttUsername)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-username")
            Text(CredentialDisclosure.copy)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("credential-disclosure-mqtt")
            SecureField("MQTT password", text: $mqttPassword)
                .textContentType(.password)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-password")
            Toggle("Allow plain MQTT (unsafe)", isOn: $allowInsecureMQTT)
                .frame(minHeight: 44)
                .accessibilityIdentifier("mqtt-insecure")
            if allowInsecureMQTT {
                Text("Plain MQTT exposes health exports to anyone able to observe this network.")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
            }
            Button("Test MQTT destination") {
                Task { await testMQTT() }
            }
            .disabled(phase == .working || mqttURL.isEmpty || mqttClientID.isEmpty || mqttTopic.isEmpty)
            .accessibilityIdentifier("mqtt-enable")
            Button("Export one page (MQTT destination)") {
                Task { await runMQTTExport() }
            }
            .disabled(phase == .working)
            .accessibilityIdentifier("mqtt-export")
            ForEach(Array(mqttTestLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
            #if !OHE_OBS25_SIZE_BASELINE
            TextField("OTLP collector URL", text: $otlpURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .frame(minHeight: 44)
                .accessibilityIdentifier("otlp-url")
            Toggle("Allow plain HTTP for OTLP (unsafe)", isOn: $allowInsecureOTLP)
                .frame(minHeight: 44)
                .accessibilityIdentifier("otlp-insecure")
            if allowInsecureOTLP {
                Text("Plain HTTP exposes traces to anyone able to observe this network.")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .fontWeight(.semibold)
            }
            Text("This preview is traces only. It does not include health values.")
                .font(.footnote)
            Button("Preview OTLP payload") {
                Task { await previewOTLP() }
            }
            .disabled(phase == .working)
            .accessibilityIdentifier("otlp-preview")
            if !otlpPreview.isEmpty {
                Text(otlpPreview)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("otlp-preview-body")
                Text("End of OTLP preview")
                    .font(.footnote)
                    .accessibilityIdentifier("otlp-preview-end")
                    .onScrollVisibilityChange(threshold: 0.1) { visible in
                        if visible { revealOTLPEnable() }
                    }
            }
            Button("Enable OTLP collector") {
                Task { await enableOTLP() }
            }
            .disabled(phase == .working || otlpURL.isEmpty || otlpGate.sharePayload == nil)
            .accessibilityIdentifier("otlp-enable")
            Button("Project unprojected runs") {
                Task { await projectOTLP() }
            }
            .disabled(phase == .working)
            .accessibilityIdentifier("otlp-project")
            Button("Disable OTLP collector") {
                disableOTLP()
            }
            .disabled(phase == .working)
            .accessibilityIdentifier("otlp-disable")
            ForEach(Array(otlpLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
            #endif
            Button("Refresh destination status") {
                refreshDestinationSurfaces()
            }
            .accessibilityIdentifier("destination-refresh")
            if destinationSnapshots.isEmpty {
                Text(destinationStatusLines.first ?? DestinationStatusLine.emptyCopy)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("destination-empty")
            } else {
                ForEach(Array(destinationSnapshots.enumerated()), id: \.element.destinationID) { index, snapshot in
                    let line = destinationStatusLines[index]
                    Button {
                        presentErrorFromStatus(snapshot)
                    } label: {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("destination-status-\(index)")
                    .accessibilityHint("Shows the error cause and fix when this destination needs attention.")
                }
            }
            Button("Acknowledge destination changes") {
                do {
                    try HarnessExport.acknowledgeDestinationChanges()
                    refreshDestinationSurfaces()
                    status = "Ready. Unacknowledged destination changes were cleared."
                } catch {
                    status = "Failed: \(error.localizedDescription)"
                }
            }
            .disabled(phase == .working)
            Button("Verify and show egress ledger") {
                Task { await loadLedger() }
            }
            .disabled(phase == .working)
            .accessibilityHint("Verifies the append-only hash chain and shows up to 50 recent transmission records.")
            ForEach(Array(ledgerLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            Text("Acknowledgements")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("acknowledgements-title")
            Text(acknowledgementsText)
                .font(.footnote)
                .textSelection(.enabled)
                .accessibilityIdentifier("acknowledgements-body")
            Button("Show export history (problems first)") {
                Task { await loadHistory() }
            }
            .disabled(phase == .working)
            .accessibilityIdentifier("history-load")
            ForEach(Array(historyLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityIdentifier("history-row-\(index)")
            }

            Text("If someone else set this up")
                .font(.headline)
            Text("iOS can hide this app. We cannot prevent that, and we do not offer stealth mode, alternate icons, or a second name. Check Settings → Apps → Hidden Apps, Screen Time, Battery, and App Store purchase history. Apple's Personal Safety guide: https://support.apple.com/guide/personal-safety/lock-or-hide-apps-on-your-iphone-ipsd0be4c185/web")
                .font(.footnote)

            Text("Stop and delete")
                .font(.headline)
            Text(WipeCopy.counts(wipeInventory))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wipe-counts")
            Text(WipeCopy.receivedLimit)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wipe-received-limit")
            if wipeInventory.received.isEmpty {
                Text(WipeCopy.noneReceived)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(wipeInventory.received.enumerated()), id: \.offset) { index, range in
                    Text(WipeCopy.receivedLine(range))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("wipe-received-\(index)")
                }
            }
            Text(WipeCopy.healthLimit)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("wipe-health-limit")
            Text(WipeCopy.healthPath)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Text(WipeCopy.macLimit)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Button(stopHeartRateArmed ? "Confirm: stop exporting heart rate" : "Stop exporting heart rate") {
                if stopHeartRateArmed {
                    Task { await stopHeartRate() }
                } else {
                    stopHeartRateArmed = true
                    status = "Ready. Tap again to purge queued heart-rate payloads and disable that type."
                }
            }
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
            .accessibilityIdentifier("wipe-everything")
            .disabled(phase == .working)

            Text("Diagnostics")
                .font(.headline)
                .foregroundStyle(.primary)
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
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
            .foregroundStyle(.primary)
            .accessibilityIdentifier("diagnostic-build")
            .disabled(phase == .working)
            .accessibilityHint("Assembles a redacted ohe.diagnostic/1 JSON preview. Sharing exists only below the bundle's last line.")
            if !diagnosticPreview.isEmpty {
                Text(diagnosticPreview)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                // S9: the share affordance exists only past the last line of content, so
                // it cannot be reached without traversing the bundle by scroll, VoiceOver
                // or Full Keyboard Access. Visibility, not an onAppear, is the evidence:
                // a ScrollView builds every child eagerly whether it is on screen or not.
                Text("End of diagnostic bundle")
                    .font(.footnote)
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
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("share-protection-warning")
                        Button("I understand — show sharing") {
                            shareProtectionAcknowledged = true
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("share-protection-continue")
                    }
                }
            }

            Text("Companion pairing")
                .font(.headline)
            if PairingCamera.canPresentScanner {
                Button("Scan pairing QR") {
                    Task { await openScanner() }
                }
                .disabled(phase == .working)
            } else {
                Text(PairingCamera.unavailableReason)
                    .font(.footnote)
            }
            TextEditor(text: $pairingPaste)
                .frame(minHeight: 88)
                .font(.system(.footnote, design: .monospaced))
                .accessibilityLabel("Pairing payload from the Mac")
            Button("Parse pairing payload") {
                parsePairing()
            }
            .disabled(phase == .working)
            if !sas.isEmpty {
                Text("Confirmation: \(sas)")
                    .font(.title2)
                    .accessibilityLabel("Confirmation code \(sas)")
                Text("This must match the Mac after the phone connects.")
                    .font(.footnote)
            }
            Button("Export one page to companion") {
                Task { await runCompanionExport() }
            }
            .disabled(phase == .working || pairing == nil)
            .accessibilityHint("Browses for the paired Mac name and pushes one page over TLS-PSK.")
            Button("Forget companion pairing") {
                Task { await forgetPairing() }
            }
            .disabled(phase == .working)
            Toggle("Send traceparent to Mac companion (opt-in)", isOn: $companionTraceparent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("companion-traceparent")
                .onChange(of: companionTraceparent) { _, enabled in
                    try? HarnessExport.setCompanionTraceparent(enabled)
                }
        }
        .buttonStyle(HarnessButtonStyle())
        .controlSize(.large)
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
                urlString: otlpURL,
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
        status = "Working: verifying egress ledger."
        do {
            ledgerLines = try await HarnessExport.ledgerLines()
            ledgerWarning = ledgerLines.first ?? ""
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
            historyLines = try await HarnessExport.historyLines()
            status = historyLines.contains(RunHistoryDetail.emptyStateCopy)
                ? RunHistoryDetail.emptyStateCopy
                : "Ready. Problems are listed before successful runs."
        } catch {
            historyLines = []
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
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

    @MainActor
    private func requestAccess() async {
        phase = .working
        status = "Working: Health authorisation."
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
        status = "Working: R-70 measurement."
        results = []
        let context = TemporalContext.utcHost
        let source = HealthKitSampleSource(context: context, limit: 10_000)
        var lines: [String] = []
        for metric in [MetricCatalog.heartRate.id, MetricCatalog.stepCount.id] {
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
            coverage: coverage
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
                        .accessibilityIdentifier("browser-back")
                } else if browserSelecting {
                    Button("Review changes") {
                        browserSelecting = false
                        browserReviewVisible = true
                    }
                    .accessibilityIdentifier("browser-review")
                } else {
                    Button("Select") {
                        browserBaseline = browserSelection
                        browserSelecting = true
                        browserReviewVisible = false
                    }
                    .accessibilityIdentifier("browser-select")
                }
            }
            Text(
                browserDemoMode
                    ? "Demo values. This is what App Review sees without HealthKit history."
                    : "Health values read on this iPhone."
            )
                .font(.footnote)
                .foregroundStyle(.primary)
                .fontWeight(browserDemoMode ? .semibold : .regular)

            if selectedDetail == nil {
                Picker("Export destination", selection: $scopeDestinationID) {
                    Text("Archive folder").tag("local-file")
                    Text("HTTPS").tag("https")
                    Text("MQTT").tag("mqtt")
                    Text("Mac companion").tag("companion")
                }
                .accessibilityIdentifier("scope-destination")
                .onChange(of: scopeDestinationID) { _, destinationID in
                    Task { await loadDestinationScope(destinationID) }
                }
                Text("Each destination starts with zero types. Choose a destination, types, and the earliest date it may receive.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("scope-zero-default")
                if browserSelection.isEmpty {
                    Text("Scope required: this destination cannot export until at least one type is selected.")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("scope-required")
                }
                DatePicker(
                    "Send samples starting",
                    selection: $scopeStartDate,
                    displayedComponents: .date
                )
                .accessibilityIdentifier("scope-start-date")
                Toggle("Stop sending after a date", isOn: $scopeEndEnabled)
                    .accessibilityIdentifier("scope-end-enabled")
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
                Button(browserLoadingHealth ? "Loading Health data…" : "Load 30 days from Health") {
                    Task { await loadBrowserSamples(metric: detail.metric) }
                }
                .disabled(browserLoadingHealth)
                .accessibilityIdentifier("browser-load-health")
                dataBrowserDetail(detail)
            } else {
                if browserSelecting {
                    HStack {
                        Button("Use Core Daily") {
                            browserSelection = Set(MetricCatalog.coreDaily.map(\.id))
                        }
                        .accessibilityIdentifier("browser-core-daily")
                        Button("Invert routine") {
                            var draft = DataSelectionDraft(baseline: browserSelection)
                            draft.invertRoutine(MetricCatalog.selectable.map(\.id))
                            browserSelection = draft.selected
                        }
                        .accessibilityIdentifier("browser-invert-routine")
                        Button("Clear all") { browserSelection.removeAll() }
                            .accessibilityIdentifier("browser-clear-all")
                    }
                }
                if browserReviewVisible {
                    let adding = browserSelection.subtracting(browserBaseline)
                    let removing = browserBaseline.subtracting(browserSelection)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review changes")
                            .font(.headline)
                            .accessibilityIdentifier("browser-review-title")
                        Text("Adding \(adding.count) types")
                            .accessibilityIdentifier("browser-review-adding")
                        Text("Removing \(removing.count) types")
                            .accessibilityIdentifier("browser-review-removing")
                        if !removing.isEmpty {
                            Text("Removing a type does not delete data already sent to this destination.")
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .fontWeight(.semibold)
                        }
                        Button("Continue") {
                            Task { await applyBrowserSelection() }
                        }
                        .accessibilityIdentifier("browser-review-continue")
                    }
                }
                if let pendingSensitiveMetric {
                    Text("Sensitive type — type \(scopeDestinationID) to add it individually.")
                        .font(.footnote)
                    TextField(scopeDestinationID, text: $sensitiveDestinationConfirmation)
                    Button("Confirm sensitive type") {
                        if sensitiveDestinationConfirmation == scopeDestinationID {
                            browserSelection.insert(pendingSensitiveMetric)
                            self.pendingSensitiveMetric = nil
                            sensitiveDestinationConfirmation = ""
                        }
                    }
                    .disabled(sensitiveDestinationConfirmation != scopeDestinationID)
                }
                Toggle("Only types with data", isOn: $browserOnlyWithData)
                    .accessibilityIdentifier("browser-only-with-data")
                Toggle("Show demo values", isOn: $browserDemoMode)
                    .accessibilityIdentifier("browser-demo-mode")
                Picker("Display units", selection: $displayUnitPreference) {
                    ForEach(DisplayUnitPreference.allCases, id: \.self) { preference in
                        Text(preference.label).tag(preference)
                    }
                }
                .accessibilityLabel("Display units")
                .accessibilityIdentifier("browser-display-units")
                Picker("Time format", selection: $clockDisplay) {
                    ForEach(ClockDisplay.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .accessibilityLabel("Time format")
                .accessibilityIdentifier("browser-time-format")
                Text("Sample times read as \(clockDisplay.timeString(Date(), locale: Locale.current, timeZone: .current)).")
                    .font(.footnote)
                    .accessibilityIdentifier("browser-time-example")
                TextField("Search types", text: $browserSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search types")
                    .accessibilityIdentifier("browser-search")
                if rows.isEmpty {
                    Text("No data types match your search.")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
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
                                        .accessibilityHidden(true)
                                }
                                Text(row.title)
                                if row.sensitive {
                                    Text("sensitive")
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                }
                            }
                            Text(row.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.title), \(row.subtitle)")
                    .accessibilityIdentifier("browser-row-\(row.metric.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private func dataBrowserDetail(_ detail: DataBrowserDetail) -> some View {
        if let latest = detail.latest {
            Text("Latest").font(.caption)
            Text(
                "\(DataBrowser.formatValue(detail.displayValue ?? latest.value)) "
                    + detail.displayUnit
            )
                .accessibilityIdentifier("browser-detail-latest")
            if detail.displayUnit != detail.exportUnit {
                Text("Export remains \(detail.exportUnit).")
                    .font(.footnote)
            }
            Text(latest.start).font(.footnote)
            Text("Source: \(latest.source?.name ?? "Unknown")").font(.footnote)
        } else {
            Text(DataBrowser.emptyDetailCopy)
                .font(.footnote)
                .accessibilityIdentifier("browser-detail-empty")
        }
        Text("Exported to").font(.caption)
        if detail.destinations.isEmpty {
            Text("Not included in any export.")
        } else {
            ForEach(detail.destinations, id: \.name) { destination in
                Text("\(destination.name) · data through \(destination.sentThroughDay ?? "no day yet") has been sent")
            }
        }
        Text("Export unit: \(detail.exportUnit)").font(.footnote)
        if let horizon = detail.indexHorizonDay {
            Text(DataBrowser.horizonCopy(day: horizon))
                .font(.footnote)
                .accessibilityIdentifier("browser-index-horizon")
        }
        if let explanation = detail.aggregationExplanation {
            Text("Daily buckets (this is what we export)").font(.caption)
            Text("Computed as: \(explanation)").font(.footnote)
        }
        Text("Samples").font(.caption)
        ForEach(detail.samples, id: \.key.uuid) { sample in
            Text("\(DataBrowser.formatValue(sample.value)) \(detail.exportUnit) · \(sample.start)")
                .font(.footnote)
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

    private func browserCoverageObservations() -> [MetricID: CoverageObservation] {
        var observations: [MetricID: CoverageObservation] = [:]
        let metrics = Set(liveBrowserSamples.keys).union(browserAuthorizedDays.keys).union(browserSelection)
        for metric in metrics {
            let samples = liveBrowserSamples[metric] ?? []
            let latest = samples.max { $0.start < $1.start }
            observations[metric] = CoverageObservation(
                sampleCount: samples.count,
                latestStart: latest?.start,
                earliestAuthorizedDay: browserAuthorizedDays[metric]
            )
        }
        return observations
    }

    @MainActor
    private func refreshCoverageWindows(metrics: [MetricID]? = nil) async {
        let probed = metrics ?? Array(browserSelection.union(Set(liveBrowserSamples.keys)))
        guard !probed.isEmpty else { return }
        do {
            let days = try await HealthKitAuthorization.earliestAuthorizedDays(for: probed)
            for metric in probed {
                browserAuthorizedDays[metric] = days[metric]
            }
        } catch {
            return
        }
    }

    @MainActor
    private func loadBrowserSamples(metric: MetricID) async {
        browserLoadingHealth = true
        defer { browserLoadingHealth = false }
        let timeZone = TimeZone.current
        let context = TemporalContext(
            timeZoneIdentifier: timeZone.identifier,
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: TemporalContext.hostTzDatabaseVersion
        )
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
            results = try await HarnessExport.runDemoDataset(typedDestinationName: demoConfirmName)
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
            await HarnessExport.notifyDestinationFailure(
                destinationID: "local-file",
                destinationLabel: "Archive folder"
            )
            presentUserFacingFailure(error, destinationLabel: "Archive folder")
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
            await HarnessExport.notifyDestinationFailure(
                destinationID: "local-file",
                destinationLabel: "Archive folder"
            )
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func runBackfill(mode: BackfillMode) async {
        phase = .working
        status = NamedWorkProgress.backfill(day: 0, days: 1, type: 0, types: 1)
        results = []
        do {
            if try ContinuedBackfillCoordinator.submit(mode: mode) {
                status = "Ready. iOS accepted the unattended backfill; progress is available in the system UI."
                phase = .ready
                return
            }
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            results = try await HarnessExport.runBackfill(mode: mode) { line in
                await MainActor.run {
                    status = line
                }
            }
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            status = backfillFinishedStatus(results)
        } catch {
            await HarnessExport.notifyDestinationFailure(
                destinationID: "local-file",
                destinationLabel: "Archive folder"
            )
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
                return "Ready. Backfill is paused while your iPhone cools down."
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
        anchorHolds = (try? await HarnessExport.anchorHolds()) ?? []
    }

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
        status = "Working: re-exporting an evicted date range."
        do {
            let outcome = try await HarnessExport.reExportQueueGap(gap)
            await refreshLedgerIntegrity()
            status = "Ready. Gap re-export finished: \(outcome.kind.rawValue)."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func enableLocalFile() async {
        phase = .working
        status = "Working: local-folder destination test."
        wipeArmed = false
        do {
            _ = try await HarnessExport.enableLocalFileDestination()
            refreshDestinationSurfaces()
            await startHealthObserversIfEligible()
            await refreshLedgerIntegrity()
            status = "Ready. Local archive passed write/read/confirm and is enabled."
        } catch {
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
        guard !HarnessExport.hasDestinationConfiguration(slot) else {
            status = "Import refused: the \(slot) destination slot already has a configuration. Disable and remove it before importing another."
            return
        }
        importedDestinationDraft = draft
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
        case .mqtt:
            mqttURL = inputs.endpoint
            mqttClientID = inputs.clientID ?? mqttClientID
            mqttTopic = inputs.topic ?? mqttTopic
            mqttQoS = inputs.qos ?? 1
            allowInsecureMQTT = inputs.allowInsecure
            status = "Ready. MQTT fields loaded from the disabled draft. Add omitted credentials, then run the destination test."
        default:
            importedDestinationDraft = nil
            status = "Import refused: this destination kind does not have a setup path."
        }
    }

    @MainActor
    private func testHTTPS() async {
        phase = .working
        status = "Working: HTTPS destination test and identity pin."
        do {
            confirmationKind = .https
            confirmationCard = try await HarnessExport.prepareHTTPSDestination(
                urlString: httpsURL,
                allowInsecureHTTP: allowInsecureHTTP,
                bearer: httpsBearer.isEmpty ? nil : httpsBearer,
                importedLocalIdentifier:
                    importedDestinationDraft?.configuration.kind == .https
                        ? importedDestinationDraft?.localIdentifier : nil
            )
            httpsTestLines = confirmationCard?.lines ?? []
            userFacingError = nil
            status = "Ready. Confirm this server before any Health data moves."
        } catch {
            confirmationCard = nil
            confirmationKind = nil
            httpsTestLines = []
            presentUserFacingFailure(error, destinationLabel: httpsURL)
        }
        phase = .ready
    }

    @MainActor
    private func testMQTT() async {
        phase = .working
        status = "Working: MQTT destination test."
        do {
            confirmationKind = .mqtt
            confirmationCard = try await HarnessExport.prepareMQTTDestination(
                urlString: mqttURL,
                allowInsecure: allowInsecureMQTT,
                clientID: mqttClientID,
                topic: mqttTopic,
                clientPKCS12: mqttPKCS12Data,
                clientPKCS12Password: mqttPKCS12Password.isEmpty ? nil : mqttPKCS12Password,
                username: mqttUsername.isEmpty ? nil : mqttUsername,
                password: mqttPassword.isEmpty ? nil : mqttPassword,
                qos: mqttQoS,
                importedLocalIdentifier:
                    importedDestinationDraft?.configuration.kind == .mqtt
                        ? importedDestinationDraft?.localIdentifier : nil
            )
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
            mqttTestLines = []
            presentUserFacingFailure(error, destinationLabel: mqttURL)
        }
        phase = .ready
    }

    @MainActor
    private func confirmPendingDestination() async {
        phase = .working
        status = "Working: enabling destination."
        do {
            let activatingDraft = importedDestinationDraft.flatMap { draft in
                let kind = draft.configuration.kind
                return (confirmationKind == .https && kind == .https)
                    || (confirmationKind == .mqtt && kind == .mqtt)
                    ? draft : nil
            }
            if let draft = activatingDraft {
                let destinationID =
                    draft.configuration.kind == .https ? "https" : "mqtt"
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

    private func applyWidgetStatusURL(_ url: URL) {
        guard let route = WidgetStatusRoute(url: url) else { return }
        refreshDestinationSurfaces()
        if disclosureAcknowledged {
            phase = .ready
            status = route.destinationID.map {
                "Ready. Opened destination status for \($0) from the widget."
            } ?? "Ready. Opened destination status from the widget."
        } else {
            status = "Review the disclosure before opening destination status."
        }
    }

    private func refreshDestinationSurfaces() {
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
                        .font(.headline)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 44,
                            alignment: .leading
                        )
                        .accessibilityIdentifier("destination-confirm-title")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityRespondsToUserInteraction(false)
                    ForEach(Array(card.lines.dropFirst().enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(
                                maxWidth: .infinity,
                                minHeight: 44,
                                alignment: .leading
                            )
                    }
                    if card.requiresPublicAddressConfirmation {
                        Text(ConfirmationCopy.publicAddressWarning)
                            .font(.footnote)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("public-destination-warning")
                        TextField(
                            ConfirmationCopy.publicAddressPhrase,
                            text: $publicAddressConfirmation
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("public-destination-confirmation")
                    }
                    Button("This is my server") {
                        Task { await confirmPendingDestination() }
                    }
                    .disabled(
                        card.requiresPublicAddressConfirmation
                            && publicAddressConfirmation != ConfirmationCopy.publicAddressPhrase
                    )
                    .accessibilityIdentifier("destination-confirm")
                    .buttonStyle(.borderedProminent)
                    Button("Cancel") {
                        cancelDestinationConfirmation()
                    }
                    .accessibilityIdentifier("destination-confirm-cancel")
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .padding()
            }
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
    private func stopHeartRate() async {
        phase = .working
        status = "Working: type purge."
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
        status = "Working: destructive wipe."
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
        status = "Working: local notification."
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

    private func parsePairing() {
        do {
            let payload = try PairingPayload.parse(pairingPaste.trimmingCharacters(in: .whitespacesAndNewlines))
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
        status = NamedWorkProgress.types(current: 0, total: 1)
        results = []
        do {
            results = try await HarnessExport.runCompanion(session: pairing) { current, total in
                await MainActor.run {
                    status = NamedWorkProgress.types(current: current, total: total)
                }
            }
            refreshDestinationSurfaces()
            status = "Ready. Companion export finished. Compare confirmation \(sas) with the Mac."
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
            Task { await testMQTT() }
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
}

private struct HarnessButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
