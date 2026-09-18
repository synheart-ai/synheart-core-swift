import XCTest
@testable import SynheartCore

final class ContextEventInputTests: XCTestCase {
    private func decode(_ event: ContextEventInput) throws -> [String: Any] {
        let json = try XCTUnwrap(event.toJSONString())
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try XCTUnwrap(obj as? [String: Any])
    }

    func testKeyboardIsExternallyTagged() throws {
        let obj = try decode(.keyboard(1_000, .typingTap))
        XCTAssertEqual(obj.keys.sorted(), ["Keyboard"])
        let fields = try XCTUnwrap(obj["Keyboard"] as? [String: Any])
        XCTAssertEqual(fields["timestamp_ms"] as? Int, 1_000)
        XCTAssertEqual(fields["is_key_down"] as? Bool, true)
        XCTAssertEqual(fields["event_type"] as? String, "TypingTap")
    }

    func testMouseCarriesNullForAbsentOptionalFields() throws {
        let obj = try decode(.mouse(2_000, .scroll, scrollDirection: .up, scrollMagnitude: .large))
        let fields = try XCTUnwrap(obj["Mouse"] as? [String: Any])
        XCTAssertEqual(fields["event_type"] as? String, "Scroll")
        XCTAssertEqual(fields["scroll_direction"] as? String, "Up", "context events spell directions in PascalCase")
        XCTAssertEqual(fields["scroll_magnitude"] as? String, "Large")
        XCTAssertTrue(fields["delta_magnitude"] is NSNull, "absent optional fields are explicit nulls on this path")
    }

    func testShortcut() throws {
        let obj = try decode(.shortcut(3_000, .selectAll))
        let fields = try XCTUnwrap(obj["Shortcut"] as? [String: Any])
        XCTAssertEqual(fields["shortcut_type"] as? String, "SelectAll")
        XCTAssertEqual(fields["timestamp_ms"] as? Int, 3_000)
    }

    func testTextChangeMapsToTypingTapOrBackspace() {
        XCTAssertEqual(ContextEventInput.textChange(1, isDeletion: false), .keyboard(1, .typingTap))
        XCTAssertEqual(ContextEventInput.textChange(1, isDeletion: true), .keyboard(1, .backspace))
    }

    func testTimestampAccessor() {
        XCTAssertEqual(ContextEventInput.keyboard(42, .enter).tsMs, 42)
        XCTAssertEqual(ContextEventInput.mouse(7, .move).tsMs, 7)
    }

    func testWireSpellingsMatchRuntimeVariants() {
        XCTAssertEqual(KeyboardEventType.allCases.map(\.rawValue),
                       ["TypingTap", "NavigationKey", "Backspace", "Delete", "Enter", "Tab", "Escape", "ModifierKey", "FunctionKey"])
        XCTAssertEqual(MouseEventType.allCases.map(\.rawValue), ["Move", "LeftClick", "RightClick", "Scroll"])
        XCTAssertEqual(ShortcutType.allCases.map(\.rawValue), ["Copy", "Paste", "Cut", "Undo", "Redo", "SelectAll", "Save"])
        XCTAssertEqual(ScrollDirection.allCases.map(\.rawValue), ["up", "down", "left", "right"])
    }
}
