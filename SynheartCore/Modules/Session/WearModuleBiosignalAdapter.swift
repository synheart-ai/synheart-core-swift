import Foundation
import Combine
import SynheartSession

/// Adapts `WearModule.rawSamplePublisher` into the `BiosignalProvider`
/// protocol expected by `SessionEngine`.
///
/// Converts `WearSample` (Core) → `BiosignalSample` (SynheartSession) and
/// bridges the Combine publisher into the callback-based streaming API.
class WearModuleBiosignalAdapter: BiosignalProvider {

    private let rawSamplePublisher: AnyPublisher<WearSample, Never>
    private var cancellable: AnyCancellable?

    var isAvailable: Bool { true }
    var name: String { "wear_module" }

    init(rawSamplePublisher: AnyPublisher<WearSample, Never>) {
        self.rawSamplePublisher = rawSamplePublisher
    }

    func startStreaming(onSample: @escaping (BiosignalSample) -> Void) throws {
        cancellable = rawSamplePublisher
            .compactMap { wearSample -> BiosignalSample? in
                guard let bpm = wearSample.hr else { return nil }
                let timestampMs = Int64(wearSample.timestamp.timeIntervalSince1970 * 1000)
                return BiosignalSample(
                    timestampMs: timestampMs,
                    bpm: bpm,
                    rrIntervalsMs: wearSample.rrIntervals,
                    deviceId: nil,
                    source: "wear_module"
                )
            }
            .sink { sample in
                onSample(sample)
            }
    }

    func stopStreaming() {
        cancellable?.cancel()
        cancellable = nil
    }
}
