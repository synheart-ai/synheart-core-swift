# Synheart Core SDK — Swift

[![Version](https://img.shields.io/badge/version-0.0.8-blue.svg)](https://github.com/synheart-ai/synheart-core-swift)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-FA7343.svg)](https://swift.org)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

> **Source-available.** This repository is open for reading, auditing, and
> filing issues. We do **not** accept pull requests — see
> [CONTRIBUTING.md](CONTRIBUTING.md) for the rationale and how to contribute
> via issues. Security reports go through [SECURITY.md](SECURITY.md).

iOS/macOS/watchOS platform SDK for Synheart. This is a thin wrapper around the Synheart runtime — a native binary that owns the on-device business logic and is loaded by this SDK at startup.

Human state inference is computed on-device by a deterministic signal-processing pipeline that runs inside the runtime. This SDK communicates with the runtime via `dlsym` / static linking (`libsynheart_core_runtime`).

This SDK handles platform-specific concerns only: sensor collection (HealthKit, WatchConnectivity), Secure Enclave key management, Keychain storage, Combine reactive streams, and SwiftUI integration.

## Architecture

```
Swift App
    |
synheart-core-swift (this SDK)
    |-- Wear/Phone/Behavior modules (platform sensor collection)
    |-- CoreRuntimeBridge (loads the runtime native binary)
    |
Synheart runtime native binary
    |-- HSI computation
    |-- Storage, Crypto, Sync, Auth, Consent, Capabilities
```

## Repositories

| Repository | Purpose |
|------------|---------|
| **[synheart-core-flutter](https://github.com/synheart-ai/synheart-core-flutter)** | Flutter/Dart platform SDK |
| **[synheart-core-kotlin](https://github.com/synheart-ai/synheart-core-kotlin)** | Android/Kotlin platform SDK |
| **[synheart-core-swift](https://github.com/synheart-ai/synheart-core-swift)** | iOS/Swift platform SDK (this repository) |

## Overview

The Synheart Core SDK consolidates all Synheart signal channels into one SDK:

- **Wear Module** → Biosignals (HR, HRV, sleep, motion)
- **Phone Module** → Motion + context signals
- **Behavior Module** → Digital interaction patterns
- **HSI Runtime** → Signal fusion + state computation (via the runtime native binary)
- **Consent Module** → User permission management
- **Capabilities Module** → Feature gating (core/extended/research)
- **Cloud Connector** → Secure HSI snapshot uploads

**Key principle:**
> One SDK, many modules, unified human-state model

## Architecture

### Core Principle

> **All inference is computed by synheart-engine.**
>
> **SDKs coordinate data collection and distribution.**

The Core SDK strictly separates:
- **Computation** — synheart-engine computes HSV
- **Collection** — Core SDK modules (Wear, Phone, Behavior, Consent, Capability)
- **Distribution** — HSI JSON export, cloud upload, raw HSV diagnostics

### Core Modules

1. **Capabilities Module** — Feature gating (core/extended/research)
2. **Consent Module** — User permission management
3. **Wear Module** — Biosignal collection from wearables
4. **Phone Module** — Device motion and context signals
5. **Behavior Module** — User-device interaction patterns
6. **HSI Runtime** — Signal fusion and state computation (via the runtime native binary)
7. **Cloud Connector** — Secure HSI snapshot uploads

### Optional Modules

These ship in the same target and are wired through the runtime, but only become useful once you've granted the relevant consent / capabilities. Each is a thin Swift facade around an existing FFI surface.

| Module | Purpose | Entry point |
|---|---|---|
| **Baselines** | Reactive snapshot of the user's wearable-baseline state — `AnyPublisher<BaselinesSnapshot, Never>` with `latestSleepScore` / `latestRecoveryScore` / `latestReadinessScore` / `reference` / 7-night recent-scores ring. | `Baselines.shared` |
| **Breathing** | 4-pillar breathing-compliance detector. RR samples from `pushRr` feed it automatically; module configures target BPM / population / window. | `BreathingModule(bridge:)` |
| **Syni** | Consent-gated facade around the [`SyniSwift`](https://github.com/synheart-ai/syni-swift) on-device agent SDK. Wraps `SyniAgent` install lifecycle + chat with a `consent.syni` check. | `SyniModule(consent:)` |
| **HealthKit backfill** | Cold-start SRM seeding from HealthKit sleep + overnight HR/HRV history. Pushes `sleep_need` / `deep_sleep_min` / `rem_sleep_min` / `hrv_rmssd` / `resting_hr` per wake-day. | `HealthKitRuntimeSink(reader:, pushDaily:, triggerRecompute:)` |
| **Scoring models** | Typed input + result types for the runtime's Sleep / Recovery / Readiness scorers, plus a self-report `SleepQuestionnaireAnswers`. | `Models/{SleepScore,RecoveryScore,ReadinessScore,SleepQuestionnaire}.swift` |
| **Cloud upload models** | Typed `UploadRequest` / `UploadResponse` / `UploadErrorResponse` for the snapshot-upload protocol. Round-trips byte-equivalent JSON with Flutter + Kotlin siblings. | `Modules/Cloud/UploadModels.swift` |

Examples:

```swift
// Baselines — react to every score / reference update
Baselines.shared.updates
    .sink { snap in
        if let s = snap.latestSleepScore { render(s.score) }
        if let r = snap.latestRecoveryScore { render(r.score) }
    }
    .store(in: &cancellables)

// Breathing — configure once, evaluate per UI frame
let breathing = BreathingModule(bridge: coreRuntime)
breathing.setTargetBpm(6.0)
breathing.setPopulation(.beginner)
switch breathing.evaluate() {
case let .compliant(metrics):
    showCompliant(metrics)
case let .notCompliant(_, reason):
    showCoaching(BreathingGuidanceCopy.copyFor(reason))
case let .insufficient(reason):
    showWarming(reason)
}

// HealthKit backfill — call on first launch after authorization
let reader = HealthKitHistoryReader() // from synheart-wear-swift
let sink = HealthKitRuntimeSink(
    reader: reader,
    pushDaily: { dim, day, value, conf, fid in
        coreRuntime.pushWearableDailyValue(
            dimension: dim, dayIndex: day, value: value,
            confidence: conf, fidelity: fid
        )
    },
    triggerRecompute: { coreRuntime.triggerWearableRecompute(triggerType: 0, asOfDay: 0) }
)
let result = try await sink.backfill(daysBack: 365)
print("seeded \(result.daysIngested) days, \(result.dimensionsPushed) dimensions")

// Syni — consent-gated agent
let syni = SyniModule(consent: consentModule)
try await syni.install(
    persona: try await SyniSpecPersona.load("focus.coach.v1"),
    model: SyniModels.qwen25_15bInstructQ4
)
let reply = try await syni.chat("how should I focus right now?")
```

### Data Flow

```
Wear, Phone, Behavior Modules (raw samples)
    ↓
CoreRuntimeBridge → runtime native binary
    ↓                       ↓
    ↓             session → state → HSI 1.3 JSON
    ↓                       ↓
    ←──── HSI JSON ←────────┘
    ↓
Synheart.onHSIUpdate (raw JSON) / Synheart.onStateUpdate (typed)
```

## Installation

### Swift Package Manager

Add Synheart Core SDK to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/synheart-ai/synheart-core-swift", from: "0.0.8")
]
```

## Usage

### Basic Setup

The Core SDK publishes **HSI 1.3 JSON** as its public output. Apps subscribe via `Synheart.onHSIUpdate` (raw JSON) or `Synheart.onStateUpdate` (typed `HSIState`). There are no separate Focus / Emotion streams.

```swift
import SynheartCore
import Combine

// Initialize the Core SDK
try await Synheart.initialize(config: SynheartConfig(
    appId: "com.example.app",
    subjectId: "anon_user_123",
    allowUnsignedCapabilities: true  // Use capabilityToken + capabilitySecret in production
))

// Grant consent for biosignal collection
try await Synheart.grantConsent("biosignals")

// Subscribe to HSI updates (core state representation)
var cancellables = Set<AnyCancellable>()

Synheart.onHSIUpdate
    .sink { hsiJson in
        print("HSI JSON: \(hsiJson)")
    }
    .store(in: &cancellables)

// Subscribe to typed state updates
Synheart.onStateUpdate
    .sink { state in
        print("State: \(state)")
    }
    .store(in: &cancellables)

// Start session — data collection begins
try await Synheart.startSession()

// Later, stop when done
try await Synheart.stopSession()
try await Synheart.dispose()
```

### Module-Based Architecture

The SDK exposes individual modules for hosts that need finer-grained lifecycle control. Most apps use the `Synheart.initialize` entry point above and don't need to wire modules by hand.

```swift
import SynheartCore

let capabilities = CapabilityModule()
capabilities.loadDefaults() // Development only — use loadFromToken in production

let consent = ConsentModule()

let wearModule = WearModule(capabilities: capabilities, consent: consent)
let phoneModule = PhoneModule(capabilities: capabilities, consent: consent)
let behaviorModule = BehaviorModule(capabilities: capabilities, consent: consent)

try await capabilities.initialize()
try await consent.initialize()
try await consent.grantAll()
try await wearModule.initialize()
try await phoneModule.initialize()
try await behaviorModule.initialize()

try await wearModule.start()
try await phoneModule.start()
try await behaviorModule.start()
```

### Accessing Current State

```swift
// currentState returns the latest raw HSI JSON frame (String?).
if let currentJson = Synheart.currentState {
    print("Latest HSI JSON: \(currentJson)")
}

// For typed access, use currentHSIState:
if let state = Synheart.currentHSIState {
    print("Current state: \(state)")
}
```


## Error Handling

The SDK uses Swift's native error handling with typed errors:

```swift
do {
    try await Synheart.initialize(config: SynheartConfig(
        appId: "com.example.app",
        subjectId: "user_123",
        allowUnsignedCapabilities: true
    ))
    try await Synheart.startSession()
} catch SynheartError.alreadyConfigured {
    print("SDK already initialized")
} catch SynheartError.capabilityTokenRequired {
    print("Provide a valid capability token or set allowUnsignedCapabilities: true")
} catch SynheartError.notInitialized {
    print("Call initialize() first")
} catch {
    print("Unexpected error: \(error)")
}
```

### Error Types

| Error | When |
|-------|------|
| `SynheartError.notInitialized` | Method called before `initialize()` |
| `SynheartError.alreadyConfigured` | `initialize()` called twice |
| `SynheartError.capabilityTokenRequired` | No token provided and `allowUnsignedCapabilities` is false |
| `SynheartError.notImplemented(String)` | Feature not yet available |


## Architecture Details

### Modular Architecture (`SynheartCore/Modules/`)

A module-based system for data collection and processing:

- **WearModule**: Collects biosignal features from wearables
- **PhoneModule**: Collects phone context features (motion, app switches, screen time)
- **BehaviorModule**: Extracts behavioral patterns (typing, scrolling, interactions)
- **CapabilityModule**: Handles feature flags and capability levels
- **ConsentModule**: Manages user consent for data collection

## Data Models

The runtime emits **HSI 1.3 JSON** as its public output. Apps subscribe via `Synheart.onHSIUpdate` (raw JSON) or `Synheart.onStateUpdate` (typed `HSIState`). Internal types (`Hsv` and friends) are not part of the public SDK API.

### Window Features (`SynheartCore/Modules/Interfaces/FeatureProviders.swift`)

For the modular architecture, features are collected in time windows:

- **WearWindowFeatures**: HR, HRV, motion, sleep stage, respiration
- **PhoneWindowFeatures**: Motion level, app switch rate, screen on ratio, notification rate
- **BehaviorWindowFeatures**: Typing cadence, scroll velocity, burstiness, distraction score, focus hints

## API Reference

### Synheart (Main Entry Point)

| Method | Description |
|--------|-------------|
| `initialize(config:userId:autoStart:)` | Initialize the SDK (must be called first) |
| `startSession()` | Start data collection |
| `stopSession()` | Stop data collection |
| `activate(_:)` | Enable a feature (wear, behavior, phoneContext, etc.) |
| `deactivate(_:)` | Disable a feature |
| `syncNow()` | Execute a sync cycle (push + pull) |
| `grantConsent(_:)` | Grant consent for a data type |
| `revokeConsent(_:)` | Revoke consent for a data type |
| `hasConsent(_:)` | Check if consent is granted |
| `stop()` | Stop the session |
| `dispose()` | Release all resources |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `onHSIUpdate` | `AnyPublisher<String, Never>` | HSI JSON frames from synheart-engine |
| `onStateUpdate` | `AnyPublisher<HSIState, Never>` | Typed HSI state updates |
| `currentState` | `String?` | Latest HSI JSON frame |
| `currentHSIState` | `HSIState?` | Latest typed HSI state |
| `currentConsent` | `ConsentSnapshot?` | Current consent state |
| `isInitialized` | `Bool` | Whether SDK is initialized |
| `isRunning` | `Bool` | Whether a session is active |

## Project Structure

```
SynheartCore/
├── Config/                  # SynheartConfig, CloudConfig, etc.
├── CoreRuntime/             # Bridge to the runtime native binary
├── Models/                  # Internal data models (HSI 1.3 typed projection)
├── Modules/
│   ├── Base/               # Module base classes and manager
│   ├── Wear/               # Wearable data collection
│   ├── Phone/              # Phone context collection
│   ├── Behavior/            # Behavior event collection
│   ├── Capabilities/       # Feature flags and capabilities
│   ├── Consent/            # Consent management
│   ├── Cloud/              # Cloud connector
│   ├── SRM/                # Self-Reference Model (baseline persistence)
│   └── Interfaces/         # Module contracts and data types
└── Synheart.swift          # Public SDK facade / main entry point
```

## Platform Integration

### HealthKit (via synheart-wear-swift)

The Wear Module collects biosignals from HealthKit via synheart-wear-swift:

- Heart rate monitoring
- Heart rate variability (HRV)
- Respiratory rate
- Sleep stage detection
- Motion/activity data

### CoreMotion (via synheart-behavior-swift)

The Phone Module collects device motion via CoreMotion:

- Accelerometer data
- Gyroscope data
- Device motion (attitude, rotation rate)

### Behavior Tracking (via synheart-behavior-swift)

The Behavior Module captures user-device interaction patterns:

- Tap events
- Scroll gestures
- Typing/keystroke events

## Privacy & Security

- All processing is **on-device by default**
- **No raw biosignals** stored or transmitted
- **HSI stream is consent-gated** — `onHSIUpdate` only emits frames when `biosignals` consent is granted
- Cloud sync only for aggregated HSI (with consent)
- **SRM baseline persistence** — Learned baselines are encrypted and persisted to Keychain, restored automatically on next launch
- Consent management via `ConsentModule`
- Capability-based feature access control
- Non-medical use only

## Requirements

- iOS 16.0+ / macOS 13.0+ / watchOS 8.0+ / tvOS 15.0+
- Swift 5.9+

## Testing

### Running Tests

```bash
swift test
```

### Testing with Mock Providers

The SDK ships with mock data sources for development and testing. When no real wearable or sensor is connected, modules use mock collectors that emit synthetic data.

To test your integration without hardware:

```swift
// Initialize with default capabilities (no real token needed)
try await Synheart.initialize(config: SynheartConfig(
    appId: "com.example.test",
    subjectId: "test_user",
    allowUnsignedCapabilities: true
))

// Start session — mock data will flow through all streams
try await Synheart.startSession()

// Subscribe and verify
Synheart.onHSIUpdate
    .sink { hsiJson in
        // Verify HSI JSON from synheart-engine
        print("HSI: \(hsiJson)")
    }
    .store(in: &cancellables)
```

## Edge ingest (watch → phone)

`EdgeIngest` is the canonical phone-side consumer of the Synheart **edge wire
contract** (watch → phone). It is the counterpart to the watch producer and
exists so apps stop re-implementing watch→phone ingest: parse, hash-verify
(`payload_hash_sha256`), HSI-version validate, dedupe by `artifact_id`,
and ACK all live here once. The core holds **no** `WatchConnectivity` import,
so it compiles and unit-tests on any platform (`swift test` runs on macOS). The
canonical message shapes are defined by the Synheart edge wire contract.

```swift
import Combine
import SynheartCore

// 1. Construct (optionally with a Delegate).
let ingest = EdgeIngest()

// 2. Observe the broadcast `events` publisher (parity with Kotlin's
//    `SharedFlow` and Dart's `Stream<EdgeEvent>`).
let cancellable = ingest.events.sink { event in
    switch event {
    case .hr(let s):        // …
    case .bio(let s):       // …
    case .artifact(let a):  render(a.payloadJson)  // verified + non-duplicate
    case .sessionEvent(let type, let body): break
    }
}

// 3. Feed decoded bodies in; then drain + send the artifact_ack.
let outcome = ingest.ingest(body)           // [String: Any] from the adapter
if let ack = ingest.drainAck() {            // { "command":"artifact_ack", … }
    session.sendMessage(ack, replyHandler: nil)  // → docs.synheart.ai/synheart-core/edge
}
```

**Three notification mechanisms — pick what fits.** `EdgeIngest` surfaces every
parsed body three ways, all firing in lock-step, so you wire only what you need:

- **`delegate` (`EdgeIngest.Delegate`)** — classic protocol callbacks
  (`edgeIngestDidReceiveHrSample`, `…DidAcceptArtifact`, etc.). Use when you have
  a single, long-lived owner object (e.g. a coordinator) that wants push
  callbacks. All methods are optional.
- **`events: AnyPublisher<EdgeEvent, Never>`** — a Combine publisher. Use for
  reactive/SwiftUI pipelines or when multiple subscribers need the stream.
- **`@discardableResult Outcome` return from `ingest(_:)`** — a synchronous,
  per-body result (`.artifactAccepted` / `.artifactDuplicate` /
  `.artifactHashMismatch` / `.artifactDeadLettered` / `.sessionEvent` /
  `.dropped(reason:)`). Use in the
  transport adapter or tests when you want to branch on the result of a single
  body without holding state.

For parity awareness: the Kotlin SDK additionally exposes `Listener` hooks
`onUnsupportedHsiVersion(...)` / `onHashMismatch(...)`; Swift folds those signals
into the `Outcome` return value (`.artifactHashMismatch`) and logging.

**Delivery hardening.** Because the watch outbox is delete-on-ACK, ingest is
hardened against two failure modes:

- **Duplicate re-ack.** A duplicate `artifact_id` (already accepted) is **not**
  re-surfaced — `ingest(_:)` returns `.artifactDuplicate(artifactId:)` — but it
  **is** re-queued for ACK. A lost ACK would otherwise make the watch resend
  forever; re-acking duplicates clears the outbox. The dedupe set is a bounded
  LRU (capacity `EdgeIngest.seenLruCapacity`), so memory stays flat.
- **Poison-pill dead-letter.** A deterministically-corrupt artifact whose
  `payload_hash_sha256` keeps mismatching is detected per `artifact_id`: after
  `EdgeIngest.poisonPillThreshold` (3) mismatches it is **dead-lettered** —
  `ingest(_:)` returns `.artifactDeadLettered(artifactId:)`, the optional
  delegate hook `edgeIngestDidDeadLetterArtifact(artifactId:expected:actual:attempts:)`
  fires, and the id is ack-to-discarded so it stops blocking the outbox. The
  first/normal mismatch still returns `.artifactHashMismatch` without acking.

**Opt-in transport adapter.** `EdgeIngestSessionAdapter` is a thin, opt-in
`WCSession` adapter that routes incoming bodies into an `EdgeIngest` core by the
body `type` and sends the produced `artifact_ack` back. Nothing in the SDK wires
it in by default.

## Related Repositories

This iOS implementation is part of a multi-platform SDK:

- **Flutter:** `synheart-core-flutter` (Dart/Flutter implementation)
- **iOS:** `synheart-core-swift` (this repository)
- **Android:** `synheart-core-kotlin` (Kotlin implementation)

All three implementations share the same modular architecture. See the Flutter repository for comprehensive documentation.

## Local Development with `synheart local`

For offline SDK development and testing, use the **Synheart CLI** local platform server. It replicates the cloud consent and ingest APIs locally.

### Setup

1. Install the Synheart CLI:

```bash
# macOS / Linux
curl -fsSL https://synheart.sh/install | sh

# Windows (PowerShell)
iwr -useb https://synheart.sh/install.ps1 | iex
```

See [docs.synheart.ai/setup/install-cli](https://docs.synheart.ai/setup/install-cli) for details.

2. Start the local platform:

```bash
synheart local
```

This starts an HTTP server on `localhost:8083` with mock consent profiles, token issuance, and ingest endpoints.

### Connecting your iOS app

Point the SDK at the local server:

```swift
let config = SynheartConfig(
    appId: "your_app_id",
    subjectId: "user_123",
    allowUnsignedCapabilities: true,
    labIngestConfig: LabIngestConfig(
        baseUrl: "http://localhost:8083",  // Simulator can reach host localhost
        apiKey: "mock-dev-api-key-2026"
    )
)
```

For a physical device on the same network:

```swift
baseUrl: "http://192.168.1.100:8083"  // your machine's LAN IP
```

**Note:** For physical devices, add an App Transport Security exception in `Info.plist` to allow HTTP:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

### Available endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/apps/{id}/consent-profiles` | Fetch consent profiles |
| `POST` | `/api/v1/sdk/consent-token` | Issue consent token |
| `POST` | `/api/v1/sdk/consent-revoke` | Revoke consent |
| `POST` | `/v1/ingest/hsi` | Ingest HSI snapshots |
| `POST` | `/v1/platform/session/ingest` | Ingest session data |
| `POST` | `/v1/platform/metadata/ingest` | Ingest metadata |
| `GET` | `/status` | Server status and stats |

### Default credentials

Production cloud ingest is device-signed and consent-gated. The `synheart local`
server ships development-only mock keys for offline iteration.

- **API Key:** `mock-dev-api-key-2026` (mock platform only)
- **Mock dev secret:** `mock-dev-hmac-secret-2026` (local testing only)

Ingested payloads are persisted as JSON files in the local server's data directory.

## 📄 License

Apache 2.0 License - see [LICENSE](LICENSE) for details.

Copyright 2025-2026 Synheart AI Inc.

## Author

Synheart AI Team

## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.
