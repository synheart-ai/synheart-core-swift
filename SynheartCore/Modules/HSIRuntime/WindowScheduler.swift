import Foundation

/// Callback for window events
public typealias WindowCallback = (WindowType) -> Void

/// Schedules window-based computation
public class WindowScheduler {
    private var timer30s: Timer?
    private var timer5m: Timer?
    private var timer1h: Timer?
    private var timer24h: Timer?
    
    private let onWindow: WindowCallback
    
    public init(onWindow: @escaping WindowCallback) {
        self.onWindow = onWindow
    }
    
    /// Start scheduling windows
    public func start() {
        // 30-second window
        timer30s = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.onWindow(.window30s)
        }
        
        // 5-minute window
        timer5m = Timer.scheduledTimer(withTimeInterval: 5 * 60.0, repeats: true) { [weak self] _ in
            self?.onWindow(.window5m)
        }
        
        // 1-hour window
        timer1h = Timer.scheduledTimer(withTimeInterval: 60 * 60.0, repeats: true) { [weak self] _ in
            self?.onWindow(.window1h)
        }
        
        // 24-hour window
        timer24h = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60.0, repeats: true) { [weak self] _ in
            self?.onWindow(.window24h)
        }
        
        // Trigger initial computation immediately
        DispatchQueue.main.async { [weak self] in
            self?.onWindow(.window30s)
            self?.onWindow(.window5m)
            self?.onWindow(.window1h)
            self?.onWindow(.window24h)
        }
    }
    
    /// Stop scheduling
    public func stop() {
        timer30s?.invalidate()
        timer5m?.invalidate()
        timer1h?.invalidate()
        timer24h?.invalidate()
        
        timer30s = nil
        timer5m = nil
        timer1h = nil
        timer24h = nil
    }
}

