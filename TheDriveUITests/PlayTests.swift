import XCTest

final class PlayTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testMarketplaceOpeningCanBeSkippedIntoGameplay() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["MARKET ROAD"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["REAR GUN"].exists)
        capture("Marketplace title and automatic background drive")
        app.buttons["HIT THE ROAD"].tap()
        XCTAssertTrue(app.buttons["SKIP INTRO"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["REAR GUN"].exists, "Driving controls should wait for the cinematic handover.")
        capture("Bazaar opening cutscene")
        app.buttons["SKIP INTRO"].tap()
        XCTAssertTrue(app.buttons["REAR GUN"].waitForExistence(timeout: 3))
        let initialLabel = app.buttons["Unmute music"].exists ? "Unmute music" : "Mute music"
        let toggledLabel = initialLabel == "Mute music" ? "Unmute music" : "Mute music"
        XCTAssertTrue(app.buttons[initialLabel].exists)
        app.buttons[initialLabel].tap()
        XCTAssertTrue(app.buttons[toggledLabel].exists)
        app.buttons[toggledLabel].tap()
        XCTAssertTrue(app.buttons[initialLabel].exists)
    }

    func testDrivingMirrorBecomesLiveAndSteeringWorks() {
        let app = launchRun()
        let mirror = app.descendants(matching: .any).matching(identifier: "Live rear view mirror").firstMatch
        XCTAssertTrue(mirror.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "value == %@", "Live"), evaluatedWith: mirror)
        waitForExpectations(timeout: 5)
        app.buttons["Steer left"].press(forDuration: 0.2)
        capture("Driving with rear mirror")
    }

    func testManualAimFireAndReturnToSeat() {
        let app = launchRun()
        app.buttons["REAR GUN"].tap()
        XCTAssertTrue(app.buttons["DRIVE"].waitForExistence(timeout: 4), "The driver must finish moving to the gun.")
        XCTAssertTrue(app.staticTexts["REAR GUN · MANUAL AIM"].exists)
        let aim = app.descendants(matching: .any).matching(identifier: "Aim rear gun").firstMatch
        XCTAssertTrue(aim.exists)
        let originalAim = aim.value as? String
        let start = aim.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = aim.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertNotEqual(aim.value as? String, originalAim)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Daytime sunglass road reflection").firstMatch.exists)
        app.buttons["Fire rear gun"].press(forDuration: 0.5)
        capture("Manual rear gun view")
        app.buttons["DRIVE"].tap()
        XCTAssertTrue(app.buttons["REAR GUN"].waitForExistence(timeout: 4), "The driver must return to the seat.")
        XCTAssertTrue(app.staticTexts["DRIVING · KEEP MOVING"].exists)
    }

    func testNightDrivingAndUnavailableSunglassReflection() {
        let app = launchRun()
        app.buttons["Toggle day and night"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Live rear view mirror").firstMatch.exists)
        capture("Night driving")
        app.buttons["REAR GUN"].tap()
        XCTAssertTrue(app.buttons["DRIVE"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Sunglass reflection unavailable at night").firstMatch.exists)
        capture("Night gun without sunglass reflection")
    }

    private func launchRun() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["HIT THE ROAD"].waitForExistence(timeout: 10))
        app.buttons["HIT THE ROAD"].tap()
        let skip = app.buttons["SKIP INTRO"]
        XCTAssertTrue(skip.waitForExistence(timeout: 3))
        skip.tap()
        XCTAssertTrue(app.buttons["REAR GUN"].waitForExistence(timeout: 3))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
