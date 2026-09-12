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
