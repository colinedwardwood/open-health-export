// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CoreDomain
import Foundation

/// The first-run screens (#45), in the order a new person sees them.
public enum OnboardingStep: String, Sendable, Hashable, CaseIterable {
    case welcome
    /// What to export: Core Daily, pre-selected.
    case types
    /// Where exports go: Files, tested before it is enabled, or set up later.
    case destination
    /// How exporting works (R-63). Continuing here is the disclosure acknowledgement,
    /// so it always comes before Apple's Health sheet.
    case howItWorks
    /// The one priming screen before Apple's Health sheet (HIG, UX-03).
    case healthAccess
    /// The first export, with progress, ending on the result.
    case firstExport
}

/// Which screens to show and in what order. A person who skips the destination never
/// reaches an export that cannot run; they get a "Finish setup" row on Status, which
/// resumes here without repeating the welcome or the disclosure.
public enum OnboardingPlan {
    public static func steps(resuming: Bool) -> [OnboardingStep] {
        resuming
            ? [.types, .destination, .healthAccess, .firstExport]
            : OnboardingStep.allCases
    }

    /// The screen after `step`, or nil when onboarding is finished.
    public static func next(
        after step: OnboardingStep,
        resuming: Bool,
        destinationReady: Bool
    ) -> OnboardingStep? {
        let order = steps(resuming: resuming).filter { destinationReady || $0 != .firstExport }
        guard let index = order.firstIndex(of: step), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    /// Where the app starts: the full flow before the disclosure has been read,
    /// otherwise nothing (Status shows "Finish setup" if no destination is enabled).
    public static func launchStep(disclosureAcknowledged: Bool) -> OnboardingStep? {
        disclosureAcknowledged ? nil : .welcome
    }

    /// The first export covers the last seven days, so it has something to show.
    /// The Data tab changes it later (#50).
    public static func defaultScopeStart(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -7, to: today) ?? today
    }
}
