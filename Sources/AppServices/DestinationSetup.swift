// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import DestinationTrust
import Foundation

/// A kind of destination someone can add (#47). Only the kinds whose setup screens
/// exist are offered; the Mac companion stays hidden until 1.1 (#15).
public enum DestinationKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case files
    case homeAssistant
    case mqtt
    case https

    public var id: String { rawValue }

    /// The destination id the engine and the status snapshots use.
    public var destinationID: String {
        switch self {
        case .files: "local-file"
        case .homeAssistant: "home-assistant"
        case .mqtt: "mqtt"
        case .https: "https"
        }
    }

    /// What the person needs before they start, in one line.
    public var requirement: String {
        switch self {
        case .files: "A folder in Files on this phone or in iCloud Drive."
        case .homeAssistant: "Your Home Assistant address and a webhook ID."
        case .mqtt: "Your broker's address, and a username if it needs one."
        case .https: "An HTTPS endpoint you control."
        }
    }

    /// The kinds with a setup flow today. #48 and #49 add the network ones.
    public static let addable: [DestinationKind] = [.files]
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
