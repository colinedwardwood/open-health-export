import XCTest

final class ExporterUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ohe.disclosureAcknowledged", "false",
            "-ohe.advisoryEnabled", "false",
        ]
        app.launch()
    }

    func testDisclosurePrecedesHealthPermissionControl() {
        let disclosure = app.buttons["disclosure-continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["health-request"].exists)

        disclosure.tap()
        XCTAssertTrue(app.buttons["health-request"].waitForExistence(timeout: 2))
    }

    func testDiagnosticShareDoesNotExistBeforeFullPreviewConfirmation() {
        enterControls()
        let build = scrollToHittable(app.buttons["diagnostic-build"])
        XCTAssertFalse(app.buttons["diagnostic-share"].exists)
        build.tap()

        let confirm = scrollToHittable(app.buttons["diagnostic-confirm"])
        XCTAssertFalse(app.buttons["diagnostic-share"].exists)
        confirm.tap()
        XCTAssertTrue(app.buttons["diagnostic-share"].waitForExistence(timeout: 2))
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
                .waitForExistence(timeout: 5)
        )
    }

    func testDataBrowserSelectAndEmptyMeasurementsAreVisibleAfterDisclosure() {
        enterControls()
        XCTAssertTrue(app.staticTexts["browser-title"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["browser-title"].label, "Data")
        XCTAssertTrue(app.buttons["browser-select"].exists)
        XCTAssertFalse(app.buttons["browser-review"].exists)
        app.buttons["browser-select"].tap()
        XCTAssertTrue(app.buttons["browser-invert-routine"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["browser-clear-all"].exists)
        XCTAssertTrue(app.buttons["browser-review"].exists)
        XCTAssertTrue(app.staticTexts["Measurements"].exists == false)
    }

    func testDemoExportStaysDisabledUntilTypedConfirmation() {
        enterControls()
        let export = scrollToHittable(app.buttons["demo-export"])
        XCTAssertFalse(export.isEnabled)
        let field = app.textFields["demo-confirm"]
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText("local-file")
        XCTAssertTrue(export.isEnabled)
    }

    private func enterControls() {
        let disclosure = app.buttons["disclosure-continue"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        disclosure.tap()
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement) -> XCUIElement {
        for _ in 0 ..< 12 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        return element
    }
}
