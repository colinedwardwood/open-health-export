// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CompanionReceive
import CompanionWire
import NetEgress
import SinkCompanion
import SwiftUI
import AppKit
import UserNotifications
import Combine

@main
struct CompanionApp: App {
    @ObservedObject private var chrome = CompanionChrome.shared

    var body: some Scene {
        WindowGroup {
            CompanionView(chrome: chrome)
        }
        MenuBarExtra(CompanionQuietWatch.menuBarTitle, systemImage: "laptopcomputer") {
            Text(chrome.watchLine)
            Button(CompanionQuietWatch.openWindow) {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

@MainActor
final class CompanionChrome: ObservableObject {
    static let shared = CompanionChrome()
    @Published var watchLine = CompanionQuietWatch.waitingCopy
}

struct CompanionView: View {
    @ObservedObject var chrome: CompanionChrome
    @State private var folder: URL?
    @State private var warning: String?
    @State private var payloadText = ""
    @State private var qrImage: NSImage?
    @State private var confirmation = ""
    @State private var pairing: PairingSession?
    @State private var status = "Choose a folder, then open a receive window."
    @State private var listening = false
    @State private var listener: CompanionListener?
    @State private var deleteEverythingArmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(status)
            Text(chrome.watchLine)
                .font(.footnote)
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
            Button(
                deleteEverythingArmed
                    ? "Confirm: delete received archives and pairing"
                    : "Delete everything received"
            ) {
                if deleteEverythingArmed {
                    Task { await deleteEverythingReceived() }
                } else {
                    deleteEverythingArmed = true
                    status = "Confirm to delete this folder's received archives, receipt ledger, and stored pairing."
                }
            }
            .disabled(listening || folder == nil)
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
        .onAppear { refreshQuietWatch() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            refreshQuietWatch()
        }
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
        deleteEverythingArmed = false
        folder = url
        warning = FolderRisk.iCloudSyncWarning(for: url)
        status = warning == nil
            ? "Folder selected. Open a receive window to pair."
            : "Folder selected with a warning. Export is not refused (O-10)."
        refreshQuietWatch()
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
            refreshQuietWatch()
            let archive = CompanionArchive(directory: folder)
            let installation = session.localInstallationID
            Task {
                while true {
                    let stream = try await started.accept()
                    let inbound = try CompanionInbound(
                        stream: stream,
                        archive: archive,
                        installationID: installation,
                        nowEpoch: { Date().timeIntervalSince1970 },
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
                    Task {
                        try await inbound.serve()
                        await MainActor.run { refreshQuietWatch() }
                    }
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

    @MainActor
    private func deleteEverythingReceived() async {
        guard let folder else { return }
        do {
            let deleted = try CompanionArchive(directory: folder).deleteEverythingReceived()
            try await CompanionPersistence.vault().forget()
            pairing = nil
            payloadText = ""
            qrImage = nil
            confirmation = ""
            deleteEverythingArmed = false
            status = "Deleted \(deleted) received archive(s), the receipt ledger, and the stored pairing."
            refreshQuietWatch()
        } catch {
            status = "Failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshQuietWatch() {
        guard let folder else {
            chrome.watchLine = CompanionQuietWatch.waitingCopy
            return
        }
        let archive = CompanionArchive(directory: folder)
        var watch = (try? archive.loadWatch()) ?? CompanionReceiveWatch()
        let now = Date().timeIntervalSince1970
        let kind = CompanionQuietWatch.evaluate(
            lastReceivedEpoch: watch.lastReceivedEpoch,
            nowEpoch: now
        )
        chrome.watchLine = CompanionQuietWatch.statusCopy(kind)
        if CompanionQuietWatch.claimQuietNotice(kind: kind, nowEpoch: now, watch: &watch) {
            try? archive.saveWatch(watch)
            Task { await CompanionQuietNotice.post(body: chrome.watchLine) }
        }
    }
}

enum CompanionQuietNotice {
    static func post(body: String) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        content.title = CompanionQuietWatch.quietTitle
        content.body = body
        let request = UNNotificationRequest(
            identifier: CompanionQuietWatch.notificationIdentifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
