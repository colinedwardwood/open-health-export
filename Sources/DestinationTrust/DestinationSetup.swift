import EnginePorts
import Foundation
import NetEgress

public enum DestinationState: String, Sendable, Equatable {
    case draft
    case previewed
    case canarySent
    case canaryConfirmed
    case pinned
    case enabled
    case halted
}

public enum SetupError: Error, Equatable {
    case illegalTransition(from: DestinationState, to: DestinationState)
    case canaryMismatch
    case notEnabled
    case verificationRequired
}

/// R-40: trust changes the user must be told about. Accumulated by the transitions
/// and drained by the caller, so a transition stays synchronous and side-effect-free.
public enum TrustEvent: Sendable, Equatable {
    case canaryConfirmed
    /// `groupedFingerprint` is nil for a destination pinned without TLS.
    case pinRecorded(groupedFingerprint: String?)
    case pinChangedAndHalted(previous: String, observed: String)
    case destinationEnabled
    case trustLost
}

public struct DestinationSetup: Sendable {
    public private(set) var state: DestinationState
    public private(set) var previewBytes: Data?
    public private(set) var canaryCode: String?
    public private(set) var pin: PinRecord?
    public private(set) var displayedIdentity: TLSIdentity?
    public private(set) var testReport: DestinationTestReport?
    private var pendingEvents: [TrustEvent] = []

    public init() {
        state = .draft
    }

    /// Returns the trust events accumulated since the last drain and clears them.
    public mutating func drainEvents() -> [TrustEvent] {
        let drained = pendingEvents
        pendingEvents.removeAll()
        return drained
    }

    public mutating func recordPreview(_ bytes: Data) throws {
        guard state == .draft || state == .previewed else {
            throw SetupError.illegalTransition(from: state, to: .previewed)
        }
        previewBytes = bytes
        state = .previewed
    }

    public mutating func markCanarySent(code: String) throws {
        guard state == .previewed else {
            throw SetupError.illegalTransition(from: state, to: .canarySent)
        }
        canaryCode = code
        state = .canarySent
    }

    public mutating func confirmCanary(_ entered: String) throws {
        guard state == .canarySent else {
            throw SetupError.illegalTransition(from: state, to: .canaryConfirmed)
        }
        guard entered == canaryCode else { throw SetupError.canaryMismatch }
        state = .canaryConfirmed
        pendingEvents.append(.canaryConfirmed)
    }

    public mutating func recordPin(from identity: TLSIdentity, at observedAt: String, policy: PinPolicy) throws {
        guard state == .canaryConfirmed else {
            throw SetupError.illegalTransition(from: state, to: .pinned)
        }
        displayedIdentity = identity
        pin = PinRecord(
            leafSPKISha256: identity.leafSPKISha256,
            issuerSPKISha256: identity.issuerSPKISha256,
            firstSeen: observedAt,
            policy: policy
        )
        state = .pinned
        pendingEvents.append(.pinRecorded(groupedFingerprint: TLSIdentity.grouped(spki(of: identity, under: policy))))
    }

    public mutating func pinWithoutTLS() throws {
        guard state == .canaryConfirmed else {
            throw SetupError.illegalTransition(from: state, to: .pinned)
        }
        pin = nil
        state = .pinned
        pendingEvents.append(.pinRecorded(groupedFingerprint: nil))
    }

    public mutating func observeIdentity(_ identity: TLSIdentity, at observedAt: String) throws {
        let wasHalted = state == .halted
        displayedIdentity = identity
        switch PinGate.evaluate(observed: identity, stored: pin, policy: pin?.policy ?? .leaf, observedAt: observedAt) {
        case .matched, .firstUse, .noTLS:
            return
        case .mismatch:
            state = .halted
            // One halt is one notice: re-observing an already-halted destination does not re-notify.
            if !wasHalted, let pin {
                pendingEvents.append(
                    .pinChangedAndHalted(
                        previous: TLSIdentity.grouped(spki(of: pin, under: pin.policy)),
                        observed: TLSIdentity.grouped(spki(of: identity, under: pin.policy))
                    )
                )
            }
            throw PinError.mismatch
        }
    }

    /// A timeout is not a trust change (R-31): deliberately emits no `TrustEvent`.
    public mutating func noteTransportFailure() {}

    /// Trust withdrawn out of band — a revoked companion pairing or a deleted credential.
    public mutating func noteTrustLost() {
        let wasHalted = state == .halted
        state = .halted
        if !wasHalted {
            pendingEvents.append(.trustLost)
        }
    }

    /// R-25: a destination cannot enable until a real-path test has a non-failure verdict.
    public mutating func recordTest(_ report: DestinationTestReport) throws {
        guard state == .pinned || state == .enabled else {
            throw SetupError.illegalTransition(from: state, to: state)
        }
        testReport = report
    }

    public mutating func enable(sink: any DestinationSink) throws -> VerifiedDestination {
        guard state != .halted else { throw SetupError.notEnabled }
        guard state == .pinned || state == .enabled else {
            throw SetupError.illegalTransition(from: state, to: .enabled)
        }
        guard let testReport, testReport.allowsEnablement else {
            throw SetupError.verificationRequired
        }
        let wasEnabled = state == .enabled
        state = .enabled
        if !wasEnabled {
            pendingEvents.append(.destinationEnabled)
        }
        return VerifiedDestination(sink: sink)
    }

    private func spki(of identity: TLSIdentity, under policy: PinPolicy) -> String {
        switch policy {
        case .leaf: identity.leafSPKISha256
        case .issuer: identity.issuerSPKISha256
        }
    }

    private func spki(of record: PinRecord, under policy: PinPolicy) -> String {
        switch policy {
        case .leaf: record.leafSPKISha256
        case .issuer: record.issuerSPKISha256
        }
    }

}

public struct VerifiedDestination: Sendable {
    public let sink: any DestinationSink

    init(sink: any DestinationSink) {
        self.sink = sink
    }

    /// R-83 seam: tests and the DEBUG harness. Release UI must go through `DestinationSetup.enable`.
    public static func testing(_ sink: any DestinationSink) -> VerifiedDestination {
        VerifiedDestination(sink: sink)
    }
}

public enum CanaryCode {
    public static func fromEntropy(_ bytes: Data) -> String {
        let hex = bytes.prefix(4).map { String(format: "%02X", $0) }.joined()
        if hex.count >= 8 {
            return "\(hex.prefix(4))-\(hex.dropFirst(4).prefix(4))"
        }
        return hex
    }
}

/// Lives here, not in `EnginePorts`, because `DestinationTrust` depends on `EnginePorts`
/// and not the reverse: the port stays ignorant of trust vocabulary.
public enum TrustNotice {
    /// Total over `TrustEvent` — no `default`, so a new trust change cannot ship unnotified.
    public static func notice(for event: TrustEvent, destination: String) -> UserNotice {
        switch event {
        case .canaryConfirmed:
            return UserNotice(kind: .destinationVerified, destination: destination)
        case .pinRecorded(let groupedFingerprint):
            return UserNotice(kind: .destinationPinned, destination: destination, fingerprint: groupedFingerprint)
        case .pinChangedAndHalted(let previous, let observed):
            return UserNotice(
                kind: .destinationRepointed,
                destination: destination,
                fingerprint: observed,
                previousFingerprint: previous
            )
        case .destinationEnabled:
            return UserNotice(kind: .destinationEnabled, destination: destination)
        case .trustLost:
            return UserNotice(kind: .destinationTrustLost, destination: destination)
        }
    }
}

public enum HTTPPreview {
    public static func render(method: String, url: String, headers: [String: String], body: Data) -> Data {
        var lines = ["\(method) \(url)"]
        for key in headers.keys.sorted() {
            let value = mask(header: key, value: headers[key] ?? "")
            lines.append("\(key): \(value)")
        }
        lines.append("")
        var out = Data(lines.joined(separator: "\n").utf8)
        out.append(body)
        return out
    }

    static func mask(header: String, value: String) -> String {
        if header.caseInsensitiveCompare("Authorization") == .orderedSame {
            return "Bearer ****"
        }
        return value
    }
}
