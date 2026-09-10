import CoreDomain
import Foundation

public enum DisplayUnitPreference: String, Sendable, CaseIterable, Codable {
    /// R-65's default: follow the region, with the three below as the explicit override.
    case automatic
    case canonical
    case metric
    case usCustomary

    public var label: String {
        switch self {
        case .automatic: "Follow this iPhone's region"
        case .canonical: "Export units"
        case .metric: "Metric display"
        case .usCustomary: "US customary display"
        }
    }

    /// The locale is only consulted for `automatic`; resolving here keeps every reading
    /// path a pure function of an explicit policy.
    public func policy(locale: Locale) -> UnitDisplayPolicy {
        switch self {
        case .automatic: UnitDisplayPolicy.following(locale)
        case .canonical: .canonical
        case .metric: .metric
        case .usCustomary: .usCustomary
        }
    }
}

public struct DisplayMeasurement: Sendable, Equatable {
    public var value: Double
    public var unit: String

    public init(value: Double, unit: String) {
        self.value = value
        self.unit = unit
    }
}

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

public enum DataBrowserPeriod: Int, Sendable, CaseIterable {
    case day = 1
    case week = 7
    case month = 30
}

public struct DataBrowserDestination: Sendable, Equatable {
    public var name: String
    public var lastSent: String?

    public init(name: String, lastSent: String? = nil) {
        self.name = name
        self.lastSent = lastSent
    }
}

public struct DataBrowserDetail: Sendable, Equatable {
    public var metric: MetricID
    public var title: String
    public var exportUnit: String
    public var displayValue: Double?
    public var displayUnit: String
    public var latest: SampleRecord?
    public var samples: [SampleRecord]
    public var aggregates: [AggregateRecord]
    public var destinations: [DataBrowserDestination]
    public var aggregationExplanation: String?

    public init(
        metric: MetricID,
        title: String,
        exportUnit: String,
        displayValue: Double?,
        displayUnit: String,
        latest: SampleRecord?,
        samples: [SampleRecord],
        aggregates: [AggregateRecord],
        destinations: [DataBrowserDestination],
        aggregationExplanation: String?
    ) {
        self.metric = metric
        self.title = title
        self.exportUnit = exportUnit
        self.displayValue = displayValue
        self.displayUnit = displayUnit
        self.latest = latest
        self.samples = samples
        self.aggregates = aggregates
        self.destinations = destinations
        self.aggregationExplanation = aggregationExplanation
    }
}

public struct DataSelectionReview: Sendable, Equatable {
    public var adding: [MetricID]
    public var removing: [MetricID]
    public var needingPermission: [MetricID]
    public var removalWarning: String?

    public init(
        adding: [MetricID],
        removing: [MetricID],
        needingPermission: [MetricID],
        removalWarning: String?
    ) {
        self.adding = adding
        self.removing = removing
        self.needingPermission = needingPermission
        self.removalWarning = removalWarning
    }
}

public enum DataSelectionError: Error, Equatable {
    case sensitiveConfirmationRequired
}

public struct DataSelectionDraft: Sendable, Equatable {
    public var baseline: Set<MetricID>
    public private(set) var selected: Set<MetricID>

    public init(baseline: Set<MetricID>) {
        self.baseline = baseline
        self.selected = baseline
    }

    public mutating func toggle(
        _ metric: MetricID,
        destinationName: String,
        sensitiveConfirmation: String? = nil
    ) throws {
        if selected.contains(metric) {
            selected.remove(metric)
            return
        }
        if MetricCatalog.declaration(for: metric)?.sensitivity == .sensitive,
           sensitiveConfirmation != destinationName {
            throw DataSelectionError.sensitiveConfirmationRequired
        }
        selected.insert(metric)
    }

    /// Section-scoped bulk action. Sensitive metrics always require individual confirmation.
    public mutating func invertRoutine(_ metrics: [MetricID]) {
        for metric in metrics
            where MetricCatalog.declaration(for: metric)?.sensitivity != .sensitive {
            if selected.contains(metric) {
                selected.remove(metric)
            } else {
                selected.insert(metric)
            }
        }
    }

    public mutating func clearAll() {
        selected.removeAll()
    }

    public func review(
        authorized: Set<MetricID>,
        destinationName: String
    ) -> DataSelectionReview {
        let adding = selected.subtracting(baseline).sorted { $0.rawValue < $1.rawValue }
        let removing = baseline.subtracting(selected).sorted { $0.rawValue < $1.rawValue }
        return DataSelectionReview(
            adding: adding,
            removing: removing,
            needingPermission: adding.filter { !authorized.contains($0) },
            removalWarning: removing.isEmpty
                ? nil
                : "Removing a type does not delete data already sent to \(destinationName)."
        )
    }
}

/// R-69 type list: catalogue rows with values when present, never a denial claim.
public enum DataBrowser {
    public static let noDataCopy = "No data on this iPhone"
    /// R-60: a denied read and absent data are indistinguishable, so zero results name
    /// both causes and hand over the route to check, rather than claiming either one.
    public static let healthPathCopy =
        "Check in Health, under Sharing, then Apps."
    public static let emptyDetailCopy =
        "No samples for this type on this iPhone. Either there aren't any, or access is off in Health. "
            + healthPathCopy

    public static func rows(
        latest: [MetricID: SampleRecord],
        exported: Set<MetricID> = [],
        search: String = "",
        onlyWithData: Bool = false,
        displayUnits: UnitDisplayPolicy = .canonical
    ) -> [DataBrowserRow] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return MetricCatalog.all.compactMap { declaration in
            let title = declaration.wireId.replacingOccurrences(of: "_", with: " ")
            let sample = latest[declaration.id]
            let subtitle: String
            if let sample {
                let display = displayMeasurement(
                    sample.value,
                    unit: declaration.wireUnit,
                    policy: displayUnits
                )
                let source = sample.source.map { " · \($0.name)" } ?? ""
                subtitle = "\(formatValue(display.value)) \(display.unit) · \(sample.start)\(source)"
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

    public static func detail(
        metric: MetricID,
        samples: [SampleRecord],
        aggregates: [AggregateRecord] = [],
        destinations: [DataBrowserDestination] = [],
        period: DataBrowserPeriod = .month,
        displayUnits: UnitDisplayPolicy = .canonical,
        now: Date
    ) -> DataBrowserDetail? {
        guard let declaration = MetricCatalog.declaration(for: metric) else { return nil }
        let cutoff = now.addingTimeInterval(-Double(period.rawValue) * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        let visibleSamples = samples
            .filter { sample in
                sample.metric == metric
                    && (formatter.date(from: sample.start).map { $0 >= cutoff } ?? false)
            }
            .sorted { $0.start > $1.start }
        let visibleAggregates = aggregates
            .filter { $0.metric == metric }
            .sorted { $0.bucketStart > $1.bucketStart }
        let title = declaration.wireId.replacingOccurrences(of: "_", with: " ")
        let explanation = declaration.haRequiresAggregate
            ? "\(declaration.cumulative ? "sum" : "mean") · "
                + "\(declaration.cumulative ? "cumulative" : "discrete") · local day"
            : nil
        let display = visibleSamples.first.map {
            displayMeasurement(
                $0.value,
                unit: declaration.wireUnit,
                policy: displayUnits
            )
        }
        return DataBrowserDetail(
            metric: metric,
            title: title,
            exportUnit: declaration.wireUnit,
            displayValue: display?.value,
            displayUnit: display?.unit ?? declaration.wireUnit,
            latest: visibleSamples.first,
            samples: visibleSamples,
            aggregates: visibleAggregates,
            destinations: destinations,
            aggregationExplanation: explanation
        )
    }

    public static func formatValue(_ value: Double) -> String {
        String(format: "%.4g", value)
    }

    public static func displayMeasurement(
        _ value: Double,
        unit: String,
        preference: DisplayUnitPreference,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> DisplayMeasurement {
        displayMeasurement(value, unit: unit, policy: preference.policy(locale: locale))
    }

    public static func displayMeasurement(
        _ value: Double,
        unit: String,
        policy: UnitDisplayPolicy
    ) -> DisplayMeasurement {
        let converted: (Double?, String)?
        switch unit {
        case "mg/dL" where policy.glucose == .millimolesPerLitre:
            converted = (
                try? UnitMath.millimolesPerLitre(fromMilligramsPerDecilitre: value),
                "mmol/L"
            )
        case "kg" where policy.mass == .pounds:
            converted = (try? UnitMath.pounds(fromKilograms: value), "lb")
        case "km" where policy.distance == .miles:
            converted = (try? UnitMath.miles(fromKilometres: value), "mi")
        case "degC" where policy.temperature == .fahrenheit:
            converted = (try? UnitMath.fahrenheit(fromCelsius: value), "degF")
        case "m" where policy.length == .inches:
            converted = (try? UnitMath.inches(fromMetres: value), "in")
        case "mL" where policy.volume == .fluidOunces:
            converted = (try? UnitMath.fluidOunces(fromMillilitres: value), "fl oz")
        default:
            converted = nil
        }
        guard let converted, let convertedValue = converted.0 else {
            return DisplayMeasurement(value: value, unit: unit)
        }
        return DisplayMeasurement(value: convertedValue, unit: converted.1)
    }
}
