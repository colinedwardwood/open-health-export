import CoreDomain
import Foundation

public struct DataBrowserRow: Sendable, Equatable, Identifiable {
    public var id: MetricID { metric }
    public var metric: MetricID
    public var title: String
    public var subtitle: String
    public var exported: Bool
    public var sensitive: Bool
    public var hasData: Bool

    public init(
        metric: MetricID,
        title: String,
        subtitle: String,
        exported: Bool,
        sensitive: Bool,
        hasData: Bool
    ) {
        self.metric = metric
        self.title = title
        self.subtitle = subtitle
        self.exported = exported
        self.sensitive = sensitive
        self.hasData = hasData
    }
}

/// R-69 type list: catalogue rows with values when present, never a denial claim.
public enum DataBrowser {
    public static let noDataCopy = "No data on this iPhone"

    public static func rows(
        latest: [MetricID: SampleRecord],
        exported: Set<MetricID> = [],
        search: String = "",
        onlyWithData: Bool = false
    ) -> [DataBrowserRow] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return MetricCatalog.all.compactMap { declaration in
            let title = declaration.wireId.replacingOccurrences(of: "_", with: " ")
            let sample = latest[declaration.id]
            let subtitle: String
            if let sample {
                subtitle = "\(formatValue(sample.value)) \(declaration.wireUnit) · \(sample.start)"
            } else {
                subtitle = noDataCopy
            }
            let row = DataBrowserRow(
                metric: declaration.id,
                title: title,
                subtitle: subtitle,
                exported: exported.contains(declaration.id),
                sensitive: declaration.sensitivity == .sensitive,
                hasData: sample != nil
            )
            if onlyWithData, !row.hasData { return nil }
            if needle.isEmpty { return row }
            let haystack = [
                title,
                declaration.wireId,
                declaration.hkIdentifier,
                declaration.id.rawValue,
            ].joined(separator: " ").lowercased()
            return haystack.contains(needle) ? row : nil
        }
    }

    private static func formatValue(_ value: Double) -> String {
        String(format: "%.4g", value)
    }
}
