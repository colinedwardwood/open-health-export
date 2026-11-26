// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import CoreDomain
import DestinationTrust
import Foundation
import NetEgress
import Observation

#if !OHE_OBS25_SIZE_BASELINE
/// Add your own OpenTelemetry collector (OTLP over HTTP). It receives the app's run
/// outcomes, never health values. The address is said back as it is typed, the test
/// sends one empty trace, the preview shows what an export would carry, and nothing is
/// saved until the person confirms it. The token goes to the Keychain.
@MainActor
@Observable
final class OTLPSetupModel {
    enum Stage: Equatable {
        case form
        case testing
        case confirm(preview: String, payload: Data)
        case saved
    }

    var address = ""
    var token = ""
    var allowsPlainHTTP = false
    private(set) var stage: Stage = .form
    private(set) var checklist = DestinationTestChecklist(steps: [.sendCanary])
    private(set) var error: UserFacingErrorObject?

    var addressCheck: NetworkAddressCheck {
        NetworkAddressCheck.check(address, allowsPlainHTTP: allowsPlainHTTP)
    }

    var canTest: Bool {
        addressCheck.isUsable && (stage == .form || error != nil)
    }

    private var cleanAddress: String { CredentialFieldHygiene.url(address).normalized }
    private var cleanToken: String? {
        let value = CredentialFieldHygiene.secret(token).normalized
        return value.isEmpty ? nil : value
    }

    func test() async {
        error = nil
        checklist = DestinationTestChecklist(steps: [.sendCanary])
        checklist.start(.sendCanary)
        stage = .testing
        do {
            try await AppDestinationSetup.testOTLP(
                urlString: cleanAddress,
                allowInsecureHTTP: allowsPlainHTTP,
                bearer: cleanToken
            )
            let preview = try await AppDestinationSetup.previewOTLP()
            checklist.finish(failedAt: nil)
            stage = .confirm(preview: preview.preview, payload: preview.payload)
        } catch {
            checklist.finish(failedAt: .sendCanary)
            fail(error)
            stage = .form
        }
    }

    func save() async {
        guard case let .confirm(_, payload) = stage else { return }
        do {
            _ = try await AppDestinationSetup.enableOTLPCollector(
                urlString: cleanAddress,
                allowInsecureHTTP: allowsPlainHTTP,
                previewPayload: payload,
                bearer: cleanToken
            )
            token = ""
            stage = .saved
        } catch {
            fail(error)
        }
    }

    private func fail(_ failure: Error) {
        error = UserFacingFailure.object(for: failure, destinationLabel: addressCheck.host ?? "the collector")
    }
}
#endif
