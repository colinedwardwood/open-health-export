import CompanionWire
import CoreDomain
import CoreTemporal
import CorrectnessEngine
import DestinationTrust
import DiagnosticBundle
import EnginePorts
import HealthKitSource
import MetricCatalog
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Watchdog
import WireFormat

struct HarnessView: View {
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var httpsTestLines: [String] = []
    @State private var mqttURL = ""
    @State private var mqttClientID = "ohe-iphone"
    @State private var mqttTopic = "ohe/health"
    @State private var mqttQoS: UInt8 = 1
    @State private var mqttUsername = ""
    @State private var mqttPassword = ""
    @State private var allowInsecureMQTT = false
    @State private var mqttPKCS12Name = "No client certificate"
    @State private var mqttPKCS12Data: Data?
    @State private var mqttPKCS12Password = ""
    @State private var pickingMQTTPKCS12 = false
    @State private var mqttTestLines: [String] = []
    @State private var otlpURL = ""
    @State private var allowInsecureOTLP = false
    @State private var otlpPreview = ""
    @State private var otlpPayload: Data?
    @State private var otlpGate = DiagnosticPreviewGate()
    @State private var otlpLines: [String] = []
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
    @State private var ledgerLines: [String] = []
    @State private var historyLines: [String] = []
    @State private var ledgerWarning = ""
    @State private var wakeAttribution = ""
    @State private var queueEvictionGaps: [GapRecord] = []
    @State private var wipeArmed = false
    @State private var stopHeartRateArmed = false
    @State private var demoConfirmName = ""
    @State private var browserSearch = ""
    @State private var browserSelecting = false
    @State private var browserReviewVisible = false
    @State private var browserBaseline = Set(MetricCatalog.coreDaily.map(\.id))
    @State private var browserSelection = Set(MetricCatalog.coreDaily.map(\.id))
    @State private var selectedBrowserMetric: MetricID?
    @State private var pendingSensitiveMetric: MetricID?
    @State private var sensitiveDestinationConfirmation = ""
    @State private var liveBrowserSamples: [MetricID: [SampleRecord]] = [:]
    @State private var browserSentThroughDay: [MetricID: String] = [:]
    @State private var browserLoadingHealth = false
    @State private var foregroundCatchUpStarted = false
    @AppStorage("ohe.browserOnlyWithData")
    private var browserOnlyWithData = true
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(status)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Status: \(status)")
                        .accessibilityIdentifier("status-line")

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
        }
        .tint(.primary)
        .safeAreaInset(edge: .top) {
            if let overdueBanner {
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
            if let destinationChangeBanner {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unacknowledged destination change")
                        .font(.headline)
                    Text(destinationChangeBanner)
                        .font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.yellow)
                .accessibilityIdentifier("destination-change-banner")
            }
        }
        .safeAreaInset(edge: .top) {
            if AnchorHoldBanner.isVisible(anchorHolds) {
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
            timeToFirstFrameMS = LaunchMark.millisecondsToNow()
            refreshDestinationSurfaces()
            if otlpURL.isEmpty {
                otlpURL = HarnessExport.storedOTLPURL()
            }
            let selected = Set(HarnessExport.selectedMetrics())
            browserBaseline = selected
            browserSelection = selected
            if disclosureAcknowledged {
                phase = .ready
                status = "Ready."
            }
            Task {
                do {
                    let expired = try await HarnessExport.expireQueuesAndNotify()
                    if expired.expiredBatches > 0 {
                        status = "Ready. Deleted \(expired.expiredBatches) queued export(s) older than seven days."
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
                if let scenario = ProcessInfo.processInfo
                    .environment["OHE_SEED_DESTINATION_STATUS"]
                {
                    try? HarnessExport.seedDestinationStatusForUITests(scenario: scenario)
                    refreshDestinationSurfaces()
                }
                if let held = ProcessInfo.processInfo.environment["OHE_SEED_ANCHOR_HOLD"] {
                    try? await HarnessExport.seedAnchorHoldForUITests(
                        metric: MetricID(rawValue: held)
                    )
                }
                if let raw = ProcessInfo.processInfo.environment["OHE_OPEN_URL"],
                   let url = URL(string: raw)
                {
                    applyWidgetStatusURL(url)
                }
                #endif
                await refreshQueueGaps()
                if disclosureAcknowledged,
                   !foregroundCatchUpStarted,
                   HarnessExport.isLocalFileEnabled() {
                    foregroundCatchUpStarted = true
                    await runLocalExport(trigger: .appForeground)
                }
            }
        }
        .onOpenURL { url in
            applyWidgetStatusURL(url)
        }
        .onChange(of: scenePhase) { _, next in
            guard next == .active else { return }
            AppLifecycleCoordinator.shared.recordWake(.appForeground)
            Task {
                try? await HarnessExport.recordNotificationSuppressionIfNeeded()
                await startHealthObserversIfEligible()
                await refreshSecurityAdvisory()
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
            Text("When the phone is locked, Apple withholds Health data after a short window. Background export is best-effort: iOS may not wake the app, and we will say so instead of pretending a schedule ran.")
                .fixedSize(horizontal: false, vertical: true)
            Text("You choose what is read. We do not hide destinations, and we do not send telemetry to the maintainers.")
                .fixedSize(horizontal: false, vertical: true)
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
            Text("Shortcuts can run one page to the local archive after you enable it.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shortcut-export")
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
            TextField("Type local-file to confirm demo export", text: $demoConfirmName)
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
            Text(FreshnessTarget.provisionalDisclosure)
                .font(.footnote)
                .accessibilityIdentifier("freshness-target")
            ForEach(FreshnessClass.allCases, id: \.self) { freshnessClass in
                Text(FreshnessTarget.classDisclosure(freshnessClass))
                    .font(.footnote)
                    .accessibilityIdentifier("freshness-class-\(freshnessClass.rawValue)")
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
                    .textSelection(.enabled)
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
            Button("Refresh destination status") {
                refreshDestinationSurfaces()
            }
            .accessibilityIdentifier("destination-refresh")
            ForEach(Array(destinationStatusLines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .accessibilityIdentifier(
                        line == "No destination snapshots yet."
                            ? "destination-empty"
                            : "destination-status-\(index)"
                    )
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
            Button(wipeArmed ? "Confirm: delete credentials and ledger identity" : "Delete everything on this device") {
                if wipeArmed {
                    Task { await wipeDevice() }
                } else {
                    wipeArmed = true
                    status = "Ready. Tap again to destroy credentials, pairing, and the ledger signing identity."
                }
            }
            .disabled(phase == .working)

            Text("Diagnostics")
                .font(.headline)
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
                    ShareLink(item: diagnosticShareURL) {
                        Text("Share diagnostic")
                    }
                    .accessibilityIdentifier("diagnostic-share")
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
            .accessibilityHint("Browses for the paired Mac name and pushes one page over TLS 1.3 PSK.")
            Button("Forget companion pairing") {
                Task { await forgetPairing() }
            }
            .disabled(phase == .working)
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
            status = historyLines.isEmpty
                ? "Ready. No export history yet."
                : "Ready. Problems are listed before successful runs."
        } catch {
            historyLines = []
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func applyBrowserSelection() async {
        phase = .working
        let adding = browserSelection.subtracting(browserBaseline)
        let removing = browserBaseline.subtracting(browserSelection)
        do {
            if !adding.isEmpty {
                try await HealthKitAuthorization.requestReadAccess(
                    metrics: adding.sorted { $0.rawValue < $1.rawValue }
                )
            }
            try await HarnessExport.applySelectedMetrics(
                browserSelection,
                removing: removing
            )
            browserBaseline = browserSelection
            browserReviewVisible = false
            AppLifecycleCoordinator.shared.stopObservers()
            await startHealthObserversIfEligible()
            status = "Ready. Export selection updated."
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
            try await HealthKitAuthorization.requestReadAccess(
                metrics: HarnessExport.selectedMetrics()
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
        let samples = MetricCatalog.all.enumerated().map { index, declaration in
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
        let rows = DataBrowser.rows(
            latest: latest,
            exported: browserSelection,
            search: browserSearch,
            onlyWithData: browserOnlyWithData && !browserSelecting,
            displayUnits: displayUnitPolicy
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
                now: detailNow
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
                        Button("Invert routine") {
                            var draft = DataSelectionDraft(baseline: browserSelection)
                            draft.invertRoutine(MetricCatalog.all.map(\.id))
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
                            Text("Removing a type does not delete data already sent to Archive folder.")
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
                    Text("Sensitive type — type Archive folder to add it individually.")
                        .font(.footnote)
                    TextField("Archive folder", text: $sensitiveDestinationConfirmation)
                    Button("Confirm sensitive type") {
                        if sensitiveDestinationConfirmation == "Archive folder" {
                            browserSelection.insert(pendingSensitiveMetric)
                            self.pendingSensitiveMetric = nil
                            sensitiveDestinationConfirmation = ""
                        }
                    }
                    .disabled(sensitiveDestinationConfirmation != "Archive folder")
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
        let source = HealthKitDayObservationSource(context: context, limit: 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var loaded: [SampleRecord] = []
        do {
            for offset in 0 ..< DataBrowserPeriod.month.rawValue {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else {
                    continue
                }
                loaded.append(contentsOf: try await source.samples(
                    metric: metric,
                    day: formatter.string(from: date)
                ))
            }
            liveBrowserSamples[metric] = loaded
            await refreshSentThroughDay(metric)
            status = loaded.isEmpty
                ? DataBrowser.emptyDetailCopy
                : "Loaded \(loaded.count) Health samples for comparison."
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
        status = "Working: local-file export."
        results = []
        do {
            results = try await HarnessExport.runOnePageEachMetric(trigger: trigger)
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            await refreshWakeAttribution()
            await refreshQueueGaps()
            status = "Ready. Local export finished. Outcome kinds are engine-derived, not assigned by this screen."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func runFullReconcile() async {
        phase = .working
        status = "Working: full Health history reconciliation."
        results = []
        do {
            results = try await HarnessExport.runFullReconcile()
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            status = "Ready. Full reconciliation finished without advancing anchored cursors."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func runBackfill(mode: BackfillMode) async {
        phase = .working
        status = mode == .raw
            ? "Working: preparing explicit raw-history backfill."
            : "Working: preparing aggregate-only history backfill."
        results = []
        do {
            if try ContinuedBackfillCoordinator.submit(mode: mode) {
                status = "Ready. iOS accepted the unattended backfill; progress is available in the system UI."
                phase = .ready
                return
            }
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            results = try await HarnessExport.runBackfill(mode: mode)
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            status = "Ready. Foreground backfill completed."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
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
            return
        }
        browserSentThroughDay[metric] = day
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
    private func testHTTPS() async {
        phase = .working
        status = "Working: HTTPS destination test and identity pin."
        do {
            confirmationKind = .https
            confirmationCard = try await HarnessExport.prepareHTTPSDestination(
                urlString: httpsURL,
                allowInsecureHTTP: allowInsecureHTTP,
                bearer: httpsBearer.isEmpty ? nil : httpsBearer
            )
            httpsTestLines = confirmationCard?.lines ?? []
            status = "Ready. Confirm this server before any Health data moves."
        } catch {
            confirmationCard = nil
            confirmationKind = nil
            httpsTestLines = []
            status = "Failed: \(error.localizedDescription)"
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
                qos: mqttQoS
            )
            mqttTestLines = confirmationCard?.lines ?? []
            status = "Ready. Confirm this server before any Health data moves."
        } catch {
            confirmationCard = nil
            confirmationKind = nil
            mqttTestLines = []
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func confirmPendingDestination() async {
        phase = .working
        status = "Working: enabling destination."
        do {
            switch confirmationKind {
            case .https:
                httpsTestLines = try await HarnessExport.confirmPendingHTTPSDestination()
                httpsBearer = ""
                status = "Ready. Network destination passed its real-path test and is enabled."
            case .mqtt:
                mqttTestLines = try await HarnessExport.confirmPendingMQTTDestination()
                status = "Ready. MQTT destination passed its real-path test and is enabled."
            case nil:
                status = "Failed: nothing to confirm."
            }
            confirmationCard = nil
            confirmationKind = nil
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
        destinationStatusLines = HarnessExport.destinationStatusLines()
        destinationChangeBanner = HarnessExport.destinationChangeBannerDetail()
        overdueBanner = HarnessExport.overdueBannerDetail()
    }

    @ViewBuilder
    private func destinationConfirmation(_ card: DestinationConfirmationCard) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                    Button("This is my server") {
                        Task { await confirmPendingDestination() }
                    }
                    .accessibilityIdentifier("destination-confirm")
                    Button("Cancel") {
                        cancelDestinationConfirmation()
                    }
                    .accessibilityIdentifier("destination-confirm-cancel")
                }
                .padding()
            }
            .navigationTitle("Confirm this server")
        }
        .interactiveDismissDisabled()
        .presentationDetents([.large])
    }

    @MainActor
    private func runMQTTExport() async {
        phase = .working
        status = "Working: MQTT export."
        do {
            results = try await HarnessExport.runMQTTDestination()
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            await refreshWakeAttribution()
            status = "Ready. MQTT export finished."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
        phase = .ready
    }

    @MainActor
    private func runHTTPSExport() async {
        phase = .working
        status = "Working: HTTPS export."
        do {
            results = try await HarnessExport.runHTTPSDestination()
            refreshDestinationSurfaces()
            await refreshLedgerIntegrity()
            await refreshWakeAttribution()
            status = "Ready. HTTPS export finished."
        } catch {
            status = "Failed: \(error.localizedDescription)"
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
        status = "Working: companion export."
        results = []
        do {
            results = try await HarnessExport.runCompanion(session: pairing)
            refreshDestinationSurfaces()
            status = "Ready. Companion export finished. Compare confirmation \(sas) with the Mac."
        } catch {
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
