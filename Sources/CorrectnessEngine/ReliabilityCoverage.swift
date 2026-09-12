// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreTemporal
import EnginePorts
import Foundation

/// The reliability design's no-silent-loss and I5 over-cover checks.
///
/// `delivered ∪ gap ⊇ read` is counted in sample records: every sample that
/// entered the queue is still pending, present on a delivery receipt, or
/// copied onto a gap record. I5 requires the union of gap day ranges to
/// cover every evicted batch's measurement extent.
public enum ReliabilityCoverage {
    public static func holds(delivered: Int, gapped: Int, queued: Int, read: Int) -> Bool {
        delivered >= 0 && gapped >= 0 && queued >= 0 && read >= 0
            && delivered + gapped + queued >= read
    }

    public static func holds(
        deliveries: [DeliveryReceipt],
        gaps: [GapRecord],
        pending: [PendingBatch],
        read: Int
    ) -> Bool {
        holds(
            delivered: deliveries.reduce(0) { $0 + $1.accepted },
            gapped: gaps.reduce(0) { $0 + $1.expectedRecords },
            queued: pending.reduce(0) { $0 + $1.expectedRecords },
            read: read
        )
    }

    public static func holds(on tx: any StateTransaction, read: Int) throws -> Bool {
        holds(
            delivered: try tx.deliveredAccepted(),
            gapped: try tx.loadGaps().reduce(0) { $0 + $1.expectedRecords },
            queued: try tx.pendingBatches().reduce(0) { $0 + $1.expectedRecords },
            read: read
        )
    }

    /// I5: every evicted `[rangeStartDay, rangeEndDay]` is a subset of the
    /// union of recorded gap day ranges.
    public static func gapsOvercoverExtents(
        gaps: [GapRecord],
        extents: [(start: String, end: String)]
    ) -> Bool {
        let intervals = gaps.compactMap { gap -> (String, String)? in
            guard let start = gap.rangeStartDay, let end = gap.rangeEndDay else {
                return nil
            }
            return (start, end)
        }
        return extents.allSatisfy { extent in
            daysCovered(from: extent.start, to: extent.end, by: intervals)
        }
    }

    public static func gapsOvercoverEvicted(_ gaps: [GapRecord], _ evicted: [PendingBatch]) -> Bool {
        let extents = evicted.compactMap { batch -> (String, String)? in
            guard let start = batch.rangeStartDay, let end = batch.rangeEndDay else {
                return nil
            }
            return (start, end)
        }
        guard extents.count == evicted.count else { return false }
        return gapsOvercoverExtents(gaps: gaps, extents: extents)
    }
}

private func daysCovered(
    from start: String,
    to end: String,
    by intervals: [(String, String)]
) -> Bool {
    guard let days = inclusiveISODays(from: start, to: end) else { return false }
    return days.allSatisfy { day in
        intervals.contains { interval in
            interval.0 <= day && day <= interval.1
        }
    }
}

private func inclusiveISODays(from start: String, to end: String) -> [String]? {
    guard start <= end else { return nil }
    let calendar = TemporalContext.utc.calendar()
    func date(from iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }
    guard let first = date(from: start), let last = date(from: end) else { return nil }
    var days: [String] = []
    var cursor = first
    while cursor <= last {
        let parts = calendar.dateComponents([.year, .month, .day], from: cursor)
        days.append(
            DayBucket(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0).isoDay
        )
        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
        cursor = next
        if days.count > 400 { return nil }
    }
    return days
}
