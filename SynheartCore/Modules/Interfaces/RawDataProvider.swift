import Foundation

/// Protocols for modules to expose raw buffered data to the runtime pipeline.
///
/// RFC-CORE-0007: Core caches buffer raw data only. Feature computation,
/// fusion, embedding, and HSV construction are delegated to Flux.

/// Provides raw wear samples for a given window.
public protocol RawWearDataProvider: AnyObject {
    func rawSamples(_ window: WindowType) -> [WearSample]
}

/// Provides raw phone data points for a given window.
public protocol RawPhoneDataProvider: AnyObject {
    func rawDataPoints(_ window: WindowType) -> [PhoneDataPoint]
}

/// Provides raw behavior events for a given window.
public protocol RawBehaviorDataProvider: AnyObject {
    func rawEvents(_ window: WindowType) -> [BehaviorEvent]
}
