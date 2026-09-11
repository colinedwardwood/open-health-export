// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// SEC-45: sharing hands the bundle to another app, which ends this app's Data
/// Protection guarantees over those bytes. The warning is shown once and has to be
/// acknowledged, because informed consent for T-21 cannot be inferred from a tap on a
/// share button.
public enum ShareDisclosure {
    public static let copy =
        "Sharing copies this bundle to whichever app you choose. Once it leaves, this "
            + "app's on-device protection no longer applies to that copy. The bundle is "
            + "redacted and holds no health values, but it does name your destinations."
}
