# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2026-10-07

### Added
- **`SynheartInstance.create(config:dataDirectory:) async throws`** — creates
  an instance without blocking the calling thread. The synchronous initializer
  runs the native runtime create (store open and migrations, cloud connector,
  identity restore), which takes 0.5-1.5 s on a mid-range device and froze the
  UI when called on the main thread. Additive: `init(config:dataDirectory:)`
  is unchanged.

## [0.3.0] - 2026-10-02

### Added — per-instance HSI delivery
- **`SynheartInstance` can now receive every HSI window it completes.**
  `setHsiListener`, `clearHsiListener`, `drainHsi` and `isHsiBuffered` are the
  per-instance equivalent of `Synheart.onHSIUpdate`, which reaches the
  personal runtime only. A host reading a second instance's output had
  `tick()`'s return value alone — but `startSession` also starts the runtime's
  own 1 s background tick loop on the same pipeline, and a window that loop
  closes first never comes back from `tick()`. Buffered delivery on runtime
  ≥ 0.31.1, push callback on older runtimes. No new native calls.

### Added — host notification support
- **`Synheart.onRuntimeBehaviorEvent`.** Every behavior event in the rich form
  the personal runtime receives it, so a host feeding a second
  `SynheartInstance`, which has no collectors, can forward what it needs with
  `pushBehaviorEvent`. A facade-level publisher: one subscription outlives
  the behavior module being rebuilt.
- **`HostDeclarations.notificationsObservable`** sends
  `notifications_observable` (runtime ≥ 0.32.0). Absent, the runtime resolves
  it from the platform; a host without a running notification producer should
  declare `false`. Older runtimes ignore it.

### Added — worn accelerometer streams
- **`pushWornAccel`** on `Synheart` and `SynheartInstance` binds
  `synheart_core_push_worn_accel`: a body-worn stream tagged with its
  `AccelPlacement` per sample. `pushWristAccel` is now also available on
  `SynheartInstance`. Samples are in g with gravity included. Both degrade to
  no-ops on a runtime without the symbol; `mobileHostAbiSupport` reports them.

### Changed — behavior module feeds the rich and context channels
- **The behavior module now tries `push_behavior_event` first** and falls back
  to the legacy int-coded `push_behavior` only on a runtime without the
  symbol, so scroll and swipe payloads reach the engine instead of a single
  flattened double. Taps, scrolls and swipes are also forwarded on the
  **context channel** (`push_context_event`), the only source of
  `context.deviation.*` and so of the friction index; keystrokes are not — they
  must enter from the host's text layer via `ContextEventInput.textChange`.

### Fixed — notification follow-ups counted as arrivals
- **A notification's later outcome no longer reaches the runtime as a new
  arrival.** The host reports a notification on arrival and again when it is
  opened; the engine counts every notification event as an arrival, so an
  opened notification counted twice, inflating the notification rate,
  Interruption Pressure and the lab `notification_count`. Follow-ups are no
  longer pushed to the runtime; `onBehaviorEvent` still carries them.

### Added — runtime version gate

- **The SDK now states which runtime its bindings assume and checks it at
  init.** `RuntimeCompat.writtenAgainst` (`0.31.1`) and `RuntimeCompat.minimum`
  (`0.20.0`) are compared against `build_info.core_runtime` once the bridge is
  created; the result is logged and exposed as `Synheart.runtimeCompatibility`.
  Below the minimum, `initialize` throws `SynheartError.runtimeVersionTooOld`
  naming the fix (`synheart install runtime`); between minimum and
  written-against it warns once. Until now nothing in this package recorded
  the runtime version the hand-written `dlsym` surface was written for, so
  every behavioural change in the runtime's `SDK-CONTRACT-CHANGES.md` was
  invisible to a consumer — the C ABI is additive, so an old linked library
  resolves fine and diverges silently.

### Added — research instance fan-in

- **`SynheartInstance` can now be given rich behavior events, an app identity
  and keystroke context.** `pushBehaviorEvent`, `pushAppForeground`,
  `pushContextEvent`, `pushContextEventJson` and `supportsRichBehaviorEvents`
  are the per-instance equivalents of the `Synheart.*` calls, which reach the
  personal runtime only. A host running a second (research) instance had no
  way to feed any of them, so every research window resolved to the `Unknown`
  app category — an all-zero interpretation-mask row — and carried
  `context_label: UK` with no evidence behind it, starving CFI / Cognitive
  Load's digital term, Valence's friction index and the behaviour-only Stress
  path on every research row. No new native calls: all route through the
  existing bridge symbols.

### Fixed — HSI callback lifetime (runtime ≥ 0.31.1)

- **HSI delivery is now buffered (pull-based) when the runtime supports it.**
  The push path hands the runtime a C function pointer plus a retained
  `user_data` box whose lifetime its tokio workers know nothing about; if the
  Swift side that owns the box is torn down while the native runtime, its
  workers and the HSI listener survive in the process, the next completed
  window is dispatched through a dangling pointer and the process aborts on a
  `tokio-rt-worker` thread. On a runtime ≥ 0.31.1 the bridge now calls
  `synheart_core_init_hsi_buffered` instead of registering a callback and
  drains `synheart_core_drain_hsi` from a dispatch timer on an SDK-owned queue
  every `CoreRuntimeBridge.hsiDrainIntervalMs` (1 s; ring
  `CoreRuntimeBridge.hsiBufferCapacity`, default 64 — the oldest frame is
  evicted when full). `Synheart.tick` / `tickAll` / `flushPending` drain in
  the same call, so a host that ticks itself sees no added latency; delivery
  stays deduplicated by `hsi_id`. Older runtimes fall back to the push
  callback unchanged. `Synheart.isHsiDeliveryBuffered` and
  `Synheart.droppedHsiFrames` expose the mode and the runtime's eviction
  counter. Same pattern as the buffered logging path. The four symbols join
  the optional set in `RuntimeSymbolManifest`.
- **Stream callback teardown uses `synheart_core_clear_stream_callback`**
  when exported (≥ 0.31.1) and releases the box immediately; older runtimes
  keep the swap-in-a-no-op path. The stream callback itself is still a pushed
  function pointer — 0.31.1 adds clear-only, no buffered mode.

### Fixed — `secure_load` no longer reports a failed read as "no such key"

- The Keychain-backed `load` callback returned NULL for every status other
  than success — including `errSecInteractionNotAllowed` (device locked /
  before first unlock) and `errSecNotAvailable`. The runtime reads NULL as
  "absent", so one locked-Keychain launch minted a new storage master key
  over the existing one and orphaned every sealed blob. Absence
  (`errSecItemNotFound`) is now the only immediate NULL; transient statuses
  are retried with a bounded ~1.5 s backoff; other failures are logged with
  their `OSStatus`. A non-UTF-8 item is reported as unavailable, not absent.
  The callback still has to return NULL when storage is genuinely unavailable
  — the C signature has no error channel. On runtime ≥ 0.31.1 the
  provisioning marker turns that into `ERR_SECURE_STORAGE_UNAVAILABLE`
  (retryable) rather than a re-mint; older runtimes keep the re-mint exposure.

### Added — mobile-host runtime surface
- **Mobile-host runtime surface.** Optional bindings for
  `synheart_core_tick`, `tick_all`, `flush_pending`, `push_behavior_event`,
  `push_context_event`, `push_speed`, `set_accel_placement`,
  `declare_rest_window`, `push_wrist_accel`, `roll_day`,
  `export_session_state`, `load_session_state`, `config_id`, `last_hsv` and
  `attach_strain_score_json`, exposed on `Synheart` with typed inputs
  (`BehaviorEventInput`, `ContextEventInput`, `AccelPlacement`). Every call
  degrades to a no-op / `nil` on a runtime that predates the symbol;
  `Synheart.mobileHostAbiSupport` reports which ones resolved. Windows drained
  by `tick` / `tickAll` / `flushPending` are delivered through `onHSIUpdate`
  on the same de-duplicated path as the native callback.
- **Engine configuration.** `SynheartConfig` gains `windowMs`, `extraHeads`,
  `emitDiagnostics`, `researchBaseline` and `hostDeclarations` (`sensing`,
  `device_class`, `mask_profile`, `cfi_structural_components`). Keys are
  emitted only when set, so an unchanged config produces an unchanged runtime
  config object.

## [0.2.0] - 2026-09-04

### Added
- Core v0.24 device identity APIs: `reattestDeviceAuth()` preserves installed
  identity during repair; `logoutDeviceAuth()` clears identity and sync membership.
  Independent instances expose `reattestDevice()` and `logoutDevice()`.
- `ensureDeviceAuthRegisteredOrThrow()` preserves typed native failures,
  including `DEVICE_ACCOUNT_MISMATCH`. Restored canonical subjects are compared
  before reusing registration.
- Full sync-space lifecycle and typed readiness checks, including create,
  pairing, join, recovery, device management, leave, deletion, and local clear.
- Typed baseline envelopes and snapshot hydration for reference, HSI-axis,
  session-SRM, and longitudinal-wear baselines.
- Runtime-backed sleep, recovery, and readiness scoring, score attachment, and
  longitudinal snapshot import/export.
- Typed customer-data deletion request/status/list APIs plus research status and
  explicit study-consent recording.
- RR batch, vendor HRV/vitals/event ingestion, HSI history, cloud-history,
  personalization, workout, vendor-stream, and buffered-logging APIs.
- Optional typed Syni cloud service and `SynheartInstance` for advanced
  independent native handles with unique data-directory enforcement.
- Public SDK version metadata and additive runtime-symbol diagnostics for the
  expanded capability surface.
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
  lifecycle, real collection evidence, live HSI 1.3 state, native upload queue,
  device registration, storage, and runtime ABI diagnostics. CI builds the
  example against the local package on an iOS simulator target.
- Typed editable/effective consent models, collector startup reports, real
  behavior/motion publishers, and upload/device-auth diagnostic results.

### Changed
- `reregisterDeviceAuth()` is deprecated and delegates to identity-preserving
  re-attestation, never first-time registration. Repair requires Core v0.24.
- `logout()` awaits native identity logout before local data and consent cleanup.
  Hosts must await logout before removing their own account credentials. Older
  runtimes retain local cleanup without claiming native identity removal.
- Blocking sync and identity operations share a serial queue per native handle.
  Pending work retains the handle and isolated data-directory reservation through
  disposal; independent runtimes no longer block each other's queued operations.
- Platform and authentication origins are now explicit configuration. Empty
  origins are omitted from native configuration instead of silently selecting a
  production endpoint.
- Concurrent device-registration requests are coalesced into one native call.
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
  and tiers; duplicate native deliveries are suppressed by HSI ID. Typed state
  is parsed once per delivery and malformed JSON is reported explicitly.
- Independent collectors now start resiliently: one failed collector is
  reported without stopping healthy siblings.
- Local-only initialization no longer configures cloud auth/consent clients.
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
- The external-PR membership check leaves PRs open when private membership
  cannot be verified. CI now runs a real SwiftLint config and rejects binary or
  oversized artifacts from the source package.

### Removed
- The production mock wearable source and its random physiological samples.
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

[Unreleased]: https://github.com/synheart-ai/synheart-core-swift/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/synheart-ai/synheart-core-swift/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/synheart-ai/synheart-core-swift/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/synheart-ai/synheart-core-swift/releases/tag/v0.1.0
[0.0.5]: https://github.com/synheart-ai/synheart-core-swift/releases/tag/v0.0.5
