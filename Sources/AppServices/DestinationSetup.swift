// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import DestinationTrust
import Foundation

/// A kind of destination someone can add (#47). Only the kinds whose setup screens
/// exist are offered; the Mac companion stays hidden until 1.1 (#15).
public enum DestinationKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case files
    case https
    /// The webhook route into Home Assistant. Advanced: it delivers the feed to an
    /// automation, and creates no sensors by itself (#48). The recommended route is
    /// MQTT discovery (#49).
    case homeAssistantWebhook
    case mqtt

    public var id: String { rawValue }

    /// The destination id the engine and the status snapshots use.
    public var destinationID: String {
        switch self {
        case .files: "local-file"
        case .https: "https"
        case .homeAssistantWebhook: "home-assistant"
        case .mqtt: "mqtt"
        }
    }

    /// What the person needs before they start, in one line.
    public var requirement: String {
        switch self {
        case .files: "A folder in Files on this phone or in iCloud Drive."
        case .https: "An HTTPS address you control, and a token if it needs one."
        case .homeAssistantWebhook: "Your Home Assistant address and a webhook automation."
        case .mqtt: "Your broker's address, and a username if it needs one."
        }
    }

    /// Said before any configuration, so nobody sets up something that won't do what
    /// they expect (#48).
    public var caveat: String? {
        switch self {
        case .homeAssistantWebhook:
            "This sends your data to a Home Assistant automation. It doesn't create sensors by itself: you need an automation that does something with each delivery."
        default:
            nil
        }
    }

    /// The kinds with a setup flow today. #49 adds MQTT.
    public static let addable: [DestinationKind] = [.files, .https, .homeAssistantWebhook]
}

/// The named steps of a destination test, each with its own state, so the screen can
/// show live checkmarks and VoiceOver can announce progress (#47).
public struct DestinationTestChecklist: Sendable, Equatable {
    public enum StepState: Sendable, Equatable {
        case pending
        case running
        case passed
        case failed
    }

    public struct Step: Sendable, Equatable, Identifiable {
        public var step: DestinationTestStep
        public var title: String
        public var state: StepState
        public var id: String { step.rawValue }
    }

    public private(set) var steps: [Step]
    /// Set once the test has an outcome. Progress reports arrive asynchronously and
    /// one can land after the outcome; it must not reopen a finished test (#47).
    public private(set) var isFinished = false

    public init(steps: [DestinationTestStep]) {
        self.steps = steps.map { Step(step: $0, title: Self.title($0), state: .pending) }
    }

    /// The Files test: open the folder, write a test file, read it back, check it.
    public static let localFile = DestinationTestChecklist(
        steps: [.openFolder, .writeCanary, .readBack, .confirmBytes]
    )

    /// The HTTPS test. Plain HTTP (an explicit opt-in) has no certificate to check.
    public static func https(encrypted: Bool) -> DestinationTestChecklist {
        DestinationTestChecklist(
            steps: encrypted
                ? [.resolveHost, .tlsHandshake, .confirmCertificate, .authenticate, .sendCanary, .readResponse]
                : [.resolveHost, .authenticate, .sendCanary, .readResponse]
        )
    }

    public var passed: Bool { !steps.isEmpty && steps.allSatisfy { $0.state == .passed } }
    public var failed: Bool { steps.contains { $0.state == .failed } }
    public var running: Bool { steps.contains { $0.state == .running } }

    /// The test reports the step it is starting; everything before it has passed.
    public mutating func start(_ step: DestinationTestStep) {
        guard !isFinished, let index = steps.firstIndex(where: { $0.step == step }) else { return }
        for i in steps.indices {
            steps[i].state = i < index ? .passed : (i == index ? .running : .pending)
        }
    }

    public mutating func finish(failedAt step: DestinationTestStep?) {
        isFinished = true
        guard let step else {
            for i in steps.indices { steps[i].state = .passed }
            return
        }
        let failedIndex = steps.firstIndex { $0.step == step }
            ?? steps.firstIndex { $0.state == .running }
            ?? 0
        for i in steps.indices {
            steps[i].state = i < failedIndex ? .passed : (i == failedIndex ? .failed : .pending)
        }
    }

    public mutating func reset() {
        isFinished = false
        for i in steps.indices { steps[i].state = .pending }
    }

    /// What VoiceOver says as the test moves on.
    public var announcement: String? {
        if passed { return "Test passed." }
        if let failed = steps.first(where: { $0.state == .failed }) { return "\(failed.title) failed." }
        if let running = steps.first(where: { $0.state == .running }) { return "\(running.title)…" }
        return nil
    }

    static func title(_ step: DestinationTestStep) -> String {
        switch step {
        case .openFolder: "Open the folder"
        case .writeCanary: "Write a test file"
        case .readBack: "Read it back"
        case .confirmBytes: "Check it matches"
        case .resolveHost: "Find the server"
        case .tlsHandshake: "Start a secure connection"
        case .confirmCertificate: "Check the certificate"
        case .authenticate: "Sign in"
        case .sendCanary, .publishCanary: "Send a test record"
        case .readResponse, .receiveEcho: "Confirm it arrived"
        case .connect: "Connect"
        case .subscribe: "Listen for the reply"
        }
    }
}

/// What a typed server address will actually do, said back before anything is sent
/// (#48: parse-back under URL fields).
public struct NetworkAddressCheck: Sendable, Equatable {
    public var host: String?
    public var encrypted: Bool
    public var message: String
    public var isUsable: Bool

    public static func check(_ raw: String, allowsPlainHTTP: Bool) -> NetworkAddressCheck {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return NetworkAddressCheck(host: nil, encrypted: false, message: "Enter the address, starting with https://.", isUsable: false)
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            return NetworkAddressCheck(host: nil, encrypted: false, message: "That isn't a full address. It should look like https://example.com/path.", isUsable: false)
        }
        if url.user != nil || url.password != nil {
            return NetworkAddressCheck(host: host, encrypted: false, message: "Remove the name and password from the address. Use the token field instead.", isUsable: false)
        }
        switch scheme {
        case "https":
            return NetworkAddressCheck(host: host, encrypted: true, message: "Will send to \(host), encrypted.", isUsable: true)
        case "http" where allowsPlainHTTP:
            return NetworkAddressCheck(host: host, encrypted: false, message: "Will send to \(host) without encryption. Anyone on the network path can read it.", isUsable: true)
        case "http":
            return NetworkAddressCheck(host: host, encrypted: false, message: "This address isn't encrypted. Use https://, or turn on plain HTTP below if this server is on your own network.", isUsable: false)
        default:
            return NetworkAddressCheck(host: host, encrypted: false, message: "Only https:// addresses are supported.", isUsable: false)
        }
    }
}

/// The smallest automation that shows a delivery arrived, from the Home Assistant
/// quickstart: it makes receipt visible and does nothing else (#48). Valid for the
/// oldest Home Assistant CI tests against (2025.9).
public enum HomeAssistantWebhookExample {
    public static let yaml = """
    alias: KeepMyMetrics delivery
    description: Shows a notification each time KeepMyMetrics delivers an export.
    triggers:
      - trigger: webhook
        webhook_id: PASTE-THE-SAME-WEBHOOK-ID-HERE
        allowed_methods:
          - POST
        local_only: true
    actions:
      - action: persistent_notification.create
        data:
          title: KeepMyMetrics
          message: An export arrived.
    """
}
