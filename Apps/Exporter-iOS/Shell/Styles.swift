// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

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

/// What a screen says when it has nothing to list yet. Not `ContentUnavailableView`,
/// which the accessibility audit reports as clipped text (#56).
struct EmptyState: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondaryText)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .accessibilityElement(children: .combine)
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
}
