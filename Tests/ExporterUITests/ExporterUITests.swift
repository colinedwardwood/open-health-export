// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: FSL-1.1-ALv2

import UIKit
import XCTest

/// The app's URL scheme is its identifier root from Brand.xcconfig (#35).
private let appURLScheme = "com.cewdesign.exporter"

/// #39: UIKit's own raw value. The hand-written "...AccessibilityExtraExtraExtraLarge"
/// is not a content size category, so every "AX5" case used to run at the default size.
private let ax5ContentSize = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue


@MainActor
final class ExporterUITests: XCTestCase {
    /// CI runs three simulator clones on a shared runner, where every launch and
    /// transition takes several times what it does locally. These waits assert that a
    /// control exists, not how fast it arrives; the timing budgets are R-73's job.
    /// Local runs omit `CI`, so the same assertions use a shorter wait instead of
    /// burning 30s on every existence check.
    private var uiWait: TimeInterval {
        ProcessInfo.processInfo.environment["CI"] == nil ? 8 : 30
    }

    private var app: XCUIApplication!
    /// Where a screen's leading content ends, recorded before an audit. Content below
    /// it is pushed off screen at the larger sizes, which the Dynamic Type audit
    /// reports as partial; each part passes the same audit on its own (#172).
    private var auditFoldBottom: CGFloat?

    /// The default launch is the product app past first run. Cases that are about
    /// something else override the arguments and environment themselves.
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.terminate()
        app.launchEnvironment = ["OHE_RESET_SEEDED_SURFACES": "1"]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
    }

    /// #58: with no Health data and nothing typed, a reviewer reaches a finished export
    /// and its values in one tap from first run, and the same from Settings.
    func testSampleDataIsOneTapFromFirstRunAndFromSettings() throws {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_RESET_FIRST_RUN": "1",
        ]
        app.launchArguments = [
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        let trySample = app.buttons["onboarding-sample-data"]
        XCTAssertTrue(trySample.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        trySample.tap()
        func assertSampleExport() {
            XCTAssertTrue(
                identified("sample-done").firstMatch.waitForExistence(timeout: 60),
                visibleIdentifiers().joined(separator: ",")
            )
            XCTAssertTrue(identified("sample-value-stepCount").firstMatch.exists)
            XCTAssertTrue(app.staticTexts["Sample data. Not from your Apple Health."].exists)
            XCTAssertFalse(app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] 'App Review'")
            ).firstMatch.exists)
        }
        assertSampleExport()
        // The values list is longer than one screen; at the larger sizes its header is
        // pushed below the fold and reported as partial (#172), as on About.
        auditFoldBottom = app.staticTexts["sample-banner"].firstMatch.frame.maxY
        try performAccessibilityAudit("sample-data")
        auditFoldBottom = nil
        app.buttons["sample-close"].tap()

        // Then Settings, on a launch that has finished first run.
        app.terminate()
        app.launchEnvironment = ["OHE_RESET_SEEDED_SURFACES": "1"]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        let settings = app.buttons["shell-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        settings.tap()
        let sample = app.buttons["settings-sample-data"]
        for _ in 0 ..< 6 where !sample.exists { app.swipeUp() }
        sample.tap()
        assertSampleExport()
    }

    /// #45: a new person reaches a successful first export from launch, with the
    /// disclosure before Apple's Health sheet, in eight taps or fewer of our own.
    func testFirstRunReachesAFirstExport() {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_RESET_FIRST_RUN": "1",
            "OHE_SEED_LOCAL_EXPORT_FOLDER": "1",
        ]
        app.launchArguments = [
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        let started = Date()
        app.launch()
        var taps = 0
        func tap(_ identifier: String) {
            let button = app.buttons[identifier]
            XCTAssertTrue(
                button.waitForExistence(timeout: uiWait),
                "\(identifier) missing: \(visibleIdentifiers().joined(separator: ","))"
            )
            button.tap()
            taps += 1
        }
        tap("onboarding-start")
        tap("onboarding-types-continue")
        tap("onboarding-choose-files")
        XCTAssertTrue(
            app.staticTexts["first-run-disclaimer"].waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertFalse(app.buttons["health-priming-continue"].exists)
        tap("disclosure-continue")
        tap("health-priming-continue")
        allowHealthSheetIfShown()
        // The simulator's Health store is usually empty, which is the "nothing came
        // back" ending; a store with data ends on the summary. Both are a finished
        // first export, and both offer Done.
        let summary = app.staticTexts["onboarding-export-summary"]
        let empty = app.staticTexts["onboarding-nothing-came-back"]
        let deadline = Date().addingTimeInterval(90)
        while !summary.exists, !empty.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(summary.exists || empty.exists, visibleIdentifiers().joined(separator: ","))
        if empty.exists {
            XCTAssertTrue(app.buttons["onboarding-check-again"].exists)
            XCTAssertTrue(app.buttons["onboarding-choose-types"].exists)
        }
        tap("onboarding-done")
        XCTAssertTrue(app.buttons["status-export-now"].waitForExistence(timeout: uiWait))
        XCTAssertLessThanOrEqual(taps, 8)
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(started), 90)
    }

    /// Apple's sheet appears only for types whose permission is still undecided, so a
    /// simulator that already answered goes straight on.
    private func allowHealthSheetIfShown() {
        let turnOnAll = app.descendants(matching: .any)["Turn On All"]
        guard turnOnAll.waitForExistence(timeout: 10) else { return }
        turnOnAll.tap()
        let allow = app.navigationBars.buttons["Allow"].exists
            ? app.navigationBars.buttons["Allow"]
            : app.buttons["Allow"]
        if allow.waitForExistence(timeout: uiWait) {
            allow.tap()
        }
    }

    /// #47: a Files destination is added from a clean state in six taps or fewer, each
    /// test step shows its state, and Save waits for the test to pass.
    func testFilesDestinationIsAddedAfterItsTestPasses() throws {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_SEED_LOCAL_EXPORT_FOLDER": "1",
        ]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        var taps = 0
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
            element.tap()
            taps += 1
        }
        tap(app.tabBars.buttons["Destinations"])
        tap(app.buttons["destinations-add"])
        tap(app.buttons["add-files"])
        let save = app.buttons["files-save"]
        XCTAssertTrue(save.waitForExistence(timeout: uiWait))
        XCTAssertFalse(save.isEnabled)
        tap(app.buttons["files-choose-folder"])
        // Enabling asks Apple Health for the new destination's types; on a fresh
        // simulator (CI) the sheet appears and must be answered.
        allowHealthSheetIfShown()
        let lastStep = identified("test-step-confirmBytes")
        XCTAssertTrue(lastStep.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(
            NSPredicate(format: "isEnabled == true").evaluate(with: save)
                || save.waitForEnabled(timeout: 30),
            "Save never enabled: \(lastStep.value ?? "")"
        )
        XCTAssertEqual(lastStep.value as? String, "Passed")
        try performAccessibilityAudit("files-setup")
        tap(save)
        XCTAssertTrue(app.buttons["destinations-row-local-file"].waitForExistence(timeout: uiWait))
        XCTAssertLessThanOrEqual(taps, 6)
    }

    /// #59: a folder in iCloud Drive shows a warning and is not used, tested or saved
    /// until the person acknowledges it.
    func testICloudFolderWarnsAndNeedsAcknowledgement() throws {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_SEED_ICLOUD_FOLDER": "1",
        ]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        func tap(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
            element.tap()
        }
        tap(app.tabBars.buttons["Destinations"])
        tap(app.buttons["destinations-add"])
        tap(app.buttons["add-files"])
        tap(app.buttons["files-choose-folder"])
        XCTAssertTrue(identified("icloud-warning").waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        // Nothing was tested or saved while the warning is open.
        XCTAssertFalse(app.buttons["files-save"].isEnabled)
        XCTAssertFalse(identified("test-step-openFolder").exists)
        // The two choices sit under the warning, so the larger Dynamic Type sizes push
        // them below the fold and the audit reports them as partial, as it does for
        // the Status rows under their summary (statusRowsBelowFold).
        auditFoldBottom = identified("icloud-warning").firstMatch.frame.maxY
        try performAccessibilityAudit("files-icloud-warning")
        auditFoldBottom = nil
        tap(app.buttons["icloud-choose-another"])
        XCTAssertFalse(identified("icloud-warning").exists)
        tap(app.buttons["files-choose-folder"])
        tap(app.buttons["icloud-acknowledge"])
        allowHealthSheetIfShown()
        XCTAssertTrue(identified("test-step-confirmBytes").waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertFalse(identified("icloud-warning").exists)
    }

    /// #68: without the unlock, Status says exports run on Export now and Settings
    /// offers Buy and Restore; unlocked shows neither; a refund keeps everything.
    func testUnlockStatesAreShownWhereTheyMatter() throws {
        func launch(_ state: String) {
            app.terminate()
            app.launchEnvironment = [
                "OHE_RESET_SEEDED_SURFACES": "1",
                "OHE_SEED_DESTINATION_STATUS": "success",
                "OHE_UNLOCK_STATE": state,
            ]
            app.launchArguments = [
                "-ohe.disclosureAcknowledged", "true",
                "-ohe.advisoryEnabled", "false",
                "-ohe.appPrivacyGateEnabled", "false",
            ]
            app.launch()
        }
        launch("locked")
        let note = app.buttons["status-unlock-note"]
        for _ in 0 ..< 3 where !note.exists { app.swipeUp() }
        XCTAssertTrue(note.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        note.tap()
        XCTAssertTrue(app.buttons["unlock-buy"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(app.buttons["unlock-restore"].exists)
        auditFoldBottom = identified("unlock-summary").firstMatch.frame.maxY
        try performAccessibilityAudit("unlock-settings")
        auditFoldBottom = nil

        launch("unlocked")
        XCTAssertTrue(app.buttons["status-export-now"].waitForExistence(timeout: uiWait))
        XCTAssertFalse(app.buttons["status-unlock-note"].exists)
        app.buttons["shell-settings"].firstMatch.tap()
        XCTAssertTrue(identified("unlock-summary").waitForExistence(timeout: uiWait))
        XCTAssertFalse(app.buttons["unlock-buy"].exists)

        launch("revoked")
        app.buttons["shell-settings"].firstMatch.tap()
        let summary = identified("unlock-summary")
        XCTAssertTrue(summary.waitForExistence(timeout: uiWait))
        XCTAssertTrue(app.buttons["unlock-restore"].exists)
    }

    /// Backfill UI: Settings leads to the history screen, a range can be chosen, and
    /// starting with nowhere to send says so instead of doing nothing.
    func testBackfillScreenChoosesARangeAndReportsTheResult() throws {
        app.terminate()
        app.launchEnvironment = ["OHE_RESET_SEEDED_SURFACES": "1"]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        let settings = app.buttons["shell-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        settings.tap()
        let entry = identified("settings-backfill").firstMatch
        for _ in 0 ..< 6 where !entry.exists { app.swipeUp() }
        entry.tap()
        let range = identified("backfill-range-days30").firstMatch
        XCTAssertTrue(range.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(identified("backfill-mode-raw").firstMatch.exists)
        let start = app.buttons["backfill-start"]
        XCTAssertTrue(start.exists)
        start.tap()
        XCTAssertTrue(
            identified("backfill-result").firstMatch.waitForExistence(timeout: 30)
                || identified("backfill-error").firstMatch.exists,
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertTrue(app.buttons["backfill-start"].waitForExistence(timeout: uiWait))
    }

    /// #49: the MQTT path lists the Home Assistant entities discovery will create,
    /// shows QoS once, and a broker that refuses the connection fails at Connect. A
    /// real broker is exercised by the container contracts and by
    /// OHE_UI_MQTT_BROKER when a local Mosquitto is available.
    func testMQTTShowsTheEntitiesItWillCreateAndNamesTheFailedStep() throws {
        app.terminate()
        app.launchEnvironment = ["OHE_RESET_SEEDED_SURFACES": "1"]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        app.tabBars.buttons["Destinations"].tap()
        let add = app.buttons["destinations-add"]
        XCTAssertTrue(add.waitForExistence(timeout: uiWait))
        add.tap()
        let mqtt = app.buttons["add-mqtt"]
        XCTAssertTrue(mqtt.waitForExistence(timeout: uiWait))
        mqtt.tap()
        let broker = ProcessInfo.processInfo.environment["OHE_UI_MQTT_BROKER"]
        type(broker ?? "mqtt://127.0.0.1:1", into: app.textFields["network-address"])
        dismissKeyboard()
        let plain = app.switches["network-plain-http"]
        XCTAssertTrue(plain.waitForExistence(timeout: uiWait))
        if plain.value as? String != "1" { plain.switches.firstMatch.tap() }
        XCTAssertEqual(app.segmentedControls.count, 1, "QoS should appear once")
        let test = app.buttons["network-test"]
        XCTAssertTrue(test.waitForEnabled(timeout: uiWait))
        test.tap()
        if broker != nil {
            let card = identified("network-confirm-card")
            for _ in 0 ..< 8 where !card.exists { app.swipeUp() }
            XCTAssertTrue(card.waitForExistence(timeout: 60), visibleIdentifiers().joined(separator: ","))
            let save = app.buttons["network-save"]
            XCTAssertTrue(save.waitForEnabled(timeout: uiWait))
            save.tap()
            XCTAssertTrue(app.buttons["destinations-row-mqtt"].waitForExistence(timeout: uiWait))
            return
        }
        let step = identified("test-step-connect")
        for _ in 0 ..< 8 where !step.exists { app.swipeUp() }
        XCTAssertTrue(step.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        expectation(for: NSPredicate(format: "value == %@", "Failed"), evaluatedWith: step)
        waitForExpectations(timeout: 60)
        let error = identified("test-error")
        for _ in 0 ..< 4 where !error.exists { app.swipeUp() }
        XCTAssertTrue(error.waitForExistence(timeout: uiWait))
    }

    /// #48: the webhook's caveat and example automation come before configuration,
    /// the address is said back, and a server that can't be found fails at its step.
    func testHomeAssistantWebhookWarnsFirstAndNamesTheFailedStep() throws {
        app.terminate()
        app.launchEnvironment = ["OHE_RESET_SEEDED_SURFACES": "1"]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        app.tabBars.buttons["Destinations"].tap()
        let add = app.buttons["destinations-add"]
        XCTAssertTrue(add.waitForExistence(timeout: uiWait))
        add.tap()
        let webhook = app.buttons["add-homeAssistantWebhook"]
        XCTAssertTrue(webhook.waitForExistence(timeout: uiWait))
        webhook.tap()
        XCTAssertTrue(identified("network-caveat").waitForExistence(timeout: uiWait))
        XCTAssertTrue(identified("network-example-yaml").exists)
        let test = app.buttons["network-test"]
        XCTAssertFalse(test.isEnabled)
        let address = app.textFields["network-address"]
        type("https://ohe-ui-test.invalid", into: address)
        XCTAssertTrue(identified("network-address-check").waitForExistence(timeout: uiWait))
        let secret = app.secureTextFields["network-secret"]
        secret.tap()
        secret.typeText("ui-test-webhook")
        dismissKeyboard()
        XCTAssertTrue(test.waitForEnabled(timeout: uiWait))
        test.tap()
        // The test steps sit below the example automation.
        let step = identified("test-step-resolveHost")
        for _ in 0 ..< 6 where !step.exists {
            app.swipeUp()
        }
        XCTAssertTrue(step.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        let failed = NSPredicate(format: "value == %@", "Failed")
        expectation(for: failed, evaluatedWith: step)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(identified("test-error").exists)
        XCTAssertTrue(app.buttons["test-again"].exists)
    }

    /// OTLP: the collector is a choice in Add destination, plain HTTP is refused until
    /// opted into, the address is said back, and a collector that can't be reached
    /// fails at the test step with Save withheld.
    func testOTLPCollectorIsSelectableAndAnUnreachableOneFailsTheTest() throws {
        app.terminate()
        app.launchEnvironment = ["OHE_RESET_SEEDED_SURFACES": "1"]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        app.tabBars.buttons["Destinations"].tap()
        let add = app.buttons["destinations-add"]
        XCTAssertTrue(add.waitForExistence(timeout: uiWait))
        add.tap()
        let otlp = app.buttons["add-otlp"]
        XCTAssertTrue(otlp.waitForExistence(timeout: uiWait))
        otlp.tap()
        XCTAssertTrue(identified("otlp-explainer").waitForExistence(timeout: uiWait))
        let test = app.buttons["otlp-test"]
        XCTAssertFalse(test.isEnabled)
        let address = app.textFields["otlp-address"]
        type("http://ohe-ui-test.invalid:4318/v1/traces", into: address)
        XCTAssertTrue(identified("otlp-address-check").waitForExistence(timeout: uiWait))
        XCTAssertFalse(test.isEnabled, "plain HTTP needs the explicit opt-in")
        dismissKeyboard()
        let plain = app.switches["otlp-plain-http"]
        XCTAssertTrue(plain.waitForExistence(timeout: uiWait))
        if plain.value as? String != "1" { plain.switches.firstMatch.tap() }
        let token = app.secureTextFields["otlp-token"]
        token.tap()
        token.typeText("ui-test-token")
        dismissKeyboard()
        XCTAssertTrue(test.waitForEnabled(timeout: uiWait))
        test.tap()
        let step = identified("test-step-sendCanary")
        for _ in 0 ..< 6 where !step.exists {
            app.swipeUp()
        }
        XCTAssertTrue(step.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        expectation(for: NSPredicate(format: "value == %@", "Failed"), evaluatedWith: step)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(identified("test-error").exists)
        XCTAssertFalse(app.buttons["otlp-save"].exists)
    }

    /// #52: the privacy policy is one tap from Settings, About links this build's
    /// source, and Delete everything confirms and then starts first run again.
    func testSettingsLinksTheLegalPagesAndDeleteEverythingStartsOver() throws {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_SEED_DESTINATION_STATUS": "success",
        ]
        app.launchArguments = [
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launchEnvironment["OHE_RESET_FIRST_RUN"] = "1"
        app.launch()
        // Through first run quickly with Set up later, so Delete everything has
        // something to reset.
        for id in ["onboarding-start", "onboarding-types-continue", "onboarding-setup-later", "disclosure-continue"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: uiWait), "\(id): \(visibleIdentifiers().joined(separator: ","))")
            button.tap()
        }
        let healthContinue = app.buttons["health-priming-continue"]
        if healthContinue.waitForExistence(timeout: uiWait) {
            healthContinue.tap()
            allowHealthSheetIfShown()
        }
        let settings = app.buttons["shell-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        settings.tap()
        let privacy = identified("settings-privacy-policy").firstMatch
        for _ in 0 ..< 4 where !privacy.exists { app.swipeUp() }
        XCTAssertTrue(privacy.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        let about = app.buttons["settings-about"]
        for _ in 0 ..< 4 where !about.exists { app.swipeUp() }
        about.tap()
        let source = identified("about-source").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: uiWait))
        // Text below the first line is pushed off screen at the larger sizes (#172).
        auditFoldBottom = identified("about-copyright").firstMatch.frame.maxY
        try performAccessibilityAudit("about")
        auditFoldBottom = nil
        app.navigationBars.buttons.firstMatch.tap()

        let delete = app.buttons["settings-delete-everything"]
        for _ in 0 ..< 4 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        let confirm = app.buttons["settings-delete-confirm"].firstMatch.exists
            ? app.buttons["settings-delete-confirm"].firstMatch : app.buttons["Delete everything"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        confirm.tap()
        XCTAssertTrue(app.buttons["onboarding-start"].waitForExistence(timeout: uiWait))
    }

    /// #51: History opens on problems; with none, it says how many runs delivered,
    /// and All shows each run with its detail in words.
    func testHistoryShowsProblemsFirstAndRunDetail() throws {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_SEED_LOCAL_EXPORT_FOLDER": "1",
        ]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        addFilesDestination()
        app.tabBars.buttons["Status"].tap()
        let export = app.buttons["status-export-now"]
        XCTAssertTrue(export.waitForExistence(timeout: uiWait))
        export.tap()
        XCTAssertTrue(export.waitForEnabled(timeout: 90))

        app.tabBars.buttons["History"].tap()
        let empty = identified("history-empty")
        XCTAssertTrue(empty.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(empty.label.contains("runs delivered") || empty.label.contains("run delivered"), empty.label)
        XCTAssertFalse(empty.label.contains("%"), "an unresolved plural reads as \(empty.label)")
        app.segmentedControls.buttons["All"].tap()
        let row = app.buttons["history-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: uiWait))
        row.tap()
        let result = identified("run-result").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: uiWait))
        // Detail rows below the result are pushed off screen at the larger sizes (#172).
        auditFoldBottom = result.frame.maxY
        try performAccessibilityAudit("run-detail")
        auditFoldBottom = nil
    }

    /// #50: a sensitive type is turned on only after its own confirmation, and
    /// changing a destination's types offers Save until it is saved.
    func testDataAsksBeforeASensitiveTypeAndSaves() throws {
        launchDataWithArchive()
        let dataSave = try changeDataSelection()
        dataSave.tap()
        allowHealthSheetIfShown()
        XCTAssertTrue(dataSave.waitForNonExistence(timeout: uiWait), "Save stayed after saving")
        XCTAssertFalse(identified("data-save-error").exists)
    }

    /// A save that fails says so in the five-part error's words, keeps Save on offer
    /// and shows no raw error text. `OHE_FAIL_DATA_SAVE` makes the save throw.
    func testDataSaveFailureIsShownAndKeepsSave() throws {
        launchDataWithArchive(environment: ["OHE_FAIL_DATA_SAVE": "1"])
        let dataSave = try changeDataSelection()
        dataSave.tap()
        let error = identified("data-save-error")
        XCTAssertTrue(error.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertFalse(error.label.isEmpty)
        XCTAssertFalse(error.label.contains("InjectedFailure"), error.label)
        XCTAssertTrue(app.buttons["data-save"].exists, "Save must stay on offer after a failed save")
    }

    /// The same failure through the doubled pseudo-locale: its copy comes from
    /// `Sources/`, so it is localised too.
    func testDataSaveFailureCopyIsPseudoLocalised() throws {
        launchDataWithArchive(arguments: Self.pseudoLocaleArguments, environment: ["OHE_FAIL_DATA_SAVE": "1"])
        try changeDataSelection().tap()
        let error = identified("data-save-error")
        XCTAssertTrue(error.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(Self.isDoubled(error.label), "save error: \(error.label)")
    }

    /// The Data screen's own copy, with a destination and its types listed, in the
    /// doubled pseudo-locale. Not audited: UIKit list headers are reported as
    /// partially unsupported Dynamic Type once doubled, which says nothing about the copy.
    func testDataWithADestinationInPseudoLocale() throws {
        launchDataWithArchive(arguments: Self.pseudoLocaleArguments)
        let coreDaily = app.buttons["data-core-daily"]
        XCTAssertTrue(Self.isDoubled(coreDaily.label), "Core Daily: \(coreDaily.label)")
    }

    func testSettingsInPseudoLocale() throws {
        launchProduct(arguments: Self.pseudoLocaleArguments)
        openSettings()
        let about = app.buttons["settings-about"]
        for _ in 0 ..< 4 where !about.exists { app.swipeUp() }
        XCTAssertTrue(about.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        // Not audited: UIKit list headers are reported as partially unsupported Dynamic
        // Type once doubled, which says nothing about the copy.
        XCTAssertTrue(Self.isDoubled(about.label), "About: \(about.label)")
        let notices = app.switches["settings-security-notices"]
        for _ in 0 ..< 4 where !notices.exists { app.swipeDown() }
        XCTAssertTrue(Self.isDoubled(notices.label), "Security notices: \(notices.label)")
    }

    /// Launches past first run with the seeded archive folder added, then opens Data.
    private func launchDataWithArchive(arguments: [String] = [], environment: [String: String] = [:]) {
        launchProduct(
            arguments: arguments,
            environment: ["OHE_SEED_LOCAL_EXPORT_FOLDER": "1"].merging(environment) { _, new in new }
        )
        addFilesDestination()
        openTab("data")
        XCTAssertTrue(app.buttons["data-core-daily"].waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
    }

    /// Turns on a sensitive type through its confirmation and returns the Save button.
    private func changeDataSelection() throws -> XCUIElement {
        XCTAssertFalse(app.buttons["data-save"].exists)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: uiWait))
        search.tap()
        search.typeText("glucose\n")
        let glucose = identified("data-type-bloodGlucose")
        XCTAssertTrue(glucose.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        // Saved choices outlive a launch, so an earlier case may have left glucose on.
        // Turning it off needs no confirmation and is a change all the same.
        let wasOn = glucose.value as? String == "1"
        if glucose.switches.firstMatch.exists { glucose.switches.firstMatch.tap() } else { glucose.tap() }
        if !wasOn {
            // The label doubles in the pseudo-locale, where the confirm button is the
            // one that is not Cancel.
            let confirm = app.alerts.buttons.matching(NSPredicate(format: "NOT label BEGINSWITH 'Cancel'")).firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: uiWait))
            confirm.tap()
        }
        XCTAssertEqual(glucose.value as? String, wasOn ? "0" : "1")
        // An active search hides the navigation bar and its Save; close it first.
        let cancelSearch = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cancel'")).firstMatch
        if cancelSearch.exists { cancelSearch.tap() }
        let dataSave = app.buttons["data-save"]
        for _ in 0 ..< 3 where !dataSave.exists { app.swipeDown() }
        XCTAssertTrue(dataSave.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        return dataSave
    }

    /// #46: an overdue destination is named in the headline, its row shows the
    /// widget's words, and the one action opens it. Identifiers, not copy.
    func testStatusNamesTheOverdueDestinationAndOpensIt() throws {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_SEED_DESTINATION_STATUS": "overdue",
        ]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["status-headline"].waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        let check = app.buttons["status-check"]
        XCTAssertTrue(check.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(app.buttons["status-export-now"].exists)
        auditFoldBottom = check.frame.maxY
        try performAccessibilityAudit("status")
        auditFoldBottom = nil
        check.tap()
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: uiWait))
        XCTAssertFalse(app.staticTexts["status-headline"].exists)
    }

    /// #63: with Background App Refresh off (injected), Status says why exports only run
    /// when the app is open, whatever the destinations look like.
    func testStatusExplainsWhenBackgroundRefreshIsOff() {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_SEED_BACKGROUND_REFRESH": "denied",
        ]
        app.launch()
        XCTAssertTrue(
            app.otherElements["status-notice-background-refresh"].waitForExistence(timeout: uiWait)
                || app.staticTexts["Background App Refresh is not available"].waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
    }

    /// QA-17: a held type shows on Status with its cause; sending again asks first, and
    /// the decision removes the buttons.
    func testStatusShowsAHeldTypeAndConfirmsBeforeSendingAgain() throws {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_SEED_ANCHOR_HOLD": "cursorLost",
        ]
        app.launch()
        let notice = app.descendants(matching: .any)["status-notice-anchor-hold-stepCount"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(notice.label.contains("Export paused for"), notice.label)
        XCTAssertTrue(notice.label.contains("lost track"), notice.label)
        // The choice that sends history twice never skips its confirmation.
        app.buttons["status-anchor-reexport-stepCount"].tap()
        XCTAssertTrue(app.buttons["status-anchor-confirm"].waitForExistence(timeout: uiWait))
        app.buttons["status-anchor-confirm"].firstMatch.tap()
        // The decision is recorded; the buttons go and the notice says what happens next.
        XCTAssertTrue(
            app.buttons["status-anchor-stop-stepCount"].waitForNonExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertTrue(notice.label.contains("next export"), notice.label)
        auditFoldBottom = identified("status-detail").frame.maxY
        try performAccessibilityAudit("status-anchor-hold")
        auditFoldBottom = nil
    }

    /// #43: the product app routes a cold-launch link through AppModel.
    func testProductShellColdLaunchLinkOpensTheDestinationError() {
        app.terminate()
        app.launchEnvironment = [
            "OHE_OPEN_URL": "\(appURLScheme)://error?destination=home-assistant&archetype=hostUnresolvable",
        ]
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["shell-error-title"].waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertFalse(app.buttons["disclosure-continue"].exists)
    }


    // MARK: Deep links

    /// A widget tap opens that destination's detail, past first run, with nothing in
    /// between.
    func testWidgetURLOpensTheDestinationDetail() {
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
            "OHE_SEED_DESTINATION_STATUS": "success",
            "OHE_OPEN_URL": "\(appURLScheme)://status?destination=home-assistant",
        ]
        app.launch()
        XCTAssertTrue(
            identified("detail-state").waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertFalse(app.buttons["onboarding-start"].exists)
    }

    /// A failing destination's row on Status is one tap from its detail.
    func testStatusRowOpensTheDestinationDetailInOneTap() {
        launchStatus(seeding: "failed")
        let row = identified("status-row-home-assistant").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        row.tap()
        XCTAssertTrue(
            identified("detail-state").waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
    }

    // MARK: Privacy lock

    /// SEC-29: failed owner authentication covers the entire UI. The production
    /// gate is optional and remains off in the common/default launch.
    func testOptionalPrivacyGateFailsClosedAndUsesInjectedAuthenticator() throws {
        launchProduct(arguments: ["-ohe.appPrivacyGateEnabled", "true"], environment: [
            "OHE_TEST_USER_PRESENCE": "deny",
        ])
        XCTAssertTrue(app.buttons["privacy-gate-unlock"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(identified("privacy-gate").exists)
        XCTAssertEqual(
            app.staticTexts["privacy-gate-locked-title"].label,
            "Keep Metrics is locked"
        )
        XCTAssertTrue(
            app.staticTexts["privacy-gate-background-scope"].label.contains("Background exports")
        )
        XCTAssertFalse(contentIsReachable)
        try performAccessibilityAudit("privacy-gate-locked")

        app.buttons["privacy-gate-unlock"].tap()
        XCTAssertTrue(app.staticTexts["privacy-gate-failure"].waitForExistence(timeout: uiWait))
        XCTAssertFalse(contentIsReachable)
        try performAccessibilityAudit("privacy-gate-authentication-failed")
    }

    /// SEC-29: leaving the foreground immediately relocks presentation. The
    /// adapter's second result is denied so activation cannot silently reopen it.
    func testPrivacyGateRelocksAfterLeavingForeground() {
        launchProduct(arguments: ["-ohe.appPrivacyGateEnabled", "true"], environment: [
            "OHE_TEST_USER_PRESENCE": "allow-then-deny",
        ])
        XCTAssertTrue(app.buttons["status-export-now"].waitForExistence(timeout: uiWait))
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(app.buttons["privacy-gate-unlock"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(identified("privacy-gate").exists)
        XCTAssertEqual(
            app.staticTexts["privacy-gate-locked-title"].label,
            "Keep Metrics is locked"
        )
        XCTAssertFalse(contentIsReachable)
    }

    // MARK: Settings

    func testDiagnosticsListsTheBuildAndAsksBeforeSharing() throws {
        launchProduct()
        openSettings()
        let diagnostics = app.buttons["settings-diagnostics"]
        for _ in 0 ..< 4 where !diagnostics.exists { app.swipeUp() }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        diagnostics.tap()
        let build = identified("diagnostics-build").firstMatch
        XCTAssertTrue(build.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        // A lazy list: on a simulator with run history the launch section starts below the fold.
        let launch = identified("diagnostics-launch").firstMatch
        for _ in 0 ..< 4 where !launch.exists { app.swipeUp() }
        XCTAssertTrue(launch.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        try performAccessibilityAudit("diagnostics")
        let share = app.buttons["diagnostics-share"]
        for _ in 0 ..< 4 where !share.isHittable { app.swipeUp() }
        share.tap()
        // The disclosure is acknowledged before anything leaves the app.
        XCTAssertTrue(app.buttons["diagnostics-share-confirm"].waitForExistence(timeout: uiWait))
    }

    func testAcknowledgementsRenderTheGeneratedNotice() {
        launchProduct()
        openSettings()
        let about = app.buttons["settings-about"]
        for _ in 0 ..< 4 where !about.exists { app.swipeUp() }
        about.tap()
        let link = identified("about-acknowledgements").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        link.tap()
        let body = identified("acknowledgements-body").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(body.label.contains("no third-party Swift packages"), body.label)
        XCTAssertTrue(body.label.contains("sqlite3"), body.label)
        XCTAssertTrue(body.label.contains("zlib"), body.label)
    }

    // MARK: Accessibility audits of the product screens

    func testOnboardingPassesAccessibilityAudit() throws {
        launchProduct(arguments: ["-ohe.disclosureAcknowledged", "false"])
        XCTAssertTrue(app.buttons["onboarding-start"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("onboarding")
    }

    func testStatusStatesPassAccessibilityAudit() throws {
        for scenario in ["success", "stale", "failed", "changed"] {
            launchStatus(seeding: scenario)
            XCTAssertTrue(
                identified("status-headline").waitForExistence(timeout: uiWait),
                visibleIdentifiers().joined(separator: ",")
            )
            // Rows below the summary pass this audit on their own; at the larger sizes
            // the summary pushes them off screen and they are reported as partial (#172).
            auditFoldBottom = identified("status-detail").frame.maxY
            try performAccessibilityAudit("status-\(scenario)")
            auditFoldBottom = nil
        }
    }

    func testEveryDestinationDisplayStatePassesAccessibilityAudit() throws {
        launchStatus(seeding: "all-states")
        XCTAssertTrue(
            identified("status-headline").waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        auditFoldBottom = identified("status-detail").frame.maxY
        try performAccessibilityAudit("status-all-states")
        auditFoldBottom = nil
    }

    func testDataTabPassesAccessibilityAudit() throws {
        launchProduct(environment: ["OHE_SEED_LOCAL_EXPORT_FOLDER": "1"])
        addFilesDestination()
        openTab("data")
        XCTAssertTrue(app.buttons["data-core-daily"].waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        try performAccessibilityAudit("data")

        // Nothing to choose types for yet.
        launchProduct()
        openTab("data")
        XCTAssertTrue(identified("data-empty").waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        try performAccessibilityAudit("data-empty")
    }

    func testDestinationsTabPassesAccessibilityAudit() throws {
        launchProduct()
        openTab("destinations")
        XCTAssertTrue(app.buttons["destinations-add"].waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        try performAccessibilityAudit("destinations")
    }

    func testHistoryTabPassesAccessibilityAudit() throws {
        launchProduct()
        openTab("history")
        XCTAssertTrue(identified("history-filter").waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        try performAccessibilityAudit("history")
    }

    // MARK: Dynamic Type, dark, bold, localization and layout direction

    /// #39 canary: the AX5 cases mean nothing unless the size is actually applied. The
    /// headline wraps onto several more lines at AX5 than at the default size.
    func testAX5ContentSizeIsActuallyApplied() {
        launchStatus(seeding: "success")
        let headline = identified("status-headline").firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: uiWait))
        let defaultHeight = headline.frame.height
        launchStatus(seeding: "success", arguments: ["-UIPreferredContentSizeCategoryName", ax5ContentSize])
        XCTAssertTrue(headline.waitForExistence(timeout: uiWait))
        XCTAssertGreaterThanOrEqual(
            headline.frame.height,
            defaultHeight * 2,
            "AX5 \(headline.frame.height)pt vs default \(defaultHeight)pt"
        )
    }

    func testStatusAtAX5PassesAccessibilityAudit() throws {
        launchStatus(seeding: "success", arguments: ["-UIPreferredContentSizeCategoryName", ax5ContentSize])
        XCTAssertTrue(identified("status-headline").waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("ax5-status")
    }

    /// Dark, bold, and AX5 at once is the heaviest state the suite audits, and
    /// auditing three screens in one process put the third one past the audit's
    /// own deadline. One screen per case keeps every audit and makes a timeout name
    /// the screen it happened on.
    private func launchDarkBoldAX5(seeding scenario: String = "success") {
        launchStatus(
            seeding: scenario,
            arguments: ["-UIPreferredContentSizeCategoryName", ax5ContentSize],
            environment: ["OHE_ACCESSIBILITY_MATRIX": "combined"]
        )
        XCTAssertTrue(identified("status-headline").waitForExistence(timeout: uiWait))
    }

    func testDarkBoldAX5StatusPassesAudit() throws {
        launchDarkBoldAX5()
        try performAccessibilityAudit("dark-bold-ax5-status")
    }

    func testDarkBoldAX5DataPassesAudit() throws {
        launchDarkBoldAX5()
        openTab("data")
        XCTAssertTrue(identified("data-empty").waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        try performAccessibilityAudit("dark-bold-ax5-data")
    }

    func testDarkBoldAX5DestinationsPassAudit() throws {
        launchDarkBoldAX5()
        openTab("destinations")
        XCTAssertTrue(app.buttons["destinations-add"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("dark-bold-ax5-destinations")
    }

    /// QA-27 exercises structure and accessibility under localization expansion and
    /// mirrored layout. It intentionally avoids pixel snapshots: identifiers and
    /// accessibility audits stay stable across SDK font and rasterization changes while
    /// still catching clipped, unreachable, unlabeled and incorrectly ordered UI.
    private static let pseudoLocaleArguments = ["-NSDoubleLocalizedStrings", "YES"]
    private static let rtlArguments = [
        "-AppleLanguages", "(ar)",
        "-NSForceRightToLeftWritingDirection", "YES",
    ]

    private func auditLocalizedStatusAndData(_ arguments: [String], _ configuration: String) throws {
        launchStatus(seeding: "success", arguments: arguments)
        XCTAssertTrue(identified("status-headline").waitForExistence(timeout: uiWait))
        // The summary's copy now goes through the catalog, so the doubled pseudo-locale
        // makes it taller and pushes the rows below the fold (#172), as at large sizes.
        auditFoldBottom = identified("status-detail").frame.maxY
        try performAccessibilityAudit("\(configuration)-status")
        auditFoldBottom = nil
        openTab("data")
        XCTAssertTrue(identified("data-empty").waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        try performAccessibilityAudit("\(configuration)-data")
    }

    private func auditLocalizedDestinationsAndHistory(_ arguments: [String], _ configuration: String) throws {
        launchProduct(arguments: arguments)
        openTab("destinations")
        XCTAssertTrue(app.buttons["destinations-add"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("\(configuration)-destinations")
        openTab("history")
        XCTAssertTrue(identified("history-filter").waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("\(configuration)-history")
    }

    func testStatusAndDataInPseudoLocale() throws {
        try auditLocalizedStatusAndData(Self.pseudoLocaleArguments, "pseudo")
    }

    func testDestinationsAndHistoryInPseudoLocale() throws {
        try auditLocalizedDestinationsAndHistory(Self.pseudoLocaleArguments, "pseudo")
    }

    /// #54: copy that `Sources/` produces reaches the catalog, so the doubled
    /// pseudo-locale doubles it too. Before, these screens showed it unchanged.
    func testStatusCopyFromSourcesIsPseudoLocalised() throws {
        launchStatus(seeding: "overdue", arguments: Self.pseudoLocaleArguments)
        let headline = identified("status-headline")
        XCTAssertTrue(headline.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(Self.isDoubled(headline.label), "headline: \(headline.label)")
        let detail = identified("status-detail")
        XCTAssertTrue(detail.exists)
        XCTAssertTrue(Self.isDoubled(detail.label), "detail: \(detail.label)")
    }

    func testDestinationRowCopyFromSourcesIsPseudoLocalised() throws {
        launchStatus(seeding: "overdue", arguments: Self.pseudoLocaleArguments)
        openTab("destinations")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'destinations-row-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(Self.isDoubled(row.label), "destination row: \(row.label)")
    }

    func testHistoryCopyFromSourcesIsPseudoLocalised() throws {
        launchProduct(arguments: Self.pseudoLocaleArguments)
        openTab("history")
        let empty = identified("history-empty")
        XCTAssertTrue(empty.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        // A shard that already ran exports shows the plural "No problems ... N runs
        // delivered" line instead of the empty state. Xcode's pseudo-locale renders a
        // plural variation as "#@value@ %#@value@", which is its mark that the string
        // went through the catalog; the singular empty copy is doubled text.
        XCTAssertTrue(
            Self.isDoubled(empty.label) || empty.label.contains("#@value@"),
            "history: \(empty.label)"
        )
    }

    func testSettingsAboutCopyFromSourcesIsPseudoLocalised() throws {
        launchProduct(arguments: Self.pseudoLocaleArguments)
        openSettings()
        let about = app.buttons["settings-about"]
        for _ in 0 ..< 4 where !about.exists { app.swipeUp() }
        about.tap()
        let source = identified("about-source").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: uiWait))
        XCTAssertTrue(Self.isDoubled(source.label), "version line: \(source.label)")
    }

    /// `-NSDoubleLocalizedStrings` repeats each localised string, and a string with
    /// substitutions loses its second set (`@ needs attention. Archive needs
    /// attention.`). Either way a run of the sentence appears twice.
    private static func isDoubled(_ text: String) -> Bool {
        let characters = Array(text)
        let run = 12
        guard characters.count >= run * 2 else { return false }
        var seen: [ArraySlice<Character>: Int] = [:]
        for start in 0...(characters.count - run) {
            let window = characters[start..<(start + run)]
            if let first = seen[window], start - first >= run { return true }
            if seen[window] == nil { seen[window] = start }
        }
        return false
    }

    func testStatusAndDataInRTL() throws {
        try auditLocalizedStatusAndData(Self.rtlArguments, "rtl")
    }

    func testDestinationsAndHistoryInRTL() throws {
        try auditLocalizedDestinationsAndHistory(Self.rtlArguments, "rtl")
    }

    // MARK: Helpers

    /// Past first run, with nothing seeded.
    private func launchProduct(arguments: [String] = [], environment: [String: String] = [:]) {
        app.terminate()
        app.launchEnvironment = ["OHE_RESET_SEEDED_SURFACES": "1"].merging(environment) { _, new in new }
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ] + arguments
        app.launch()
    }

    private func launchStatus(
        seeding scenario: String,
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) {
        launchProduct(
            arguments: arguments,
            environment: ["OHE_SEED_DESTINATION_STATUS": scenario].merging(environment) { _, new in new }
        )
    }

    /// Whether the screen under the lock can be touched. Automation still lists it, so
    /// "covered" is what a test can check; the lock also hides it from VoiceOver.
    private var contentIsReachable: Bool {
        let export = app.buttons["status-export-now"]
        return export.exists && export.isHittable
    }

    private func identified(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// `status`, `data`, `destinations` or `history`, by position in the tab bar: a
    /// tab's title is doubled in the pseudo-locale and an icon name at accessibility
    /// sizes, and its order does not change with layout direction.
    private func openTab(_ name: String) {
        let index = ["status", "data", "destinations", "history"].firstIndex(of: name) ?? 0
        let target = app.tabBars.firstMatch.buttons.element(boundBy: index)
        XCTAssertTrue(target.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        tapWithinScreen(target)
    }

    /// Adds the seeded archive folder as a destination, which is what makes the Data tab
    /// list types. Launch with `OHE_SEED_LOCAL_EXPORT_FOLDER`.
    private func addFilesDestination() {
        openTab("destinations")
        app.buttons["destinations-add"].tap()
        let files = app.buttons["add-files"]
        XCTAssertTrue(files.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        files.tap()
        app.buttons["files-choose-folder"].tap()
        allowHealthSheetIfShown()
        let save = app.buttons["files-save"]
        XCTAssertTrue(save.waitForEnabled(timeout: 30), visibleIdentifiers().joined(separator: ","))
        save.tap()
        XCTAssertTrue(app.buttons["destinations-row-local-file"].waitForExistence(timeout: uiWait))
    }

    private func openSettings() {
        let gear = app.buttons["shell-settings"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        gear.tap()
    }

    /// Doubled pseudo-locale labels can make a tab control wider than the screen, so
    /// its centre, where a plain `tap()` lands, is outside the window and the tap does
    /// nothing. Tapping the part that is actually on screen does.
    private func tapWithinScreen(_ element: XCUIElement) {
        let window = app.windows.firstMatch.frame
        let frame = element.frame
        let visible = frame.intersection(window)
        guard !visible.isNull, visible.width > 1, visible.height > 1,
              !window.contains(CGPoint(x: frame.midX, y: frame.midY)),
              frame.width > 1, frame.height > 1
        else {
            element.tap()
            return
        }
        element.coordinate(
            withNormalizedOffset: CGVector(
                dx: (visible.midX - frame.minX) / frame.width,
                dy: (visible.midY - frame.minY) / frame.height
            )
        ).tap()
    }


    /// Dynamic Type asks whether text scales with the content size category.
    /// Asking it while the app is already pinned at an accessibility size is the
    /// least informative place to ask and by far the most expensive: on the
    /// dark/bold/AX5 Destinations screen that one pass costs 19s against 2s for
    /// every other check combined, which is what returned `-56` on hosted
    /// iPad 0. The screens audited here keep their Dynamic Type pass at the
    /// default content size, where the question means something. What an
    /// accessibility size is actually for — clipping, contrast, hit regions,
    /// element detection — is still audited here.
    private var isAtAccessibilityContentSize: Bool {
        guard
            let index = app.launchArguments.firstIndex(
                of: "-UIPreferredContentSizeCategoryName"
            ),
            app.launchArguments.indices.contains(index + 1)
        else { return false }
        return app.launchArguments[index + 1]
            .hasPrefix("UICTContentSizeCategoryAccessibility")
    }


    private func performAccessibilityAudit(_ state: String = #function) throws {
        // Do not retry a timed-out audit in-process. Hosted iPhone 2 on
        // `69cf566` spent 186s in `testBrowserEmptyStateInRTL` (-56) and
        // then poisoned the rest of the shard with background-assertion
        // timeouts. `-retry-tests-on-failure` relaunches cleanly; stacking
        // inner retries does not.
        let chrome = AccessibilityChromeSnapshot(app: app)
        // Dynamic Type is the expensive pass: it re-renders the screen at every
        // content size, while the rest only walk the tree once. Sharing one
        // budget with it is what produced `-56` "Audit failed to complete in
        // time" on hosted iPad 0, and Dynamic Type findings on `.font(.body)`
        // controls that pass the identical audit on other shards and locally.
        // Splitting by subtraction rather than by listing each type keeps the
        // coverage of `.all` if the SDK adds one.
        var passes: [XCUIAccessibilityAuditType] = [.all.subtracting(.dynamicType)]
        if isAtAccessibilityContentSize {
            print("SKIPPED AX PASS \(state): dynamicType at an accessibility content size")
        } else {
            passes.append(.dynamicType)
        }
        for auditType in passes {
            let passName = auditType == .dynamicType ? "dynamicType" : "allExceptDynamicType"
            let started = Date()
            defer {
                // `-56` names neither the screen nor the pass it gave up on, so a
                // timeout otherwise reads as "the audit failed" with nothing to
                // act on. Report the slow passes that precede one.
                let elapsed = Date().timeIntervalSince(started)
                if elapsed > 20 {
                    print("SLOW AX PASS \(state): \(passName) took \(Int(elapsed))s")
                }
            }
            do {
            try app.performAccessibilityAudit(for: auditType) { issue in
                    let cause: String?
                    if issue.auditType == .contrast, let element = issue.element {
                        cause = self.suppressionCause(for: element, chrome: chrome)
                    } else if let element = issue.element,
                              (issue.auditType == .textClipped
                                || issue.auditType.rawValue == 131_072),
                              element.elementType == .textField
                                || element.elementType == .secureTextField
                                || element.elementType == .searchField
                    {
                        cause = "systemTextFieldPlaceholder"
                    } else if issue.auditType == .dynamicType {
                        cause = self.dynamicTypeSuppressionCause(
                            for: issue.element,
                            chrome: chrome
                        )
                    } else if issue.element == nil,
                              Self.iPadUnhostedTextStates.contains(state),
                              self.iPadUnhostedIssueMatches(issue)
                    {
                        cause = "iPadUnhostedPotentiallyInaccessibleText"
                    } else if issue.auditType == .contrast, issue.element == nil,
                              Self.anonymousContrastBehindTabBarStates.contains(state)
                    {
                        // These screens are longer than one screen, so a row always sits in
                        // the band the floating tab bar fades at the bottom edge. The audit
                        // reports that row as an anonymous node; which row it is changes
                        // with the content, and removing almost any one of them hides it.
                        cause = "behindTabBar"
                    } else {
                        cause = nil
                    }
                    guard let cause else {
                        if let element = issue.element {
                            let label = element.label
                            let longest = label.split(separator: "\n").map(\.count).max() ?? label.count
                            print(
                                "UNSUPPRESSED AX \(state): type=\(issue.auditType) "
                            + "id=\(element.identifier) "
                            + "labelChars=\(label.count) labelLines=\(label.split(separator: "\n").count) "
                            + "longestLine=\(longest) "
                            + "frame=\(element.frame) window=\(chrome.window) "
                            + "label=\(label)"
                            )
                        } else {
                            print(
                                "UNSUPPRESSED AX \(state): type=\(issue.auditType) "
                                    + "element=nil issue=\(String(describing: issue))"
                            )
                        }
                        return false
                    }
                    guard let link = Self.accessibilitySuppressionIssues[cause],
                          link.hasPrefix("https://")
                    else {
                        XCTFail("suppressed \(cause) in \(state) with no linked issue")
                        return false
                    }
                    return true
                }
            } catch {
                XCTFail("accessibility audit pass \(passName) failed in \(state): \(error)")
                throw error
            }
        }
    }

    /// Xcode 26 audits system-rendered empty SwiftUI text-field placeholders and
    /// disabled controls as low contrast, and audits content that system chrome draws
    /// over: the navigation bar at the top, and the floating tab bar at the bottom.
    /// Both bars fade a band of content just inside the scroll edge. Those findings
    /// are SDK-owned, so they are named rather than silently tolerated.
    ///
    /// Both bars are measured at audit time. A hardcoded cutoff stops describing the
    /// chrome as soon as a device or SDK changes its bar heights, which turns an
    /// SDK-owned finding into an unexplained contrast failure on one simulator only.
    private func suppressionCause(
        for element: XCUIElement,
        chrome: AccessibilityChromeSnapshot
    ) -> String? {
        let frame = element.frame
        for bar in chrome.navigationBarFrames {
            if frame.minY < bar.maxY + Self.navigationScrollEdgeEffectHeight {
                return "behindNavigationBar"
            }
        }
        if let tabBar = chrome.tabBarFrame,
           frame.maxY > tabBar.minY - Self.tabBarScrollEdgeEffectHeight
        {
            return "behindTabBar"
        }
        // iPadOS `sidebarAdaptable` often has no XCUITest tab bar, but still
        // fades the bottom of the window the same way.
        let window = chrome.window
        if window.height > 0, frame.maxY > window.maxY - Self.tabBarScrollEdgeEffectHeight {
            return "behindTabBar"
        }
        if window.height > 0, !frame.intersects(window) {
            return "offscreenElement"
        }
        if element.isEnabled == false { return "disabledControl" }
        if element.elementType == .textField || element.elementType == .secureTextField {
            return "systemTextFieldPlaceholder"
        }
        return nil
    }

    /// iPadOS `sidebarAdaptable` tab labels are UIKit UILabels that do not take the
    /// accessibility content-size category. Xcode 26 reports that as a Dynamic Type
    /// failure with no `XCUIElement`, so the finding cannot be attributed to app copy.
    private func dynamicTypeSuppressionCause(
        for element: XCUIElement?,
        chrome: AccessibilityChromeSnapshot
    ) -> String? {
        // Status rows pass this audit on their own; with the summary above them they
        // are pushed below the fold at the larger sizes and reported as partial.
        if let element, let bottom = auditFoldBottom, element.frame.minY >= bottom {
            return "statusRowsBelowFold"
        }
        guard let element else { return "unhostedDynamicTypeLabel" }
        let frame = element.frame
        if let tabBar = chrome.tabBarFrame, frame.intersects(tabBar) {
            return "unhostedDynamicTypeLabel"
        }
        if chrome.navigationBarFrames.contains(where: { frame.intersects($0) }) {
            return "unhostedDynamicTypeLabel"
        }
        // The History list's retention footer is a UIKit section footer. With a short
        // list it sits on screen and is reported as partially unsupported at the larger
        // sizes; with a long one it is below the fold and never audited, so whether a
        // shard sees it depends on how much history earlier cases left behind.
        if element.identifier.isEmpty, element.label == "Keeping 90 days or 1,000 runs, whichever is reached first." {
            return "unhostedDynamicTypeLabel"
        }
        // SwiftUI DatePicker is UIKit chrome that ignores the accessibility
        // content-size category. Hosted iPad 5 attributed that to the picker
        // itself or to its inner label (empty identifier, doubled title).
        if element.elementType == .datePicker || element.elementType == .picker {
            return "unhostedDynamicTypeLabel"
        }
        return nil
    }

    func testAccessibilitySuppressionsCarryALinkedIssue() {
        XCTAssertFalse(Self.accessibilitySuppressionIssues.isEmpty)
        for (cause, link) in Self.accessibilitySuppressionIssues {
            XCTAssertTrue(link.hasPrefix("https://"), "\(cause) has no linked issue: \(link)")
        }
    }

    /// Long lists always sit in the band the floating tab bar fades at the bottom edge,
    /// and the audit reports that row as an anonymous node (see the cause above).
    private static let anonymousContrastBehindTabBarStates: Set<String> = [
        "unlock-settings", "data", "status-all-states", "dark-bold-ax5-destinations",
    ]

    private static let trackingIssue =
        "https://github.com/colinedwardwood/open-health-export/issues/4"

    private static let accessibilitySuppressionIssues = [
        "statusRowsBelowFold": "https://github.com/colinedwardwood/open-health-export/issues/172",
        "behindNavigationBar": trackingIssue,
        "behindTabBar": trackingIssue,
        "offscreenElement": trackingIssue,
        "disabledControl": trackingIssue,
        "systemTextFieldPlaceholder": trackingIssue,
        "unhostedDynamicTypeLabel": trackingIssue,
        "iPadUnhostedPotentiallyInaccessibleText": trackingIssue,
    ]

    /// iPadOS 26.5 sometimes returns a text-detection, element-detection, or
    /// clipped-text audit finding with no `XCUIElement`, despite the queried
    /// SwiftUI controls being present in the accessibility tree. Keep this
    /// exception restricted to the reproduced states instead of suppressing
    /// unattributed findings globally.
    private static let iPadUnhostedTextStates: Set<String> = [
        "pseudo-destinations",
        "pseudo-history",
    ]

    private func iPadUnhostedIssueMatches(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let description = String(describing: issue)
        return description.contains("Potentially inaccessible text")
            || description.contains("Potentially inaccessible element")
            || description.contains("Text clipped")
    }

    /// The floating tab bar fades content above its own frame, and the navigation
    /// bar (including large-title / scroll-edge material) fades a taller band below
    /// its bar frame. Intersection against the bar frames alone leaves those faded
    /// bands reported as app contrast defects.
    private static let scrollEdgeEffectHeight: CGFloat = 32
    /// iPad floating tabs fade a much taller band than the 32-point iPhone
    /// cutoff. After scrolling the paused-anchor explanation into view, demo
    /// honesty copy sat at y≈826 / window 1210 (Contrast, empty identifier).
    private static let iPadTabBarScrollEdgeEffectHeight: CGFloat = 360
    private static var tabBarScrollEdgeEffectHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad
            ? iPadTabBarScrollEdgeEffectHeight
            : scrollEdgeEffectHeight
    }
    private static let navigationScrollEdgeEffectHeight: CGFloat = 56

    /// A single tap does not reliably take keyboard focus on CI's simulator, and typing
    /// without focus fails the run rather than retrying. Waiting for the keyboard is the
    /// signal that the tap landed.
    private func type(_ text: String, into field: XCUIElement) {
        // Shorter than uiWait on purpose: a tap that did not take focus is fixed by
        // tapping again, not by waiting longer for a keyboard that is not coming.
        // Hosted simulators often connect the hardware keyboard, so no software
        // Keyboard row appears; `hasKeyboardFocus` is the signal in that mode.
        //
        // Repeating an identical tap is not a retry. A field the scroll view has
        // left mid-deceleration, or seated under chrome that still reports it
        // hittable, swallows every element tap the same way, so the later
        // attempts aim at the field's own coordinate space instead.
        for attempt in 0 ..< 4 {
            if attempt >= 2 {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                field.tap()
            }
            let deadline = Date().addingTimeInterval(min(10, uiWait))
            while Date() < deadline {
                if fieldAcceptsTyping(field) { break }
                _ = XCTWaiter().wait(for: [XCTestExpectation(description: "keyboard")], timeout: 0.25)
            }
            if fieldAcceptsTyping(field) { break }
        }
        XCTAssertTrue(
            fieldAcceptsTyping(field),
            "keyboard never appeared for \(field.identifier): "
                + "frame=\(field.frame) window=\(app.windows.firstMatch.frame) "
                + "hittable=\(field.isHittable) enabled=\(field.isEnabled) "
                + "keyboards=\(app.keyboards.count)"
        )
        field.typeText(text)
        dismissKeyboard()
    }

    /// Hosted Xcode 26's XCUIElement overlay does not expose `hasKeyboardFocus`.
    /// KVC still reports focus when the simulator hardware keyboard is connected.
    private func fieldAcceptsTyping(_ field: XCUIElement) -> Bool {
        if visibleKeyboard() != nil { return true }
        return (field.value(forKey: "hasKeyboardFocus") as? NSNumber)?.boolValue == true
    }

    /// Arabic and other software keyboards do not expose identifier `return`. A
    /// keyboard that stays up is not a cosmetic problem: the accessibility audits then
    /// inspect the system keyboard, and its undescribed candidate bar is reported as an
    /// app element with no description. Dismissal is therefore confirmed, not assumed.
    /// Swiping the *app* scrolls content and leaves the keyboard; swiping the keyboard
    /// itself, or tapping its return corner, is what actually puts it away.
    private func dismissKeyboard() {
        guard let keyboard = visibleKeyboard() else { return }
        // iPad keyboards carry their own hide key and do not dismiss on return, so
        // the iPhone-shaped attempts below are not enough on their own.
        let names = [
            "return", "done", "search", "hide keyboard", "dismiss",
            "بحث", "إدخال",
        ]
        for name in names {
            guard let keyboard = visibleKeyboard() else { return }
            let key = keyboard.buttons.matching(
                NSPredicate(
                    format: "identifier CONTAINS[cd] %@ OR label CONTAINS[cd] %@",
                    name,
                    name
                )
            ).firstMatch
            if key.waitForExistence(timeout: 1), key.isHittable, keyboardIsShowing() {
                key.tap()
                if keyboardIsGone() { return }
            }
        }
        // The keyboard can go away on its own between any two of these attempts, and
        // acting on one that has already gone is a hard failure rather than a no-op.
        if let keyboard = visibleKeyboard() {
            keyboard.swipeDown()
        }
        if keyboardIsGone() { return }
        // Bottom-trailing Return dismisses the software keyboard. Under RTL that
        // same coordinate can also type a glyph; `filterBrowserToHeartRate`
        // retries the query after clearing the field.
        if let keyboard = visibleKeyboard() {
            keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.88)).tap()
        }
        if keyboardIsGone() { return }
        app.navigationBars.firstMatch.tap()
        XCTAssertTrue(
            keyboardIsGone(),
            "keyboard stayed up, so the audit would inspect system keyboard chrome"
        )
    }

    /// On iPad the keyboard element stays in the hierarchy with an empty frame,
    /// parked below the screen, when the simulator is using the hardware keyboard.
    /// Nothing is drawn over the app and there is no candidate bar for an audit to
    /// find.
    ///
    /// Typed `app.keyboards` queries fail the hosted case when the query is empty
    /// (`No matches found for Descendants matching type Keyboard`), including
    /// `firstMatch`, `element(boundBy:)`, and `waitForExistence`. Walk the dumped
    /// tree first; only resolve the typed query after a Keyboard row is present.
    private func visibleKeyboard() -> XCUIElement? {
        guard app.debugDescription.contains("Keyboard") else { return nil }
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return nil }
        let window = app.windows.firstMatch.frame
        guard keyboard.frame.height > 1, keyboard.frame.minY < window.maxY else {
            return nil
        }
        return keyboard
    }

    private func keyboardIsShowing() -> Bool {
        visibleKeyboard() != nil
    }

    private func keyboardIsGone() -> Bool {
        for _ in 0 ..< 8 {
            if !keyboardIsShowing() { return true }
            _ = XCTWaiter().wait(
                for: [XCTestExpectation(description: "keyboard-gone")],
                timeout: 0.25
            )
        }
        return !keyboardIsShowing()
    }

    private func visibleIdentifiers() -> [String] {
        app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.identifier)
            .filter { !$0.isEmpty }
    }
}

/// Bar and window frames used while classifying accessibility-audit findings.
/// Captured once per audit so each contrast/Dynamic Type issue does not
/// re-query XCTest chrome.
private struct AccessibilityChromeSnapshot {
    let navigationBarFrames: [CGRect]
    let tabBarFrame: CGRect?
    let window: CGRect

    init(app: XCUIApplication) {
        var bars: [CGRect] = []
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists {
            bars.append(bar.frame)
        }
        navigationBarFrames = bars
        let tabBar = app.tabBars.firstMatch
        tabBarFrame = tabBar.exists ? tabBar.frame : nil
        window = app.windows.firstMatch.frame
    }
}

private extension XCUIElement {
    /// Polls until the element is enabled; XCUIElement has no built-in wait for it.
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists, isEnabled { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return exists && isEnabled
    }
}
