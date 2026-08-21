import Foundation

/// Result of a best-effort module start. Independent modules continue starting
/// after a sibling fails; dependents of a failed module are skipped.
public struct ModuleStartReport: Equatable {
    public let runningModuleIds: Set<String>
    public let failures: [String: String]

    public init(runningModuleIds: Set<String>, failures: [String: String]) {
        self.runningModuleIds = runningModuleIds
        self.failures = failures
    }
}

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
        try await startModules(Set(modules.keys))
    }

    /// Start only the requested modules and their dependencies.
    ///
    /// This is the collection-safe entry point used by the Synheart facade: a
    /// collector is never started merely because it was registered.
    public func startModules(_ moduleIds: Set<String>) async throws {
        guard isInitialized else {
            throw NSError(domain: "ModuleManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Modules must be initialized before starting"
            ])
        }

        let startOrder = try resolveInitializationOrder()
        let selectedModuleIds = try moduleIds.reduce(into: Set<String>()) { selected, moduleId in
            try includeModuleAndDependencies(moduleId, in: &selected)
        }
        var startedInThisCall: [SynheartModule] = []

        do {
            for moduleId in startOrder where selectedModuleIds.contains(moduleId) {
                if let module = modules[moduleId],
                   module.status == .initialized || module.status == .stopped {
                    try await module.start()
                    startedInThisCall.append(module)
                }
            }
        } catch {
            for module in startedInThisCall.reversed() where module.status == .running {
                try? await module.stop()
            }
            throw error
        }
    }

    /// Start requested modules and their dependencies without letting one
    /// independent collector abort healthy siblings.
    public func startModulesResiliently(_ moduleIds: Set<String>) async throws -> ModuleStartReport {
        guard isInitialized else {
            throw NSError(domain: "ModuleManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Modules must be initialized before starting"
            ])
        }

        let startOrder = try resolveInitializationOrder()
        let selectedModuleIds = try moduleIds.reduce(into: Set<String>()) { selected, moduleId in
            try includeModuleAndDependencies(moduleId, in: &selected)
        }
        var running = Set<String>()
        var failures: [String: String] = [:]

        for moduleId in startOrder where selectedModuleIds.contains(moduleId) {
            let failedDependencies = (dependencies[moduleId] ?? []).filter { failures[$0] != nil }
            if !failedDependencies.isEmpty {
                failures[moduleId] = "Dependency failed: \(failedDependencies.sorted().joined(separator: ", "))"
                continue
            }
            guard let module = modules[moduleId] else {
                failures[moduleId] = "Module is not registered"
                continue
            }
            if module.status == .running {
                running.insert(moduleId)
                continue
            }
            guard module.status == .initialized || module.status == .stopped else {
                failures[moduleId] = "Module cannot start from status \(String(describing: module.status))"
                continue
            }
            do {
                try await module.start()
                running.insert(moduleId)
            } catch {
                failures[moduleId] = error.localizedDescription
            }
        }

        return ModuleStartReport(runningModuleIds: running, failures: failures)
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
                    SynheartLogger.log("Error stopping module \(moduleId): \(error)")
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
                    SynheartLogger.log("Error disposing module \(moduleId): \(error)")
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

    private func includeModuleAndDependencies(
        _ moduleId: String,
        in selected: inout Set<String>
    ) throws {
        guard modules[moduleId] != nil else {
            throw NSError(domain: "ModuleManager", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Module \(moduleId) is not registered"
            ])
        }
        guard selected.insert(moduleId).inserted else { return }
        for dependency in dependencies[moduleId] ?? [] {
            try includeModuleAndDependencies(dependency, in: &selected)
        }
    }

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
