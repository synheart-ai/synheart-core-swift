# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Added
- **Cloud consent token binding** — `Synheart.ensureCloudConsentReady()`,
  `Synheart.subjectId`, and `consentTokenSubjectStale()`. Mints/refreshes a
  consent token scoped to the current subject (configure-cloud on init,
  mint-on-grant, init self-heal) so uploads are attributed to that subject.
- Runtime symbol diagnostics that distinguish required ABI symbols from
  optional capabilities and fail initialization with an actionable
  compatibility error when the linked runtime is incomplete.
- Runtime-backed session catalog, HSI-window, storage-usage, retention,
  orphan-repair, sync-status, and sync-conflict handling.
- A runnable SwiftUI iOS example app covering configuration, consent/session
  lifecycle, live HSI 1.3 state, storage, sync, and runtime ABI diagnostics.
  CI builds the example against the local package on an iOS simulator target.

### Changed
- Account deletion (`requestAccountDeletion` / `cancelAccountDeletion`) now goes
  through the native runtime's device-signed request instead of an in-process
  bearer token. Request signing is backed by `synheart-auth-swift`.
- **BREAKING:** research-study enrolment, validation, withdrawal, and data
  deletion methods are now `async`; their native network calls execute away
  from the caller executor, matching the Flutter API contract.
- Sync, upload flush, local wipe, and account-deletion runtime work now executes
  on a serial utility queue instead of blocking the caller executor.
- Native runtime configuration is built in one place and uses durable
  application-support storage. Bundle secrets are no longer forwarded to the
  native runtime.
- Starting a session now requires collection consent and a real native session
  handle. A runtime failure is no longer hidden by a synthetic handle.
- **BREAKING:** session start now requires at least one collection feature with
  matching developer activation, user consent, device-role support, and SDK
  capability. Registered collectors are no longer started unconditionally.
- Device-auth configuration now uses provisional SDK capability defaults while
  the native runtime performs registration and consent-token enforcement. The
  static bundle capability-token/secret path is deprecated for new apps.
- **BREAKING:** `Synheart.logout()` is now `async throws`; it revokes native
  grants and clears persisted consent tokens before changing Swift-visible state.
- Phone collectors are injectable. Production defaults use CoreMotion and app
  lifecycle notifications, while unavailable system-wide app/notification data
  remains idle instead of being fabricated.

### Fixed
- Native FFI declarations and symbol names now match the current runtime ABI,
  including RR providers, lab-window functions, wearable SRM functions, and
  runtime-owned callback strings.
- Initialization is concurrency-safe, retryable after failure, and reports
  native creation errors truthfully.
- Failed session/module starts roll back partially allocated resources and can
  be retried. Wear, Phone, and Behavior now participate in the shared lifecycle
  state machine instead of bypassing it.
- Wear collection no longer injects a mock source in production by default.
- HSI 1.3 payloads parse canonical domain arrays, IDs, timestamps, modalities,
  and tiers; duplicate native deliveries are suppressed by HSI ID.
- Sync and privacy APIs no longer report placeholder or successful outcomes
  when the native operation failed.
- Legacy capability tokens are rejected when expired, not yet valid,
  unverifiable, or rejected by the native signature verifier.
- Phone and Wear callbacks recheck consent before caching or publishing data.
- Consent updates are native-first, compensate partial failures, restore native
  state during initialization, and never enable Swift collection after native
  rejection.
- Custom platform origins now configure native ingest/sync plus Swift auth and
  consent consistently; storage retention is forwarded to the native runtime.
- Failed native session stops preserve the active Swift/native session handle.
- HSI 1.3 digital axes (`focus_quality`, `interruption_pressure`, and
  `interaction_mode`) are available as typed values.

### Removed
- **BREAKING:** deprecated `PhoneContextConsent.motion` / `.screenState` aliases —
  use `deviceMotion` / `systemState`.
- Internal migration stubs (stub `SynheartAuth` / `SignedHeadersStub` /
  `AuthTokenStub`, `ConsentModule.getCurrentToken`). These are replaced by
  `synheart-auth-swift` and runtime-backed equivalents; `SyncResult`,
  `SyncStatus`, `SessionRecord`, and `CapabilityException` are now real public
  types (no longer deprecated stubs).

## [0.0.8] - 2026-06-17

### Added
- **`HSIAxes.stress`** — typed accessor for the engine's multimodal stress
  reading (engine v0.10.0; HSI 1.3 `axes.affective[].stress`). Hosts get a named
  field instead of digging through `rawJson`. Resolves to `null` on the legacy
  1.2 path that never carried it. Parity with the Dart/Kotlin bindings.
- **`EdgeIngest`** — canonical phone-side consumer of the Synheart edge wire
  contract (watch → phone).
  Holds no `WatchConnectivity` import, so it compiles and unit-tests on macOS.
  Parses `hr_sample` / `bio_sample` / `hsi_artifact` / session events and, for
  artifacts, dedupes by `artifact_id`, verifies `payload_hash_sha256` ==
  sha256(`payload_json`), validates the inner `hsi_version` against the supported
  set, and produces the `artifact_ack` body. Public surface:
  - Sealed `EdgeEvent` family (`.hr | .bio | .artifact | .sessionEvent`) plus
    the typed payloads (`HrSample`, `BioSample`, `Artifact`, `Accel`).
  - Reactive `events: AnyPublisher<EdgeEvent, Never>` broadcast publisher,
    emitting in lock-step with the `Delegate` callbacks (parity with the Kotlin
    `SharedFlow` and Dart `Stream<EdgeEvent>`).
  - `Delegate` protocol callbacks and the `@discardableResult Outcome` return
    from `ingest(_:)` (which folds the Kotlin-only `onUnsupportedHsiVersion` /
    `onHashMismatch` signals into `.artifactHashMismatch` + logging), plus the
    optional poison-pill / dead-letter delegate hook
    `edgeIngestDidDeadLetterArtifact(artifactId:expected:actual:attempts:)`.
  - ACK helpers `drainAck()` / `makeAckBody(artifactIds:)`.
  - Delivery hardening (the watch outbox is delete-on-ACK):
    - **Duplicate re-ack** — a duplicate `artifact_id` is not re-surfaced
      (`Outcome.artifactDuplicate`) but is re-queued for ACK, so a lost ACK no
      longer makes the watch resend forever.
    - **Bounded dedupe set** — the seen-artifact set is a bounded LRU
      (`seenLruCapacity`), keeping memory flat over a long-lived process.
    - **Poison-pill dead-letter** — an artifact that fails hash verification
      `poisonPillThreshold` (3) times for the same id is dead-lettered
      (`Outcome.artifactDeadLettered`, the new delegate hook, and
      ack-to-discard) so a deterministically-corrupt artifact stops blocking the
      outbox.
- **`EdgeIngestSessionAdapter`** — opt-in `WCSession` adapter that routes bodies
  into `EdgeIngest` by the body `type` and sends the `artifact_ack` back. Not
  wired in by default.

## [0.0.7] - 2026-06-07

### Added
- `Synheart.requestStudyDataDeletion(dryRun:)`: request erasure of the data the
  participant contributed to their study for this app — the deletion the consent
  copy promises alongside withdrawal. No identifiers are passed; the participant
  and app come from the device's signed credential. `dryRun` returns an inventory
  preview without deleting; a real request is accepted asynchronously and carries
  a `request_id`. Idempotent.

## [0.0.6] - 2026-06-07

### Added
- Research-study enrolment API: `Synheart.enrolResearchStudy(accessCode:studyCode:)`,
  `Synheart.validateResearchStudyCodes(accessCode:studyCode:)`, and
  `Synheart.withdrawResearchStudy()`. Enrolment rides the device's signed cloud
  credential — no tokens are handled by the caller. Withdrawal is idempotent.

## [0.0.5] - 2026-05-25

### Added — cross-SDK API parity
- **`Synheart.processVendorEvent(...)`** — facade over `WearModule.processVendorEvent`. Returns `CanonicalWearableEvent?` (the canonical mapping the vendor event was normalized to, or `nil` if dropped). Mirrors the Dart and Kotlin counterparts.
- **`Synheart.recordMetrics(_:)`** — batch wrapper over `recordMetric` for hosts that capture bursts of metrics.
- **`Synheart.setAmbientCapture(_:)` / `Synheart.getAmbientCapture()`** — surface for the runtime's ambient-capture mode (forwards every closed HSI window to the host's HSI callback regardless of session state). New FFI bindings to `synheart_core_set_ambient_capture` / `synheart_core_get_ambient_capture`.

### Fixed
- `Baselines.isReady` (renamed from `isStable`) now also checks runtime READY status.
- `CoreRuntimeBridge.setHsiCallback` no longer leaks the previously
  registered closure. The retained `Unmanaged` box is stored on the
  bridge and released when the callback is replaced, cleared, or the
  bridge deinits.
- Score-model `toJsonString()` (RecoveryScore, SleepScore,
  ReadinessScore) no longer crashes with `try!` / force-unwrap if the
  underlying `JSONSerialization` fails — returns `"{}"` and logs a
  warning instead.
- `DeviceAuthProvider` async-to-sync bridges (`signRequest`, clock-skew
  correction, key rotation) now use `Task.detached` so they cannot
  deadlock when called from an actor-isolated context.
- README platform minimums corrected to match `Package.swift`
  (iOS 16+, macOS 13+).

### Docs
- `Synheart.hasConsent`, `grantConsent`, `revokeConsent` — expanded
  DocC comments with accepted `consentType` values and throw conditions.

## [0.0.4] - 2026-05-07

Initial open-source release of the Synheart Core SDK for iOS.

The SDK is a thin native-bridge shell over the runtime — storage,
crypto, sync, consent, the artifact pipeline, the cloud connector,
and SRM live in the runtime, and this package exposes them through
a Swift surface.

### Public surface
- `Synheart` facade with async initialize / activate / deactivate
  lifecycle.
- `SynheartConfig` (single source of truth for app metadata, modules,
  cloud, consent, capabilities, device auth).
- `CoreRuntime` bridge to `libsynheart_core_runtime`.
- New public APIs: `SynheartPriority` (multi-source priority
  resolution) and `SynheartResilience` (HRV-CV resilience). Both
  fall back to a pure-Swift in-memory path when the native library
  is not loaded.
- `AppleXmlBackfillSink` — runtime sink for the Apple Health XML
  import path (paired with `AppleXmlImport` in synheart-wear-swift).
- HSI state updates delivered via the runtime callback mechanism.
- Lab protocol API routed through the runtime bridge.

### Breaking
- `CloudConfig.tenantId` removed — dead field. The cloud resolves
  `(org_id, tenant_id, project_id)` from `app_id` server-side.
- `CloudConfig.hmacSecret` removed — dead field. Request signing is
  performed by the runtime's hardware-backed ECDSA key, not HMAC.
- `precondition(hmacSecret != nil || authProvider != nil, ...)` block
  removed alongside `hmacSecret`. `authProvider` is now optional.
- `CloudConnectorError.invalidTenant` removed — never raised on the
  SDK→ingest path.
- `Synheart.cancelAccountDeletion()` now returns
  `DeletionRequestResult` instead of `Bool`, mirroring
  `requestAccountDeletion()` and the Dart/Kotlin counterparts.

### Changed
- `CloudConnectorError.invalidSignature` description string
  `"HMAC signature validation failed"` → `"request signature
  validation failed"`. The signing path is ECDSA, not HMAC.

### Distribution
- Swift Package Manager — products: `SynheartCore`.

[0.2.0]: https://github.com/synheart-ai/synheart-core-swift/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/synheart-ai/synheart-core-swift/releases/tag/v0.1.0
[0.0.5]: https://github.com/synheart-ai/synheart-core-swift/releases/tag/v0.0.5
[0.0.4]: https://github.com/synheart-ai/synheart-core-swift/releases/tag/v0.0.4
