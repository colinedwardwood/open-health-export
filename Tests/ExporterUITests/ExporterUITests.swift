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
        app.keyboards.buttons["return"].tap()
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
        // A failure still says when it last worked, which is what makes it reportable.
        XCTAssertTrue(failed.contains("last success"), failed)
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
        XCTAssertTrue(app.staticTexts["destination-status-0"].waitForExistence(timeout: uiWait))
    }

    private func destinationLine(seeding scenario: String) -> String {
        app.terminate()
        app.launchEnvironment["OHE_SEED_DESTINATION_STATUS"] = scenario
        app.launch()
        enterControls()
        let refresh = scrollToHittable(app.buttons["destination-refresh"])
        refresh.tap()
        let line = app.staticTexts["destination-status-0"]
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

    /// SEC-45: sharing ends our protection over those bytes, so consent is a tap on the
    /// warning rather than an inference from a tap on the share button.
    func testShareWarningIsShownOnceAndGatesTheShareControl() {
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

    func testDataBrowserSelectAndEmptyMeasurementsAreVisibleAfterDisclosure() {
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

    func testDisclosurePassesAccessibilityAuditInPseudoLocaleAndRTL() throws {
        app.terminate()
        app.launchArguments += [
            "-NSDoubleLocalizedStrings", "YES",
            "-NSForceRightToLeftWritingDirection", "YES",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["disclosure-continue"].waitForExistence(timeout: uiWait))
        try performAccessibilityAudit()
        enterControls()
        try performAccessibilityAudit()
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
        let line = app.staticTexts["destination-status-0"]
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
            let line = app.staticTexts["destination-status-0"]
            XCTAssertTrue(
                line.waitForExistence(timeout: uiWait),
                "no destination line for \(scenario); available: \(visibleIdentifiers())"
            )
            try performAccessibilityAudit("destination-\(scenario)")
        }
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

    private func enterControls() {
        let disclosure = app.buttons["disclosure-continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: uiWait))
        disclosure.tap()
    }

    private func performAccessibilityAudit(_ state: String = #function) throws {
        try app.performAccessibilityAudit { issue in
            guard issue.auditType == .contrast, let element = issue.element else {
                return false
            }
            guard let cause = Self.suppressionCause(for: element) else { return false }
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
        app.keyboards.buttons["return"].tap()
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
