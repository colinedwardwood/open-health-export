// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import DestinationTrust
import Testing

@Test func checklistMarksEarlierStepsPassedAsTheTestMovesOn() {
    var list = DestinationTestChecklist.localFile
    #expect(list.steps.map(\.state) == [.pending, .pending, .pending, .pending])
    list.start(.writeCanary)
    #expect(list.steps.map(\.state) == [.passed, .running, .pending, .pending])
    #expect(list.announcement == "Write a test file…")
    list.finish(failedAt: nil)
    #expect(list.passed)
    #expect(list.announcement == "Test passed.")
}

@Test func checklistNamesTheStepThatFailed() {
    var list = DestinationTestChecklist.localFile
    list.start(.readBack)
    list.finish(failedAt: .readBack)
    #expect(list.steps.map(\.state) == [.passed, .passed, .failed, .pending])
    #expect(!list.passed && list.failed)
    #expect(list.announcement == "Read it back failed.")
    list.reset()
    #expect(!list.failed)
}

@Test func everyStepHasItsOwnName() {
    let titles = DestinationTestChecklist.localFile.steps.map(\.title)
    #expect(Set(titles).count == titles.count)
}

@Test func onlyFilesIsAddableAndTheMacStaysHidden() {
    #expect(DestinationKind.addable == [.files])
    #expect(!DestinationKind.allCases.map(\.destinationID).contains("companion"))
    #expect(DestinationKind.files.destinationID == "local-file")
}

/// #47: on CI the last progress report arrived after the test passed and put the
/// last step back to running, so Save never enabled.
@Test func aLateProgressReportCannotReopenAFinishedTest() {
    var list = DestinationTestChecklist.localFile
    list.start(.readBack)
    list.finish(failedAt: nil)
    list.start(.confirmBytes)
    #expect(list.passed)
    list.reset()
    list.start(.openFolder)
    #expect(list.running)
}
