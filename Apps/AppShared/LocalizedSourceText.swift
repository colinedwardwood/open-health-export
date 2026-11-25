// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import Foundation

/// A fixed sentence from `Sources/` (its English text is its catalog key), in the
/// running language (#54, ADR-0006). Text with no catalog entry, such as a
/// destination's name the person typed, comes back unchanged.
func localized(_ sourceText: String) -> String {
    Bundle.main.localizedString(forKey: sourceText, value: sourceText, table: nil)
}
