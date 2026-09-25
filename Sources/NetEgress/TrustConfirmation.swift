// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// #66: a destination presented a certificate the system does not trust (self-signed
/// or a private CA). Nothing has been sent to it: no canary, no credential, no Health
/// data. The person has to compare the fingerprint with the one their server shows
/// and confirm it; setup then continues pinned to exactly that certificate.
public enum TrustConfirmation: Error, Equatable, Sendable {
    case required(TLSIdentity)

    public var identity: TLSIdentity {
        switch self {
        case .required(let identity): identity
        }
    }

    /// True when `identity` may carry data: the system trusts it, or it is the exact
    /// certificate the person confirmed.
    public static func permits(_ identity: TLSIdentity, confirmedLeafSPKISha256: String?) -> Bool {
        identity.isSystemTrusted || identity.leafSPKISha256 == confirmedLeafSPKISha256
    }
}

extension TrustConfirmation: LocalizedError {
    public var errorDescription: String? {
        "This destination's certificate is not publicly trusted. Compare its fingerprint with your server's before continuing. Nothing was sent."
    }
}
