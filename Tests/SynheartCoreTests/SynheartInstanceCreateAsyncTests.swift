import XCTest
@testable import SynheartCore

final class SynheartInstanceCreateAsyncTests: XCTestCase {
    /// The async factory runs the same initializer, so its validation errors
    /// must reach the caller rather than being swallowed on the background
    /// queue.
    func testCreatePropagatesInitializerErrors() async {
        let config = SynheartConfig(appId: "", subjectId: "usr_123", mode: .personal)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("synheart-instance-\(UUID().uuidString)")
        do {
            _ = try await SynheartInstance.create(config: config, dataDirectory: dir)
            XCTFail("expected an invalid config to throw")
        } catch {
            // Expected.
        }
    }
}
