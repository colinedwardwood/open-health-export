// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import LocalAuthentication
import Observation

/// The only authentication seam used by the optional foreground privacy gate.
/// Export and destination-delivery code deliberately have no dependency on it.
@MainActor
protocol UserPresenceAuthenticating {
    func authenticate(reason: String) async -> Bool
}

struct LocalAuthenticationAdapter: UserPresenceAuthenticating {
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Keep locked"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}

/// SEC-65: the app has no stored-credential reveal feature. Authentication does
/// not turn a saved token or password into displayable text; credentials can
/// only be replaced through secure entry controls.
enum CredentialPresentationPolicy {
    static let allowsStoredCredentialReveal = false
    static let copy =
        "Saved credential values are never shown. Replace a credential by entering a new one."
}

@MainActor
@Observable
final class AppPrivacyGate {
    enum State: Equatable {
        case locked
        case authenticating
        case unlocked
    }

    private(set) var state: State = .locked
    private(set) var authenticationFailed = false

    @ObservationIgnored
    private let authenticator: any UserPresenceAuthenticating

    init(authenticator: any UserPresenceAuthenticating) {
        self.authenticator = authenticator
    }

    func prepare(enabled: Bool) {
        state = enabled ? .locked : .unlocked
        authenticationFailed = false
    }

    func lockIfEnabled(_ enabled: Bool) {
        guard enabled else { return }
        state = .locked
        authenticationFailed = false
    }

    @discardableResult
    func authenticateIfNeeded(enabled: Bool) async -> Bool {
        guard enabled else {
            state = .unlocked
            authenticationFailed = false
            return true
        }
        guard state != .unlocked else { return true }
        guard state != .authenticating else { return false }

        state = .authenticating
        let authenticated = await authenticator.authenticate(
            reason: "Open Open Health Exporter"
        )
        state = authenticated ? .unlocked : .locked
        authenticationFailed = !authenticated
        return authenticated
    }
}

#if DEBUG
/// Deterministic adapter used only by UI tests. Production builds always use
/// LocalAuthenticationAdapter.
@MainActor
final class TestUserPresenceAuthenticator: UserPresenceAuthenticating {
    private var outcomes: [Bool]

    init(outcomes: [Bool]) {
        self.outcomes = outcomes
    }

    func authenticate(reason _: String) async -> Bool {
        outcomes.isEmpty ? false : outcomes.removeFirst()
    }
}

@MainActor
enum UserPresenceAuthenticatorFactory {
    static func make() -> any UserPresenceAuthenticating {
        switch ProcessInfo.processInfo.environment["OHE_TEST_USER_PRESENCE"] {
        case "allow":
            TestUserPresenceAuthenticator(outcomes: [true])
        case "deny":
            TestUserPresenceAuthenticator(outcomes: [false, false])
        case "allow-then-deny":
            TestUserPresenceAuthenticator(outcomes: [true, false, false])
        default:
            LocalAuthenticationAdapter()
        }
    }
}
#else
@MainActor
enum UserPresenceAuthenticatorFactory {
    static func make() -> any UserPresenceAuthenticating {
        LocalAuthenticationAdapter()
    }
}
#endif
