// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import DestinationTrust
import Foundation
import MetricCatalog
import NetEgress
import Observation

/// #48: add your own HTTPS server or a Home Assistant webhook. The address is said
/// back as it is typed; the test shows each step; a certificate that isn't publicly
/// trusted is compared by fingerprint before anything is sent (#66); and the server
/// is only saved after the person confirms it on the card (R-31), with a typed phrase
/// for a public address (SEC-14).
@MainActor
@Observable
final class NetworkSetupModel {
    enum Stage: Equatable {
        case form
        case testing
        case confirmCertificate(TLSIdentity)
        case confirmServer(DestinationConfirmationCard)
        case saved
    }

    let kind: DestinationKind
    var address = ""
    /// The token (HTTPS), webhook ID (Home Assistant) or password (MQTT).
    var secret = ""
    var allowsPlainHTTP = false
    // MQTT (#49). QoS 1 waits for the broker to acknowledge each export.
    var username = ""
    var qos: UInt8 = 1
    var clientID = "ohe-iphone"
    var topic = "ohe/health"
    var publicPhrase = ""
    private(set) var stage: Stage = .form
    private(set) var checklist = DestinationTestChecklist.https(encrypted: true)
    private(set) var error: UserFacingErrorObject?

    @ObservationIgnored private let services: AppEnvironment

    init(kind: DestinationKind, services: AppEnvironment = .live) {
        self.kind = kind
        self.services = services
    }

    var addressCheck: NetworkAddressCheck {
        kind == .mqtt
            ? NetworkAddressCheck.checkBroker(address, allowsUnencrypted: allowsPlainHTTP)
            : NetworkAddressCheck.check(address, allowsPlainHTTP: allowsPlainHTTP)
    }

    private func freshChecklist(checksCertificate: Bool) -> DestinationTestChecklist {
        kind == .mqtt
            ? .mqtt(encrypted: addressCheck.encrypted, checksCertificate: checksCertificate, confirmsDelivery: qos > 0)
            : .https(encrypted: addressCheck.encrypted)
    }

    /// Home Assistant needs its webhook ID; an HTTPS token is optional.
    var canTest: Bool {
        guard addressCheck.isUsable, stage == .form || error != nil else { return false }
        return kind != .homeAssistantWebhook || !secret.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canConfirm: Bool {
        guard case let .confirmServer(card) = stage else { return false }
        return !card.requiresPublicAddressConfirmation
            || publicPhrase.trimmingCharacters(in: .whitespaces) == ConfirmationCopy.publicAddressPhrase
    }

    func test(confirmed: TLSIdentity? = nil) async {
        let confirmedFingerprint = confirmed?.leafSPKISha256
        error = nil
        checklist = freshChecklist(checksCertificate: confirmed != nil)
        if let first = checklist.steps.first?.step { checklist.start(first) }
        stage = .testing
        let progress: DestinationTestProgress = { _, _, step in
            Task { @MainActor in self.checklist.start(step) }
        }
        let address = CredentialFieldHygiene.url(address).normalized
        let secret = CredentialFieldHygiene.secret(secret).normalized
        do {
            let card: DestinationConfirmationCard
            switch kind {
            case .mqtt:
                card = try await AppDestinationSetup.prepareMQTT(
                    urlString: address,
                    allowInsecure: allowsPlainHTTP,
                    clientID: clientID.trimmingCharacters(in: .whitespaces),
                    topic: topic.trimmingCharacters(in: .whitespaces),
                    clientPKCS12: nil,
                    clientPKCS12Password: nil,
                    username: username.isEmpty ? nil : username,
                    password: secret.isEmpty ? nil : secret,
                    qos: qos,
                    importedLocalIdentifier: nil,
                    confirmedIdentity: confirmed,
                    onProgress: progress
                )
            case .homeAssistantWebhook:
                card = try await AppDestinationSetup.prepareHomeAssistantWebhook(
                    baseURLString: address,
                    webhookID: secret,
                    allowInsecureHTTP: allowsPlainHTTP,
                    importedLocalIdentifier: nil,
                    confirmedLeafSPKISha256: confirmedFingerprint,
                    onProgress: progress
                )
            default:
                card = try await AppDestinationSetup.prepareHTTPS(
                    urlString: address,
                    allowInsecureHTTP: allowsPlainHTTP,
                    bearer: secret.isEmpty ? nil : secret,
                    destinationID: kind.destinationID,
                    destinationLabel: "Your server",
                    webhookID: nil,
                    persistedURLString: nil,
                    importedLocalIdentifier: nil,
                    confirmedLeafSPKISha256: confirmedFingerprint,
                    onProgress: progress
                )
            }
            checklist.finish(failedAt: nil)
            publicPhrase = ""
            stage = .confirmServer(card)
        } catch let TrustConfirmation.required(identity) {
            // Nothing has been sent: the test stops before the canary carries any token.
            checklist.reset()
            stage = .confirmCertificate(identity)
        } catch {
            let running = checklist.steps.first { $0.state == .running }?.step
            if case let SetupError.testFailed(step) = error {
                checklist.finish(failedAt: step)
            } else {
                checklist.finish(failedAt: running ?? checklist.steps.first?.step)
            }
            self.error = UserFacingFailure.object(for: error, destinationLabel: addressCheck.host ?? "the server")
            stage = .form
        }
    }

    func trustCertificate(_ identity: TLSIdentity) async {
        await test(confirmed: identity)
    }

    func cancel() async {
        if case .confirmServer = stage {
            if kind == .mqtt {
                await AppDestinationSetup.service.cancelMQTT()
            } else {
                await AppDestinationSetup.service.cancelHTTPS()
            }
        }
        checklist.reset()
        stage = .form
    }

    /// Saves and enables the confirmed server. A new destination starts with the
    /// everyday types from the last seven days, as Files and first run do.
    func confirm() async {
        guard canConfirm else { return }
        do {
            let existing = try await services.destinations.scope(kind.destinationID)
            if !existing.isConfigured {
                let scope = try DestinationExportScope(
                    destinationID: kind.destinationID,
                    metrics: Set(MetricCatalog.coreDaily.map(\.id)),
                    startInclusive: OnboardingPlan.defaultScopeStart(now: Date(), calendar: .current)
                )
                try await services.destinations.applyScope(scope, previousMetrics: [])
            }
            if kind == .mqtt {
                _ = try await AppDestinationSetup.service.confirmMQTT()
            } else {
                _ = try await AppDestinationSetup.service.confirmHTTPS()
            }
            try? services.status.acknowledgeDestinationChanges()
            secret = ""
            AppLifecycleCoordinator.shared.stopObservers()
            try? await AppLifecycleCoordinator.shared.startObserversIfEligible()
            stage = .saved
        } catch {
            self.error = UserFacingFailure.object(for: error, destinationLabel: addressCheck.host ?? "the server")
        }
    }
}
