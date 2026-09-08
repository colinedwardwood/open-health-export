import AppIntents
import Foundation
import Watchdog

struct DestinationStatusEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Export destination"
    )
    static var defaultQuery = DestinationStatusEntityQuery()

    var id: String

    @Property(title: "Destination")
    var label: String

    @Property(title: "Last successful export")
    var lastSuccessAt: String?

    @Property(title: "Last confirmed acknowledgement")
    var lastConfirmedAckAt: String?

    @Property(title: "Age in seconds")
    var ageSeconds: Int?

    @Property(title: "State")
    var state: String

    @Property(title: "Last outcome")
    var lastOutcome: String?

    @Property(title: "Attribution")
    var attribution: String?

    @Property(title: "Attribution confidence")
    var attributionConfidence: String?

    @Property(title: "Error class")
    var errorClass: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)", subtitle: "\(state)")
    }

    init(status: DestinationMonitoringStatus) {
        id = status.destinationID
        label = status.label
        lastSuccessAt = status.lastSuccessAt
        lastConfirmedAckAt = status.lastConfirmedAckAt
        ageSeconds = status.ageSeconds
        state = status.state
        lastOutcome = status.lastOutcome
        attribution = status.attribution
        attributionConfidence = status.attributionConfidence
        errorClass = status.errorClass
    }
}

struct DestinationStatusEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [DestinationStatusEntity] {
        Self.current().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DestinationStatusEntity] {
        Self.current()
    }

    private static func current() -> [DestinationStatusEntity] {
        let now = Date().timeIntervalSince1970
        return StatusSnapshotLocation.readAll().map {
            DestinationStatusEntity(
                status: DestinationMonitoringStatus(snapshot: $0, nowEpoch: now)
            )
        }
    }
}

struct LastSuccessfulExportIntent: AppIntent {
    static var title: LocalizedStringResource = "Last successful export"
    static var description = IntentDescription(
        "Returns value-free freshness and delivery status for every export destination."
    )
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[DestinationStatusEntity]> {
        .result(value: try await DestinationStatusEntityQuery().suggestedEntities())
    }
}

struct ExporterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LastSuccessfulExportIntent(),
            phrases: [
                "Get last successful export with \(.applicationName)",
                "Check export status with \(.applicationName)",
            ],
            shortTitle: "Last export status",
            systemImageName: "heart.text.clipboard"
        )
    }
}
