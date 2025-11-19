import Foundation

/// Module lifecycle status
public enum ModuleStatus {
    case uninitialized
    case initializing
    case initialized
    case starting
    case running
    case stopping
    case stopped
    case error
    case disposed
}

/// Base protocol for all Synheart modules
///
/// Each module (Wear, Phone, Behavior, HSI Runtime, etc.) conforms to this protocol
/// to ensure consistent lifecycle management.
public protocol SynheartModule: AnyObject {
    /// Module identifier
    var moduleId: String { get }

    /// Current module status
    var status: ModuleStatus { get }

    /// Whether this module is currently enabled
    var isEnabled: Bool { get }

    /// Initialize the module with required dependencies
    func initialize() async throws

    /// Start the module's operation
    func start() async throws

    /// Stop the module's operation (can be restarted)
    func stop() async throws

    /// Dispose of all resources (final cleanup)
    func dispose() async throws
}

/// Module exception
public struct ModuleException: Error, LocalizedError {
    public let moduleId: String
    public let message: String
    public let underlyingError: Error?

    public init(_ moduleId: String, _ message: String, underlyingError: Error? = nil) {
        self.moduleId = moduleId
        self.message = message
        self.underlyingError = underlyingError
    }

    public var errorDescription: String? {
        var description = "ModuleException [\(moduleId)]: \(message)"
        if let error = underlyingError {
            description += "\nCaused by: \(error.localizedDescription)"
        }
        return description
    }
}

/// Base implementation of SynheartModule with common functionality
open class BaseSynheartModule: SynheartModule {
    public let moduleId: String
    private var _status: ModuleStatus = .uninitialized

    public var status: ModuleStatus {
        return _status
    }

    public var isEnabled: Bool {
        return _status == .running
    }

    public init(moduleId: String) {
        self.moduleId = moduleId
    }

    public func initialize() async throws {
        guard _status == .uninitialized else {
            throw ModuleException(moduleId, "Module already initialized")
        }

        do {
            setStatus(.initializing)
            try await onInitialize()
            setStatus(.initialized)
        } catch {
            setStatus(.error)
            throw ModuleException(moduleId, "Failed to initialize", underlyingError: error)
        }
    }

    public func start() async throws {
        guard _status == .initialized || _status == .stopped else {
            throw ModuleException(moduleId, "Module must be initialized or stopped before starting")
        }

        do {
            setStatus(.starting)
            try await onStart()
            setStatus(.running)
        } catch {
            setStatus(.error)
            throw ModuleException(moduleId, "Failed to start", underlyingError: error)
        }
    }

    public func stop() async throws {
        guard _status == .running else {
            throw ModuleException(moduleId, "Module is not running")
        }

        do {
            setStatus(.stopping)
            try await onStop()
            setStatus(.stopped)
        } catch {
            setStatus(.error)
            throw ModuleException(moduleId, "Failed to stop", underlyingError: error)
        }
    }

    public func dispose() async throws {
        do {
            if _status == .running {
                try await stop()
            }
            try await onDispose()
            setStatus(.disposed)
        } catch {
            setStatus(.error)
            throw ModuleException(moduleId, "Failed to dispose", underlyingError: error)
        }
    }

    // MARK: - Protected methods for subclasses

    /// Set the module status
    protected func setStatus(_ newStatus: ModuleStatus) {
        _status = newStatus
    }

    /// Called during initialization - override in subclass
    open func onInitialize() async throws {
        // Override in subclass
    }

    /// Called when starting the module - override in subclass
    open func onStart() async throws {
        // Override in subclass
    }

    /// Called when stopping the module - override in subclass
    open func onStop() async throws {
        // Override in subclass
    }

    /// Called during disposal - override in subclass
    open func onDispose() async throws {
        // Override in subclass
    }
}

// Swift doesn't have a "protected" keyword, so we use this workaround
extension BaseSynheartModule {
    func setStatus(_ newStatus: ModuleStatus) {
        _status = newStatus
    }
}
