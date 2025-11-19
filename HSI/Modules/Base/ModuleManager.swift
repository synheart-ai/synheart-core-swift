import Foundation

/// Manages the lifecycle of all Synheart modules
///
/// Responsibilities:
/// - Initialize modules in correct order
/// - Handle module dependencies
/// - Coordinate module lifecycle
/// - Handle errors and recovery
public class ModuleManager {
    private var modules: [String: SynheartModule] = [:]
    private var dependencies: [String: [String]] = [:]
    private var isInitialized = false

    public init() {}

    /// Register a module with optional dependencies
    public func registerModule(_ module: SynheartModule, dependsOn: [String] = []) throws {
        if modules[module.moduleId] != nil {
            throw ModuleException(module.moduleId, "Module already registered")
        }

        modules[module.moduleId] = module
        if !dependsOn.isEmpty {
            dependencies[module.moduleId] = dependsOn
        }
    }

    /// Get a module by ID
    public func getModule<T: SynheartModule>(_ moduleId: String) -> T? {
        return modules[moduleId] as? T
    }

    /// Initialize all registered modules in dependency order
    public func initializeAll() async throws {
        guard !isInitialized else {
            throw NSError(domain: "ModuleManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Modules already initialized"
            ])
        }

        let initOrder = try resolveInitializationOrder()

        for moduleId in initOrder {
            if let module = modules[moduleId] {
                try await module.initialize()
            }
        }

        isInitialized = true
    }

    /// Start all modules in dependency order
    public func startAll() async throws {
        guard isInitialized else {
            throw NSError(domain: "ModuleManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Modules must be initialized before starting"
            ])
        }

        let startOrder = try resolveInitializationOrder()

        for moduleId in startOrder {
            if let module = modules[moduleId], module.status == .initialized {
                try await module.start()
            }
        }
    }

    /// Stop all modules in reverse dependency order
    public func stopAll() async {
        guard let stopOrder = try? resolveInitializationOrder().reversed() else {
            return
        }

        for moduleId in stopOrder {
            if let module = modules[moduleId], module.status == .running {
                do {
                    try await module.stop()
                } catch {
                    print("Error stopping module \(moduleId): \(error)")
                }
            }
        }
    }

    /// Dispose all modules in reverse dependency order
    public func disposeAll() async {
        guard let disposeOrder = try? resolveInitializationOrder().reversed() else {
            return
        }

        for moduleId in disposeOrder {
            if let module = modules[moduleId] {
                do {
                    try await module.dispose()
                } catch {
                    print("Error disposing module \(moduleId): \(error)")
                }
            }
        }

        modules.removeAll()
        dependencies.removeAll()
        isInitialized = false
    }

    /// Get status of all modules
    public func getModuleStatuses() -> [String: ModuleStatus] {
        return modules.mapValues { $0.status }
    }

    // MARK: - Private Methods

    /// Resolve the initialization order based on dependencies
    private func resolveInitializationOrder() throws -> [String] {
        var order: [String] = []
        var visited: Set<String> = []
        var visiting: Set<String> = []

        func visit(_ moduleId: String) throws {
            if visited.contains(moduleId) {
                return
            }

            if visiting.contains(moduleId) {
                throw NSError(domain: "ModuleManager", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Circular dependency detected for module: \(moduleId)"
                ])
            }

            visiting.insert(moduleId)

            // Visit dependencies first
            if let deps = dependencies[moduleId] {
                for dep in deps {
                    guard modules[dep] != nil else {
                        throw NSError(domain: "ModuleManager", code: 4, userInfo: [
                            NSLocalizedDescriptionKey: "Module \(moduleId) depends on \(dep), but \(dep) is not registered"
                        ])
                    }
                    try visit(dep)
                }
            }

            visiting.remove(moduleId)
            visited.insert(moduleId)
            order.append(moduleId)
        }

        // Visit all modules
        for moduleId in modules.keys {
            try visit(moduleId)
        }

        return order
    }
}
