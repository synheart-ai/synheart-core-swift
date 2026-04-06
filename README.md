# Synheart Core SDK - SWIFT

[![Version](https://img.shields.io/badge/version-1.2.0-blue.svg)](https://github.com/synheart-ai/synheart-core-swift)
[![Swift](https://img.shields.io/badge/swift-%3E%3D5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)

iOS/macOS/watchOS platform SDK for Synheart. This is a thin wrapper around **[synheart-core-runtime](https://github.com/synheart-ai/synheart-core-runtime)** — the shared implementation that owns all business logic (storage, crypto, sync, consent, capabilities, artifact pipeline, session orchestration, and cloud integration).

Human state inference is computed on-device by `synheart-engine` (deterministic signal processing pipeline), which runs inside `synheart-core-runtime`. This SDK communicates with the runtime via `dlsym` / static linking (`libsynheart_core_runtime`).

This SDK handles platform-specific concerns only: sensor collection (HealthKit, WatchConnectivity), Secure Enclave key management, Keychain storage, Combine reactive streams, and SwiftUI integration.

## Architecture

```
Swift App
    |
synheart-core-swift (this SDK)
    |-- Wear/Phone/Behavior modules (platform sensor collection)
    |-- CoreRuntimeBridge (dlsym to C ABI)
    |-- SynheartCoreShim (Swift-friendly wrapper)
    |
libsynheart_core_runtime.{dylib,a}
    |-- synheart-engine (HSI computation)
    |-- Storage, Crypto, Sync, Auth, Consent, Capabilities
    |-- 67 C ABI functions
```

## Repositories

| Repository | Purpose |
|------------|---------|
| **[synheart-core-runtime](https://github.com/synheart-ai/synheart-core-runtime)** | Shared implementation (all business logic) |
| **[synheart-core-flutter](https://github.com/synheart-ai/synheart-core-flutter)** | Flutter/Dart platform SDK |
| **[synheart-core-kotlin](https://github.com/synheart-ai/synheart-core-kotlin)** | Android/Kotlin platform SDK |
| **[synheart-core-swift](https://github.com/synheart-ai/synheart-core-swift)** | iOS/Swift platform SDK (this repository) |

## Overview

The Synheart Core SDK consolidates all Synheart signal channels into one SDK:

- **Wear Module** → Biosignals (HR, HRV, sleep, motion)
- **Phone Module** → Motion + context signals
- **Behavior Module** → Digital interaction patterns
- **HSI Runtime** → Signal fusion + state computation (via synheart-engine)
- **Consent Module** → User permission management
- **Capabilities Module** → Feature gating (core/extended/research)
- **Sync Module** → Secure artifact sync (replaces Cloud Connector)

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

1. **Capabilities Module** - Feature gating (core/extended/research)
2. **Consent Module** - User permission management
3. **Wear Module** - Biosignal collection from wearables
4. **Phone Module** - Device motion and context signals
5. **Behavior Module** - User-device interaction patterns
6. **HSI Runtime** - Signal fusion and state computation (via synheart-engine)
7. **Sync Module** - Secure artifact sync (replaces Cloud Connector)

### Data Flow

```
Wear, Phone, Behavior Modules (raw samples)
    ↓
RuntimeModule → RuntimeBridge → synheart-engine (via dlsym)
    ↓                              ↓
    ↓                   session → state → HSI JSON
    ↓                              ↓
    ←──── HumanStateVector ←───────┘
    ↓
Optional: Focus Module → Focus Estimates
Optional: Emotion Module → Emotion Estimates
```

## Installation

### Swift Package Manager

Add Synheart Core SDK to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/synheart-ai/synheart-core-swift", from: "1.0.0")
]
```

## Usage

### Basic Setup

The Core SDK publishes the Human State Vector (`HSV`) as the core state representation, with optional interpretation streams for Focus and Emotion:

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

The SDK also provides a modular architecture for windowed feature collection:

```swift
import SynheartCore

// Initialize modules
let capabilities = CapabilityModule()
// In production, use loadFromToken(token, secret: secret)
// For development only:
capabilities.loadDefaults()

let consent = ConsentModule()

let wearModule = WearModule(capabilities: capabilities, consent: consent)
let phoneModule = PhoneModule(capabilities: capabilities, consent: consent)
let behaviorModule = BehaviorModule(capabilities: capabilities, consent: consent)

// Initialize modules (this loads consent from storage)
try await capabilities.initialize()
try await consent.initialize() // Loads consent from storage
try await consent.grantAll() // Or update specific consents as needed
try await wearModule.initialize()
try await phoneModule.initialize()
try await behaviorModule.initialize()

// Create RuntimeBridge (wraps synheart-engine)
let bridge = RuntimeBridge.createIfAvailable()

// Create Runtime Module
let runtime = RuntimeModule(
    bridge: bridge,
    wearSamplePublisher: wearModule.rawSamplePublisher,
    behaviorEventPublisher: behaviorModule.eventPublisher
)

// Initialize and start runtime
try await runtime.initialize()
try await runtime.start()

// Start data collection modules
try await wearModule.start()
try await phoneModule.start()
try await behaviorModule.start()

// Subscribe to final HSV
var cancellables = Set<AnyCancellable>()
runtime.hsiStream
    .sink { hsiJson in
        // Handle HSI JSON frames from synheart-engine
    }
    .store(in: &cancellables)
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

## Batch Ingest Mode

By default, the runtime module streams data in real-time. **Batch ingest mode** buffers all events during a session and runs a single `ingestBatch` call on stop.

```swift
let runtimeModule = RuntimeModule(
    bridge: bridge,
    batchIngestOnStop: true  // Enable batch mode
)
```

## Lab Ingestion

Send structured session and metadata payloads to the Synheart platform API.

### Auto-Ingest

```swift
let config = SynheartConfig(
    appId: "your_app_id",
    subjectId: "sub_user_123",
    labIngestConfig: LabIngestConfig(
        apiKey: "your_platform_api_key",
        autoIngest: true
    )
)
```

### Manual Ingestion

```swift
// Ingest current session data
try await synheart.ingestSession()

// Ingest app/user metadata
try await synheart.ingestMetadata()
```

### Standalone Payload Builder

```swift
let payload = LabPayloadBuilder.buildSession(
    sessionId: "sess_123",
    // ... other params
)
```

## Architecture Details

### Modular Architecture (`SynheartCore/Modules/`)

A module-based system for data collection and processing:

- **RuntimeModule**: Orchestrates window-based processing (30s, 5m, 1h, 24h windows)
- **WearModule**: Collects biosignal features from wearables
- **PhoneModule**: Collects phone context features (motion, app switches, screen time)
- **BehaviorModule**: Extracts behavioral patterns (typing, scrolling, interactions)
- **ModuleManager**: Manages module lifecycle and dependencies
- **CapabilityModule**: Handles feature flags and capability levels
- **ConsentModule**: Manages user consent for data collection

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture documentation.

## Data Models

### HumanStateVector (HSV)

The main data structure (`SynheartCore/Models/Hsv.swift`) containing:

- **Biometric signals**: Heart rate, HRV, RMSSD, SDNN
- **Behavior**: Typing rate, scrolling rate, app switch rate (via `BehaviorState`)
- **Context**: Conversation timing, device state, user patterns (via `ContextState`)
- **Emotion**: Stress, calm, engagement, activation, valence (via `EmotionState`)
- **Focus**: Score, cognitive load, clarity, distraction (via `FocusState`)
- **Metadata**: Device info, session ID, timestamp, embeddings (via `MetaState`)

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
├── Core/                    # Core architecture components
│   ├── StateEngine.swift   # Main orchestration engine
│   ├── IngestionService.swift
│   ├── SignalProcessor.swift
│   ├── FusionEngine.swift
│   └── [Adapters]          # HealthKit, CoreMotion, Behavior, Context
├── Models/                  # Data models
│   ├── Hsv.swift           # HumanStateVector
│   ├── Emotion.swift
│   ├── Focus.swift
│   ├── Behavior.swift
│   ├── Context.swift
│   └── MetaState.swift
├── Modules/                 # Modular architecture
│   ├── Base/               # Module base classes and manager
│   ├── Runtime/            # Runtime orchestration
│   ├── Wear/               # Wearable data collection
│   ├── Phone/              # Phone context collection
│   ├── Behavior/            # Behavior event collection
│   ├── Capabilities/       # Feature flags and capabilities
│   ├── Consent/            # Consent management
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

- iOS 15.0+ / macOS 12.0+ / watchOS 8.0+ / tvOS 15.0+
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

## Related Repositories

This iOS implementation is part of a multi-platform SDK:

- **Flutter:** `synheart-core-flutter` (Dart/Flutter implementation)
- **iOS:** `synheart-core-swift` (this repository)
- **Android:** `synheart-core-kotlin` (Kotlin implementation)

All three implementations share the same modular architecture. See the Flutter repository for comprehensive documentation.

## Local Development with `synheart local`

For offline SDK development and testing, use the **Synheart CLI** local platform server. It replicates the cloud consent and ingest APIs locally.

### Setup

1. Install the [Synheart CLI](https://github.com/synheart-ai/synheart-cli):

```bash
git clone https://github.com/synheart-ai/synheart-cli
cd synheart-cli
make build && make install
```

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

- **API Key:** `mock-dev-api-key-2026`
- **HMAC Secret:** `mock-dev-hmac-secret-2026`

Ingested payloads are persisted as JSON files in the local server's data directory.

## Documentation

- **[Architecture](docs/ARCHITECTURE.md)** - Detailed architecture documentation

## 📄 License

Apache 2.0 License - see [LICENSE](LICENSE) for details.

Copyright 2025-2026 Synheart AI Inc.

## Author

Synheart AI Team

## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.
