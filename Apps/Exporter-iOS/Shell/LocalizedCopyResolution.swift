// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import CoreDomain
import SwiftUI

// #54 / ADR-0006: copy owned by Linux-buildable `Sources/` arrives as a catalog key
// plus arguments (`LocalizedCopy`) or, for fixed sentences, as its English source
// text. The app resolves both against `Apps/Localizable.xcstrings`, so the doubled
// pseudo-locale, plural variants and every future language reach them.

extension LocalizedCopy.Argument {
    fileprivate var resolved: CVarArg {
        switch self {
        case let .text(value): value
        case let .number(value): value
        case let .copy(value): value.resolved
        }
    }
}

extension LocalizedCopy {
    /// The copy in the language the app is running in. Numbers format with the
    /// current locale and a count picks its plural variant from the catalog.
    var resolved: String {
        let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: .current, arguments: arguments.map(\.resolved))
    }
}

// Labelled, because `LocalizedCopy` is string-literal expressible: an unlabelled
// initialiser would make every literal Text ambiguous with the LocalizedStringKey one.
extension Text {
    init(copy: LocalizedCopy) {
        self.init(verbatim: copy.resolved)
    }
}

extension Button where Label == Text {
    init(copy: LocalizedCopy, action: @escaping () -> Void) {
        self.init(action: action) { Text(copy: copy) }
    }
}
