// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@MainActor
final class ExporterUITests: XCTestCase {
    /// CI runs three simulator clones on a shared runner, where every launch and
    /// transition takes several times what it does locally. These waits assert that a
    /// control exists, not how fast it arrives; the timing budgets are R-73's job.
    private let uiWait: TimeInterval = 30

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "false",
            "-ohe.advisoryEnabled", "false",
            "-ohe.browserDemoMode", "true",
            "-ohe.browserOnlyWithData", "true",
            "-ohe.appPrivacyGateEnabled", "false",
            // SEC-45's warning is one-time and gates the share control. Cases that are
            // about something else start past it; the SEC-45 case turns it back on.
            "-ohe.shareProtectionAcknowledged", "true",
        ]
        app.launch()
    }

    func testDisclosurePrecedesHealthPermissionControl() {
        let disclosure = app.buttons["disclosure-continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            app.staticTexts["first-run-disclaimer"].label,
            "This is not a medical device. It does not diagnose or treat anything."
        )
        XCTAssertFalse(app.buttons["health-request"].exists)
        XCTAssertTrue(app.otherElements["data-flow-explainer"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(
            app.staticTexts["No destinations yet. Health stays on this iPhone until you add one."]
                .exists
        )
        XCTAssertTrue(
            app.staticTexts["Nowhere else. No account. No analytics. No crash reporting."]
                .exists
        )
        XCTAssertTrue(app.otherElements["scheduling-honesty"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(
            app.staticTexts["Nothing here promises a send at 3 a.m."].exists
        )

        disclosure.tap()
        XCTAssertTrue(app.buttons["health-request"].waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            app.staticTexts["about-disclaimer"].label,
            "This is not a medical device. It does not diagnose or treat anything."
        )
        XCTAssertTrue(app.buttons["history-load"].exists)
        XCTAssertEqual(
            app.staticTexts["shortcut-export"].label,
            "Shortcuts can run one page to the local archive after you enable it."
        )
        XCTAssertTrue(app.otherElements["scheduling-honesty"].exists)
    }

    /// UX-07 / HK-01: no Health store means one terminal screen, not onboarding
    /// or the empty dashboard.
    func testHealthKitUnavailableShowsTerminalScreen() throws {
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "false",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launchEnvironment["OHE_HEALTHKIT_UNAVAILABLE"] = "1"
        app.launch()

        XCTAssertTrue(app.otherElements["healthkit-unavailable"].waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            app.staticTexts["Apple Health is not on this device"].label,
            "Apple Health is not on this device"
        )
        XCTAssertFalse(app.buttons["disclosure-continue"].exists)
        XCTAssertFalse(app.buttons["health-request"].exists)
        XCTAssertFalse(app.activityIndicators.firstMatch.exists)
        XCTAssertFalse(app.buttons["Retry"].exists)
        try performAccessibilityAudit("healthkit-unavailable")
    }

    /// UX-46: Delete everything is two taps from Settings, with counts and the
    /// two limits we do not honour.
    func testDeleteEverythingShowsHonestLimitsWithinTwoTaps() {
        enterControls()
        XCTAssertTrue(app.buttons["health-request"].waitForExistence(timeout: uiWait))
        let wipe = scrollToHittable(app.buttons["wipe-everything"])
        XCTAssertEqual(wipe.label, "Delete everything on this device")
        XCTAssertTrue(scrollToHittable(app.staticTexts["wipe-received-limit"]).exists)
        XCTAssertEqual(
            app.staticTexts["wipe-received-limit"].label,
            "We cannot delete data your destinations already received."
        )
        XCTAssertEqual(
            app.staticTexts["wipe-health-limit"].label,
            "We cannot turn off our own Health access."
        )
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Health → your profile picture → Privacy → Apps"
                )
            ).firstMatch.exists
        )
        wipe.tap()
        XCTAssertTrue(app.buttons["health-request"].exists)
        XCTAssertEqual(
            app.buttons["wipe-everything"].label,
            "Confirm: delete credentials and ledger identity"
        )
        XCTAssertFalse(app.buttons["disclosure-continue"].exists)
    }

    /// SEC-29: failed owner authentication covers the entire UI. The production
    /// gate is optional and remains off in the common/default launch above.
    func testOptionalPrivacyGateFailsClosedAndUsesInjectedAuthenticator() throws {
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "true",
        ]
        app.launchEnvironment["OHE_TEST_USER_PRESENCE"] = "deny"
        app.launch()

        XCTAssertTrue(app.buttons["privacy-gate-unlock"].waitForExistence(timeout: uiWait))
        XCTAssertFalse(app.buttons["health-request"].exists)
        try performAccessibilityAudit("privacy-gate-locked")

        app.buttons["privacy-gate-unlock"].tap()
        XCTAssertTrue(app.staticTexts["privacy-gate-failure"].waitForExistence(timeout: uiWait))
        XCTAssertFalse(app.buttons["health-request"].exists)
        try performAccessibilityAudit("privacy-gate-authentication-failed")
    }

    /// SEC-29: leaving the foreground immediately relocks presentation. The
    /// adapter's second result is denied so activation cannot silently reopen it.
    func testPrivacyGateRelocksAfterLeavingForeground() {
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "true",
        ]
        app.launchEnvironment["OHE_TEST_USER_PRESENCE"] = "allow-then-deny"
        app.launch()

        XCTAssertTrue(app.buttons["health-request"].waitForExistence(timeout: uiWait))
        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(app.buttons["privacy-gate-unlock"].waitForExistence(timeout: uiWait))
        XCTAssertFalse(app.buttons["health-request"].exists)
    }

    /// SEC-65: there is intentionally no stored-secret reveal affordance. Owner
    /// authentication protects the app screen but never makes credentials legible.
    func testStoredCredentialsHaveNoRevealControl() {
        enterControls()
        let policy = scrollToHittable(app.staticTexts["credential-no-reveal-policy"])
        XCTAssertTrue(policy.label.contains("never shown"), policy.label)
        XCTAssertFalse(app.buttons["credential-reveal-https"].exists)
        XCTAssertFalse(app.buttons["credential-reveal-mqtt"].exists)
    }

    func testDisclosureAndMainControlsPassAccessibilityAudit() throws {
        XCTAssertTrue(app.buttons["disclosure-continue"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit()
        enterControls()
        try performAccessibilityAudit()
    }

    func testBrowserEmptyAndDetailStatesPassAccessibilityAudit() throws {
        enterControls()
        let search = scrollToHittable(app.textFields["browser-search"])
        type("no-such-health-type", into: search)
        XCTAssertTrue(app.staticTexts["browser-empty"].waitForExistence(timeout: uiWait))
        dismissKeyboard()
        try performAccessibilityAudit()
        app.terminate()
        app.launch()
        enterControls()
        filterBrowserToHeartRate()
        let row = app.descendants(matching: .any)["browser-row-heartRate"]
        XCTAssertTrue(
            row.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        row.tap()
        XCTAssertTrue(app.buttons["browser-back"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit()
    }

    func testAccessibilityExtraExtraExtraLargeContentSize() throws {
        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["disclosure-continue"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit()
        enterControls()
        try performAccessibilityAudit()
    }

    func testDarkBoldAX5AccessibilitySettingsPassAudit() throws {
        app.terminate()
        app.launchEnvironment["OHE_ACCESSIBILITY_MATRIX"] = "combined"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        XCTAssertTrue(
            app.buttons["disclosure-continue"]
                .waitForExistence(timeout: uiWait)
        )
        try performAccessibilityAudit("dark-bold-ax5-disclosure")
        enterControls()
        try performAccessibilityAudit("dark-bold-ax5-controls")
        _ = scrollToHittable(app.staticTexts["destination-title"])
        try performAccessibilityAudit("dark-bold-ax5-destinations")
    }

    /// QA-17: a paused type says so where the user will see it, and offers two named
    /// choices. Neither the pause nor the resumption may be silent.
    func testPausedAnchorIsVisibleAndOffersBothChoices() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_ANCHOR_HOLD"] = "heartRate"
        app.launch()

        let banner = app.descendants(matching: .any)["anchor-hold-banner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        enterControls()
        let explanation = scrollToHittable(app.staticTexts["anchor-hold-explanation-0"])
        XCTAssertTrue(explanation.exists)
        XCTAssertTrue(explanation.label.contains("2026-09-08"), explanation.label)

        XCTAssertTrue(app.buttons["anchor-hold-reexport-0"].exists)
        let stop = scrollToHittable(app.buttons["anchor-hold-stop-0"])
        stop.tap()

        // Deciding is what clears it. The banner going away proves the decision was
        // recorded rather than the view forgetting.
        XCTAssertTrue(
            app.descendants(matching: .any)["anchor-hold-banner"]
                .waitForNonExistence(timeout: uiWait)
        )
    }

    /// QA-14: the three states a person needs to tell apart, on the surface they read.
    func testDestinationStatusShowsSuccessStaleAndFailedWithItsReason() {
        let healthy = destinationLine(seeding: "success")
        XCTAssertTrue(healthy.contains("Home Assistant"), healthy)
        XCTAssertTrue(healthy.contains("healthy"), healthy)
        XCTAssertTrue(healthy.contains("last success"), healthy)

        // Nothing ran in between. Only the reading moved, and the answer changed.
        let stale = destinationLine(seeding: "stale")
        XCTAssertTrue(stale.contains("stale"), stale)

        let failed = destinationLine(seeding: "failed")
        XCTAssertTrue(failed.contains("failing"), failed)
        XCTAssertTrue(failed.contains("destinationUnreachable"), failed)
        XCTAssertTrue(failed.contains("Couldn't find your Mac"), failed)
        // A failure still says when it last worked, which is what makes it reportable.
        XCTAssertTrue(failed.contains("last success"), failed)
    }

    func testDeferredLockedDestinationIsNonActionableAndNotFailing() {
        let deferred = destinationLine(seeding: "deferred")
        XCTAssertTrue(deferred.contains("deferred"), deferred)
        XCTAssertTrue(deferred.contains("non-actionable"), deferred)
        XCTAssertFalse(deferred.contains("failing"), deferred)
        XCTAssertTrue(deferred.contains("last success"), deferred)
    }

    func testWidgetURLOpensDestinationStatusAfterDisclosure() {
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.browserDemoMode", "true",
            "-ohe.browserOnlyWithData", "true",
        ]
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = "success"
        app.launchEnvironment["OHE_OPEN_URL"] =
            "openhealthexporter://status?destination=home-assistant"
        app.launch()
        let status = app.staticTexts["status-line"]
        XCTAssertTrue(status.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(
            status.label.contains("Opened destination status for home-assistant"),
            status.label
        )
        XCTAssertTrue(destinationStatusElement(0).waitForExistence(timeout: uiWait))
    }

    func testFailureNotificationURLOpensFivePartErrorWithNoFurtherTap() {
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "true",
            "-ohe.advisoryEnabled", "false",
            "-ohe.browserDemoMode", "true",
            "-ohe.browserOnlyWithData", "true",
        ]
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = "failed"
        app.launchEnvironment["OHE_OPEN_URL"] =
            "openhealthexporter://error?destination=home-assistant&archetype=hostUnresolvable"
        app.launch()
        let part0 = app.staticTexts["error-part-0"]
        XCTAssertTrue(
            part0.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertTrue(part0.label.hasPrefix("①"), part0.label)
        XCTAssertTrue(app.staticTexts["error-part-3"].label.hasPrefix("④"))
        XCTAssertTrue(
            app.staticTexts["status-line"].label.contains("Couldn't find"),
            app.staticTexts["status-line"].label
        )
    }

    func testStatusRowOpensFivePartErrorInOneTap() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = "failed"
        app.launch()
        enterControls()
        let row = scrollToHittable(destinationStatusElement(0))
        row.tap()
        let part0 = scrollToHittable(app.staticTexts["error-part-0"])
        XCTAssertTrue(
            part0.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertTrue(part0.label.hasPrefix("①"), part0.label)
        XCTAssertTrue(app.staticTexts["error-part-3"].waitForExistence(timeout: uiWait))
    }

    private func destinationLine(seeding scenario: String) -> String {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = scenario
        app.launch()
        enterControls()
        let refresh = scrollToHittable(app.buttons["destination-refresh"])
        refresh.tap()
        let line = destinationStatusElement(0)
        XCTAssertTrue(
            line.waitForExistence(timeout: uiWait),
            "no destination line for \(scenario); available: \(visibleIdentifiers())"
        )
        return line.label
    }

    func testDiagnosticShareExistsOnlyPastTheBundlesLastLine() {
        enterControls()
        let build = scrollToHittable(app.buttons["diagnostic-build"])
        XCTAssertFalse(app.buttons["diagnostic-share"].exists)
        build.tap()

        // S9 makes this structural rather than a state machine: sharing lives below the
        // bundle's last line, so it cannot be reached without traversing the content by
        // scroll, VoiceOver or Full Keyboard Access. Asserting order rather than
        // off-screen absence keeps the test honest when a short bundle fits on one screen.
        let end = app.staticTexts["diagnostic-end"]
        XCTAssertTrue(end.waitForExistence(timeout: uiWait))
        scrollToHittable(end)

        // The reveal is driven by the end marker's scroll visibility, and a marker that
        // has only just become hittable can sit far enough off the edge that no
        // visibility change is delivered. Keep traversing until the bundle's last line
        // is genuinely on screen rather than technically reachable.
        let share = app.buttons["diagnostic-share"]
        for _ in 0 ..< 10 where !share.exists {
            app.swipeUp()
            _ = share.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(
            share.waitForExistence(timeout: uiWait),
            "share never appeared after traversing to the bundle's end"
        )
        XCTAssertGreaterThan(share.frame.minY, end.frame.minY)
    }

    /// SEC-64: the keychain is device-only, so the cost of that shows up before the
    /// user types a secret, not after a restore has already lost it.
    func testCredentialDisclosurePrecedesEveryCredentialField() {
        enterControls()
        for (disclosure, field) in [
            ("credential-disclosure-https", "https-bearer"),
            ("credential-disclosure-mqtt", "mqtt-password"),
        ] {
            let copy = scrollToHittable(app.staticTexts[disclosure])
            XCTAssertTrue(
                copy.waitForExistence(timeout: uiWait),
                "no \(disclosure); available: \(visibleIdentifiers())"
            )
            XCTAssertTrue(copy.label.contains("never synced to iCloud"), copy.label)
            XCTAssertTrue(copy.label.contains("enter them again"), copy.label)

            let secure = app.secureTextFields[field]
            XCTAssertTrue(secure.waitForExistence(timeout: uiWait), field)
            // "Precedes" is a layout claim, so it is asserted as one.
            XCTAssertLessThan(copy.frame.minY, secure.frame.minY, "\(disclosure) sits below \(field)")
        }
    }

    /// SEC-14: a public address requires explicit typed confirmation before enable.
    func testPublicDestinationStaysDisabledUntilPhraseIsEntered() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_PUBLIC_CONFIRMATION"] = "true"
        app.launch()

        let warning = app.staticTexts["public-destination-warning"]
        XCTAssertTrue(warning.waitForExistence(timeout: uiWait))
        XCTAssertTrue(warning.label.contains("public address"), warning.label)

        let confirm = app.buttons["destination-confirm"]
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(confirm.isEnabled)

        let phrase = app.textFields["public-destination-confirmation"]
        try performAccessibilityAudit("public-destination-confirmation")
        type("send to public server", into: phrase)
        XCTAssertTrue(confirm.isEnabled)
    }

    /// SEC-45: sharing ends our protection over those bytes, so consent is a tap on the
    /// warning rather than an inference from a tap on the share button.
    func testShareWarningIsShownOnceAndGatesTheShareControl() throws {
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "false",
            "-ohe.advisoryEnabled", "false",
            "-ohe.browserDemoMode", "true",
            "-ohe.browserOnlyWithData", "true",
        ]
        // Cleared rather than overridden, so the app's own write is what dismisses it.
        app.launchEnvironment["OHE_SEED_SHARE_ACK"] = "clear"
        app.launch()
        enterControls()
        scrollToHittable(app.buttons["diagnostic-build"]).tap()

        // R-26 still decides where this lives: nothing about sharing is reachable until
        // the bundle's last line has been traversed.
        let end = app.staticTexts["diagnostic-end"]
        XCTAssertTrue(end.waitForExistence(timeout: uiWait))
        scrollToHittable(end)
        let warning = app.staticTexts["share-protection-warning"]
        for _ in 0 ..< 10 where !warning.exists {
            app.swipeUp()
            _ = warning.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(warning.waitForExistence(timeout: uiWait), "no SEC-45 warning after traversal")
        XCTAssertTrue(warning.label.contains("protection no longer applies"), warning.label)
        XCTAssertFalse(app.buttons["diagnostic-share"].exists, "share was reachable before the warning")
        try performAccessibilityAudit("diagnostic-preview-share-warning")

        scrollToHittable(app.buttons["share-protection-continue"]).tap()
        // Acknowledging replaces three lines of warning with one control, so the share
        // button lands below the fold and has to be traversed to like anything else.
        let revealed = app.buttons["diagnostic-share"]
        for _ in 0 ..< 10 where !revealed.exists {
            app.swipeUp()
            _ = revealed.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(revealed.waitForExistence(timeout: uiWait), "share never appeared after acknowledgement")
        XCTAssertFalse(app.staticTexts["share-protection-warning"].exists)

        // One-time: acknowledging survives a relaunch, or it is not a warning, it is a
        // nag, and people learn to tap through it.
        app.terminate()
        app.launchEnvironment["OHE_SEED_SHARE_ACK"] = "keep"
        app.launch()
        enterControls()
        scrollToHittable(app.buttons["diagnostic-build"]).tap()
        XCTAssertTrue(app.staticTexts["diagnostic-end"].waitForExistence(timeout: uiWait))
        scrollToHittable(app.staticTexts["diagnostic-end"])
        let share = app.buttons["diagnostic-share"]
        for _ in 0 ..< 10 where !share.exists {
            app.swipeUp()
            _ = share.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(share.waitForExistence(timeout: uiWait), "warning came back after acknowledgement")
        XCTAssertFalse(app.staticTexts["share-protection-warning"].exists)
    }

    func testExplicitTypeStopRequiresTwoTaps() {
        enterControls()
        let stop = scrollToHittable(app.buttons["stop-heart-rate"])
        stop.tap()
        let confirm = app.buttons["stop-heart-rate"]
        XCTAssertEqual(confirm.label, "Confirm: stop exporting heart rate")
        confirm.tap()
        XCTAssertTrue(
            app.staticTexts["Status: Ready. Heart rate is disabled and queued payloads for that type were purged."]
                .waitForExistence(timeout: uiWait)
        )
    }

    func testDeletionBehaviourStatesBestEffortAndNoCallback() {
        enterControls()
        let explanation = scrollToHittable(app.staticTexts["deletion-behaviour"])
        XCTAssertTrue(explanation.label.contains("no deletion callback"))
        XCTAssertTrue(explanation.label.contains("best-effort"))
        XCTAssertTrue(explanation.label.contains("full reconcile"))
    }

    func testBackfillDisclosesOSTiersAndKeepsRawExplicit() {
        enterControls()
        let disclosure = scrollToHittable(app.staticTexts["backfill-os-disclosure"])
        XCTAssertTrue(disclosure.label.contains("iOS 26"))
        XCTAssertTrue(disclosure.label.contains("iOS 18 through 25"))
        XCTAssertTrue(app.buttons["backfill-aggregate"].exists)
        XCTAssertEqual(
            app.buttons["backfill-raw"].label,
            "Backfill raw history (explicit action)"
        )
    }

    func testDataBrowserSelectAndEmptyMeasurementsAreVisibleAfterDisclosure() throws {
        enterControls()
        XCTAssertTrue(app.staticTexts["browser-title"].waitForExistence(timeout: uiWait))
        XCTAssertEqual(app.staticTexts["browser-title"].label, "Data")
        XCTAssertTrue(app.buttons["browser-select"].exists)
        XCTAssertFalse(app.buttons["browser-review"].exists)
        app.buttons["browser-select"].tap()
        XCTAssertTrue(app.buttons["browser-invert-routine"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(app.buttons["browser-clear-all"].exists)
        XCTAssertTrue(app.buttons["browser-review"].exists)
        XCTAssertTrue(app.staticTexts["Measurements"].exists == false)
        try performAccessibilityAudit("browser-select")
        app.buttons["browser-review"].tap()
        XCTAssertTrue(
            app.staticTexts["browser-review-title"]
                .waitForExistence(timeout: uiWait)
        )
        try performAccessibilityAudit("browser-review")
    }

    func testDestinationScopeStartsEmptyAndOffersAnExplicitPreset() {
        enterControls()
        let required = app.staticTexts["scope-required"]
        XCTAssertTrue(scrollToHittable(required).exists)
        XCTAssertTrue(app.descendants(matching: .any)["scope-destination"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scope-start-date"].exists)

        let select = scrollToHittable(app.buttons["browser-select"])
        select.tap()
        XCTAssertTrue(
            scrollToHittable(app.buttons["browser-core-daily"]).exists,
            "Core Daily must be an explicit action, not a destination default."
        )
    }

    func testImportedHTTPSDraftLoadsOnlyAfterExplicitSetupAction() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_IMPORTED_DRAFT"] = "https"
        app.launch()
        enterControls()
        let configure = scrollToHittable(
            app.buttons["Add credentials and test"]
        )
        XCTAssertTrue(configure.exists)
        try performAccessibilityAudit("configuration-import-disabled-draft")
        configure.tap()

        let endpoint = scrollToHittable(app.textFields["https-url"])
        XCTAssertEqual(
            endpoint.value as? String,
            "https://collector.example/upload"
        )
        XCTAssertTrue(app.secureTextFields["https-bearer"].exists)
        XCTAssertFalse(
            app.buttons["destination-confirm"].exists,
            "loading a draft must not run its destination test or enable it"
        )
    }

    func testConfigurationExportIsExplicitAndCredentialFreeLabeled() {
        enterControls()
        XCTAssertFalse(app.buttons["configuration-export-share"].exists)
        scrollToHittable(
            app.buttons["configuration-export-prepare"]
        ).tap()
        let share = app.buttons["configuration-export-share"]
        XCTAssertTrue(share.waitForExistence(timeout: uiWait))
        XCTAssertEqual(share.label, "Share .tributary configuration")
    }

    func testDataBrowserShowsAnExplicitEmptySearchState() {
        enterControls()
        let search = scrollToHittable(app.textFields["browser-search"])
        type("no-such-health-type", into: search)
        XCTAssertTrue(app.staticTexts["browser-empty"].waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            app.staticTexts["browser-empty"].label,
            "No data types match your search."
        )
    }

    func testDataBrowserOpensMetricDetailAndOffersNavigationBack() {
        enterControls()
        filterBrowserToHeartRate()
        let row = app.descendants(matching: .any)["browser-row-heartRate"]
        XCTAssertTrue(
            row.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        row.tap()
        XCTAssertTrue(app.buttons["browser-back"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(app.buttons["browser-load-health"].exists)
        XCTAssertEqual(app.staticTexts["browser-title"].label, "heart rate")
    }

    func testDemoExportStaysDisabledUntilTypedConfirmation() {
        enterControls()
        let export = scrollToHittable(app.buttons["demo-export"])
        XCTAssertFalse(export.isEnabled)
        let field = app.textFields["demo-confirm"]
        XCTAssertTrue(field.waitForExistence(timeout: uiWait))
        type("local-file", into: field)
        XCTAssertTrue(export.isEnabled)
    }

    func testR114DemoQuickstartCompletesAFullExportWithinTenMinutes() {
        let started = Date()
        addUIInterruptionMonitor(withDescription: "Notification permission") { alert in
            let allow = alert.buttons["Allow"]
            guard allow.exists else { return false }
            allow.tap()
            return true
        }
        enterControls()
        let field = app.textFields["demo-confirm"]
        XCTAssertTrue(field.waitForExistence(timeout: uiWait))
        type("local-file", into: field)
        dismissKeyboard()
        let export = scrollToHittable(app.buttons["demo-export"])
        XCTAssertTrue(export.isEnabled)
        export.tap()
        app.tap()
        let finished = NSPredicate(
            format: "label CONTAINS %@",
            "Demo export finished. Files are DEMO- prefixed."
        )
        expectation(for: finished, evaluatedWith: app.staticTexts["status-line"])
        waitForExpectations(timeout: 600)
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            600,
            "R-114 demo quickstart exceeded ten minutes"
        )
    }

    func testDisclosureAndControlsInPseudoLocale() throws {
        try auditLocalizedDisclosureAndControls(Self.pseudoLocaleArguments, "pseudo")
    }

    func testBrowserEmptyStateInPseudoLocale() throws {
        try auditLocalizedBrowserEmpty(Self.pseudoLocaleArguments, "pseudo")
    }

    func testBrowserDetailInPseudoLocale() throws {
        try auditLocalizedBrowserDetail(Self.pseudoLocaleArguments, "pseudo")
    }

    func testDestinationsAndHistoryInPseudoLocale() throws {
        try auditLocalizedDestinationsAndHistory(Self.pseudoLocaleArguments, "pseudo")
    }

    func testDisclosureAndControlsInRTL() throws {
        try auditLocalizedDisclosureAndControls(Self.rtlArguments, "rtl")
    }

    func testBrowserEmptyStateInRTL() throws {
        try auditLocalizedBrowserEmpty(Self.rtlArguments, "rtl")
    }

    func testBrowserDetailInRTL() throws {
        try auditLocalizedBrowserDetail(Self.rtlArguments, "rtl")
    }

    func testDestinationsAndHistoryInRTL() throws {
        try auditLocalizedDestinationsAndHistory(Self.rtlArguments, "rtl")
    }

    /// QA-15: silence itself is visible. A destination that succeeded and then stopped
    /// still produces an in-app overdue banner without talking to a server.
    func testOverdueExportShowsAnInAppBanner() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = "overdue"
        app.launch()
        enterControls()
        let refresh = scrollToHittable(app.buttons["destination-refresh"])
        refresh.tap()
        let banner = app.descendants(matching: .any)["export-overdue-banner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Export is overdue"))
                .firstMatch.waitForExistence(timeout: uiWait)
        )
        let line = destinationStatusElement(0)
        XCTAssertTrue(line.waitForExistence(timeout: uiWait))
        XCTAssertTrue(line.label.contains("overdue"), line.label)
    }

    func testDestinationSectionExposesTheEmptyStateAndRefreshControl() throws {
        enterControls()
        let title = scrollToHittable(app.staticTexts["destination-title"])
        XCTAssertEqual(title.label, "Where your data goes")
        XCTAssertTrue(app.buttons["destination-refresh"].exists)
        XCTAssertEqual(
            app.staticTexts["destination-empty"].label,
            "No destination snapshots yet."
        )
        let hae = scrollToHittable(app.staticTexts["hae-compatibility-label"])
        XCTAssertEqual(
            hae.label,
            "compatibility export — correctness claims do not apply"
        )
        XCTAssertFalse(app.otherElements["destination-change-banner"].exists)
        XCTAssertFalse(app.staticTexts["destination-change-banner"].exists)
        _ = scrollToHittable(app.textFields["https-url"])
        try performAccessibilityAudit()
    }

    /// QA-26 names permission-denied and permission-limited as audited states. R-60 is
    /// why neither gets its own rendering: a denied read and absent data are
    /// indistinguishable to us, so the no-data state *is* the denied state, and it is
    /// the one that has to survive the audit.
    func testPermissionLimitedStatesPassAccessibilityAudit() throws {
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "false",
            "-ohe.advisoryEnabled", "false",
            // Live values with the filter off: every catalogue row renders without data,
            // which is what a partially authorised store looks like from inside the app.
            "-ohe.browserDemoMode", "false",
            "-ohe.browserOnlyWithData", "false",
        ]
        app.launch()
        enterControls()
        let row = app.descendants(matching: .any)["browser-row-heartRate"]
        XCTAssertTrue(
            row.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        scrollToHittable(row)
        try performAccessibilityAudit("browser-permission-limited")

        row.tap()
        let empty = app.staticTexts["browser-detail-empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: uiWait))
        // The copy must keep naming both causes, not resolve to a denial.
        XCTAssertTrue(empty.label.contains("access is off in Health"), empty.label)
        XCTAssertTrue(empty.label.contains("Sharing"), empty.label)
        try performAccessibilityAudit("browser-detail-permission-denied")
    }

    /// QA-26's error state: a failing destination and an overdue export both escalate on
    /// the surface a person reads, so both renderings are audited.
    func testErrorStatesPassAccessibilityAudit() throws {
        for scenario in ["failed", "overdue"] {
            app.terminate()
            app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = scenario
            app.launch()
            enterControls()
            let refresh = scrollToHittable(app.buttons["destination-refresh"])
            refresh.tap()
            let line = destinationStatusElement(0)
            XCTAssertTrue(
                line.waitForExistence(timeout: uiWait),
                "no destination line for \(scenario); available: \(visibleIdentifiers())"
            )
            try performAccessibilityAudit("destination-\(scenario)")
        }
    }

    func testSuccessStaleAndDestinationChangeStatesPassAccessibilityAudit() throws {
        for scenario in ["success", "stale", "changed"] {
            app.terminate()
            app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = scenario
            app.launch()
            enterControls()
            let refresh = scrollToHittable(app.buttons["destination-refresh"])
            refresh.tap()
            XCTAssertTrue(
                destinationStatusElement(0)
                    .waitForExistence(timeout: uiWait),
                "no destination line for \(scenario); available: \(visibleIdentifiers())"
            )
            if scenario == "changed" {
                XCTAssertTrue(
                    app.descendants(matching: .any)["destination-change-banner"]
                        .waitForExistence(timeout: uiWait)
                )
            }
            try performAccessibilityAudit("destination-\(scenario)")
        }
    }

    func testDestinationChangeStillEscalatesWhenNotificationsAreDenied() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = "changed"
        app.launchEnvironment["OHE_SEED_NOTIFICATION_AUTHORIZATION"] = "denied"
        app.launch()
        enterControls()
        let refresh = scrollToHittable(app.buttons["destination-refresh"])
        refresh.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["destination-change-banner"]
                .waitForExistence(timeout: uiWait)
        )
        XCTAssertTrue(
            destinationStatusElement(0).waitForExistence(timeout: uiWait)
        )
    }

    /// QA-17's paused type is the other half of permission-limited: the type is enabled
    /// but not flowing, and the banner saying so is on the first screen.
    func testPausedAnchorBannerPassesAccessibilityAudit() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_ANCHOR_HOLD"] = "heartRate"
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["anchor-hold-banner"]
                .waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        try performAccessibilityAudit("anchor-hold-banner")
        enterControls()
        _ = scrollToHittable(app.staticTexts["anchor-hold-explanation-0"])
        try performAccessibilityAudit("anchor-hold-explanation")
    }

    func testAcknowledgementsRenderTheGeneratedNotice() {
        enterControls()
        let body = scrollToHittable(app.staticTexts["acknowledgements-body"])
        XCTAssertTrue(
            body.label.contains("no third-party Swift packages"),
            body.label
        )
        XCTAssertTrue(body.label.contains("sqlite3"), body.label)
        XCTAssertTrue(body.label.contains("zlib"), body.label)
    }

    func testFreshnessTargetsAreShownPerClassWhileR71IsPending() {
        enterControls()
        _ = scrollToHittable(app.staticTexts["freshness-target"])
        for freshnessClass in ["a", "b", "c", "d"] {
            let line = app.staticTexts["freshness-class-\(freshnessClass)"]
            XCTAssertTrue(
                line.waitForExistence(timeout: uiWait),
                "available identifiers: \(visibleIdentifiers())"
            )
            XCTAssertTrue(line.label.contains("pending R-71"), line.label)
            XCTAssertTrue(line.label.contains("not a delivery promise"), line.label)
        }
    }

    private func destinationStatusElement(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any)["destination-status-\(index)"]
    }

    private func enterControls() {
        let disclosure = app.buttons["disclosure-continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: uiWait))
        disclosure.tap()
    }

    /// QA-27 exercises structure and accessibility under localization expansion and
    /// mirrored layout. It intentionally avoids pixel snapshots: identifiers and
    /// accessibility audits remain stable across SDK font/rasterization changes while
    /// still catching clipped, unreachable, unlabeled and incorrectly ordered UI.
    private static let pseudoLocaleArguments = ["-NSDoubleLocalizedStrings", "YES"]
    private static let rtlArguments = [
        "-AppleLanguages", "(ar)",
        "-NSForceRightToLeftWritingDirection", "YES",
    ]

    private func launchLocalized(_ arguments: [String]) {
        app.terminate()
        app.launchArguments += arguments
        app.launch()
    }

    private func auditLocalizedDisclosureAndControls(
        _ arguments: [String],
        _ configuration: String
    ) throws {
        launchLocalized(arguments)
        XCTAssertTrue(app.buttons["disclosure-continue"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("\(configuration)-disclosure")
        enterControls()
        XCTAssertTrue(app.staticTexts["browser-title"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("\(configuration)-controls")
    }

    private func auditLocalizedBrowserEmpty(
        _ arguments: [String],
        _ configuration: String
    ) throws {
        launchLocalized(arguments)
        enterControls()
        let search = scrollToHittable(app.textFields["browser-search"])
        type("no-such-health-type", into: search)
        XCTAssertTrue(app.staticTexts["browser-empty"].waitForExistence(timeout: uiWait))
        dismissKeyboard()
        try performAccessibilityAudit("\(configuration)-browser-empty")
    }

    private func auditLocalizedDestinationsAndHistory(
        _ arguments: [String],
        _ configuration: String
    ) throws {
        launchLocalized(arguments)
        enterControls()
        XCTAssertTrue(scrollToHittable(app.staticTexts["destination-title"]).exists)
        XCTAssertTrue(app.buttons["destination-refresh"].exists)
        try performAccessibilityAudit("\(configuration)-destinations")
        XCTAssertTrue(scrollToHittable(app.buttons["history-load"]).exists)
        app.buttons["history-load"].tap()
        try performAccessibilityAudit("\(configuration)-history")
    }

    private func auditLocalizedBrowserDetail(
        _ arguments: [String],
        _ configuration: String
    ) throws {
        launchLocalized(arguments)
        enterControls()
        filterBrowserToHeartRate()
        let row = app.descendants(matching: .any)["browser-row-heartRate"]
        XCTAssertTrue(row.waitForExistence(timeout: uiWait))
        row.tap()
        XCTAssertTrue(app.buttons["browser-back"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("\(configuration)-browser-detail")
    }

    private func performAccessibilityAudit(_ state: String = #function) throws {
        try app.performAccessibilityAudit { issue in
            guard let element = issue.element else {
                return false
            }
            let cause: String?
            if issue.auditType == .contrast {
                cause = Self.suppressionCause(for: element)
            } else {
                cause = nil
            }
            guard let cause else {
                print(
                    "UNSUPPRESSED AX \(state): type=\(issue.auditType) "
                        + "id=\(element.identifier) label=\(element.label) "
                        + "enabled=\(element.isEnabled) hittable=\(element.isHittable) "
                        + "frame=\(element.frame)"
                )
                return false
            }
            // QA-26: a waiver is only valid with a tracking issue behind it. A cause
            // that is not in the table cannot be suppressed, so adding one without a
            // link fails the audit instead of passing quietly.
            guard let link = Self.accessibilitySuppressionIssues[cause],
                  link.hasPrefix("https://")
            else {
                XCTFail("suppressed \(cause) in \(state) with no linked issue")
                return false
            }
            return true
        }
    }

    /// Xcode 26 audits system-rendered empty SwiftUI text-field placeholders and
    /// disabled controls as low contrast, and audits content behind the navigation bar
    /// after a scroll. Those findings are SDK-owned, so they are named rather than
    /// silently tolerated.
    private static func suppressionCause(for element: XCUIElement) -> String? {
        if element.frame.minY < 130 { return "behindNavigationBar" }
        if !element.isHittable { return "offscreenElement" }
        if element.isEnabled == false { return "disabledControl" }
        if element.elementType == .textField || element.elementType == .secureTextField {
            return "systemTextFieldPlaceholder"
        }
        return nil
    }

    func testAccessibilitySuppressionsCarryALinkedIssue() {
        XCTAssertFalse(Self.accessibilitySuppressionIssues.isEmpty)
        for (cause, link) in Self.accessibilitySuppressionIssues {
            XCTAssertTrue(link.hasPrefix("https://"), "\(cause) has no linked issue: \(link)")
        }
    }

    private static let trackingIssue =
        "https://github.com/colinedwardwood/open-health-export/issues/4"

    private static let accessibilitySuppressionIssues = [
        "behindNavigationBar": trackingIssue,
        "offscreenElement": trackingIssue,
        "disabledControl": trackingIssue,
        "systemTextFieldPlaceholder": trackingIssue,
    ]

    private func filterBrowserToHeartRate() {
        let search = app.textFields["browser-search"]
        XCTAssertTrue(search.waitForExistence(timeout: uiWait))
        type("heart", into: search)
        dismissKeyboard()
    }

    /// A single tap does not reliably take keyboard focus on CI's simulator, and typing
    /// without focus fails the run rather than retrying. Waiting for the keyboard is the
    /// signal that the tap landed.
    private func type(_ text: String, into field: XCUIElement) {
        // Shorter than uiWait on purpose: a tap that did not take focus is fixed by
        // tapping again, not by waiting longer for a keyboard that is not coming.
        for _ in 0 ..< 3 {
            field.tap()
            if app.keyboards.element.waitForExistence(timeout: 10) { break }
        }
        XCTAssertTrue(app.keyboards.element.exists, "keyboard never appeared for \(field.identifier)")
        field.typeText(text)
    }

    /// Arabic and other software keyboards do not expose identifier `return`.
    private func dismissKeyboard() {
        guard app.keyboards.element.exists else { return }
        let predicate = NSPredicate(
            format: "identifier CONTAINS[cd] %@ OR label CONTAINS[cd] %@",
            "return",
            "return"
        )
        let key = app.keyboards.buttons.matching(predicate).firstMatch
        if key.waitForExistence(timeout: 2), key.isHittable {
            key.tap()
            return
        }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).tap()
    }

    private func visibleIdentifiers() -> [String] {
        app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.identifier)
            .filter { !$0.isEmpty }
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement) -> XCUIElement {
        for _ in 0 ..< 40 where !element.isHittable {
            app.swipeUp()
        }
        if !element.isHittable {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Element did not become hittable"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(element.isHittable)
        return element
    }
}
