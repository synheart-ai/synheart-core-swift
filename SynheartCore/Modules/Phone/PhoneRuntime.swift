import Foundation

protocol PhoneRuntimeSinking: AnyObject {
    func pushAccel(tsMs: Int64, x: Double, y: Double, z: Double)
}

extension SynheartCoreShim: PhoneRuntimeSinking {}

