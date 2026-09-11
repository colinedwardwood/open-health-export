// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// QA-08 volunteer/maintainer tool: aggregate store *shape* only.
/// Counts, month ranges, source classes, duration/interval histograms, and
/// metadata-key frequencies. Never values, UUIDs, hostnames, or source names.
public enum StoreCharacterisation {
    public static let sourceClassAppleWatch = "apple-watch"
    public static let sourceClassIPhone = "iphone"
    public static let sourceClassUserEntered = "user-entered"
    public static let sourceClassThirdParty = "third-party"
    public static let sourceClassUnknown = "unknown"

    public struct Event: Sendable, Equatable {
        public var metricId: String
        public var start: String
        public var end: String
        public var sourceClass: String
        public var metadataKeys: [String]

        public init(
            metricId: String,
            start: String,
            end: String,
            sourceClass: String,
            metadataKeys: [String]
        ) {
            self.metricId = metricId
            self.start = start
            self.end = end
            self.sourceClass = sourceClass
            self.metadataKeys = metadataKeys
        }
    }

    public struct TypeShape: Sendable, Equatable {
        public var metricId: String
        public var count: Int
        public var firstMonth: String?
        public var lastMonth: String?
        public var sourceClasses: [String: Int]
        public var durationBuckets: [String: Int]
        public var intervalBuckets: [String: Int]
        public var metadataKeyFrequencies: [String: Int]
    }

    public struct Report: Sendable, Equatable {
        public var sampleCount: Int
        public var typeCount: Int
        public var types: [TypeShape]
    }

    public static func classify(
        source: SampleSourceIdentity?,
        device: SampleDevice?,
        wasUserEntered: Bool?
    ) -> String {
        if wasUserEntered == true {
            return sourceClassUserEntered
        }
        let haystack = [
            source?.name,
            source?.productType,
            source?.bundleIdentifier,
            device?.name,
            device?.model,
            device?.productTypeHint,
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        if haystack.contains("watch") {
            return sourceClassAppleWatch
        }
        if haystack.contains("iphone") {
            return sourceClassIPhone
        }
        if source != nil || device != nil {
            return sourceClassThirdParty
        }
        return sourceClassUnknown
    }

    public static func event(from sample: SampleRecord) -> Event {
        Event(
            metricId: sample.metric.rawValue,
            start: sample.start,
            end: sample.end,
            sourceClass: classify(
                source: sample.source,
                device: sample.device,
                wasUserEntered: sample.wasUserEntered
            ),
            metadataKeys: metadataKeys(
                source: sample.source,
                device: sample.device,
                wasUserEntered: sample.wasUserEntered
            )
        )
    }

    public static func event(from object: [String: Any]) -> Event? {
        let kind = object["kind"] as? String ?? ""
        if kind == "batch.header" || kind == "batch.footer" {
            return nil
        }
        guard let start = object["start"] as? String else { return nil }
        let metricId = (object["metricId"] as? String)
            ?? (object["hkIdentifier"] as? String)
            ?? kind
        if metricId.isEmpty { return nil }
        let end = (object["end"] as? String) ?? start
        let source = object["source"] as? [String: Any]
        let device = object["device"] as? [String: Any]
        let identity = source.map {
            SampleSourceIdentity(
                name: ($0["name"] as? String) ?? "",
                bundleIdentifier: $0["bundleId"] as? String,
                productType: $0["productType"] as? String
            )
        }
        let sampleDevice = device.map {
            SampleDevice(
                name: $0["name"] as? String,
                manufacturer: $0["manufacturer"] as? String,
                model: $0["model"] as? String,
                hardwareVersion: $0["hardwareVersion"] as? String,
                softwareVersion: $0["softwareVersion"] as? String
            )
        }
        return Event(
            metricId: metricId,
            start: start,
            end: end,
            sourceClass: classify(
                source: identity,
                device: sampleDevice,
                wasUserEntered: object["wasUserEntered"] as? Bool
            ),
            metadataKeys: collectKeyNames(object)
        )
    }

    public static func report(events: [Event]) -> Report {
        var grouped: [String: [Event]] = [:]
        for event in events {
            grouped[event.metricId, default: []].append(event)
        }
        let types = grouped.keys.sorted().map { metricId -> TypeShape in
            let rows = grouped[metricId]!.sorted { $0.start < $1.start }
            let months = rows.compactMap { month(fromISO: $0.start) }
            var sourceClasses: [String: Int] = [:]
            var durationBuckets: [String: Int] = [:]
            var intervalBuckets: [String: Int] = [:]
            var metadataKeyFrequencies: [String: Int] = [:]
            for row in rows {
                sourceClasses[row.sourceClass, default: 0] += 1
                durationBuckets[durationBucket(start: row.start, end: row.end), default: 0] += 1
                for key in row.metadataKeys {
                    metadataKeyFrequencies[key, default: 0] += 1
                }
            }
            for index in 1..<rows.count {
                let label = intervalBucket(previous: rows[index - 1].start, current: rows[index].start)
                intervalBuckets[label, default: 0] += 1
            }
            return TypeShape(
                metricId: metricId,
                count: rows.count,
                firstMonth: months.min(),
                lastMonth: months.max(),
                sourceClasses: sourceClasses,
                durationBuckets: durationBuckets,
                intervalBuckets: intervalBuckets,
                metadataKeyFrequencies: metadataKeyFrequencies
            )
        }
        return Report(
            sampleCount: events.count,
            typeCount: types.count,
            types: types
        )
    }

    public static func json(_ report: Report) throws -> Data {
        var types: [[String: Any]] = []
        for shape in report.types {
            var row: [String: Any] = [
                "count": shape.count,
                "durationBuckets": shape.durationBuckets,
                "intervalBuckets": shape.intervalBuckets,
                "metadataKeyFrequencies": shape.metadataKeyFrequencies,
                "metricId": shape.metricId,
                "sourceClasses": shape.sourceClasses,
            ]
            if let firstMonth = shape.firstMonth {
                row["firstMonth"] = firstMonth
            }
            if let lastMonth = shape.lastMonth {
                row["lastMonth"] = lastMonth
            }
            types.append(row)
        }
        return try JSONSerialization.data(
            withJSONObject: [
                "sampleCount": report.sampleCount,
                "typeCount": report.typeCount,
                "types": types,
            ],
            options: [.sortedKeys, .prettyPrinted]
        )
    }

    public static func events(fromNDJSON text: String) -> [Event] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return event(from: object)
        }
    }

    static func month(fromISO timestamp: String) -> String? {
        let digits = timestamp.prefix(7)
        guard digits.count == 7, digits.dropLast(3).allSatisfy(\.isNumber),
              digits.dropFirst(4).prefix(1) == "-",
              digits.dropFirst(5).allSatisfy(\.isNumber)
        else { return nil }
        return String(digits)
    }

    static func durationBucket(start: String, end: String) -> String {
        bucket(seconds: seconds(from: start, to: end) ?? 0)
    }

    static func intervalBucket(previous: String, current: String) -> String {
        bucket(seconds: seconds(from: previous, to: current) ?? 0)
    }

    static func seconds(from start: String, to end: String) -> TimeInterval? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        let startDate = formatter.date(from: start) ?? fallback.date(from: start)
        let endDate = formatter.date(from: end) ?? fallback.date(from: end)
        guard let startDate, let endDate else { return nil }
        return endDate.timeIntervalSince(startDate)
    }

    static func bucket(seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        switch value {
        case 0..<1: return "0s"
        case 1..<60: return "1-59s"
        case 60..<300: return "1-4m"
        case 300..<900: return "5-14m"
        case 900..<3600: return "15-59m"
        case 3600..<14400: return "1-3h"
        case 14400..<86400: return "4-23h"
        default: return "1d+"
        }
    }

    static func metadataKeys(
        source: SampleSourceIdentity?,
        device: SampleDevice?,
        wasUserEntered: Bool?
    ) -> [String] {
        var keys: [String] = []
        if source != nil { keys.append("source") }
        if device != nil { keys.append("device") }
        if wasUserEntered != nil { keys.append("wasUserEntered") }
        return keys
    }

    static func collectKeyNames(_ object: [String: Any]) -> [String] {
        object.keys.sorted()
    }
}

private extension SampleDevice {
    var productTypeHint: String? { model ?? name }
}
