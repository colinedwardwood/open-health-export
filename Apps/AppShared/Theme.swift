// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Watchdog

/// UX-5 (#44): the one place a status tone becomes a colour, shared by the app and
/// the widget. Colours live in Theme.xcassets with light and dark variants, so both
/// follow the phone's appearance setting.
extension StatusTone {
    var color: Color {
        switch self {
        case .ok: Color("StatusOK")
        case .attention: Color("StatusAttention")
        case .blocked: Color("StatusBlocked")
        case .neutral: .secondaryText
        }
    }
}

extension Color {
    /// Secondary text that passes 4.5:1. The system `.secondary` blends to about
    /// 3.4:1 on white, which fails the contrast audit for small text (#46).
    static let secondaryText = Color("TextSecondary")
}

extension ShapeStyle where Self == Color {
    static var secondaryText: Color { Color.secondaryText }
}

extension DestinationDisplayState {
    /// The state's glyph, painted in its tone. Hidden from VoiceOver, since every
    /// place that shows it also shows the label.
    var toneGlyph: some View {
        Image(systemName: glyph)
            .foregroundStyle(tone.color)
            .accessibilityHidden(true)
    }
}
