# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/synheart-ai/synheart-core-swift/compare/v0.0.4...HEAD
[0.0.4]: https://github.com/synheart-ai/synheart-core-swift/releases/tag/v0.0.4
