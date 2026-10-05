// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import AppServices
import EnginePorts
import Testing

@Test func manualExportIsFreeForEveryState() {
    for state in [UnlockState.sourceBuild, .locked, .unlocked, .revoked] {
        #expect(AutomationGate.allows(.manual, state: state))
        #expect(AutomationGate.allows(.widgetControl, state: state))
    }
}

@Test func automaticRunsNeedTheUnlock() {
    let automatic: [RunTrigger] = [.observerQuery, .bgAppRefresh, .bgProcessing, .shortcut, .appForeground, .launch]
    for trigger in automatic {
        #expect(!AutomationGate.allows(trigger, state: .locked), "\(trigger)")
        #expect(!AutomationGate.allows(trigger, state: .revoked), "\(trigger)")
        #expect(AutomationGate.allows(trigger, state: .unlocked), "\(trigger)")
        #expect(AutomationGate.allows(trigger, state: .sourceBuild), "\(trigger)")
    }
    // Every trigger is classified, so a new one can't slip through ungated.
    #expect(RunTrigger.allCases.count == automatic.count + 2)
}

@Test func sourceBuildsAreAlwaysUnlocked() {
    #expect(UnlockDecision.state(isStoreBuild: false, hasEntitlement: false, wasRevoked: true, lastKnown: .locked) == .sourceBuild)
}

@Test func storeBuildsFollowStoreKitAndRememberTheLastAnswerOffline() {
    #expect(UnlockDecision.state(isStoreBuild: true, hasEntitlement: true, wasRevoked: false, lastKnown: nil) == .unlocked)
    #expect(UnlockDecision.state(isStoreBuild: true, hasEntitlement: false, wasRevoked: false, lastKnown: .unlocked) == .locked)
    #expect(UnlockDecision.state(isStoreBuild: true, hasEntitlement: nil, wasRevoked: false, lastKnown: .unlocked) == .unlocked)
    #expect(UnlockDecision.state(isStoreBuild: true, hasEntitlement: nil, wasRevoked: false, lastKnown: nil) == .locked)
    #expect(UnlockDecision.state(isStoreBuild: true, hasEntitlement: true, wasRevoked: true, lastKnown: nil) == .revoked)
}

@Test func aRevokedUnlockKeepsEverythingAndSaysSo() {
    #expect(UnlockDecision.summary(.revoked).contains("unchanged"))
    #expect(!UnlockState.revoked.isUnlocked)
}
