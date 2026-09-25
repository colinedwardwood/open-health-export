// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The reverse-DNS root every bundle-scoped identifier hangs from: keychain services,
/// queue labels, the logger subsystem, the widget kind and the URL scheme (#35).
///
/// It is set once, as `PRODUCT_BUNDLE_IDENTIFIER_ROOT` in `Brand.xcconfig`, and reaches
/// code through each bundle's `OHEIdentifierRoot` Info.plist key, so renaming the root
/// is a one-file change. Keychain service names in particular must never drift after
/// release: an item stored under one service is invisible under another.
public enum IdentifierRoot {
    public static let infoKey = "OHEIdentifierRoot"

    /// Package tests and Linux tools run without the key. They get a root that cannot
    /// be mistaken for a shipped one.
    public static let unconfigured = "invalid.unconfigured"

    public static let value: String = {
        guard let root = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String,
              !root.isEmpty, !root.contains("$(")
        else { return unconfigured }
        return root
    }()

    public static func qualified(_ suffix: String) -> String {
        "\(value).\(suffix)"
    }
}
