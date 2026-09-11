// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionReceive
import CompanionWire
import NetEgress
import SinkCompanion
import SwiftUI
import AppKit

@main
struct CompanionApp: App {
    var body: some Scene {
        WindowGroup {
            CompanionView()
        }
    }
}

struct CompanionView: View {
    @State private var folder: URL?
    @State private var warning: String?
    @State private var payloadText = ""
    @State private var qrImage: NSImage?
    @State private var confirmation = ""
    @State private var pairing: PairingSession?
    @State private var status = "Choose a folder, then open a receive window."
    @State private var listening = false
    @State private var listener: CompanionListener?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(status)
            if let warning {
                Text(warning)
                    .foregroundStyle(.orange)
            }
            Button("Choose folder") { pickFolder() }
            if let folder {
                Text(folder.path)
                    .textSelection(.enabled)
                    .font(.footnote)
            }
            if let qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .accessibilityLabel("Pairing QR code")
            }
            if !payloadText.isEmpty {
                Text("Scan this on the phone, or paste the text. Compare the confirmation code after the phone connects — it is derived from both installation IDs.")
                Text(payloadText)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .monospaced))
            }
            if !confirmation.isEmpty {
                Text("Confirmation: \(confirmation)")
                    .font(.title2)
                    .accessibilityLabel("Confirmation code \(confirmation)")
            }
            Button(listening ? "Close receive window" : "Open receive window") {
                Task { await toggleListen() }
            }
            .disabled(folder == nil)
            Button("Forget pairing") {
                Task { await forgetPairing() }
            }
            .disabled(listening)
            Text("Source offer: this receiver is AGPL-3.0. If you run it for someone else, you must offer them the source.")
                .font(.footnote)
            Text("Acknowledgements")
                .font(.headline)
            Text(acknowledgementsText)
                .font(.footnote)
                .textSelection(.enabled)
                .accessibilityIdentifier("acknowledgements-body")
        }
        .padding()
        .frame(minWidth: 480, minHeight: 320)
    }

    private var acknowledgementsText: String {
        guard let url = Bundle.main.url(forResource: "NOTICE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "NOTICE is missing from this build."
        }
        return text
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        warning = FolderRisk.iCloudSyncWarning(for: url)
        status = warning == nil
            ? "Folder selected. Open a receive window to pair."
            : "Folder selected with a warning. Export is not refused (O-10)."
    }

    @MainActor
    private func toggleListen() async {
        if listening {
            await listener?.stop()
            listener = nil
            listening = false
            confirmation = ""
            status = "Receive window closed. The Mac is not advertising."
            return
        }
        guard let folder else { return }
        do {
            let vault = try CompanionPersistence.vault()
            let session: PairingSession
            if let existing = try? await vault.load() {
                session = existing
                status = "Reusing the stored pairing. Same QR as last time."
            } else {
                let secret = try PairingSecret.generateFromSystemRandomness()
                let installation = "mac-\(UUID().uuidString.prefix(8))"
                let hostName = Host.current().localizedName ?? "Mac"
                let serviceName = String("OHE \(hostName)".prefix(63))
                session = PairingSession.mac(
                    secret: secret,
                    localInstallationID: installation,
                    serviceName: serviceName
                )
                try await vault.save(session)
            }
            let payload = try session.qrPayload()
            payloadText = payload.encoded()
            qrImage = PairingQR.image(from: payloadText)
            pairing = session
            confirmation = session.confirmationCode ?? ""
            let psk = try CompanionPSK.preSharedKey(from: session.secret)
            let service = try BonjourService(name: session.serviceName)
            let started = CompanionListener(service: service, preSharedKey: psk)
            try await started.start()
            listener = started
            listening = true
            if confirmation.isEmpty {
                status = "Listening as \(session.serviceName). Advertise only while this window is open."
            }
            let archive = CompanionArchive(directory: folder)
            let installation = session.localInstallationID
            Task {
                while true {
                    let stream = try await started.accept()
                    let inbound = try CompanionInbound(
                        stream: stream,
                        archive: archive,
                        installationID: installation,
                        onPeerHello: { peer in
                            Task { @MainActor in
                                guard var current = pairing else { return }
                                let code = current.notePeer(peer)
                                pairing = current
                                confirmation = code
                                try? await vault.save(current)
                                status = "Phone connected. Compare confirmation \(code) with the phone."
                            }
                        }
                    )
                    Task { try await inbound.serve() }
                }
            }
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func forgetPairing() async {
        do {
            try await CompanionPersistence.vault().forget()
            pairing = nil
            payloadText = ""
            qrImage = nil
            confirmation = ""
            status = "Pairing forgotten. The next receive window will mint a new PSK."
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }
}
