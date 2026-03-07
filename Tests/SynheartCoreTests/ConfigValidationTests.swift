import XCTest
@testable import SynheartCore

final class ConfigValidationTests: XCTestCase {

    func testValidConfigPasses() {
        let config = SynheartConfig(
            appId: "com.test.app",
            subjectId: "usr_123",
            mode: .personal
        )
        XCTAssertNoThrow(try config.validate())
    }

    func testResearchModeRequiresAllowResearch() {
        let config = SynheartConfig(
            appId: "com.test.app",
            subjectId: "usr_123",
            mode: .research,
            privacy: PrivacyConfig(allowResearch: false)
        )
        XCTAssertThrowsError(try config.validate()) { error in
            XCTAssertTrue(error is SynheartCoreError)
            if case SynheartCoreError.researchNotAllowed = error {} else {
                XCTFail("Expected researchNotAllowed, got \(error)")
            }
        }
    }

    func testResearchModeWithAllowResearchPasses() {
        let config = SynheartConfig(
            appId: "com.test.app",
            subjectId: "usr_123",
            mode: .research,
            privacy: PrivacyConfig(allowResearch: true)
        )
        XCTAssertNoThrow(try config.validate())
    }

    func testEmptyAppIdFails() {
        let config = SynheartConfig(
            appId: "",
            subjectId: "usr_123",
            mode: .personal
        )
        XCTAssertThrowsError(try config.validate()) { error in
            if case SynheartCoreError.notConfigured(let msg) = error {
                XCTAssertTrue(msg.contains("appId"))
            } else {
                XCTFail("Expected notConfigured error, got \(error)")
            }
        }
    }

    func testEmptySubjectIdFails() {
        let config = SynheartConfig(
            appId: "com.test.app",
            subjectId: "",
            mode: .personal
        )
        XCTAssertThrowsError(try config.validate()) { error in
            if case SynheartCoreError.notConfigured = error {} else {
                XCTFail("Expected notConfigured error, got \(error)")
            }
        }
    }

    func testPipeInSubjectIdFails() {
        let config = SynheartConfig(
            appId: "com.test.app",
            subjectId: "usr|bad",
            mode: .personal
        )
        XCTAssertThrowsError(try config.validate()) { error in
            if case SynheartCoreError.invalidMode = error {} else {
                XCTFail("Expected invalidMode error, got \(error)")
            }
        }
    }
}
