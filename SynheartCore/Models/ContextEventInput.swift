import Foundation

/// Keyboard event classes the context engine distinguishes.
public enum KeyboardEventType: String, CaseIterable, Codable, Sendable {
    case typingTap = "TypingTap"
    case navigationKey = "NavigationKey"
    case backspace = "Backspace"
    case delete = "Delete"
    case enter = "Enter"
    case tab = "Tab"
    case escape = "Escape"
    case modifierKey = "ModifierKey"
    case functionKey = "FunctionKey"
}

/// Pointer event classes the context engine distinguishes.
public enum MouseEventType: String, CaseIterable, Codable, Sendable {
    case move = "Move"
    case leftClick = "LeftClick"
    case rightClick = "RightClick"
    case scroll = "Scroll"
}

/// Coarse scroll magnitude for a pointer scroll event.
public enum ScrollMagnitude: String, CaseIterable, Codable, Sendable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
}

/// Editing shortcuts the context engine recognises.
public enum ShortcutType: String, CaseIterable, Codable, Sendable {
    case copy = "Copy"
    case paste = "Paste"
    case cut = "Cut"
    case undo = "Undo"
    case redo = "Redo"
    case selectAll = "SelectAll"
    case save = "Save"
}

/// One event for `synheart_core_push_context_event`.
///
/// Context events are raw interaction evidence the runtime's context engine
/// turns into the 12-class context label itself. Send events, never a label:
/// two-letter application codes collide with live label codes.
///
/// The wire form is an externally tagged object, `{ "<Variant>": { ...fields } }`.
/// Field spellings follow the runtime (`timestamp_ms`, `is_key_down`, …), and
/// the enum spellings are the runtime's PascalCase variant names — note that
/// scroll directions here are `Up`/`Down`, unlike the lowercase spelling on
/// ``BehaviorEventInput``.
public struct ContextEventInput: Equatable, Sendable {
    /// The externally-tagged variant name (`Keyboard`, `Mouse`, `Shortcut`).
    public let variant: String
    /// The variant's fields.
    public let fields: [String: JSONValue]

    init(variant: String, fields: [String: JSONValue]) {
        self.variant = variant
        self.fields = fields
    }

    public static func keyboard(_ tsMs: Int64, _ eventType: KeyboardEventType, isKeyDown: Bool = true) -> ContextEventInput {
        .init(variant: "Keyboard", fields: [
            "timestamp_ms": .int(Int(tsMs)),
            "is_key_down": .bool(isKeyDown),
            "event_type": .string(eventType.rawValue),
        ])
    }

    public static func mouse(
        _ tsMs: Int64,
        _ eventType: MouseEventType,
        deltaMagnitude: Double? = nil,
        scrollDirection: ScrollDirection? = nil,
        scrollMagnitude: ScrollMagnitude? = nil
    ) -> ContextEventInput {
        var f: [String: JSONValue] = [
            "timestamp_ms": .int(Int(tsMs)),
            "event_type": .string(eventType.rawValue),
        ]
        f["delta_magnitude"] = deltaMagnitude.map { JSONValue.double($0) } ?? .null
        f["scroll_direction"] = scrollDirection.map { JSONValue.string($0.contextWire) } ?? .null
        f["scroll_magnitude"] = scrollMagnitude.map { JSONValue.string($0.rawValue) } ?? .null
        return .init(variant: "Mouse", fields: f)
    }

    public static func shortcut(_ tsMs: Int64, _ shortcutType: ShortcutType) -> ContextEventInput {
        .init(variant: "Shortcut", fields: [
            "timestamp_ms": .int(Int(tsMs)),
            "shortcut_type": .string(shortcutType.rawValue),
        ])
    }

    /// A text change from a text field, classified as a typing tap or a
    /// backspace. Use when the host sees edits but not individual keys.
    public static func textChange(_ tsMs: Int64, isDeletion: Bool) -> ContextEventInput {
        keyboard(tsMs, isDeletion ? .backspace : .typingTap)
    }

    /// Epoch milliseconds of the event.
    public var tsMs: Int64 {
        if case .int(let v)? = fields["timestamp_ms"] { return Int64(v) }
        return 0
    }

    /// The JSON object the runtime parses.
    public func toJSON() -> [String: Any] {
        [variant: JSONValue.foundation(from: fields)]
    }

    /// Serialised wire form, or nil if the payload cannot be encoded.
    public func toJSONString() -> String? {
        JSONValue.encode(toJSON())
    }
}

extension ScrollDirection {
    /// PascalCase spelling used inside context events.
    var contextWire: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}
