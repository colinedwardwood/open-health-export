// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import Foundation
import MetricCatalog
import Testing

@Test func firstRunWalksEveryScreenWithTheDisclosureBeforeHealth() {
    var step: OnboardingStep? = OnboardingPlan.launchStep(disclosureAcknowledged: false)
    var seen: [OnboardingStep] = []
    while let current = step {
        seen.append(current)
        step = OnboardingPlan.next(after: current, resuming: false, destinationReady: true)
    }
    #expect(seen == OnboardingStep.allCases)
    #expect(seen.firstIndex(of: .howItWorks)! < seen.firstIndex(of: .healthAccess)!)
}

@Test func skippingTheDestinationNeverReachesAnExport() {
    #expect(OnboardingPlan.next(after: .healthAccess, resuming: false, destinationReady: false) == nil)
    #expect(OnboardingPlan.next(after: .destination, resuming: false, destinationReady: false) == .howItWorks)
}

@Test func finishSetupResumesWithoutTheWelcomeOrTheDisclosure() {
    let steps = OnboardingPlan.steps(resuming: true)
    #expect(!steps.contains(.welcome))
    #expect(!steps.contains(.howItWorks))
    #expect(OnboardingPlan.next(after: .destination, resuming: true, destinationReady: true) == .healthAccess)
}

@Test func onboardingOnlyStartsBeforeTheDisclosure() {
    #expect(OnboardingPlan.launchStep(disclosureAcknowledged: false) == .welcome)
    #expect(OnboardingPlan.launchStep(disclosureAcknowledged: true) == nil)
}

@Test func firstExportCoversTheLastSevenDays() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21T12:53:20Z
    let start = OnboardingPlan.defaultScopeStart(now: now, calendar: calendar)
    #expect(start == Date(timeIntervalSince1970: 1_789_344_000)) // 2026-09-14T00:00:00Z
}

@Test func coreDailyNamesReadAsWords() {
    let names = MetricCatalog.coreDaily.map(\.displayName)
    #expect(names.contains("Step count"))
    #expect(names.contains("Heart rate"))
    #expect(names.contains("Sleep"))
    for name in names {
        #expect(!name.contains("_"), "\(name)")
        #expect(name.first?.isUppercase == true, "\(name)")
    }
    #expect(MetricCatalog.vo2Max.displayName == "VO₂ max")
}

/// #45: the first export failed on Mindful minutes because the export asked the
/// quantity-only day reader for a category type.
@Test func onlyQuantityTypesAreTotalledFromDaySamples() {
    #expect(MetricCatalog.stepCount.readsByDay)
    #expect(!MetricCatalog.mindfulSession.readsByDay)
    #expect(!MetricCatalog.sleepAnalysis.readsByDay)
    #expect(!MetricCatalog.workout.readsByDay)
}
