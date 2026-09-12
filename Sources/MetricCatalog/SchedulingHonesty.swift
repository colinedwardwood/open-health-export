// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-20: background timing is iOS's, locked phones withhold Health, and a
/// chosen-time run is a Shortcut or Control Centre control — never a promised
/// 3 a.m. schedule.
public enum SchedulingHonesty {
    public static let title = "When export runs"
    public static let body =
        "iOS decides when background export runs. Health data is withheld while this iPhone is locked. A Shortcut or Control Centre control is how you run at a time you choose."
    public static let noSchedulePromise = "Nothing here promises a send at 3 a.m."
    public static let shortcutsLine =
        "Shortcuts can run one page to the local archive after you enable it."
}
