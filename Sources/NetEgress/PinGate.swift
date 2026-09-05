public enum PinPolicy: String, Sendable, Equatable {
    case leaf
    case issuer
}

public struct PinRecord: Sendable, Equatable {
    public var leafSPKISha256: String
    public var issuerSPKISha256: String
    public var firstSeen: String
    public var policy: PinPolicy

    public init(leafSPKISha256: String, issuerSPKISha256: String, firstSeen: String, policy: PinPolicy) {
        self.leafSPKISha256 = leafSPKISha256
        self.issuerSPKISha256 = issuerSPKISha256
        self.firstSeen = firstSeen
        self.policy = policy
    }
}

public enum PinOutcome: Sendable, Equatable {
    case firstUse(PinRecord)
    case matched
    case mismatch
    case noTLS
}

public enum PinError: Error, Equatable {
    case mismatch
    case notPinned
}

public enum PinGate {
    public static func evaluate(
        observed: TLSIdentity?,
        stored: PinRecord?,
        policy: PinPolicy,
        observedAt: String
    ) -> PinOutcome {
        guard let observed else { return .noTLS }
        guard let stored else {
            return .firstUse(
                PinRecord(
                    leafSPKISha256: observed.leafSPKISha256,
                    issuerSPKISha256: observed.issuerSPKISha256,
                    firstSeen: observedAt,
                    policy: policy
                )
            )
        }
        switch stored.policy {
        case .leaf:
            return observed.leafSPKISha256 == stored.leafSPKISha256 ? .matched : .mismatch
        case .issuer:
            return observed.issuerSPKISha256 == stored.issuerSPKISha256 ? .matched : .mismatch
        }
    }

    public static func requireMatch(observed: TLSIdentity?, stored: PinRecord) throws {
        switch evaluate(observed: observed, stored: stored, policy: stored.policy, observedAt: stored.firstSeen) {
        case .matched:
            return
        case .noTLS:
            return
        case .firstUse:
            throw PinError.notPinned
        case .mismatch:
            throw PinError.mismatch
        }
    }
}
