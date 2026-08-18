import XCTest
@testable import SynheartCore

final class RuntimeDataDirectoryTests: XCTestCase {
    func testPrepareCreatesStableSynheartCoreDirectory() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        let path = try RuntimeDataDirectory.prepare(
            using: fileManager,
            applicationSupportDirectory: testRoot
        )

        var isDirectory: ObjCBool = false
        XCTAssertTrue(fileManager.fileExists(atPath: path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(URL(fileURLWithPath: path).lastPathComponent, "SynheartCore")
        XCTAssertEqual(
            try RuntimeDataDirectory.prepare(
                using: fileManager,
                applicationSupportDirectory: testRoot
            ),
            path
        )
    }
}
