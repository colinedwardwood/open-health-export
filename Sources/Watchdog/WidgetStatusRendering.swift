// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// WidgetKit `widgetRenderingMode` mapped into ExportCore so Linux tests can lock
/// UX-41: status stays glyph+label when accented/vibrant chrome strips hue.
public enum WidgetStatusRenderingMode: String, Sendable, CaseIterable {
    case fullColor
    case accented
    case vibrant

    public var stripsHue: Bool {
        self != .fullColor
    }
}

public enum WidgetStatusChrome {
    public static func identity(
        for state: DestinationDisplayState,
        mode: WidgetStatusRenderingMode
    ) -> String {
        _ = mode.stripsHue
        return "\(state.glyph) \(state.label)"
    }
}

/// SEC-28: Lock Screen / locked-device widget chrome. No destination names, timestamps,
/// or health values — those wait until the device is unlocked.
public enum WidgetLockRedaction {
    public static let glyph = "lock.fill"
    public static let copy = "Locked"
}
