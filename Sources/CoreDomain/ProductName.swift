// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The user-visible product name, from the bundle that `Brand.xcconfig` configured, so
/// copy that names the app follows a rename without a code change.
public enum ProductName {
    /// Package tests and Linux tools have no app bundle; they read a neutral stand-in.
    public static let fallback = "this app"

    public static let display: String = {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = Bundle.main.object(forInfoDictionaryKey: key) as? String,
               !name.isEmpty, !name.contains("$(")
            {
                return name
            }
        }
        return fallback
    }()
}
