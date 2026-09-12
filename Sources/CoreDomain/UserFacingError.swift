// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-27: a user-facing error is a five-part object, not a localizedDescription.
public enum UserFacingFixAction: String, Sendable, Equatable, CaseIterable {
    case testAgain
    case editDestination
    case replaceToken
    case shortenWindow
    case lowerFreshness
    case setQoS1
    case reviewCoverage
    case exportNow
    case openBackgroundSettings

    public var label: String {
        switch self {
        case .testAgain: "Test again"
        case .editDestination: "Edit destination"
        case .replaceToken: "Replace token"
        case .shortenWindow: "Shorten window"
        case .lowerFreshness: "Choose a less frequent target"
        case .setQoS1: "Set QoS to 1"
        case .reviewCoverage: "Review coverage"
        case .exportNow: "Export now"
        case .openBackgroundSettings: "Open Background App Refresh settings"
        }
    }
}

public struct UserFacingErrorEvidence: Sendable, Equatable {
    public var statusCode: Int?
    public var method: String?
    public var host: String?
    public var path: String?
    public var bytesSent: Int?
    public var retryAfterSeconds: Int?
    public var traceID: String?
    public var buildHash: String?

    public init(
        statusCode: Int? = nil,
        method: String? = nil,
        host: String? = nil,
        path: String? = nil,
        bytesSent: Int? = nil,
        retryAfterSeconds: Int? = nil,
        traceID: String? = nil,
        buildHash: String? = nil
    ) {
        self.statusCode = statusCode
        self.method = method
        self.host = host
        self.path = path
        self.bytesSent = bytesSent
        self.retryAfterSeconds = retryAfterSeconds
        self.traceID = traceID
        self.buildHash = buildHash
    }
}

public enum UserFacingErrorArchetype: String, Sendable, Equatable, CaseIterable {
    case hostUnresolvable
    case tlsTrustFailure
    case certificateExpired
    case http401
    case http403
    case http404
    case http413
    case http429
    case http5xx
    case timeout
    case mqttNotAuthorised
    case mqttQoS0
    case healthLocked
    case backgroundNeverRan
    case waitingForUnmetered
    case zeroRecords
}

extension UserFacingErrorArchetype {
    public static func fromHTTPStatus(_ status: Int) -> UserFacingErrorArchetype? {
        switch status {
        case 401: .http401
        case 403: .http403
        case 404: .http404
        case 413: .http413
        case 429: .http429
        case 500...599: .http5xx
        default: nil
        }
    }

    public static func fromErrorClass(_ errorClass: ErrorClass) -> UserFacingErrorArchetype? {
        switch errorClass {
        case .deviceLocked, .healthDataRestricted:
            .healthLocked
        case .destinationUnreachable, .localNetworkDenied:
            .hostUnresolvable
        case .budgetExhausted, .cancelledBySystem, .lowPowerMode:
            .backgroundNeverRan
        case .awaitingUnmetered:
            .waitingForUnmetered
        case .internalFault:
            .timeout
        case .none:
            nil
        }
    }
}

public struct UserFacingErrorObject: Sendable, Equatable {
    public var archetype: UserFacingErrorArchetype
    public var destinationLabel: String
    public var title: String
    public var cause: String
    public var fix: String
    public var actions: [UserFacingFixAction]
    public var evidence: UserFacingErrorEvidence
    public var copyDiagnostics: String
    public var nonActionable: Bool

    public static func make(
        archetype: UserFacingErrorArchetype,
        destinationLabel: String,
        evidence: UserFacingErrorEvidence = UserFacingErrorEvidence(),
        identity: BuildIdentity = .current
    ) -> UserFacingErrorObject {
        let label = BuildIdentity.publicDestinationLabel(destinationLabel)
        var evidence = evidence
        if evidence.traceID == nil {
            evidence.traceID = BuildIdentity.traceID(seed: "\(archetype.rawValue)|\(label)|\(identity.sourceCommit)")
        }
        if evidence.buildHash == nil {
            evidence.buildHash = identity.buildHash
        }
        let parts = copy(archetype: archetype, label: label, evidence: evidence)
        return UserFacingErrorObject(
            archetype: archetype,
            destinationLabel: label,
            title: parts.title,
            cause: parts.cause,
            fix: parts.fix,
            actions: parts.actions,
            evidence: evidence,
            copyDiagnostics: diagnostics(
                archetype: archetype,
                label: label,
                evidence: evidence,
                identity: identity
            ),
            nonActionable: archetype == .healthLocked
        )
    }

    public var lines: [String] {
        [
            "① \(title)",
            "② \(cause)",
            "③ \(fix)",
            "④ " + actions.map(\.label).joined(separator: " · "),
            "⑤ \(copyDiagnostics)",
        ]
    }

    private static func copy(
        archetype: UserFacingErrorArchetype,
        label: String,
        evidence: UserFacingErrorEvidence
    ) -> (title: String, cause: String, fix: String, actions: [UserFacingFixAction]) {
        switch archetype {
        case .hostUnresolvable:
            return (
                "Couldn't find \(label)",
                "That name did not resolve on this network. .local names only work on the same network as the server.",
                "If you are away, use the external address or a VPN. You can add a second address for when you are away.",
                [.editDestination, .testAgain]
            )
        case .tlsTrustFailure:
            return (
                "Couldn't verify \(label)'s certificate",
                "The server presented a certificate this iPhone does not trust. Self-signed and private-CA certificates are not trusted by default.",
                "Import the server's certificate and pin it here, or install a publicly trusted certificate on the server.",
                [.editDestination, .testAgain]
            )
        case .certificateExpired:
            return (
                "\(label)'s certificate has expired",
                "The TLS certificate on the server is past its not-after date, so this iPhone refused the connection.",
                "Renew the certificate on the server. If you use Caddy or Traefik, check that automatic renewal is still running.",
                [.testAgain]
            )
        case .http401:
            return (
                "\(label) rejected the token",
                "The connection was accepted but the credential was refused. Long-lived tokens are revoked when you change a password or delete the token.",
                "Create a new access token in the destination's profile security settings, then replace it here.",
                [.replaceToken, .testAgain]
            )
        case .http403:
            return (
                "\(label) refused this request",
                "The credential was recognised but is not allowed to write here.",
                "Check the token's permissions, or the webhook's allowed scope.",
                [.editDestination, .testAgain]
            )
        case .http404:
            return (
                "That path does not exist on \(label)",
                "The server responded, but nothing is listening at the configured path.",
                "Check the webhook or topic path on the destination, then update it here.",
                [.editDestination, .testAgain]
            )
        case .http413:
            let sent = evidence.bytesSent.map { "\($0) bytes" } ?? "this batch"
            return (
                "The export was too large for \(label)",
                "We sent \(sent); the server refused the body as too large.",
                "Shorten the export window in this app, or raise the destination's maximum body size.",
                [.shortenWindow, .testAgain]
            )
        case .http429:
            let wait = evidence.retryAfterSeconds.map { "\($0) seconds" } ?? "a short interval"
            return (
                "\(label) asked us to slow down",
                "Rate limited. It asked us to wait \(wait).",
                "We will retry automatically. If this keeps happening, choose a less frequent freshness target.",
                [.lowerFreshness, .testAgain]
            )
        case .http5xx:
            let code = evidence.statusCode.map { " (\($0))" } ?? ""
            return (
                "\(label) returned an error\(code)",
                "The server, or the proxy in front of it, is not healthy. Your settings here look correct.",
                "Check the server. We will keep retrying.",
                [.testAgain]
            )
        case .timeout:
            return (
                "\(label) didn't respond in time",
                "The host may be asleep, or the connection may be slow.",
                "Try again on Wi-Fi. If the server sleeps, wake it or increase its timeout.",
                [.testAgain]
            )
        case .mqttNotAuthorised:
            return (
                "The broker refused the credential",
                "The broker accepted the connection then rejected the username or password (CONNACK not authorised).",
                "Check the MQTT user in your broker's configuration, then replace the credential here.",
                [.replaceToken, .testAgain]
            )
        case .mqttQoS0:
            return (
                "Sent — delivery not confirmed",
                "QoS 0 does not confirm that anything received the message. The broker may have accepted and dropped it.",
                "Set QoS to 1 on this destination so delivery can be confirmed.",
                [.setQoS1, .testAgain]
            )
        case .healthLocked:
            return (
                "Health data was locked",
                "The iPhone must be unlocked for any app to read Health data. Access ends shortly after you lock it. This is an Apple restriction.",
                "Nothing to change here. Export will continue after you unlock.",
                [.testAgain]
            )
        case .backgroundNeverRan:
            return (
                "No recent background exports to \(label)",
                "iOS decides when apps may run in the background and can skip us, especially in Low Power Mode or if Background App Refresh is off.",
                "Turn on Settings → General → Background App Refresh for this app, or export now for exact timing.",
                [.exportNow, .openBackgroundSettings]
            )
        case .waitingForUnmetered:
            return (
                "\(label) is waiting for Wi-Fi",
                "This destination skips cellular and other metered networks.",
                "Join Wi-Fi, or turn on Allow cellular and other metered networks for this destination.",
                [.editDestination, .exportNow]
            )
        case .zeroRecords:
            return (
                "Nothing to export",
                "None of the selected types returned data. That can mean there is no new data, or that access to those types is off in Health — this app has no way to tell which.",
                "Check Health → Sharing → Apps for this app, then review coverage.",
                [.reviewCoverage, .testAgain]
            )
        }
    }

    private static func diagnostics(
        archetype: UserFacingErrorArchetype,
        label: String,
        evidence: UserFacingErrorEvidence,
        identity: BuildIdentity
    ) -> String {
        var lines = [
            "Copy diagnostics",
            "archetype: \(archetype.rawValue)",
            "destination: \(label)",
        ]
        if let status = evidence.statusCode {
            lines.append("status: \(status)")
        }
        if let method = evidence.method {
            lines.append("method: \(method)")
        }
        if let host = evidence.host {
            lines.append("host: \(host)")
        }
        if let path = evidence.path {
            lines.append("path: \(redactPath(path))")
        }
        if let bytes = evidence.bytesSent {
            lines.append("bytesSent: \(bytes)")
        }
        if let retry = evidence.retryAfterSeconds {
            lines.append("retryAfterSeconds: \(retry)")
        }
        lines.append("trace: \(evidence.traceID ?? "none")")
        lines.append("build: \(evidence.buildHash ?? identity.buildHash)")
        lines.append("commit: \(identity.sourceCommit)")
        return lines.joined(separator: "\n")
    }

    private static func redactPath(_ path: String) -> String {
        guard path.count > 12 else { return path }
        let prefix = path.prefix(8)
        let suffix = path.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}

public enum UserFacingErrorCopy {
    public static let denylist = [
        "Something went wrong",
        "Unknown error",
        "Please try again",
        "NSURLErrorDomain",
    ]

    public static func violations(in text: String) -> [String] {
        denylist.filter { text.localizedCaseInsensitiveContains($0) }
    }

    public static func applied(_ action: UserFacingFixAction) -> String {
        "Applied \(action.label)."
    }
}

/// Settings this app owns and can change from a five-part error action (UX-29).
public struct OwnedExportSettings: Sendable, Equatable {
    public var windowHours: Int
    public var freshnessIntervalMinutes: Int
    public var mqttQoS: UInt8

    public init(windowHours: Int = 24, freshnessIntervalMinutes: Int = 15, mqttQoS: UInt8 = 1) {
        self.windowHours = max(1, windowHours)
        self.freshnessIntervalMinutes = max(1, freshnessIntervalMinutes)
        self.mqttQoS = mqttQoS
    }
}

public enum UserFacingFixApplier {
    public static func apply(_ action: UserFacingFixAction, to settings: inout OwnedExportSettings) {
        switch action {
        case .shortenWindow:
            settings.windowHours = max(1, settings.windowHours / 4)
        case .lowerFreshness:
            settings.freshnessIntervalMinutes = min(
                24 * 60,
                max(settings.freshnessIntervalMinutes * 2, 30)
            )
        case .setQoS1:
            settings.mqttQoS = 1
        default:
            break
        }
    }

    public static func scaledBytes(sent: Int, fromHours: Int, toHours: Int) -> Int {
        guard fromHours > 0 else { return sent }
        return sent * toHours / fromHours
    }

    public static func http413Resolved(
        bytesSent: Int,
        fromHours: Int,
        toHours: Int,
        serverLimitBytes: Int
    ) -> Bool {
        toHours < fromHours && scaledBytes(
            sent: bytesSent,
            fromHours: fromHours,
            toHours: toHours
        ) <= serverLimitBytes
    }

    public static func http429Resolved(
        fromMinutes: Int,
        toMinutes: Int,
        retryAfterMinutes: Int
    ) -> Bool {
        toMinutes > fromMinutes && toMinutes >= retryAfterMinutes
    }

    public static func mqttQoS0Resolved(from: UInt8, to: UInt8) -> Bool {
        from == 0 && to == 1
    }
}
