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
}
