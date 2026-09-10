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
        ]
        app.launch()
    }

    func testDisclosurePrecedesHealthPermissionControl() {
        let disclosure = app.buttons["disclosure-continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: uiWait))
        XCTAssertFalse(app.buttons["health-request"].exists)

        disclosure.tap()
        XCTAssertTrue(app.buttons["health-request"].waitForExistence(timeout: uiWait))
        XCTAssertTrue(app.buttons["history-load"].exists)
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

        let share = app.buttons["diagnostic-share"]
        XCTAssertTrue(share.waitForExistence(timeout: uiWait))
        XCTAssertGreaterThan(share.frame.minY, end.frame.minY)
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

    func testDestinationSectionExposesTheEmptyStateAndRefreshControl() {
        enterControls()
        let title = scrollToHittable(app.staticTexts["destination-title"])
        XCTAssertEqual(title.label, "Where your data goes")
        XCTAssertTrue(app.buttons["destination-refresh"].exists)
        XCTAssertEqual(
            app.staticTexts["destination-empty"].label,
            "No destination snapshots yet."
        )
        XCTAssertFalse(app.otherElements["destination-change-banner"].exists)
        XCTAssertFalse(app.staticTexts["destination-change-banner"].exists)
    }

    private func enterControls() {
        let disclosure = app.buttons["disclosure-continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: uiWait))
        disclosure.tap()
    }

    private func performAccessibilityAudit() throws {
        try app.performAccessibilityAudit { issue in
            // Xcode 26 audits system-rendered disabled SwiftUI controls as low
            // contrast. Suppress only that exact SDK-owned state; all enabled
            // contrast findings and every other audit type still fail.
            // Tracking: https://github.com/colinedwardwood/open-health-export/issues/4
            issue.auditType == .contrast && issue.element?.isEnabled == false
        }
    }

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
