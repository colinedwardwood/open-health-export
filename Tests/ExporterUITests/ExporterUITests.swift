// SPDX-FileCopyrightText: 2026 Colin Edward Wood and contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import UIKit
import XCTest

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

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.terminate()
        app.launchEnvironment = [
            "OHE_RESET_SEEDED_SURFACES": "1",
        ]
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
        let emptyFlow = app.staticTexts["data-flow-empty"]
        XCTAssertTrue(
            emptyFlow.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertEqual(
            emptyFlow.label,
            "No destinations yet. Health stays on \(thisDeviceNoun) until you add one."
        )
        XCTAssertEqual(
            app.staticTexts["data-flow-nowhere-else"].label,
            "Nowhere else. No account. No analytics. No crash reporting."
        )
        XCTAssertTrue(app.otherElements["scheduling-honesty"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(
            app.staticTexts["scheduling-honesty-promise"].exists
                || app.staticTexts["Nothing here promises a send at 3 a.m."].exists
        )

        disclosure.tap()
        XCTAssertTrue(app.buttons["health-request"].waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            app.staticTexts["about-disclaimer"].label,
            "This is not a medical device. It does not diagnose or treat anything."
        )
        XCTAssertTrue(scrollHistory(app.buttons["history-load"]).exists)
        let shortcuts = scrollStatus(identified("shortcut-export"))
        XCTAssertEqual(
            shortcuts.label,
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

    func testIPadOnlyExporterNoticeIsVisibleWhenForced() {
        app.terminate()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "false",
            "-ohe.advisoryEnabled", "false",
            "-ohe.appPrivacyGateEnabled", "false",
        ]
        app.launchEnvironment["OHE_IPAD_ONLY_EXPORTER"] = "1"
        app.launch()

        let notice = app.descendants(matching: .any)["ipad-only-exporter"]
        XCTAssertTrue(
            notice.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        XCTAssertTrue(
            app.staticTexts["This iPad is your only exporter."].exists
                || notice.label.contains("This iPad is your only exporter."),
            notice.label
        )
        XCTAssertFalse(app.buttons["ipad-only-exporter-dismiss"].exists)
    }

    /// UX-46: Delete everything is two taps from Settings, with counts and the
    /// two limits we do not honour.
    func testDeleteEverythingShowsHonestLimitsWithinTwoTaps() {
        enterControls()
        XCTAssertTrue(app.buttons["health-request"].waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            scrollSettings(app.staticTexts["app-privacy-heading"]).label,
            "App privacy"
        )
        XCTAssertEqual(
            scrollSettings(app.staticTexts["hide-lock-heading"]).label,
            "If someone else set this up"
        )
        XCTAssertTrue(
            scrollSettings(app.staticTexts["hide-lock-body"]).label.contains("Hidden Apps")
        )
        let wipe = scrollSettings(app.buttons["wipe-everything"])
        XCTAssertEqual(
            scrollSettings(app.staticTexts["wipe-section-heading"]).label,
            "Stop and delete"
        )
        XCTAssertEqual(wipe.label, "Delete everything on this device")
        XCTAssertTrue(scrollSettings(app.staticTexts["wipe-received-limit"]).exists)
        XCTAssertEqual(
            app.staticTexts["wipe-received-limit"].label,
            "We cannot delete data your destinations already received."
        )
        XCTAssertEqual(
            app.staticTexts["wipe-health-limit"].label,
            "We cannot turn off our own Health access."
        )
        XCTAssertEqual(
            scrollSettings(app.staticTexts["wipe-health-path"]).label,
            "To turn access off: Health → your profile picture → Privacy → Apps → Open Health Exporter."
        )
        XCTAssertEqual(
            scrollSettings(app.staticTexts["wipe-mac-limit"]).label,
            "A Mac companion keeps its own copy. Use Delete everything received there. Deleting here does not reach it."
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
        XCTAssertTrue(app.otherElements["privacy-gate"].exists)
        XCTAssertEqual(
            app.staticTexts["privacy-gate-locked-title"].label,
            "Open Health Exporter is locked"
        )
        XCTAssertTrue(
            app.staticTexts["privacy-gate-background-scope"].label.contains("Background exports")
        )
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
        XCTAssertTrue(app.otherElements["privacy-gate"].exists)
        XCTAssertEqual(
            app.staticTexts["privacy-gate-locked-title"].label,
            "Open Health Exporter is locked"
        )
        XCTAssertFalse(app.buttons["health-request"].exists)
    }

    /// SEC-65: there is intentionally no stored-secret reveal affordance. Owner
    /// authentication protects the app screen but never makes credentials legible.
    func testStoredCredentialsHaveNoRevealControl() {
        enterControls()
        let policy = scrollSettings(app.staticTexts["credential-no-reveal-policy"])
        XCTAssertTrue(policy.label.contains("never shown"), policy.label)
        XCTAssertFalse(app.buttons["credential-reveal-https"].exists)
        XCTAssertFalse(app.buttons["credential-reveal-mqtt"].exists)
    }

    func testHistoryPayloadRevealRequiresAnExplicitActionAndStaysOffByDefault() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_HISTORY_PAYLOAD"] = "1"
        app.launchEnvironment["OHE_HISTORY_PAYLOAD_AUTH"] = "skip"
        app.launch()
        enterHistory()
        let load = scrollHistory(app.buttons["history-load"])
        load.tap()
        let reveal = app.buttons["history-reveal-payload-0"]
        for _ in 0 ..< 8 where !reveal.waitForExistence(timeout: 2) {
            if load.exists, load.isHittable {
                load.tap()
            }
        }
        XCTAssertTrue(
            reveal.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")).firstMatch.exists
        )
        reveal.tap()
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS %@", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
            ).firstMatch.waitForExistence(timeout: uiWait)
        )
        XCTAssertFalse(app.buttons["history-reveal-payload-0"].exists)
    }

    func testDisclosureAndMainControlsPassAccessibilityAudit() throws {
        XCTAssertTrue(app.buttons["disclosure-continue"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit()
        enterControls()
        try performAccessibilityAudit()
    }

    func testBrowserEmptyAndDetailStatesPassAccessibilityAudit() throws {
        enterData()
        let search = scrollData(app.textFields["browser-search"])
        type("no-such-health-type", into: search)
        XCTAssertTrue(app.staticTexts["browser-empty"].waitForExistence(timeout: uiWait))
        dismissKeyboard()
        try performAccessibilityAudit("browser-empty")
        app.terminate()
        app.launch()
        enterData()
        filterBrowserToHeartRate()
        let row = app.descendants(matching: .any)["browser-row-heartRate"]
        XCTAssertTrue(
            row.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        row.tap()
        XCTAssertTrue(app.buttons["browser-back"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("browser-detail")
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
        _ = scrollDestinations(app.staticTexts["destination-title"])
        try performAccessibilityAudit("dark-bold-ax5-destinations")
    }

    /// QA-17: a paused type says so where the user will see it, and offers two named
    /// choices. Neither the pause nor the resumption may be silent.
    func testPausedAnchorIsVisibleAndOffersBothChoices() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_ANCHOR_HOLD"] = "heartRate"
        app.launch()
        // The banner is on Status, under the first-run cover. Looking for it
        // before Continue only sees disclosure identifiers.
        enterControls()

        let banner = app.descendants(matching: .any)["anchor-hold-banner"]
        XCTAssertTrue(
            banner.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        let explanation = scrollStatus(app.staticTexts["anchor-hold-explanation-0"])
        XCTAssertTrue(explanation.exists)
        XCTAssertTrue(explanation.label.contains("2026-09-08"), explanation.label)

        XCTAssertTrue(app.buttons["anchor-hold-reexport-0"].exists)
        let stop = scrollStatus(app.buttons["anchor-hold-stop-0"])
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
        let part0 = identified("error-part-0")
        XCTAssertTrue(
            part0.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertTrue(part0.label.hasPrefix("①"), part0.label)
        XCTAssertTrue(identified("error-part-3").label.hasPrefix("④"))
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
        let row = scrollStatus(destinationStatusElement(0))
        row.tap()
        let part0 = scrollStatus(identified("error-part-0"))
        XCTAssertTrue(
            part0.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertTrue(part0.label.hasPrefix("①"), part0.label)
        XCTAssertTrue(identified("error-part-3").waitForExistence(timeout: uiWait))
    }

    func testNonDesignatedDestinationCanBeMadeManualOnly() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = "success"
        app.launch()
        enterControls()

        let role = scrollStatus(
            identified("destination-export-role-home-assistant")
        )
        XCTAssertTrue(role.waitForExistence(timeout: uiWait))
        XCTAssertTrue(
            identified("destination-export-role-copy-home-assistant").label
                .contains("designated automatic exporter")
        )
        scrollStatus(
            identified("destination-export-role-manual-home-assistant")
        ).tap()

        let copy = identified("destination-export-role-copy-home-assistant")
        XCTAssertTrue(copy.waitForExistence(timeout: uiWait))
        XCTAssertTrue(copy.label.contains("only when you ask"), copy.label)
        selectRootTab(0)
        XCTAssertTrue(
            destinationStatusElement(0).label.contains("manual_only"),
            destinationStatusElement(0).label
        )
    }

    private func destinationLine(seeding scenario: String) -> String {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = scenario
        app.launch()
        enterControls()
        let refresh = scrollStatus(app.buttons["destination-refresh"])
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
        let build = scrollSettings(app.buttons["diagnostic-build"])
        XCTAssertFalse(app.buttons["diagnostic-share"].exists)
        build.tap()

        // S9 makes this structural rather than a state machine: sharing lives below the
        // bundle's last line, so it cannot be reached without traversing the content by
        // scroll, VoiceOver or Full Keyboard Access. Asserting order rather than
        // off-screen absence keeps the test honest when a short bundle fits on one screen.
        let end = app.staticTexts["diagnostic-end"]
        XCTAssertTrue(end.waitForExistence(timeout: uiWait))
        scrollSettings(end)

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
        enterDestinations()
        for (disclosure, field) in [
            ("credential-disclosure-https", "https-bearer"),
            ("credential-disclosure-mqtt", "mqtt-password"),
        ] {
            let copy = scrollDestinations(app.staticTexts[disclosure])
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
        let identity = app.staticTexts["destination-confirm-line-0"]
        XCTAssertTrue(identity.waitForExistence(timeout: uiWait))
        XCTAssertTrue(identity.label.contains("collector.example.com"), identity.label)

        let confirm = app.buttons["destination-confirm"]
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(confirm.isEnabled)

        let phrase = app.textFields["public-destination-confirmation"]
        try performAccessibilityAudit("public-destination-confirmation")
        type("send to public server", into: phrase)
        XCTAssertTrue(confirm.isEnabled)
    }

    func testPublicDestinationConfirmationStripsLeadingWhitespace() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_PUBLIC_CONFIRMATION"] = "true"
        app.launch()
        let phrase = app.textFields["public-destination-confirmation"]
        XCTAssertTrue(phrase.waitForExistence(timeout: uiWait))
        type(" send to public server ", into: phrase)
        XCTAssertTrue(
            app.staticTexts["public-destination-confirmation-whitespace"].waitForExistence(timeout: uiWait)
        )
        XCTAssertTrue(app.buttons["destination-confirm"].isEnabled)
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
        scrollSettings(app.buttons["diagnostic-build"]).tap()
        XCTAssertTrue(identified("diagnostic-preview").waitForExistence(timeout: uiWait))
        XCTAssertFalse(identified("diagnostic-preview").label.isEmpty)

        // R-26 still decides where this lives: nothing about sharing is reachable until
        // the bundle's last line has been traversed.
        let end = app.staticTexts["diagnostic-end"]
        XCTAssertTrue(end.waitForExistence(timeout: uiWait))
        scrollSettings(end)
        let warning = identified("share-protection-warning")
        for _ in 0 ..< 10 where !warning.exists {
            app.swipeUp()
            _ = warning.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(warning.waitForExistence(timeout: uiWait), "no SEC-45 warning after traversal")
        XCTAssertTrue(warning.label.contains("protection no longer applies"), warning.label)
        XCTAssertFalse(app.buttons["diagnostic-share"].exists, "share was reachable before the warning")
        try performAccessibilityAudit("diagnostic-preview-share-warning")

        scrollSettings(app.buttons["share-protection-continue"]).tap()
        // Acknowledging replaces three lines of warning with one control, so the share
        // button lands below the fold and has to be traversed to like anything else.
        let revealed = app.buttons["diagnostic-share"]
        for _ in 0 ..< 10 where !revealed.exists {
            app.swipeUp()
            _ = revealed.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(revealed.waitForExistence(timeout: uiWait), "share never appeared after acknowledgement")
        XCTAssertFalse(identified("share-protection-warning").exists)

        // One-time: acknowledging survives a relaunch, or it is not a warning, it is a
        // nag, and people learn to tap through it.
        app.terminate()
        app.launchEnvironment["OHE_SEED_SHARE_ACK"] = "keep"
        app.launch()
        enterControls()
        scrollSettings(app.buttons["diagnostic-build"]).tap()
        XCTAssertTrue(app.staticTexts["diagnostic-end"].waitForExistence(timeout: uiWait))
        scrollSettings(app.staticTexts["diagnostic-end"])
        let share = app.buttons["diagnostic-share"]
        for _ in 0 ..< 10 where !share.exists {
            app.swipeUp()
            _ = share.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(share.waitForExistence(timeout: uiWait), "warning came back after acknowledgement")
        XCTAssertFalse(identified("share-protection-warning").exists)
    }

    func testExplicitTypeStopRequiresTwoTaps() {
        enterControls()
        let stop = scrollSettings(app.buttons["stop-heart-rate"])
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
        let explanation = scrollStatus(app.staticTexts["deletion-behaviour"])
        XCTAssertTrue(explanation.label.contains("no deletion callback"))
        XCTAssertTrue(explanation.label.contains("best-effort"))
        XCTAssertTrue(explanation.label.contains("full reconcile"))
    }

    func testBackfillDisclosesOSTiersAndKeepsRawExplicit() {
        enterControls()
        let disclosure = scrollStatus(app.staticTexts["backfill-os-disclosure"])
        XCTAssertTrue(disclosure.label.contains("iOS 26"))
        XCTAssertTrue(disclosure.label.contains("iOS 18 through 25"))
        XCTAssertTrue(app.buttons["backfill-aggregate"].exists)
        XCTAssertEqual(
            app.buttons["backfill-raw"].label,
            "Backfill raw history (explicit action)"
        )
    }

    func testDataBrowserSelectAndEmptyMeasurementsAreVisibleAfterDisclosure() throws {
        enterData()
        XCTAssertTrue(scrollData(app.staticTexts["browser-title"]).exists)
        XCTAssertEqual(app.staticTexts["browser-title"].label, "Data")
        XCTAssertTrue(app.buttons["browser-select"].exists)
        XCTAssertFalse(app.buttons["browser-review"].exists)
        app.buttons["browser-select"].tap()
        XCTAssertTrue(
            scrollData(app.buttons["browser-invert-routine"]).waitForExistence(timeout: uiWait)
        )
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
        app.buttons["browser-review-continue"].tap()
        XCTAssertTrue(app.buttons["browser-select"].waitForExistence(timeout: uiWait))
        app.buttons["browser-select"].tap()
        XCTAssertTrue(
            scrollData(app.buttons["browser-invert-routine"]).waitForExistence(timeout: uiWait)
        )
        app.buttons["browser-invert-routine"].tap()
        app.buttons["browser-review"].tap()
        let permission = app.staticTexts["browser-review-permission"]
        XCTAssertTrue(permission.waitForExistence(timeout: uiWait))
        XCTAssertTrue(permission.label.contains("need new Health permission"))
    }

    func testDestinationScopeStartsEmptyAndOffersAnExplicitPreset() {
        enterData()
        let required = app.staticTexts["scope-required"]
        XCTAssertTrue(scrollData(required).exists)
        XCTAssertTrue(app.descendants(matching: .any)["scope-destination"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["scope-start-date"].exists)

        let select = scrollData(app.buttons["browser-select"])
        select.tap()
        XCTAssertTrue(
            scrollData(app.buttons["browser-core-daily"]).exists,
            "Core Daily must be an explicit action, not a destination default."
        )
    }

    func testImportedHTTPSDraftLoadsOnlyAfterExplicitSetupAction() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_IMPORTED_DRAFT"] = "https"
        app.launch()
        enterDestinations()
        let configure = scrollDestinations(
            app.buttons["configuration-import-configure-https"]
        )
        XCTAssertTrue(configure.exists)
        try performAccessibilityAudit("configuration-import-disabled-draft")
        configure.tap()

        let endpoint = scrollDestinations(app.textFields["https-url"])
        XCTAssertEqual(
            endpoint.value as? String,
            "https://collector.example/upload"
        )
        XCTAssertTrue(app.secureTextFields["https-bearer"].exists)
        XCTAssertFalse(
            app.buttons["destination-confirm"].exists,
            "loading a draft must not run its destination test or enable it"
        )
        let parseBack = app.staticTexts["https-url-parseback"]
        XCTAssertTrue(parseBack.waitForExistence(timeout: uiWait))
        XCTAssertTrue(parseBack.label.contains("host collector.example"))
    }

    func testHTTPSURLParseBackNamesWhitespaceAndHost() {
        enterDestinations()
        let endpoint = scrollDestinations(app.textFields["https-url"])
        type(" https://collector.example:8443/upload ", into: endpoint)
        dismissKeyboard()
        XCTAssertTrue(
            app.staticTexts["https-url-whitespace"].waitForExistence(timeout: uiWait)
        )
        let parseBack = app.staticTexts["https-url-parseback"]
        XCTAssertTrue(parseBack.waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            parseBack.label,
            "scheme https · host collector.example · port 8443 · path /upload"
        )
    }

    func testImportedCompanionDraftPrefillsMacNameAndRefusesADifferentPairing() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_IMPORTED_DRAFT"] = "companion"
        app.launchEnvironment["OHE_SEED_PAIRING_PASTE"] = "1"
        app.launch()
        enterDestinations()
        let configure = scrollDestinations(
            app.buttons["configuration-import-configure-companion"]
        )
        XCTAssertTrue(configure.exists)
        dismissKeyboard()
        configure.tap()
        let imported = scrollDestinations(
            app.staticTexts["pairing-imported-service-name"]
        )
        XCTAssertTrue(imported.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertEqual(imported.label, "OHE Lab Mac._ohe-companion._tcp")
        let export = scrollDestinations(app.buttons["pairing-export"])
        XCTAssertFalse(export.isEnabled)
        scrollDestinations(app.buttons["pairing-parse"]).tap()
        let mismatch = scrollDestinations(
            app.staticTexts["pairing-import-name-mismatch"]
        )
        XCTAssertTrue(
            mismatch.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertFalse(export.isEnabled)
        XCTAssertFalse(app.staticTexts["pairing-confirmation"].exists)
    }

    /// R-67: local-file imports stay disabled drafts. There is no folder-path setup
    /// editor, and the UI says so rather than inventing one.
    func testImportedLocalFileDraftHasNoSetupPath() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_IMPORTED_DRAFT"] = "local-file"
        app.launch()
        enterDestinations()
        XCTAssertTrue(
            app.staticTexts["destination-ledger-honesty"].waitForExistence(timeout: uiWait)
        )
        let notice = app.staticTexts["configuration-import-unsupported-localFile"]
        if !notice.waitForExistence(timeout: uiWait) {
            for _ in 0 ..< 12 {
                app.scrollViews["root-scroll-destinations"].swipeUp()
                if notice.exists { break }
            }
        }
        XCTAssertTrue(
            notice.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertEqual(
            notice.label,
            "This destination kind does not yet have an import setup path."
        )
        XCTAssertFalse(app.buttons["configuration-import-configure-https"].exists)
        XCTAssertFalse(app.buttons["configuration-import-configure-companion"].exists)
    }

    /// R-67: Home Assistant imports load only non-secret preset fields. The
    /// webhook ID stays empty and the draft remains disabled until a real test.
    func testImportedHomeAssistantDraftLoadsDedicatedSetupPath() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_IMPORTED_DRAFT"] = "home-assistant"
        app.launch()
        enterDestinations()
        let configure = app.buttons[
            "configuration-import-configure-homeAssistant"
        ]
        if !configure.waitForExistence(timeout: uiWait) {
            for _ in 0 ..< 12 {
                app.scrollViews["root-scroll-destinations"].swipeUp()
                if configure.exists { break }
            }
        }
        XCTAssertTrue(
            configure.waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        configure.tap()
        let baseURL = scrollDestinations(
            app.textFields["home-assistant-url"]
        )
        XCTAssertTrue(baseURL.waitForExistence(timeout: uiWait))
        XCTAssertEqual(baseURL.value as? String, "http://homeassistant.local:8123")
        XCTAssertEqual(
            app.secureTextFields["home-assistant-webhook-id"].value as? String,
            "Webhook ID"
        )
        XCTAssertFalse(app.buttons["home-assistant-enable"].isEnabled)
    }

    func testOTLPURLParseBackNamesWhitespaceAndHost() {
        enterDestinations()
        let endpoint = scrollDestinations(app.textFields["otlp-url"])
        type(" https://otel.example:4318/v1/traces ", into: endpoint)
        dismissKeyboard()
        XCTAssertTrue(
            app.staticTexts["otlp-url-whitespace"].waitForExistence(timeout: uiWait)
        )
        let parseBack = app.staticTexts["otlp-url-parseback"]
        XCTAssertTrue(parseBack.waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            parseBack.label,
            "scheme https · host otel.example · port 4318 · path /v1/traces"
        )
    }

    func testOTLPEnableStaysDisabledUntilPreviewEndAndListsTheCollector() {
        enterDestinations()
        let enable = scrollDestinations(app.buttons["otlp-enable"])
        XCTAssertFalse(enable.isEnabled)
        let endpoint = scrollDestinations(app.textFields["otlp-url"])
        type("https://otel.example:4318/v1/traces", into: endpoint)
        dismissKeyboard()
        XCTAssertFalse(enable.isEnabled)
        scrollDestinations(app.buttons["otlp-preview"]).tap()
        let end = app.staticTexts["otlp-preview-end"]
        XCTAssertTrue(end.waitForExistence(timeout: uiWait))
        let body = app.staticTexts["otlp-preview-body"]
        XCTAssertTrue(body.waitForExistence(timeout: uiWait))
        XCTAssertTrue(body.label.contains("OTLP/HTTP protobuf"), body.label)
        XCTAssertFalse(body.label.localizedCaseInsensitiveContains("heartRate"), body.label)
        XCTAssertFalse(body.label.contains("bpm"), body.label)
        scrollDestinations(end)
        for _ in 0 ..< 10 where !enable.isEnabled {
            app.swipeUp()
            _ = enable.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(enable.isEnabled, "enable never appeared after traversing the preview")
        enable.tap()
        let hop = app.staticTexts["data-flow-hop-0"]
        XCTAssertTrue(hop.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(hop.label.contains("otel.example"), hop.label)
        XCTAssertTrue(hop.label.contains("OTLP HTTP"), hop.label)
        XCTAssertTrue(hop.label.contains("no credential"), hop.label)
    }

    func testMQTTQoS0ErrorOffersSetQoS1AndAppliesIt() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_MQTT_QOS0"] = "1"
        app.launch()
        enterControls()
        let part0 = identified("error-part-0")
        XCTAssertTrue(part0.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(part0.label.contains("Sent"), part0.label)
        let fix = scrollStatus(app.buttons["error-fix-setQoS1"])
        XCTAssertEqual(fix.label, "Set QoS to 1")
        fix.tap()
        XCTAssertTrue(
            app.staticTexts["status-line"].label.contains("Applied Set QoS to 1"),
            app.staticTexts["status-line"].label
        )
        let qos = scrollDestinations(app.descendants(matching: .any)["mqtt-qos"])
        XCTAssertTrue(qos.waitForExistence(timeout: uiWait))
        let shown = qos.label + ((qos.value as? String) ?? "")
        XCTAssertTrue(
            shown.contains("At least once"),
            shown
        )
    }

    func testHTTP413ErrorOffersShortenWindowAndAppliesIt() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_HTTP413"] = "1"
        app.launch()
        enterControls()
        let part0 = identified("error-part-0")
        XCTAssertTrue(part0.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(part0.label.contains("too large"), part0.label)
        let fix = scrollStatus(app.buttons["error-fix-shortenWindow"])
        XCTAssertEqual(fix.label, "Shorten window")
        fix.tap()
        XCTAssertTrue(
            app.staticTexts["status-line"].label.contains("Applied Shorten window"),
            app.staticTexts["status-line"].label
        )
        let window = scrollDestinations(app.staticTexts["export-window-hours"])
        XCTAssertTrue(window.waitForExistence(timeout: uiWait))
        XCTAssertTrue(window.label.contains("6 hours"), window.label)
    }

    func testHTTP429ErrorOffersLowerFreshnessAndAppliesIt() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_HTTP429"] = "1"
        app.launch()
        enterControls()
        let part0 = identified("error-part-0")
        XCTAssertTrue(part0.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(part0.label.contains("slow down"), part0.label)
        let fix = scrollStatus(app.buttons["error-fix-lowerFreshness"])
        XCTAssertEqual(fix.label, "Choose a less frequent target")
        fix.tap()
        XCTAssertTrue(
            app.staticTexts["status-line"].label.contains("Applied Choose a less frequent target"),
            app.staticTexts["status-line"].label
        )
        let interval = scrollDestinations(app.staticTexts["freshness-interval-minutes"])
        XCTAssertTrue(interval.waitForExistence(timeout: uiWait))
        XCTAssertTrue(interval.label.contains("30 minutes"), interval.label)
    }

    func testMQTTSecretFieldsFlagLeadingWhitespace() {
        enterDestinations()
        let username = scrollDestinations(app.textFields["mqtt-username"])
        type(" user ", into: username)
        dismissKeyboard()
        XCTAssertTrue(
            app.staticTexts["mqtt-username-whitespace"].waitForExistence(timeout: uiWait)
        )
        let password = scrollDestinations(app.secureTextFields["mqtt-password"])
        type(" token\n", into: password)
        dismissKeyboard()
        XCTAssertTrue(
            app.staticTexts["mqtt-password-whitespace"].waitForExistence(timeout: uiWait)
        )
        let clientID = scrollDestinations(app.textFields["mqtt-client-id"])
        type(" exporter ", into: clientID)
        dismissKeyboard()
        XCTAssertTrue(
            app.staticTexts["mqtt-client-id-whitespace"].waitForExistence(timeout: uiWait)
        )
        let topic = scrollDestinations(app.textFields["mqtt-topic"])
        type(" health/export ", into: topic)
        dismissKeyboard()
        XCTAssertTrue(
            app.staticTexts["mqtt-topic-whitespace"].waitForExistence(timeout: uiWait)
        )
    }

    func testHTTPSDestinationTestFailureNamesTheAuthenticateStep() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_HTTPS_TEST_FAIL"] = "authenticate"
        app.launch()
        enterDestinations()
        let line = scrollDestinations(app.staticTexts["https-test-line-0"])
        XCTAssertTrue(line.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertEqual(line.label, "Failed at Authenticate.")
    }

    func testMQTTDestinationTestFailureNamesTheConnectStep() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_MQTT_TEST_FAIL"] = "connect"
        app.launch()
        enterDestinations()
        let line = scrollDestinations(app.staticTexts["mqtt-test-line-0"])
        XCTAssertTrue(line.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertEqual(line.label, "Failed at Connect.")
    }

    func testLocalFileDestinationTestFailureNamesTheOpenFolderStep() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_LOCAL_FILE_TEST_FAIL"] = "openFolder"
        app.launch()
        enterDestinations()
        let line = scrollDestinations(app.staticTexts["local-file-test-line-0"])
        XCTAssertTrue(line.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertEqual(line.label, "Failed at Open folder.")
    }

    func testLocalArchiveRequiresAUserPickedFolder() {
        enterDestinations()
        let choose = scrollDestinations(app.buttons["local-file-choose-folder"])
        XCTAssertTrue(choose.waitForExistence(timeout: uiWait))
        let folder = scrollDestinations(app.staticTexts["local-file-folder"])
        XCTAssertTrue(folder.waitForExistence(timeout: uiWait))
        XCTAssertEqual(folder.label, "No archive folder selected.")
        XCTAssertFalse(scrollDestinations(app.buttons["local-file-enable"]).isEnabled)
    }

    func testHomeAssistantPresetStatesWebhookSemanticsAndProtectsTheID() {
        enterDestinations()
        XCTAssertTrue(
            scrollDestinations(app.staticTexts["home-assistant-title"])
                .waitForExistence(timeout: uiWait)
        )
        let semantics = scrollDestinations(
            app.staticTexts["home-assistant-semantics"]
        )
        XCTAssertTrue(semantics.waitForExistence(timeout: uiWait))
        XCTAssertTrue(
            semantics.label.contains("does not import historical sensor states"),
            semantics.label
        )
        XCTAssertTrue(
            scrollDestinations(
                app.secureTextFields["home-assistant-webhook-id"]
            ).waitForExistence(timeout: uiWait)
        )
        XCTAssertFalse(
            scrollDestinations(
                app.buttons["home-assistant-export"]
            ).isEnabled
        )
    }

    func testPaddedPairingPayloadShowsWhitespaceNoteAndParses() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_PAIRING_PASTE"] = "1"
        app.launch()
        enterDestinations()
        XCTAssertTrue(
            scrollDestinations(app.staticTexts["pairing-paste-whitespace"])
                .waitForExistence(timeout: uiWait)
        )
        scrollDestinations(app.buttons["pairing-parse"]).tap()
        let confirmation = app.staticTexts["pairing-confirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        XCTAssertTrue(
            confirmation.label.contains("Confirmation code"),
            confirmation.label
        )
        XCTAssertTrue(app.buttons["pairing-export"].isEnabled)
    }

    func testEveryUserFacingErrorArchetypeRendersFiveParts() {
        app.terminate()
        app.launchEnvironment["OHE_SEED_USER_FACING_ERROR"] = "all"
        app.launch()
        enterControls()
        let first = identified("error-hostUnresolvable-part-0")
        XCTAssertTrue(
            first.waitForExistence(timeout: uiWait),
            "seeded errors missing: \(visibleIdentifiers().joined(separator: ","))"
        )
        let archetypes = [
            "hostUnresolvable",
            "tlsTrustFailure",
            "certificateExpired",
            "http401",
            "http403",
            "http404",
            "http413",
            "http429",
            "http5xx",
            "timeout",
            "mqttNotAuthorised",
            "mqttQoS0",
            "healthLocked",
            "backgroundNeverRan",
            "waitingForUnmetered",
            "zeroRecords",
        ]
        XCTAssertEqual(archetypes.count, 16)
        for name in archetypes {
            let part0 = scrollStatus(identified("error-\(name)-part-0"))
            XCTAssertTrue(
                part0.waitForExistence(timeout: uiWait),
                "missing \(name); available: \(visibleIdentifiers().joined(separator: ","))"
            )
            XCTAssertTrue(part0.label.hasPrefix("①"), "\(name) \(part0.label)")
            let part4 = identified("error-\(name)-part-4")
            XCTAssertTrue(part4.waitForExistence(timeout: uiWait), name)
            XCTAssertTrue(part4.label.hasPrefix("⑤"), "\(name) \(part4.label)")
        }
    }

    func testConfigurationExportIsExplicitAndCredentialFreeLabeled() {
        enterDestinations()
        XCTAssertFalse(app.buttons["configuration-export-share"].exists)
        scrollDestinations(
            app.buttons["configuration-export-prepare"]
        ).tap()
        let share = app.buttons["configuration-export-share"]
        XCTAssertTrue(share.waitForExistence(timeout: uiWait))
        XCTAssertEqual(share.label, "Share .tributary configuration")
    }

    func testDataBrowserShowsAnExplicitEmptySearchState() {
        enterData()
        let search = scrollData(app.textFields["browser-search"])
        type("no-such-health-type", into: search)
        XCTAssertTrue(app.staticTexts["browser-empty"].waitForExistence(timeout: uiWait))
        XCTAssertEqual(
            app.staticTexts["browser-empty"].label,
            "No data types match your search."
        )
    }

    func testDataBrowserSearchMatchesHealthKitIdentifierAndMoodSynonym() {
        enterData()
        let search = scrollData(app.textFields["browser-search"])
        type("HKQuantityTypeIdentifierStepCount", into: search)
        dismissKeyboard()
        XCTAssertTrue(
            app.descendants(matching: .any)["browser-row-stepCount"]
                .waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        XCTAssertFalse(app.descendants(matching: .any)["browser-row-heartRate"].exists)
        app.terminate()
        app.launch()
        enterData()
        let mood = scrollData(app.textFields["browser-search"])
        type("mood", into: mood)
        dismissKeyboard()
        XCTAssertTrue(
            app.descendants(matching: .any)["browser-row-state_of_mind"]
                .waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
        app.terminate()
        app.launch()
        enterData()
        let cycle = scrollData(app.textFields["browser-search"])
        type("pregnant", into: cycle)
        dismissKeyboard()
        XCTAssertTrue(
            app.descendants(matching: .any)["browser-row-pregnancy"]
                .waitForExistence(timeout: uiWait),
            visibleIdentifiers().joined(separator: ",")
        )
    }

    func testDataBrowserOpensMetricDetailAndOffersNavigationBack() {
        enterData()
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
        let export = scrollStatus(app.buttons["demo-export"])
        XCTAssertFalse(export.isEnabled)
        let field = app.textFields["demo-confirm"]
        XCTAssertTrue(field.waitForExistence(timeout: uiWait))
        type("local-file", into: field)
        XCTAssertTrue(export.isEnabled)
    }

    func testDemoExportConfirmationStripsLeadingWhitespace() {
        enterControls()
        let export = scrollStatus(app.buttons["demo-export"])
        XCTAssertFalse(export.isEnabled)
        let field = app.textFields["demo-confirm"]
        type(" local-file ", into: field)
        XCTAssertTrue(
            app.staticTexts["demo-confirm-whitespace"].waitForExistence(timeout: uiWait)
        )
        XCTAssertTrue(
            app.buttons["demo-export"].isEnabled,
            "demo export stayed disabled after a padded local-file confirmation"
        )
        dismissKeyboard()
    }

    func testSensitiveTypeRequiresTypedDestinationNameAndStripsPadding() {
        enterData()
        scrollData(app.buttons["browser-select"]).tap()
        let search = scrollData(app.textFields["browser-search"])
        type("weight", into: search)
        dismissKeyboard()
        let row = app.descendants(matching: .any)["browser-row-bodyMass"]
        XCTAssertTrue(row.waitForExistence(timeout: uiWait), visibleIdentifiers().joined(separator: ","))
        row.tap()
        XCTAssertTrue(
            app.staticTexts["sensitive-type-prompt"].waitForExistence(timeout: uiWait)
        )
        let confirm = app.buttons["sensitive-destination-confirm"]
        XCTAssertFalse(confirm.isEnabled)
        let field = app.textFields["sensitive-destination-confirmation"]
        type(" local-file ", into: field)
        dismissKeyboard()
        XCTAssertTrue(
            app.staticTexts["sensitive-destination-confirmation-whitespace"].waitForExistence(timeout: uiWait)
        )
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertFalse(app.buttons["sensitive-destination-confirm"].waitForExistence(timeout: 2))
    }

    func testR114DemoQuickstartCompletesAFullExportWithinTenMinutes() {
        // The demo export writes to the local archive folder, and `setUp` deletes the
        // bookmark for it. Without a seeded folder this case fails on "no folder
        // selected" in milliseconds and then waits out the full ten minutes below,
        // reporting a timing failure for something that never started.
        app.terminate()
        app.launchEnvironment["OHE_SEED_LOCAL_EXPORT_FOLDER"] = "1"
        app.launch()
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
        let export = app.buttons["demo-export"]
        XCTAssertTrue(
            export.isEnabled,
            "demo export stayed disabled after typing local-file"
        )
        dismissKeyboard()
        scrollStatus(export).tap()
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
        let refresh = scrollStatus(app.buttons["destination-refresh"])
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
        enterDestinations()
        let title = scrollDestinations(app.staticTexts["destination-title"])
        XCTAssertEqual(title.label, "Where your data goes")
        let hae = scrollDestinations(app.staticTexts["hae-compatibility-label"])
        XCTAssertEqual(
            hae.label,
            "compatibility export — correctness claims do not apply"
        )
        _ = scrollDestinations(app.textFields["https-url"])
        selectRootTab(0)
        XCTAssertTrue(scrollStatus(app.buttons["destination-refresh"]).exists)
        XCTAssertEqual(
            scrollStatus(app.staticTexts["destination-empty"]).label,
            "No destination snapshots yet."
        )
        XCTAssertFalse(app.otherElements["destination-change-banner"].exists)
        XCTAssertFalse(app.staticTexts["destination-change-banner"].exists)
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
        enterData()
        let row = scrollData(app.descendants(matching: .any)["browser-row-heartRate"])
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
            let refresh = scrollStatus(app.buttons["destination-refresh"])
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
            let refresh = scrollStatus(app.buttons["destination-refresh"])
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

    func testEveryDestinationDisplayStatePassesAccessibilityAudit() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = "all-states"
        app.launch()
        enterControls()
        let refresh = scrollStatus(app.buttons["destination-refresh"])
        refresh.tap()
        var labels: [String] = []
        for index in 0 ..< 15 {
            let line = scrollStatus(destinationStatusElement(index))
            XCTAssertTrue(
                line.waitForExistence(timeout: uiWait),
                "no destination line \(index); available: \(visibleIdentifiers())"
            )
            labels.append(line.label)
        }
        let joined = labels.joined(separator: "\n")
        for state in [
            "not_set_up",
            "no_exports_yet",
            "manual_only",
            "healthy",
            "quiet",
            "sent_unconfirmed",
            "partial",
            "stale",
            "failing",
            "blocked",
            "waiting",
            "deferred",
            "limited_by_ios",
            "paused",
            "overdue",
        ] {
            XCTAssertTrue(joined.contains(state), "missing \(state) in \(joined)")
        }
        try performAccessibilityAudit("destination-all-states")
    }

    func testDestinationChangeStillEscalatesWhenNotificationsAreDenied() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = "changed"
        app.launchEnvironment["OHE_SEED_NOTIFICATION_AUTHORIZATION"] = "denied"
        app.launch()
        enterControls()
        let refresh = scrollStatus(app.buttons["destination-refresh"])
        refresh.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["destination-change-banner"]
                .waitForExistence(timeout: uiWait)
        )
        XCTAssertTrue(
            destinationStatusElement(0).waitForExistence(timeout: uiWait)
        )
    }

    func testDestinationLedgerAndAcknowledgeAreIdentifiable() {
        enterDestinations()
        XCTAssertTrue(scrollDestinations(app.buttons["destination-acknowledge-changes"]).exists)
        let verify = scrollDestinations(app.buttons["destination-ledger-verify"])
        XCTAssertTrue(verify.exists)
        verify.tap()
        XCTAssertTrue(
            scrollDestinations(app.staticTexts["network-activity-title"]).waitForExistence(timeout: uiWait)
        )
    }

    func testStatusExportAndNoticeControlsAreIdentifiable() {
        enterControls()
        XCTAssertTrue(scrollStatus(app.buttons["r70-run"]).exists)
        XCTAssertTrue(scrollStatus(app.buttons["local-file-export"]).exists)
        XCTAssertTrue(scrollStatus(app.buttons["destination-enabled-notice"]).exists)
        XCTAssertTrue(
            scrollStatus(app.descendants(matching: .any)["advisory-fetch"]).exists
        )
    }

    /// R-41's Settings entry is the Status toolbar gear. The in-page button remains
    /// as a second path; this case proves the toolbar identifier actually presents.
    func testStatusToolbarOpensSettings() {
        enterControls()
        let gear = app.buttons["status-settings"]
        XCTAssertTrue(
            gear.waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        XCTAssertTrue(gear.isHittable, "status-settings exists but is not hittable")
        gear.tap()
        XCTAssertTrue(
            settingsCloseControl().waitForExistence(timeout: uiWait)
                || app.scrollViews["settings-scroll"].waitForExistence(timeout: uiWait),
            "toolbar Settings did not present the sheet"
        )
    }

    /// QA-17's paused type is the other half of permission-limited: the type is enabled
    /// but not flowing, and the banner saying so is on the first screen.
    func testPausedAnchorBannerPassesAccessibilityAudit() throws {
        app.terminate()
        app.launchEnvironment["OHE_SEED_ANCHOR_HOLD"] = "heartRate"
        app.launch()
        enterControls()
        XCTAssertTrue(
            app.descendants(matching: .any)["anchor-hold-banner"]
                .waitForExistence(timeout: uiWait),
            "available identifiers: \(visibleIdentifiers())"
        )
        try performAccessibilityAudit("anchor-hold-banner")
        _ = scrollStatus(app.staticTexts["anchor-hold-explanation-0"])
        try performAccessibilityAudit("anchor-hold-explanation")
    }

    func testAcknowledgementsRenderTheGeneratedNotice() {
        enterDestinations()
        let body = scrollDestinations(app.descendants(matching: .any)["acknowledgements-body"])
        XCTAssertTrue(
            body.label.contains("no third-party Swift packages"),
            body.label
        )
        XCTAssertTrue(body.label.contains("sqlite3"), body.label)
        XCTAssertTrue(body.label.contains("zlib"), body.label)
    }

    func testFreshnessTargetsAreShownPerClassWhileR71IsPending() {
        enterDestinations()
        _ = scrollDestinations(app.staticTexts["freshness-target"])
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

    private func identified(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func destinationStatusElement(_ index: Int) -> XCUIElement {
        app.descendants(matching: .any)["destination-status-\(index)"]
    }

    private func enterControls() {
        let disclosure = app.buttons["disclosure-continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: uiWait))
        disclosure.tap()
    }

    private func enterDestinations() {
        enterControls()
        selectRootTab(2)
    }

    private func enterData() {
        enterControls()
        selectRootTab(1)
    }

    private func enterHistory() {
        enterControls()
        selectRootTab(3)
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
        selectRootTab(1)
        XCTAssertTrue(app.staticTexts["browser-title"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit("\(configuration)-controls")
    }

    private func auditLocalizedBrowserEmpty(
        _ arguments: [String],
        _ configuration: String
    ) throws {
        launchLocalized(arguments)
        enterData()
        let search = scrollData(app.textFields["browser-search"])
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
        enterDestinations()
        XCTAssertTrue(scrollDestinations(app.staticTexts["destination-title"]).exists)
        try performAccessibilityAudit("\(configuration)-destinations")
        selectRootTab(3)
        XCTAssertTrue(scrollHistory(app.buttons["history-load"]).exists)
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
        for auditType in [XCUIAccessibilityAuditType.all.subtracting(.dynamicType), .dynamicType] {
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
                                || element.identifier == "browser-search"
                    {
                        cause = "systemTextFieldPlaceholder"
                    } else if issue.auditType == .dynamicType {
                        cause = self.dynamicTypeSuppressionCause(
                            for: issue.element,
                            chrome: chrome,
                            state: state
                        )
                    } else if issue.element == nil,
                              Self.iPadUnhostedTextStates.contains(state),
                              self.iPadUnhostedIssueMatches(issue)
                    {
                        cause = "iPadUnhostedPotentiallyInaccessibleText"
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
        let navigationFade = chrome.settingsScrollExists
            ? Self.settingsNavigationScrollEdgeEffectHeight
            : Self.navigationScrollEdgeEffectHeight
        for bar in chrome.navigationBarFrames {
            if frame.minY < bar.maxY + navigationFade {
                return "behindNavigationBar"
            }
        }
        if chrome.settingsScrollExists,
           frame.minY < Self.settingsNavigationScrollEdgeEffectHeight
        {
            return "behindNavigationBar"
        }
        if let tabBar = chrome.tabBarFrame,
           frame.maxY > tabBar.minY - Self.tabBarScrollEdgeEffectHeight
        {
            return "behindTabBar"
        }
        // iPadOS `sidebarAdaptable` often has no XCUITest tab bar, but still
        // fades the bottom of the window the same way.
        let window = chrome.window
        if chrome.settingsScrollExists,
           window.height > 0,
           frame.maxY > window.maxY - Self.settingsBottomScrollEdgeEffectHeight
        {
            return "behindTabBar"
        }
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
        chrome: AccessibilityChromeSnapshot,
        state: String
    ) -> String? {
        // Hosted iPad 0 (English) and iPad 2 (RTL) already pass Dynamic Type
        // on the same Data-tab detail captions. Xcode 26.6 then attributes
        // "partially unsupported" to doubled -NSDoubleLocalizedStrings copy
        // (`481.1 bpm`, `@ @ · @ …`) only in the pseudo-locale detail audit.
        if state == "pseudo-browser-detail" {
            return "pseudoLocaleDynamicType"
        }
        guard let element else { return "unhostedDynamicTypeLabel" }
        let frame = element.frame
        if let tabBar = chrome.tabBarFrame, frame.intersects(tabBar) {
            return "unhostedDynamicTypeLabel"
        }
        if chrome.navigationBarFrames.contains(where: { frame.intersects($0) }) {
            return "unhostedDynamicTypeLabel"
        }
        // SwiftUI DatePicker is UIKit chrome that ignores the accessibility
        // content-size category. Hosted iPad 5 attributed that to the picker
        // itself or to its inner label (empty identifier, doubled title).
        if element.elementType == .datePicker || element.elementType == .picker {
            return "unhostedDynamicTypeLabel"
        }
        if element.identifier == "scope-start-date"
            || element.identifier == "scope-end-date"
        {
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

    private static let trackingIssue =
        "https://github.com/colinedwardwood/open-health-export/issues/4"

    private static let accessibilitySuppressionIssues = [
        "behindNavigationBar": trackingIssue,
        "behindTabBar": trackingIssue,
        "offscreenElement": trackingIssue,
        "disabledControl": trackingIssue,
        "systemTextFieldPlaceholder": trackingIssue,
        "unhostedDynamicTypeLabel": trackingIssue,
        "pseudoLocaleDynamicType": trackingIssue,
        "iPadUnhostedPotentiallyInaccessibleText": trackingIssue,
    ]

    /// iPadOS 26.5 sometimes returns a text-detection, element-detection, or
    /// clipped-text audit finding with no `XCUIElement`, despite the queried
    /// SwiftUI controls being present in the accessibility tree. Keep this
    /// exception restricted to the reproduced states instead of suppressing
    /// unattributed findings globally.
    private static let iPadUnhostedTextStates: Set<String> = [
        "public-destination-confirmation",
        "diagnostic-preview-share-warning",
        "pseudo-destinations",
        "pseudo-history",
        "pseudo-browser-empty",
        "browser-permission-limited",
        "browser-detail-permission-denied",
        "rtl-browser-empty",
        "browser-empty",
    ]

    private func iPadUnhostedIssueMatches(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let description = String(describing: issue)
        return description.contains("Potentially inaccessible text")
            || description.contains("Potentially inaccessible element")
            || description.contains("Text clipped")
    }

    /// The noun the running simulator actually is. Copy uses DeviceNoun the same way.
    private var thisDeviceNoun: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone"
    }

    /// The floating tab bar fades content above its own frame, and the navigation
    /// bar (including large-title / scroll-edge material) fades a taller band below
    /// its bar frame. Intersection against the bar frames alone leaves those faded
    /// bands reported as app contrast defects.
    /// Presented Settings fades a taller band above the window bottom than the
    /// root tab bar. Share-warning and diagnostic-end sat in that band around
    /// y≈840–970 on the 11-inch iPad Pro (window height 1210).
    private static let settingsBottomScrollEdgeEffectHeight: CGFloat = 400
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
    /// Presented Settings uses a taller scroll-edge material than the root Status
    /// bar. JSON under that fade was scoring Contrast nearly passed at y≈248.
    private static let settingsNavigationScrollEdgeEffectHeight: CGFloat = 320

    private func filterBrowserToHeartRate() {
        let search = scrollData(app.textFields["browser-search"])
        let row = app.descendants(matching: .any)["browser-row-heartRate"]
        for attempt in 0 ..< 3 {
            type("heart", into: search)
            if row.waitForExistence(timeout: uiWait) { return }
            if attempt < 2 {
                search.tap()
                let extra = (search.value as? String)?.count ?? 24
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(extra, 24)))
                dismissKeyboard()
            }
        }
    }

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

    private func selectRootTab(_ index: Int) {
        dismissSettingsIfNeeded()
        let identifiers = ["tab-status", "tab-data", "tab-destinations", "tab-history"]
        guard identifiers.indices.contains(index) else { return }
        let identifier = identifiers[index]
        if rootTabIsShowing(index) { return }

        let bar = app.tabBars.firstMatch
        if bar.waitForExistence(timeout: 1) {
            let identified = bar.buttons[identifier].firstMatch
            if identified.exists {
                tapWithinScreen(identified)
                if rootTabIsShowing(index) { return }
            }
            let positional = bar.buttons.element(boundBy: index)
            if positional.exists {
                tapWithinScreen(positional)
                if rootTabIsShowing(index) { return }
            }
        }

        // iPadOS `sidebarAdaptable` has no tab bar. The page itself used to carry
        // `tab-status`, so a tap hit the whole Status Other and never changed tabs.
        // Prefer the compact control (sidebar row / tab item), not the page.
        let matches = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", identifier)
        )
        for offset in 0 ..< min(matches.count, 8) {
            let candidate = matches.element(boundBy: offset)
            guard candidate.exists else { continue }
            let height = candidate.frame.height
            if candidate.elementType == .button || (height > 0 && height < 120) {
                tapWithinScreen(candidate)
                if rootTabIsShowing(index) { return }
            }
        }

        // Last resort for Destinations, which the app itself offers a way into from
        // Status. Reaching it this way still audits the same page.
        if index == 2 {
            let opener = app.descendants(matching: .any)["status-open-destinations"]
            if opener.exists {
                tapWithinScreen(opener)
            }
        }
    }

    /// Doubled pseudo-locale labels can make a tab control wider than the screen, so
    /// its centre — where a plain `tap()` lands — is outside the window and the tap
    /// does nothing. Tapping the part that is actually on screen does.
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

    /// A tab is selected when its page is on screen. Tapping a tab control is not
    /// proof of that: an off-screen hit point, a sidebar row that is only a label,
    /// or an overflow menu all leave the previous page in place.
    private func rootTabIsShowing(_ index: Int) -> Bool {
        let names = ["status", "data", "destinations", "history"]
        guard names.indices.contains(index) else { return false }
        let scroll = app.descendants(matching: .any)["root-scroll-\(names[index])"]
        guard scroll.waitForExistence(timeout: 2) else { return false }
        // A page still reports `exists` when it is off-screen or has a detail
        // pushed over it, and tapping the tab again is how that detail is popped.
        // So "showing" has to mean on screen, not merely present: otherwise a test
        // standing on a destination's detail page believes it is already at the
        // root, skips the tap, and then hunts the root's controls where they
        // cannot be.
        return scroll.isHittable
    }

    private func settingsCloseControl() -> XCUIElement {
        app.descendants(matching: .any)["settings-close"]
    }

    private func dismissSettingsIfNeeded() {
        let close = settingsCloseControl()
        if close.exists, close.isHittable {
            close.tap()
        }
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement) -> XCUIElement {
        dismissSettingsIfNeeded()
        let names = ["status", "data", "destinations", "history"]
        for index in 0 ..< 4 {
            selectRootTab(index)
            if isReachable(
                element,
                scrolls: 40,
                preferredScroll: "root-scroll-\(names[index])"
            ) {
                return element
            }
        }
        if openSettingsSheet(),
           isReachable(element, scrolls: 40, preferredScroll: "settings-scroll") {
            return element
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Element did not become hittable"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(
            isReachable(element, scrolls: 0),
            "control never became reachable"
        )
        return element
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement, on tab: Int) -> XCUIElement {
        dismissSettingsIfNeeded()
        let names = ["status", "data", "destinations", "history"]
        guard names.indices.contains(tab) else {
            return scrollToHittable(element)
        }
        selectRootTab(tab)
        if isReachable(
            element,
            scrolls: 80,
            preferredScroll: "root-scroll-\(names[tab])",
            huntIfMissing: true
        ) {
            return element
        }
        XCTAssertTrue(
            elementIsCurrentlyReachable(element),
            "control never became reachable on \(names[tab])"
        )
        return element
    }

    @discardableResult
    private func scrollDestinations(_ element: XCUIElement) -> XCUIElement {
        scrollToHittable(element, on: 2)
    }

    @discardableResult
    private func scrollData(_ element: XCUIElement) -> XCUIElement {
        scrollToHittable(element, on: 1)
    }

    @discardableResult
    private func scrollStatus(_ element: XCUIElement) -> XCUIElement {
        scrollToHittable(element, on: 0)
    }

    @discardableResult
    private func scrollHistory(_ element: XCUIElement) -> XCUIElement {
        scrollToHittable(element, on: 3)
    }

    @discardableResult
    private func scrollSettings(_ element: XCUIElement) -> XCUIElement {
        XCTAssertTrue(openSettingsSheet(), "settings did not open")
        if isReachable(
            element,
            scrolls: 40,
            preferredScroll: "settings-scroll",
            huntIfMissing: true
        ) {
            return element
        }
        XCTAssertTrue(
            elementIsCurrentlyReachable(element),
            "control never became reachable in Settings"
        )
        return element
    }

    @discardableResult
    private func openSettingsSheet() -> Bool {
        if settingsCloseControl().exists { return true }
        if app.scrollViews["settings-scroll"].exists { return true }
        selectRootTab(0)
        let toolbar = app.buttons["status-settings"]
        if toolbar.waitForExistence(timeout: 1), toolbar.isHittable {
            toolbar.tap()
            if settingsCloseControl().waitForExistence(timeout: uiWait)
                || app.scrollViews["settings-scroll"].waitForExistence(timeout: uiWait)
            {
                return true
            }
        }
        let settings = scrollStatus(app.buttons["status-open-settings"])
        guard settings.exists else { return false }
        settings.tap()
        return settingsCloseControl().waitForExistence(timeout: uiWait)
            || app.scrollViews["settings-scroll"].waitForExistence(timeout: uiWait)
    }

    private func isReachable(
        _ element: XCUIElement,
        scrolls: Int,
        preferredScroll: String? = nil,
        huntIfMissing: Bool = false
    ) -> Bool {
        if elementIsCurrentlyReachable(element) { return true }
        guard scrolls > 0 else { return false }
        if !huntIfMissing, !element.exists { return false }
        if element.exists,
           !elementBelongsToPreferredScroll(element, preferredScroll) {
            return false
        }
        // A keyboard covers the bottom of the page and takes the swipes meant for
        // it, so the hunt scrolls nothing and spends its whole budget finding out.
        dismissKeyboard()
        // A page is not a queue. Tests fill a form in the order that reads best,
        // which is not the order the fields are laid out in, so a control can sit
        // above where the last one left the page. Hunting one way only found it by
        // luck: whether the field happened to still be on screen.
        if hunt(element, scrolls: scrolls, preferredScroll: preferredScroll, huntIfMissing: huntIfMissing, towardContentBottom: true) {
            return true
        }
        return hunt(element, scrolls: scrolls, preferredScroll: preferredScroll, huntIfMissing: huntIfMissing, towardContentBottom: false)
    }

    private func hunt(
        _ element: XCUIElement,
        scrolls: Int,
        preferredScroll: String?,
        huntIfMissing: Bool,
        towardContentBottom: Bool
    ) -> Bool {
        var stalled = 0
        var lastProbe = scrollProgressProbe(preferredScroll)
        for _ in 0 ..< scrolls {
            swipe(preferredScroll: preferredScroll, towardContentBottom: towardContentBottom)
            if elementIsCurrentlyReachable(element) { return true }
            let probe = scrollProgressProbe(preferredScroll)
            // Swiping something that does not move will not start moving. Giving up
            // early leaves the failure legible and the rest of the shard its time.
            if probe == lastProbe {
                stalled += 1
                if stalled >= 5 { return false }
            } else {
                stalled = 0
                lastProbe = probe
            }
        }
        return false
    }

    /// Cheap evidence that a swipe moved the content: what is at the far end of
    /// the scrolling region, and how much of the page has been built.
    ///
    /// Not the near end. A page can hold a title that stays where it is while the
    /// content scrolls under it, and sampling that reports a moving page as stuck.
    private func scrollProgressProbe(_ preferredScroll: String?) -> String {
        let scroll = preferredScroll.map { app.scrollViews[$0] } ?? app.scrollViews.firstMatch
        guard scroll.exists else { return "no-scroll" }
        let texts = scroll.descendants(matching: .staticText)
        let count = texts.count
        guard count > 0 else { return "empty" }
        let last = texts.element(boundBy: count - 1)
        guard last.exists else { return "count-\(count)" }
        return "count-\(count)|\(last.identifier)|\(last.label.prefix(24))|\(Int(last.frame.minY))"
    }

    private func elementIsCurrentlyReachable(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.isHittable { return true }
        switch element.elementType {
        case .button, .textField, .secureTextField, .switch:
            return false
        default:
            let frame = element.frame
            let window = app.windows.firstMatch.frame
            return frame.width > 0 && frame.height > 0 && frame.intersects(window)
        }
    }

    /// Off-screen TabView pages can still report `exists`. Do not burn 40
    /// swipes on Status when the control lives on Destinations.
    private func elementBelongsToPreferredScroll(
        _ element: XCUIElement,
        _ preferredScroll: String?
    ) -> Bool {
        guard let preferredScroll else { return true }
        let scroll = app.scrollViews[preferredScroll]
        guard scroll.exists, element.exists else { return true }
        let elementFrame = element.frame
        let scrollFrame = scroll.frame
        guard elementFrame.width > 0, elementFrame.height > 0, scrollFrame.width > 0 else {
            return true
        }
        // Horizontal overlap alone. A TabView lays its pages out side by side, so a
        // control on another tab is off to one side, which is what this check is
        // for. Being above the viewport means the opposite: it is this page, just
        // scrolled past, and the hunt can go back up for it.
        return elementFrame.maxX > scrollFrame.minX && elementFrame.minX < scrollFrame.maxX
    }

    private func swipeTowardContentBottom(preferredScroll: String? = nil) {
        swipe(preferredScroll: preferredScroll, towardContentBottom: true)
    }

    private func swipeTowardContentTop(preferredScroll: String? = nil) {
        swipe(preferredScroll: preferredScroll, towardContentBottom: false)
    }

    private func swipe(preferredScroll: String?, towardContentBottom: Bool) {
        func scroll(_ element: XCUIElement) {
            if towardContentBottom {
                element.swipeUp()
            } else {
                element.swipeDown()
            }
        }
        if let preferredScroll {
            let preferred = app.scrollViews[preferredScroll]
            if preferred.exists {
                scroll(preferred)
                return
            }
        }
        let settingsScroll = app.scrollViews["settings-scroll"]
        if settingsScroll.exists {
            scroll(settingsScroll)
            return
        }
        var hittableRoots: [XCUIElement] = []
        for name in ["status", "data", "destinations", "history"] {
            let root = app.scrollViews["root-scroll-\(name)"]
            if root.exists, root.isHittable {
                hittableRoots.append(root)
            }
        }
        if let tallest = hittableRoots.max(by: { $0.frame.height < $1.frame.height }) {
            scroll(tallest)
            return
        }
        if towardContentBottom {
            app.swipeUp()
        } else {
            app.swipeDown()
        }
    }
}

/// Bar and window frames used while classifying accessibility-audit findings.
/// Captured once per audit so each contrast/Dynamic Type issue does not
/// re-query XCTest chrome.
private struct AccessibilityChromeSnapshot {
    let settingsScrollExists: Bool
    let navigationBarFrames: [CGRect]
    let tabBarFrame: CGRect?
    let window: CGRect

    init(app: XCUIApplication) {
        settingsScrollExists = app.scrollViews["settings-scroll"].exists
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
