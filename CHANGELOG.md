# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Core business logic (storage, crypto, sync, consent, artifact pipeline, cloud connector, SRM)
  migrated to synheart-core-runtime (Rust). SDK is now a thin FFI shell.
- RuntimeBridge/RuntimeModule replaced by CoreRuntimeBridge (FFI to libsynheart_core_runtime)
- HSI state updates delivered via native callback mechanism instead of platform-specific streams
- Lab protocol API now routes through CoreRuntimeBridge

### Removed
- StorageManager, ArtifactCrypto, SMK, URK, SyncEngine, SyncModule, ArtifactPipeline
- RuntimeBridge, RuntimeModule (replaced by CoreRuntimeBridge)
- CloudConnector, UploadQueue, UploadClient, HsiSchemaTransformer
- SRM computation modules (SRMModule, SRMBuffer, SRMSnapshotStorage)
- `configure()` method (single entry point is `Synheart.initialize(config:userId:autoStart:)`)
- Feature provider protocols (WearFeatureProvider, PhoneFeatureProvider, BehaviorFeatureProvider)
- Legacy config fields (enableWear, enablePhone, enableBehavior)
- Empty `Heads/` directory
- PlatformPayloadBuilder, PlatformIngestConfig (moved to Rust core runtime)

## [1.2.0] - 2026-02-23

### Removed

- **FeatureExtractor** — Deleted empty `BehaviorFeatureExtractor` placeholder class (`SynheartCore/Modules/Behavior/FeatureExtractor.swift`). All feature computation lives in synheart-engine per RFC-CORE-0007.

### Changed

- Removed all TODO/FIXME comments across the SDK (Synheart.swift, CapabilityModule.swift).
- Replaced stale TODO comments in FocusHead and EmotionHead reevaluation branches with concise `// FocusHead: HSI JSON parser pending.` / `// EmotionHead: HSI JSON parser pending.` notes.
- Updated placeholder comments in `FocusModelProtocol.swift` and `EmotionModelProtocol.swift` to clarify stub status.
- **README.md** — Updated version badge, fixed HSV→HSI terminology, updated code examples to use `activate()` API and `AnyPublisher<String, Never>` types, removed Syni Hooks and "(planned)" labels, updated platform integration sections.

### Added

- **SRM snapshot persistence** — SRM baseline model is now persisted to iOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`) and automatically restored on SDK initialization. Prevents baseline loss on app restart. New `SRMSnapshotStorage` class mirrors the `ConsentStorage` pattern.
- **HSI stream consent gating** — Local `onHSIUpdate` publisher now checks `biosignals` consent before forwarding HSI frames to consumers. Previously only cloud upload was gated; now local streams respect consent too.
- **Codable conformance for SRM types** — `SRMSnapshot`, `StratumSnapshot`, `BufferEntry`, and `MetricReference` now conform to `Codable` with snake_case `CodingKeys` matching the cross-platform JSON schema.
- **HSI consent gate tests** — New `ConsentGateTests.swift` with 3 XCTest tests verifying HSI frames are blocked when biosignal consent is denied.
- **synheart-engine installed** — macOS universal dylib and static lib now bundled in `lib/` via `make install-swift`.

## [1.1.0] - 2026-02-22

### Changed

- **RuntimeBridge** (renamed from `FluxFFIProvider`) — now wraps synheart-engine C ABI via dlsym instead of calling synheart-flux directly. synheart-engine composes the full session → state → flux pipeline internally.
  - `synheart_engine_new(config_json)` replaces `flux_processor_create()`
  - `synheart_engine_push_rr()`, `push_hr()`, `push_accel()`, `push_behavior()` for signal ingestion
  - `synheart_engine_tick(now_ms)` returns HSI JSON when a window completes
  - `synheart_engine_free_string()` for memory management
  - Backward-compatible: `createIfAvailable()` still returns nil when native library is absent
- **RuntimeModule** (renamed from `HSVRuntimeModule`) — orchestrates signal collection and pipeline execution via RuntimeBridge.
- Updated stale comments across 11 source files to reference current module names.

## [1.0.0] - 2026-02-21

First stable release supporting HSI 1.x.

### Added

- **Flux FFI Integration** — Live pipeline from Core SDK to synheart-flux (Rust) via C FFI
  - `FluxFFIProvider` — concrete `FluxProvider` calling `flux_processor_process_window()` via `@_silgen_name`
  - Serializes raw `WearSample`, `PhoneDataPoint`, `BehaviorEvent` into WindowInput JSON
  - Maps returned Flux HSV JSON into Core `HumanStateVector` (physiology, quality, provenance, embedding)
  - Stores raw Flux HSV JSON in `MetaState.rawFluxHsv` for downstream access
  - Baseline persistence: `saveBaselines()` / `loadBaselines()` for session continuity
  - Graceful degradation: `createIfAvailable()` returns nil when native library is absent
  - Memory-safe: all `flux_free_string()` calls paired with FFI allocations

- **synheart-flux 0.4.0 Alignment** — HSV types updated to match Rust HSV specification
  - `HsvAxisValue` — score + confidence pair for per-axis readings (replaces hardcoded 0.8 confidence)
  - `PhysiologyState` — wearable-derived physiology domain with 11 axes (sleep efficiency, recovery, HRV deviation, etc.)
  - `StateQuality` — aggregated quality assessment (overall confidence, modality count, degraded flag, quality flags)
  - `ProvenanceInfo` — data provenance tracking (source IDs, vendors, device ID, timezone, baseline days)
  - `ExportPolicy` — controls which domains/axes appear in exported HSI, with confidence threshold filtering
  - `HumanStateVector` gains `physiology`, `stateQuality`, and `provenance` fields
  - `FluxBridge.export()` now accepts optional `ExportPolicy` parameter
  - FluxBridge uses per-axis confidence from `HsvAxisValue` for physiology readings
  - FluxBridge meta block includes `modality_count`, `overall_confidence`, and `vendors`

### Changed

- **EmotionHead/FocusHead** — Feature extraction now includes `PhysiologyState` fields (recovery_score, sleep_efficiency, hrv_deviation, strain) from synheart-flux 0.4.0 HSV.

- **Capability Token Validation** — SDK now validates server-signed capability tokens during initialization
  - New `SynheartConfig` fields: `capabilityToken`, `capabilitySecret`, `allowUnsignedCapabilities`
  - When token and secret are provided, `CapabilityModule.loadFromToken()` validates HMAC signature and expiry
  - `allowUnsignedCapabilities: true` serves as a debug escape hatch (logs a warning)
  - Without a valid token or explicit opt-in, initialization throws `SynheartError.capabilityTokenRequired`

- **Consent Revocation Deactivates Modules** — Revoking consent mid-session now stops affected modules immediately
  - `biosignals` revoked → stops `WearModule`, cancels Emotion/Focus heads
  - `behavior` revoked → stops `BehaviorModule`
  - `motion` revoked → stops `PhoneModule`
  - `cloudUpload` revoked → stops `CloudConnectorModule`
  - Granting consent re-starts the corresponding module
  - Each stop/start is isolated — one module failure does not cascade
  - Consent listener registered during initialization, cleaned up on dispose

### Breaking Changes

- `Synheart.initialize()` now requires either a valid capability token or `allowUnsignedCapabilities: true` in config. Existing callers that relied on implicit `loadDefaults()` must pass `SynheartConfig(allowUnsignedCapabilities: true)`.

## [0.1.0] - 2025-12-30

### Added

- Initial release of Synheart Core SDK for Swift
- Module orchestration: Capabilities, Consent, Wear, Phone, Behavior, HSV Runtime, Cloud Connector
- Optional interpretation modules: Emotion Head, Focus Head
- HSI export via FluxBridge (HSV → HSI 1.0 canonical format)
- Combine-based reactive streams (`onHSIUpdate`, `onEmotionUpdate`, `onFocusUpdate`)
- Session lifecycle: `initialize()`, `startSession()`, `stopSession()`, `dispose()`
- Consent management: `grantConsent()`, `revokeConsent()`, `hasConsent()`, `updateConsent()`
- Cloud upload: `enableCloud()`, `uploadNow()`, `flushUploadQueue()`, `disableCloud()`
- Capability-based feature gating (core / extended / research tiers)
- On-device processing with privacy-first design
- Module manager with dependency tracking and lifecycle management
- Platform support: iOS 15+, macOS 12+, watchOS 8+, tvOS 15+
