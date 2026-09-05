import CompanionWire
import Foundation
import NetEgress

/// The one bridge from scanned pairing material to handshake material. `SinkCompanion` is the
/// only target that depends on both, which is what keeps the key out of everything else.
public enum CompanionPSK {
    /// TLS PSK *identity* (not the key). Both sides must send the same bytes or the handshake fails.
    public static let handshakeIdentity = "ohe-companion"

    public static func preSharedKey(
        from secret: PairingSecret,
        identity: String = handshakeIdentity
    ) throws -> PreSharedKey {
        try secret.withKeyBytes { key in
            try PreSharedKey(key: key, identity: Array(identity.utf8))
        }
    }
}
