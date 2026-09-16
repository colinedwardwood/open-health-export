// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Lays out the on-screen diagnostic preview so no part of the bundle can be
/// clipped away.
///
/// The preview is JSON, and JSON tokens carry no spaces: a path, an identifier or
/// a redacted value can be longer than one line with nowhere legal to wrap, and the
/// tail is then clipped rather than wrapped. Whether that happens depends on what
/// the bundle happened to contain, which is why it appeared as an accessibility
/// audit failure on one machine and not another.
public enum DiagnosticPreviewLayout {
    /// A zero-width space. It gives the layout engine somewhere to break, reads as
    /// nothing under VoiceOver, and does not change what the text says.
    public static let breakOpportunity = "\u{200B}"

    /// Inserts a break opportunity inside runs that offer none. The limit is in
    /// characters rather than points on purpose: the text still wraps wherever it
    /// needs to at any Dynamic Type size, because it now has somewhere to do it.
    public static func wrappable(_ text: String, runLimit: Int = 24) -> String {
        precondition(runLimit > 0)
        var output = ""
        output.reserveCapacity(text.count + text.count / runLimit)
        var run = 0
        for character in text {
            if character.isNewline || character.isWhitespace {
                run = 0
            } else if run >= runLimit {
                output.append(contentsOf: breakOpportunity)
                run = 0
            }
            output.append(character)
            if !character.isNewline, !character.isWhitespace {
                run += 1
            }
        }
        return output
    }

    /// Splits the preview across several text views. A bundle can hold a hundred
    /// runs, and one text view carrying all of it is both slow to lay out and prone
    /// to being clipped as a whole.
    public static func chunks(_ text: String, linesPerChunk: Int = 20) -> [String] {
        precondition(linesPerChunk > 0)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return [] }
        return stride(from: 0, to: lines.count, by: linesPerChunk).map { start in
            lines[start ..< min(start + linesPerChunk, lines.count)]
                .joined(separator: "\n")
        }
    }

    /// What the view renders: wrappable text, one line per view.
    ///
    /// A blank line is rendered as a space so it still occupies a view and the
    /// preview keeps the shape of the JSON it is showing.
    public static func displayLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map {
            let line = wrappable(String($0))
            return line.isEmpty ? " " : line
        }
    }
}
