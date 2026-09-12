// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

/// UX-03 / UX-04: the HealthKit pre-alert screen. One in-content button, titled
/// Continue, naming the types about to be requested and that Apple does not
/// report which types were turned off.
public enum HealthAuthorizationPriming {
    public static let title = "Next, iPhone will ask for permission"
    public static let continueTitle = "Continue"
    public static let sheetFollows =
        "Apple's permission sheet is next. Turn on whatever you're comfortable with. You can change it any time in Health."
    public static let invisibility =
        "One thing worth knowing: iPhone does not tell apps what you turned off. If a type is switched off, it looks to us exactly like a type you have no data for."

    public static func typeCountCopy(_ count: Int) -> String {
        if count == 1 {
            return "We're about to ask for read access to 1 type of health data you selected."
        }
        return "We're about to ask for read access to \(count) types of health data you selected."
    }
}
