import Foundation

/// File the widget, Control Centre, and watchdog read. Never SQLite (observability Q4).
public struct DestinationStatusSnapshot: Sendable, Equatable, Codable {
    public var destinationID: String
    public var enabled: Bool
    public var lastOutcome: String?
    public var lastSuccessEpoch: TimeInterval?
    public var writtenAtEpoch: TimeInterval

    public init(
        destinationID: String,
        enabled: Bool,
        lastOutcome: String? = nil,
        lastSuccessEpoch: TimeInterval? = nil,
        writtenAtEpoch: TimeInterval
    ) {
        self.destinationID = destinationID
        self.enabled = enabled
        self.lastOutcome = lastOutcome
        self.lastSuccessEpoch = lastSuccessEpoch
        self.writtenAtEpoch = writtenAtEpoch
    }
}

public enum DestinationSnapshotFile {
    public static func write(_ snapshot: DestinationStatusSnapshot, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> DestinationStatusSnapshot {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DestinationStatusSnapshot.self, from: data)
    }
}
