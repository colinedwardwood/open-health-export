// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import NetEgress
import UIKit

/// Holds a background-task assertion for the length of one HTTP exchange, so an export
/// that is mid-upload when the app leaves the foreground can usually finish. iOS may
/// still end the assertion early; the Idempotency-Key and the anchored re-send cover a
/// request cut off there (#27).
struct BackgroundTaskHTTPTransport: HTTPTransport {
    let inner: any HTTPTransport

    func execute(_ request: OutboundHTTPRequest) async throws -> OutboundHTTPResponse {
        let assertion = await BackgroundAssertion(name: "ohe.https.export")
        do {
            let response = try await inner.execute(request)
            await assertion.end()
            return response
        } catch {
            await assertion.end()
            throw error
        }
    }

    func identityProbe() async throws -> TLSIdentity? {
        try await inner.identityProbe()
    }

    func applyingPin(_ pin: PinRecord) -> any HTTPTransport {
        BackgroundTaskHTTPTransport(inner: inner.applyingPin(pin))
    }
}

@MainActor
private final class BackgroundAssertion {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
