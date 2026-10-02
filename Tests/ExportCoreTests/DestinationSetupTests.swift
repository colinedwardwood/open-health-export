// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppServices
import DestinationTrust
import MetricCatalog
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

@Test func filesAndHTTPSDestinationsAreAddableAndTheMacStaysHidden() {
    #expect(DestinationKind.addable == [.files, .mqtt, .https, .homeAssistantWebhook])
    #expect(DestinationKind.homeAssistantWebhook.caveat?.contains("doesn't create sensors") == true)
    #expect(DestinationKind.https.caveat == nil)
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

@Test func httpsChecklistChecksTheCertificateOnlyWhenEncrypted() {
    #expect(DestinationTestChecklist.https(encrypted: true).steps.map(\.step).contains(.confirmCertificate))
    #expect(!DestinationTestChecklist.https(encrypted: false).steps.map(\.step).contains(.confirmCertificate))
}

@Test func addressesAreSaidBackBeforeAnythingIsSent() {
    let good = NetworkAddressCheck.check(" https://ha.example.net:8123/api ", allowsPlainHTTP: false)
    #expect(good.isUsable && good.encrypted && good.host == "ha.example.net")
    #expect(!NetworkAddressCheck.check("http://nas.local", allowsPlainHTTP: false).isUsable)
    #expect(NetworkAddressCheck.check("http://nas.local", allowsPlainHTTP: true).isUsable)
    #expect(!NetworkAddressCheck.check("https://user:pw@host", allowsPlainHTTP: false).isUsable)
    #expect(!NetworkAddressCheck.check("ftp://host", allowsPlainHTTP: true).isUsable)
    #expect(!NetworkAddressCheck.check("not a url", allowsPlainHTTP: true).isUsable)
    #expect(!NetworkAddressCheck.check("", allowsPlainHTTP: true).isUsable)
}

@Test func theExampleAutomationNeedsOnlyTheWebhookID() {
    let yaml = HomeAssistantWebhookExample.yaml
    #expect(yaml.contains("trigger: webhook"))
    #expect(yaml.contains("PASTE-THE-SAME-WEBHOOK-ID-HERE"))
    #expect(yaml.contains("local_only: true"))
    #expect(!yaml.contains("\t"))
}

@Test func mqttChecklistFollowsEncryptionAndQoS() {
    #expect(DestinationTestChecklist.mqtt(encrypted: false, checksCertificate: false, confirmsDelivery: true)
        .steps.map(\.step) == [.connect, .publishCanary, .receiveEcho])
    #expect(DestinationTestChecklist.mqtt(encrypted: true, checksCertificate: true, confirmsDelivery: false)
        .steps.map(\.step) == [.tlsHandshake, .confirmCertificate, .connect, .publishCanary])
}

@Test func brokerAddressesUseMQTTSchemes() {
    #expect(NetworkAddressCheck.checkBroker("mqtts://ha.local:8883", allowsUnencrypted: false).isUsable)
    #expect(!NetworkAddressCheck.checkBroker("mqtt://ha.local:1883", allowsUnencrypted: false).isUsable)
    #expect(NetworkAddressCheck.checkBroker("mqtt://ha.local:1883", allowsUnencrypted: true).isUsable)
    #expect(!NetworkAddressCheck.checkBroker("https://ha.local", allowsUnencrypted: true).isUsable)
}

@Test func discoveryPreviewListsQuantityTypesByName() {
    let names = HomeAssistantDiscoveryPreview.entityNames(for: MetricCatalog.coreDaily)
    #expect(names.contains("Step count"))
    #expect(names.contains("Heart rate"))
    #expect(!names.contains("Sleep"))
    #expect(!names.contains("Workouts"))
}
