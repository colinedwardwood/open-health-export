// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import Foundation

/// User-visible copy owned by a Linux-buildable module (ADR-0006, #54).
///
/// `Sources/` cannot depend on SwiftUI or on an Xcode-compiled module catalog, so
/// copy is returned as a catalog key plus its arguments and the app resolves it
/// against `Apps/Localizable.xcstrings`. The key is the English source text in
/// printf form (`%@` for text, `%lld` for numbers), the same convention the app's
/// own literals use, so one catalog holds both. A key whose first number varies
/// by count carries plural variants in the catalog; `english` below carries the
/// `one` form so Linux tests, logs and previews read correctly without the app.
public struct LocalizedCopy: Sendable, Equatable, Hashable, ExpressibleByStringLiteral {
    public indirect enum Argument: Sendable, Equatable, Hashable {
        case text(String)
        case number(Int)
        /// Another piece of copy, localised on its own before it is substituted.
        case copy(LocalizedCopy)
    }

    /// The catalog key: English source text in printf form.
    public let key: String
    public let arguments: [Argument]
    /// The English form for exactly one, when `key` is a plural.
    private let singular: String?

    public init(_ key: String, _ arguments: Argument..., singular: String? = nil) {
        self.key = key
        self.arguments = arguments
        self.singular = singular
    }

    /// Copy whose English text is data, such as the error-class manifest. The text is
    /// the catalog key, and the catalog gate lists these keys explicitly.
    public init(verbatimKey key: String) {
        self.init(key)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// True when `key` has plural variants in the catalog, keyed on its first number.
    public var isPlural: Bool { singular != nil }

    /// The English rendering, for Linux, logs and tests. The app localises `key`.
    public var english: String {
        var template = key
        var remaining = arguments[...]
        if let singular, let position = arguments.firstIndex(where: { if case .number = $0 { true } else { false } }),
           case .number(1) = arguments[position] {
            // The singular form spells the number out, so it takes no argument.
            template = singular
            remaining.remove(at: position)
        }
        var rendered = ""
        var index = template.startIndex
        while index < template.endIndex {
            let rest = template[index...]
            if rest.hasPrefix("%@") || rest.hasPrefix("%lld"), let argument = remaining.popFirst() {
                switch argument {
                case .text(let value): rendered += value
                case .number(let value): rendered += Self.grouped(value)
                case .copy(let value): rendered += value.english
                }
                index = template.index(index, offsetBy: rest.hasPrefix("%@") ? 2 : 4)
            } else {
                rendered.append(template[index])
                index = template.index(after: index)
            }
        }
        return rendered
    }
}

extension LocalizedCopy {
    /// English digit grouping. Written out so Linux-core needs no number formatter;
    /// the app formats numbers with the current locale.
    private static func grouped(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var result = ""
        for (offset, digit) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { result.append(",") }
            result.append(digit)
        }
        return (value < 0 ? "-" : "") + String(result.reversed())
    }
}

extension LocalizedCopy: CustomStringConvertible {
    public var description: String { english }
}
