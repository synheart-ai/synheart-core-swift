import XCTest

final class SessionStopUITests: XCTestCase {
    func testSessionLiveBehaviorCounterRefreshesAfterInteraction() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--prepare-session-stop-ui-test"]
        app.launch()

        let sessionTab = app.tabBars.buttons["Session"]
        XCTAssertTrue(sessionTab.waitForExistence(timeout: 10))
        sessionTab.tap()

        let behaviorCount = app.staticTexts["session.metric.behavior"]
        for _ in 0..<4 where !behaviorCount.exists {
            app.swipeUp()
        }
        XCTAssertTrue(behaviorCount.waitForExistence(timeout: 30))

        // Tab changes are real behavior interactions collected by the example.
        app.tabBars.buttons["HSI"].tap()
        sessionTab.tap()
        app.tabBars.buttons["Data"].tap()
        sessionTab.tap()

        let counterAdvanced = expectation(
            for: NSPredicate(format: "label != '0'"),
            evaluatedWith: behaviorCount
        )
        wait(for: [counterAdvanced], timeout: 10)
        XCTAssertNotEqual(behaviorCount.label, "0")
    }

    func testStopButtonClosesPreparedSession() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--prepare-session-stop-ui-test"]
        app.launch()

        let sessionTab = app.tabBars.buttons["Session"]
        XCTAssertTrue(sessionTab.waitForExistence(timeout: 10))
        sessionTab.tap()

        let stopButton = app.buttons["session.stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 30))
        XCTAssertTrue(stopButton.isHittable)
        stopButton.tap()

        let stopButtonDisappeared = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: stopButton
        )
        wait(for: [stopButtonDisappeared], timeout: 30)
        XCTAssertFalse(stopButton.exists)

        let startButton = app.buttons["session.start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        XCTAssertTrue(startButton.isEnabled)
        XCTAssertTrue(startButton.isHittable)
        startButton.tap()

        XCTAssertTrue(stopButton.waitForExistence(timeout: 30))
        XCTAssertTrue(stopButton.isHittable)
        stopButton.tap()

        let secondStopButtonDisappeared = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: stopButton
        )
        wait(for: [secondStopButtonDisappeared], timeout: 30)
        XCTAssertFalse(stopButton.exists)
    }
}
