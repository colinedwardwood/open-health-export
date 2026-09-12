// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// Typed, value-free R-27 result shared by App Intents and tests.
public struct DestinationMonitoringStatus: Sendable, Equatable, Codable {
    public var destinationID: String
    public var label: String
    public var lastSuccessAt: String?
    public var lastConfirmedAckAt: String?
    public var ageSeconds: Int?
    public var state: String
    public var lastOutcome: String?
    public var attribution: String?
    public var attributionConfidence: String?
    public var errorClass: String?
    public var failureReason: String?
    public var freshnessEstimates: [FreshnessClass: LocalFreshnessEstimate]

    public init(snapshot: DestinationStatusSnapshot, nowEpoch: TimeInterval) {
        destinationID = snapshot.destinationID
        label = snapshot.destinationLabel
        lastSuccessAt = snapshot.lastSuccessEpoch.map {
            Date(timeIntervalSince1970: $0).ISO8601Format()
        }
        lastConfirmedAckAt = snapshot.lastConfirmedAckEpoch.map {
            Date(timeIntervalSince1970: $0).ISO8601Format()
        }
        ageSeconds = snapshot.lastSuccessEpoch.map {
            max(0, Int(nowEpoch - $0))
        }
        state = snapshot.state(at: nowEpoch).rawValue
        lastOutcome = snapshot.lastOutcome
        attribution = snapshot.attribution
        attributionConfidence = snapshot.attributionConfidence
        errorClass = DestinationStatusLine.reasonCode(snapshot)
        failureReason = ErrorClassManifest.userFacingReason(forRaw: errorClass)
        freshnessEstimates = snapshot.freshnessEstimates
    }
}

public struct WidgetStatusRoute: Sendable, Equatable {
    public static let scheme = "openhealthexporter"
    public static let host = "status"

    public var destinationID: String?

    public init(destinationID: String? = nil) {
        self.destinationID = destinationID
    }

    public init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == Self.host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        destinationID = components?.queryItems?
            .first(where: { $0.name == "destination" })?
            .value
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        if let destinationID {
            components.queryItems = [
                URLQueryItem(name: "destination", value: destinationID),
            ]
        }
        return components.url!
    }
}
