// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Pairing until both installation IDs are known. The phone has the Mac's ID from the QR, so it
/// can show the SAS immediately. The Mac learns the phone's ID from HELLO, so it shows the SAS
/// only after the first handshake — that is the comparison the user is asked to make.
public struct PairingSession: Sendable, Equatable {
    public var secret: PairingSecret
    public var localInstallationID: String
    public var macInstallationID: String
    public var serviceName: String
    public var peerInstallationID: String?

    public init(
        secret: PairingSecret,
        localInstallationID: String,
        macInstallationID: String,
        serviceName: String,
        peerInstallationID: String? = nil
    ) {
        self.secret = secret
        self.localInstallationID = localInstallationID
        self.macInstallationID = macInstallationID
        self.serviceName = serviceName
        self.peerInstallationID = peerInstallationID
    }

    public static func phone(payload: PairingPayload, localInstallationID: String) -> PairingSession {
        PairingSession(
            secret: payload.secret,
            localInstallationID: localInstallationID,
            macInstallationID: payload.macInstallationID,
            serviceName: payload.serviceName,
            peerInstallationID: payload.macInstallationID
        )
    }

    public static func mac(
        secret: PairingSecret,
        localInstallationID: String,
        serviceName: String
    ) -> PairingSession {
        PairingSession(
            secret: secret,
            localInstallationID: localInstallationID,
            macInstallationID: localInstallationID,
            serviceName: serviceName,
            peerInstallationID: nil
        )
    }

    public var confirmationCode: String? {
        guard let peer = peerInstallationID else { return nil }
        return PairingConfirmation.confirmationCode(
            secret: secret,
            installationIDs: (localInstallationID, peer)
        )
    }

    @discardableResult
    public mutating func notePeer(_ installationID: String) -> String {
        peerInstallationID = installationID
        return confirmationCode ?? ""
    }
}
