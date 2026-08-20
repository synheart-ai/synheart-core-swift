import XCTest

final class SessionStopUITests: XCTestCase {
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
