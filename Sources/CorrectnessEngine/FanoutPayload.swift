// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import EnginePorts
import Foundation
import WireFormat

enum FanoutPayload {
    static func expectedRecordCount(
        page: SamplePage,
        extraStarts: [String] = [],
        metric: MetricID,
        scope: DestinationExportScope?
    ) -> Int {
        guard let scope else {
            return page.encodedRecordCount + extraStarts.count
        }
        var count = 0
        func include(_ start: String) {
            if allows(metric: metric, start: start, scope: scope) {
                count += 1
            }
        }
        for sample in page.samples { include(sample.start) }
        for record in page.categories { include(record.start) }
        for record in page.correlations { include(record.start) }
        for record in page.workouts { include(record.start) }
        for record in page.minds { include(record.start) }
        for record in page.electrocardiograms { include(record.start) }
        for record in page.audiograms { include(record.start) }
        for record in page.medicationDoses { include(record.start) }
        for record in page.series { include(record.parentStart) }
        count += page.tombstones.count
        for start in extraStarts { include(start) }
        return count
    }

    static func attemptURL(
        canonical: PendingBatch,
        destinationID: String,
        expectedRecords: Int,
        scope: DestinationExportScope?,
        scratchDirectory: URL
    ) throws -> URL {
        let source = URL(fileURLWithPath: canonical.payloadURL)
        guard let scope, expectedRecords != canonical.expectedRecords else {
            return source
        }
        let dest = scratchDirectory.appendingPathComponent(
            "\(destinationID)-\(canonical.id.rawValue).ndjson"
        )
        let kept = try NativeWire.project(from: source, to: dest) { line in
            keepsRecord(line, metric: canonical.metric, scope: scope)
        }
        _ = kept
        return dest
    }

    static func keepsRecord(
        _ line: Data,
        metric: MetricID,
        scope: DestinationExportScope
    ) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else {
            return false
        }
        let kind = object["kind"] as? String
        if kind == "tombstone" || kind == "canary" {
            return scope.metrics.contains(metric)
        }
        let start = (object["start"] as? String)
            ?? (object["bucketStart"] as? String)
            ?? (object["parentStart"] as? String)
        guard let start else { return false }
        return allows(metric: metric, start: start, scope: scope)
    }

    private static func allows(
        metric: MetricID,
        start: String,
        scope: DestinationExportScope
    ) -> Bool {
        guard let date = parseUTC(start) else { return false }
        return scope.allows(metric: metric, sampleStart: date)
    }

    private static func parseUTC(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: .iso8601) {
            return date
        }
        return ExportScopeGate.dayStartUTC(String(string.prefix(10)))
    }
}
