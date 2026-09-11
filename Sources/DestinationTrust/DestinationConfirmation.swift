// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import EnginePorts
import Foundation
import NetEgress

/// R-31 confirmation card shown after a real-path canary and before persist/enable.
public struct DestinationConfirmationCard: Sendable, Equatable {
    public var host: String
    public var identity: TLSIdentity?
    public var preview: Data
    public var insecureWithoutTLS: Bool

    public init(
        host: String,
        identity: TLSIdentity?,
        preview: Data,
        insecureWithoutTLS: Bool
    ) {
        self.host = host
        self.identity = identity
        self.preview = preview
        self.insecureWithoutTLS = insecureWithoutTLS
    }

    public var lines: [String] {
        var lines = [ConfirmationCopy.title]
        if let identity {
            lines.append(
                "\(host) resolved to \(identity.resolvedAddress) (\(ConfirmationCopy.addressClassPhrase(identity.addressClass)))"
            )
            lines.append("TLS \(identity.tlsVersion)")
            lines.append("Subject   \(identity.leafSubject)")
            lines.append("Issuer    \(identity.leafIssuer)")
            lines.append("Valid     \(identity.notBefore) – \(identity.notAfter)")
            lines.append("SPKI      SHA-256 \(identity.groupedLeafFingerprint)")
        } else if insecureWithoutTLS {
            lines.append("\(host) is using an unencrypted transport by explicit opt-in.")
        } else {
            lines.append("\(host) returned no TLS identity.")
        }
        lines.append(ConfirmationCopy.remember)
        lines.append(ConfirmationCopy.previewHeading)
        lines.append(String(decoding: preview, as: UTF8.self))
        return lines
    }
}

public enum ConfirmationCopy {
    public static let title = "Confirm this server"
    public static let remember =
        "We'll remember this certificate. If it changes, exports stop until you confirm the new one."
    public static let approve = "This is my server"
    public static let cancel = "Cancel"
    public static let previewHeading = "Dry-run preview (no Health data)"

    public static func addressClassPhrase(_ addressClass: AddressClass) -> String {
        switch addressClass {
        case .loopback: "a loopback address"
        case .privateRFC1918: "a private address"
        case .linkLocal: "a link-local address"
        case .publicUnicast: "a public address"
        case .unknown: "an unclassified address"
        }
    }
}

public enum TrustNoticePosting {
    public static func post(
        events: [TrustEvent],
        destination: String,
        notifier: UserNotifier
    ) async throws -> [NoticeDelivery] {
        var deliveries: [NoticeDelivery] = []
        for event in events {
            deliveries.append(
                try await notifier.notify(TrustNotice.notice(for: event, destination: destination))
            )
        }
        return deliveries
    }

    public static func suppressedCount(_ deliveries: [NoticeDelivery]) -> Int {
        deliveries.filter { $0 == .skippedAuthorizationDenied }.count
    }
}
