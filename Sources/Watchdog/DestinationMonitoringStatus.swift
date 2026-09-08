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
        errorClass = snapshot.errorClass
    }
}
