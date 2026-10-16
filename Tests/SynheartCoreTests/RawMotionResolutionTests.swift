import XCTest
@testable import SynheartCore

final class RawMotionResolutionTests: XCTestCase {

    func testOffByDefaultOutsideResearchCapture() {
        XCTAssertFalse(SynheartConfig().resolvedEmitRawMotionSamples)
        XCTAssertFalse(SynheartConfig(mode: .insight).resolvedEmitRawMotionSamples)
    }

    func testResearchModeTurnsRawMotionOn() {
        XCTAssertTrue(SynheartConfig(mode: .research).resolvedEmitRawMotionSamples)
    }

    func testResearchBaselineTurnsRawMotionOn() {
        XCTAssertTrue(SynheartConfig(researchBaseline: true).resolvedEmitRawMotionSamples)
    }

    func testAnExplicitTrueEnablesItInAnyMode() {
        XCTAssertTrue(SynheartConfig(emitRawMotionSamples: true).resolvedEmitRawMotionSamples)
    }

    func testRawSamplingRunsAtFiftyHertz() {
        XCTAssertEqual(CoreMotionCollector.rawSampleInterval, 0.02, accuracy: 1e-9)
        XCTAssertEqual(CoreMotionCollector.defaultInterval, 0.1, accuracy: 1e-9)
        XCTAssertEqual(CoreMotionCollector().updateInterval, 0.1, accuracy: 1e-9)
    }
}
