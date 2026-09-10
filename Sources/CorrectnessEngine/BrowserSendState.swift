import CoreDomain
import EnginePorts

/// R-69: what the data browser says a destination received must come from the export's
/// own record of what it emitted, not from the fact that a type is selected. A type can
/// be selected and never sent — queued, purged, or added after the last run — and saying
/// otherwise would be the browser claiming a delivery that never happened.
public enum BrowserSendState {
    /// The latest sample day this metric has been emitted for, or nil when the export has
    /// never emitted it. Day granularity is what the emitted index records, so callers
    /// must phrase it as coverage of data through that day rather than a send time.
    public static func sentThroughDay(
        metric: MetricID,
        store: any StateStore
    ) async throws -> String? {
        try await store.transact { try $0.latestEmittedDay(metric: metric) }
    }

    public static func sentThroughDays(
        metrics: [MetricID],
        store: any StateStore
    ) async throws -> [MetricID: String] {
        try await store.transact { tx in
            var days: [MetricID: String] = [:]
            for metric in metrics {
                if let day = try tx.latestEmittedDay(metric: metric) {
                    days[metric] = day
                }
            }
            return days
        }
    }
}
