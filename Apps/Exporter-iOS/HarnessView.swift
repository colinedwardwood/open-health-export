import CompanionWire
import CoreDomain
import CoreTemporal
import DestinationTrust
import DiagnosticBundle
import EnginePorts
import HealthKitSource
import MetricCatalog
import SwiftUI

struct HarnessView: View {
    @Environment(\.scenePhase) private var scenePhase
    private enum Phase {
        case disclosure
        case ready
        case working
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
    @State private var showScanner = false
    @State private var diagnosticPreview = ""
    @State private var diagnosticPayload: Data?
    @State private var diagnosticGate = DiagnosticPreviewGate()
    @State private var diagnosticShareURL: URL?
    @State private var destinationStatusLines: [String] = []
    @State private var ledgerLines: [String] = []
    @State private var ledgerWarning = ""
    @State private var wipeArmed = false
    @State private var stopHeartRateArmed = false
    @State private var foregroundCatchUpStarted = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(status)
                        .font(.body)
                        .accessibilityLabel("Status: \(status)")

                    Text("Time to first screen: \(timeToFirstFrameMS, specifier: "%.0f") ms (foreground; R-73 is a background-launch budget).")
                        .font(.footnote)

                    if phase == .disclosure {
                        disclosure
                    } else {
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
        .onAppear {
            timeToFirstFrameMS = LaunchMark.millisecondsToNow()
            destinationStatusLines = HarnessExport.destinationStatusLines()
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
                await restorePairing()
                await refreshLedgerIntegrity()
                if disclosureAcknowledged,
                   !foregroundCatchUpStarted,
                   HarnessExport.isLocalFileEnabled() {
                    foregroundCatchUpStarted = true
                    await runLocalExport(trigger: .appForeground)
                }
            }
            .onChange(of: scenePhase) { _, next in
                guard next == .active else { return }
                AppLifecycleCoordinator.shared.recordWake(.appForeground)
                Task { await startHealthObserversIfEligible() }
            }
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
    }

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Before Health access")
                .font(.headline)
            Text("This is not a medical device. It does not diagnose or treat anything.")
            Text("When the phone is locked, Apple withholds Health data after a short window. Background export is best-effort: iOS may not wake the app, and we will say so instead of pretending a schedule ran.")
            Text("You choose what is read. We do not hide destinations, and we do not send telemetry to the maintainers.")
            Button("I understand — continue") {
                disclosureAcknowledged = true
                phase = .ready
                status = "Ready. Next: request Health read access, then measure."
            }
            .accessibilityHint("Shows Health permission and measurement controls.")
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Request Health read access") {
                Task { await requestAccess() }
            }
            .disabled(phase == .working)

            Button("Run R-70 (one anchored page per type)") {
                Task { await runR70() }
            }
            .disabled(phase == .working)
            Button("Export one page (local file)") {
                Task { await runLocalExport() }
            }
            .disabled(phase == .working)
            .accessibilityHint("Writes NDJSON under Application Support using the engine and local-file sink.")
            Button("Send sample destination-enabled notice") {
                Task { await sendSampleNotice() }
            }
            .disabled(phase == .working)
            .accessibilityHint("Asks for notification permission and posts one R-40 notice with copy from the registry.")

            Text("Where your data goes")
                .font(.headline)
            if !ledgerWarning.isEmpty {
                Text(ledgerWarning)
                    .font(.footnote)
                    .foregroundStyle(ledgerWarning.hasPrefix("WARNING") ? .red : .secondary)
                    .accessibilityLabel("Ledger status: \(ledgerWarning)")
            }
            Text("Your health data is sent only to destinations listed here. This is what the app records about its own use, not independent proof.")
                .font(.footnote)
            Button("Enable local archive folder (R-25 test)") {
                Task { await enableLocalFile() }
            }
            .disabled(phase == .working)
            .accessibilityHint("Writes a canary file, reads it back, then enables the local-file destination.")
            Button("Refresh destination status") {
                destinationStatusLines = HarnessExport.destinationStatusLines()
            }
            ForEach(Array(destinationStatusLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.footnote)
                    .textSelection(.enabled)
            }
            Button("Acknowledge destination changes") {
                do {
                    try HarnessExport.acknowledgeDestinationChanges()
                    destinationStatusLines = HarnessExport.destinationStatusLines()
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
            Button("Build diagnostic bundle") {
                buildDiagnostic()
            }
            .disabled(phase == .working)
            .accessibilityHint("Assembles a redacted ohe.diagnostic/1 JSON preview. Share does not exist until you confirm you read it.")
            if !diagnosticPreview.isEmpty {
                Text(diagnosticPreview)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Button("I have read this diagnostic") {
                    confirmDiagnosticRead()
                }
                .disabled(diagnosticPayload == nil)
            }
            if let diagnosticShareURL {
                ShareLink(item: diagnosticShareURL) {
                    Text("Share diagnostic")
                }
                .accessibilityIdentifier("diagnostic-share")
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
    }

    private func buildDiagnostic() {
        diagnosticShareURL = nil
        diagnosticGate = DiagnosticPreviewGate()
        do {
            let built = try HarnessExport.diagnosticBundle()
            diagnosticPreview = built.preview
            diagnosticPayload = built.payload
            status = "Ready. Read the diagnostic JSON. Share appears only after you confirm."
        } catch {
            diagnosticPreview = ""
            diagnosticPayload = nil
            status = "Failed: \(error.localizedDescription)"
        }
    }

    private func confirmDiagnosticRead() {
        guard let diagnosticPayload else { return }
        diagnosticGate.reachedEnd(of: diagnosticPayload)
        guard let payload = diagnosticGate.sharePayload else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ohe-diagnostic.json")
        do {
            try payload.write(to: url, options: .atomic)
            diagnosticShareURL = url
            status = "Ready. Share is available because you confirmed the full preview."
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
    private func requestAccess() async {
        phase = .working
        status = "Working: Health authorisation."
        do {
            try await HealthKitAuthorization.requestReadAccess()
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
        let context = TemporalContext(
            timeZoneIdentifier: "UTC",
            localeIdentifier: "en_US_POSIX",
            tzDatabaseVersion: "host"
        )
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
    private func runLocalExport(trigger: RunTrigger = .manual) async {
        phase = .working
        status = "Working: local-file export."
        results = []
        do {
            results = try await HarnessExport.runOnePageEachMetric(trigger: trigger)
            destinationStatusLines = HarnessExport.destinationStatusLines()
            await refreshLedgerIntegrity()
            status = "Ready. Local export finished. Outcome kinds are engine-derived, not assigned by this screen."
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
            destinationStatusLines = try await HarnessExport.enableLocalFileDestination()
            await startHealthObserversIfEligible()
            await refreshLedgerIntegrity()
            status = "Ready. Local archive passed write/read/confirm and is enabled."
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
            destinationStatusLines = HarnessExport.destinationStatusLines()
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
            try await LocalUserNotifier().notify(
                UserNotice(kind: .destinationEnabled, destination: "local-file")
            )
            status = "Ready. If you allowed notifications, the copy came from NoticeCopy, not this screen."
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
            destinationStatusLines = HarnessExport.destinationStatusLines()
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
            destinationStatusLines = HarnessExport.destinationStatusLines()
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
