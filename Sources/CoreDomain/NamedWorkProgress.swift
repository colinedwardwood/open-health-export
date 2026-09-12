// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-23: when a total is knowable, name the unit of work instead of an indeterminate spinner.
public enum NamedWorkProgress {
    public static func types(current: Int, total: Int) -> String {
        CombinedExportSummary.progress(current: current, total: total)
    }

    public static func backfill(day: Int, days: Int, type: Int, types: Int) -> String {
        "Reading day \(day) of \(days) · type \(type) of \(types)"
    }

    public static func archive(
        completedMonths: Int,
        totalMonths: Int,
        type: Int,
        types: Int
    ) -> String {
        "Archive month \(completedMonths) of \(totalMonths) · type \(type) of \(types)"
    }

    public static func reconcile(current: Int, total: Int) -> String {
        "Reconciling \(current) of \(total) types"
    }

    public static func test(current: Int, total: Int, step: String) -> String {
        "Testing \(current) of \(total) · \(step)"
    }

    public static func measure(current: Int, total: Int) -> String {
        "Measuring \(current) of \(total) types"
    }

    public static func purge(current: Int, total: Int) -> String {
        "Purging \(current) of \(total) types"
    }

    public static func reexport(current: Int, total: Int) -> String {
        "Re-exporting \(current) of \(total) evicted ranges"
    }

    public static func wipe(current: Int, total: Int) -> String {
        "Wiping \(current) of \(total) stores"
    }

    public static func notify(current: Int, total: Int) -> String {
        "Sending \(current) of \(total) notifications"
    }

    public static let requestingHealthAccess = "Requesting Health access"
    public static let verifyingLedger = "Verifying the egress ledger"
    public static let enablingDestination = "Saving the destination"
}
