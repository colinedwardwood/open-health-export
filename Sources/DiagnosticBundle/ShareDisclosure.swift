// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

/// SEC-45: sharing hands the bundle to another app, which ends this app's Data
/// Protection guarantees over those bytes. The warning is shown once and has to be
/// acknowledged, because informed consent for T-21 cannot be inferred from a tap on a
/// share button.
public enum ShareDisclosure {
    public static let copy =
        "Sharing copies this report to whichever app you choose. Once it leaves, this "
            + "app's on-device protection no longer applies to that copy. The report is "
            + "redacted: it holds no health values, hostnames, credentials or tokens, but "
            + "it does show your app, iOS and device versions and what your exports did."
}
