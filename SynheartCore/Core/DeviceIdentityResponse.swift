import Foundation

enum DeviceIdentityResponse {
    static func decode(_ raw: String?, operation: String) throws -> [String: Any] {
        guard let raw, let data = raw.data(using: .utf8),
              let map = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NativeOperationFailure(code: "DEVICE_IDENTITY_NO_RESULT", reason: .unknown,
                                         message: "\(operation) returned no valid result")
        }
        if let failure = NativeOperationFailure.fromRuntimeMap(map, fallback: "\(operation) failed") {
            throw failure
        }
        return map
    }
}
