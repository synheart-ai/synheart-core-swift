# Swift SDK capabilities

This document describes the public Swift feature surface. Runtime-backed
features are additive: applications can inspect `RuntimeSymbolDiagnostics`
before enabling a capability that may not exist in an older bundled runtime.

## P0 — Core contract and safety

- `SynheartCoreVersion.current` exposes the package version.
- Platform and authentication origins must be configured explicitly; the SDK
  does not silently select a production server.
- Concurrent device-registration calls are coalesced into one native request.
- Core v0.24 identity repair uses `reattestDeviceAuth()` without rotating the
  installed key or device id. `logoutDeviceAuth()` removes native identity and
  sync membership; await `logout()` before clearing host account credentials.
- `ensureDeviceAuthRegisteredOrThrow()` preserves typed registration failures.
  `NativeOperationFailure.isAccountMismatch` identifies account-switch recovery.
- Sync and identity work is serialized per native handle and retains its owner
  until completion, including during disposal.
- Runtime diagnostics separate the required ABI from optional capabilities so
  an older runtime can still initialize while newer features remain unavailable.

## P1 — Sync, baselines, scores, and privacy

- Full sync-space lifecycle: create, pair, join, inspect readiness, recover,
  list or revoke devices, leave, delete, and clear local state.
- `BaselineEnvelope` provides typed reference, HSI-axis, session-SRM, and
  longitudinal-wear snapshots while preserving unknown payload fields.
- Sleep, recovery, and readiness scores can be computed through the runtime;
  sleep and daily recovery results can be attached to the active pipeline.
- Customer-data deletion supports typed request, status, and paginated-list
  results. Research status and explicit consent recording are also exposed.

## P2 — Inputs, history, personalization, and Syni

- RR batches, vendor HRV and vitals, and canonical wearable events can be sent
  to the runtime. Vendor events can be queried, read, or deleted.
- Local HSI history supports list, count, and clear operations; cloud HSI
  windows can be fetched for a requested time range.
- Task, focus, and workout context can be supplied to personalization.
- `SyniServiceClient` exposes typed cloud chat and session operations when the
  bundled runtime provides the Syni service symbols.
- Vendor streaming and buffered runtime logging are available through typed
  configuration and event publishers.

## P3 — Independent instances

`SynheartInstance` owns an independent native runtime handle for advanced
multi-profile and research applications. Each live instance must use a unique
local data directory. The static `Synheart` facade remains the recommended API
for normal single-profile applications.

```swift
let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("participant-a", isDirectory: true)
let instance = try SynheartInstance(config: config, dataDirectory: directory)
defer { instance.dispose() }
```

## Availability behavior

The wrapper does not emulate runtime outputs. If an optional native symbol is
missing, nullable APIs return `nil`, collection APIs return an empty result, or
mutating APIs return a negative/false status as documented by their type.
Applications should use runtime diagnostics and sync readiness before showing
these capabilities to users.
