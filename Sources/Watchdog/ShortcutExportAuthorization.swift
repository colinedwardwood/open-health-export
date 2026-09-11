import Foundation

/// R-68: Shortcuts may run an export only after disclosure and R-25 enablement.
public enum ShortcutExportAuthorization: Sendable {
    public static func denyReason(
        disclosureAcknowledged: Bool,
        localFileEnabled: Bool
    ) -> String? {
        if !disclosureAcknowledged {
            return "Review the locked-device disclosure in the app first."
        }
        if !localFileEnabled {
            return "Enable the local archive folder in the app first."
        }
        return nil
    }
}
