// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// SEC-64: the consequence of SEC-33's device-only keychain storage, said before the
/// user types a credential rather than discovered during a restore. A migration
/// surprise is what pushes people towards weaker practices, so the cost is stated up
/// front and in plain terms.
public enum CredentialDisclosure {
    public static let copy =
        "Credentials are stored only on this iPhone and are never synced to iCloud. "
            + "A restore or a new device will not carry them over — you will enter them again."
}
