// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// R-68: Shortcuts may run an export only after disclosure and R-25 enablement.
public enum ShortcutExportAuthorization: Sendable {
    public static func denyReason(
        disclosureAcknowledged: Bool,
        destinationEnabled: Bool
    ) -> String? {
        if !disclosureAcknowledged {
            return "Review the locked-device disclosure in the app first."
        }
        if !destinationEnabled {
            return "Enable a destination in the app first."
        }
        return nil
    }
}
