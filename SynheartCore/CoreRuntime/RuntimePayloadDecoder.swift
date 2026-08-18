import Foundation

enum RuntimePayloadDecoder {
    static func dictionary(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Runtime array payloads sometimes contain JSON objects encoded again as
    /// strings. Normalize both representations at the SDK boundary.
    static func dictionaryArray(
        _ json: String,
        acceptingJSONStringElements: Bool = false
    ) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }

        return values.compactMap { value in
            if let dictionary = value as? [String: Any] {
                return dictionary
            }
            guard acceptingJSONStringElements,
                  let nestedJson = value as? String else { return nil }
            return dictionary(nestedJson)
        }
    }
}
