// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Watchdog

// #44: the product UI's type hierarchy and containers. Screens use these rather than
// styling text directly, so headings are always headers to VoiceOver and every
// colour comes from the system or Theme.xcassets.

/// A list section title: `.headline`, and a header to VoiceOver's rotor.
struct SectionTitle: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.headline)
            // The concrete colour: inside a List header, `.primary` is relative to the
            // header's own grey style and fails contrast (#46).
            .foregroundStyle(Color.primary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A list section footer. List footers default to the system grey, which fails the
/// contrast audit for small text; this uses the accessible secondary colour (#68).
struct SectionFooter: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text).foregroundStyle(Color.secondaryText)
    }
}

/// A destination state as glyph plus words. The glyph carries the tone; the words
/// are what VoiceOver reads.
struct StatusBadge: View {
    let state: DestinationDisplayState

    var body: some View {
        Label {
            Text(state.label)
        } icon: {
            state.toneGlyph
        }
    }
}

extension View {
    /// Secondary line under a title: timestamps, counts, where data went.
    func metadata() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondaryText)
            .monospacedDigit()
    }

    /// The inset card for something that needs the person: sits inside the list, so
    /// it scrolls with the content and can never cover the navigation title.
    func attentionCard(_ tone: StatusTone) -> some View {
        padding(.vertical, 4)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tone.color.opacity(0.14))
            )
    }
}
