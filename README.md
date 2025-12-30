# Synheart Core SDK - SWIFT

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](https://github.com/synheart-ai/synheart-core-swift)
[![Swift](https://img.shields.io/badge/swift-%3E%3D5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)

**Synheart Core SDK** is the single, unified integration point for developers who want to collect HSI-compatible data, process human state on-device, generate focus/emotion signals, and integrate with Syni.

> **📦 SDK Implementations**: This is the iOS/Swift implementation. For documentation and other platforms, see the repositories below.

## 📦 Repository Structure

The Synheart Core SDK is organized across multiple repositories:

| Repository | Purpose |
|------------|---------|
| **[synheart-core](https://github.com/synheart-ai/synheart-core)** | Main repository (source of truth for documentation) |
| **[synheart-core-dart](https://github.com/synheart-ai/synheart-core-dart)** | Flutter/Dart implementation |
| **[synheart-core-kotlin](https://github.com/synheart-ai/synheart-core-kotlin)** | Android/Kotlin implementation |
| **[synheart-core-swift](https://github.com/synheart-ai/synheart-core-swift)** | iOS/Swift implementation (this repository) |

## Overview

The Synheart Core SDK consolidates all Synheart signal channels into one SDK:

- **Wear Module** → Biosignals (HR, HRV, sleep, motion)
- **Phone Module** → Motion + context signals
- **Behavior Module** → Digital interaction patterns
- **HSV Runtime** → Signal fusion + state computation
- **Consent Module** → User permission management
- **Capabilities Module** → Feature gating (core/extended/research)
- **Cloud Connector** → Secure HSI snapshot uploads (planned)
- **Syni Hooks** → LLM conditioning (planned)

**Key principle:**
> One SDK, many modules, unified human-state model

## Architecture

### Core Principle

> **HSI represents human state.**
>
> **Interpretation is downstream and optional.**

The Core SDK strictly separates:
- **Representation (HSI)** - State axes, indices, embeddings
- **Interpretation (Focus, Emotion)** - Optional, explicit modules
- **Application logic** - Your app

### Core Modules

1. **Capabilities Module** - Feature gating (core/extended/research)
2. **Consent Module** - User permission management
3. **Wear Module** - Biosignal collection from wearables
4. **Phone Module** - Device motion and context signals
5. **Behavior Module** - User-device interaction patterns
6. **HSV Runtime** - Signal fusion and state representation
7. **Cloud Connector** - Secure HSI snapshot uploads (planned)

### Optional Interpretation Modules

- **Synheart Focus** - Focus/engagement estimation (optional, explicit enable)
- **Synheart Emotion** - Affect modeling (optional, explicit enable)

### Data Flow

```
Wear, Phone, Behavior Modules
    ↓
HSV Runtime
    ↓
HSI (State Representation)
    ↓
Optional: Focus Module → Focus Estimates
Optional: Emotion Module → Emotion Estimates
```

## Installation

### Swift Package Manager

Add Synheart Core SDK to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/synheart/synheart-core-ios", from: "1.0.0")
]
```

## Usage

### Basic Setup

The Core SDK publishes the Human State Vector (`HSV`) as the core state representation, with optional interpretation streams for Focus and Emotion:

```swift
import SynheartCore
import Combine

// Initialize the Core SDK
try await Synheart.initialize(
    userId: "anon_user_123",
    config: SynheartConfig(
        enableWear: true,
        enablePhone: true,
        enableBehavior: true
    )
)

// Subscribe to HSI updates (core state representation)
var cancellables = Set<AnyCancellable>()

Synheart.onHSIUpdate
    .sink { hsi in
        print("Arousal Index: \(hsi.affect?.arousalIndex ?? 0)")
        print("Engagement Stability: \(hsi.engagement?.engagementStability ?? 0)")
    }
    .store(in: &cancellables)

// Optional: Enable interpretation modules
try await Synheart.enableFocus()
Synheart.onFocusUpdate
    .sink { focus in
        print("Focus Score: \(focus.score)")
    }
    .store(in: &cancellables)

try await Synheart.enableEmotion()
Synheart.onEmotionUpdate
    .sink { emotion in
        print("Stress Index: \(emotion.stress)")
    }
    .store(in: &cancellables)

// Optional: Enable cloud sync (requires consent)
// try await Synheart.enableCloud()

// Later, stop when done
try await Synheart.stop()
```

### Module-Based Architecture

The SDK also provides a modular architecture for windowed feature collection:

```swift
import SynheartCore

// Initialize modules
let capabilities = CapabilityModule()
capabilities.loadDefaults() // Or use loadFromToken() for production

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

// Create channel collector
let collector = ChannelCollector(
    wear: wearModule,
    phone: phoneModule,
    behavior: behaviorModule
)

// Create HSV Runtime
let runtime = HSVRuntimeModule(collector: collector)

// Initialize and start runtime
try await runtime.initialize()
try await runtime.start()

// Start data collection modules
try await wearModule.start()
try await phoneModule.start()
try await behaviorModule.start()

// Subscribe to final HSV
var cancellables = Set<AnyCancellable>()
runtime.finalHsvStream
    .sink { hsv in
        // Handle state updates
    }
    .store(in: &cancellables)
```

### Accessing Current State

```swift
// Preferred: Synheart is the canonical entry point.
if let currentState = Synheart.currentState {
    // Use current state
    print("Current heart rate: \(currentState.heartRate ?? 0)")
}
```

### Custom Model Integration

To integrate with your own emotion or focus models:

```swift
// Create custom emotion model
class MyEmotionModel: EmotionModelProtocol {
    func predict(features: [String: Float]) async throws -> [String: Float] {
        // Your model implementation
        return [
            "stress": 0.5,
            "calm": 0.5,
            "engagement": 0.7,
            "activation": 0.6,
            "valence": 0.3
        ]
    }
}

// Create custom focus model
class MyFocusModel: FocusModelProtocol {
    func predict(features: [String: Float]) async throws -> [String: Float] {
        // Your model implementation
        return [
            "score": 0.8,
            "cognitive_load": 0.4,
            "clarity": 0.9,
            "distraction": 0.2
        ]
    }
}

// Preferred: inject models via SynheartConfig (used by HSVRuntimeModule)
try await Synheart.initialize(
    userId: "anon_user_123",
    config: SynheartConfig(
        enableWear: true,
        enablePhone: true,
        enableBehavior: true,
        emotionModel: MyEmotionModel(),
        focusModel: MyFocusModel()
    )
)
```

## Architecture Details

Synheart Core SDK provides two complementary architectures:

### Core Architecture (`SynheartCore/Core/`)

A direct, non-modular pipeline for ingestion/processing/fusion:

- **StateEngine**: Orchestrates ingestion, processing, and fusion
- **IngestionService**: Collects raw signals from HealthKit, CoreMotion, and behavior adapters
- **SignalProcessor**: Normalizes, cleans, and calculates derived metrics (RMSSD, SDNN)
- **FusionEngine**: Generates embeddings and creates base HSV
- **EmotionHead**: Populates emotion state using emotion models
- **FocusHead**: Populates focus state using focus models

### Modular Architecture (`SynheartCore/Modules/`)

A module-based system for windowed feature collection:

- **HSVRuntimeModule**: Orchestrates window-based processing (30s, 5m, 1h, 24h windows)
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

## Project Structure

```
SynheartCore/
├── Core/                    # Core architecture components
│   ├── StateEngine.swift   # Main orchestration engine
│   ├── IngestionService.swift
│   ├── SignalProcessor.swift
│   ├── FusionEngine.swift
│   └── [Adapters]          # HealthKit, CoreMotion, Behavior, Context
├── Heads/                   # Model heads for enrichment
│   ├── EmotionHead.swift
│   └── FocusHead.swift
├── Models/                  # Data models
│   ├── Hsv.swift           # HumanStateVector
│   ├── Emotion.swift
│   ├── Focus.swift
│   ├── Behavior.swift
│   ├── Context.swift
│   └── MetaState.swift
├── Modules/                 # Modular architecture
│   ├── Base/               # Module base classes and manager
│   ├── HSVRuntime/         # Runtime orchestration
│   ├── Wear/               # Wearable data collection
│   ├── Phone/              # Phone context collection
│   ├── Behavior/            # Behavior pattern extraction
│   ├── Capabilities/       # Feature flags and capabilities
│   ├── Consent/            # Consent management
│   └── Interfaces/         # Feature provider protocols
└── Synheart.swift          # Public SDK facade / main entry point
```

## Platform Integration

### HealthKit Integration (Planned, via Synheart Wear)

The Wear Module will integrate with iOS HealthKit for biosignal collection (this repo currently uses a mock wear source):

- Heart rate monitoring
- Heart rate variability (HRV)
- Respiratory rate
- Sleep stage detection
- Motion/activity data

### CoreMotion Integration (Planned, via Synheart Behavior)

The Phone Module will integrate with CoreMotion for device motion (this repo currently uses mock collectors):

- Accelerometer data
- Gyroscope data
- Device motion (attitude, rotation rate)

### UITouch Integration (Planned, via Synheart Behavior)

The Behavior Module will integrate with app-level event instrumentation for interaction tracking:

- Tap events
- Scroll gestures
- Typing/keystroke events

## Privacy & Security

- All processing is **on-device by default**
- **No raw biosignals** stored or transmitted
- Cloud sync only for aggregated HSV (with consent)
- Consent management via `ConsentModule`
- Capability-based feature access control
- Non-medical use only

## Requirements

- iOS 15.0+ / macOS 12.0+ / watchOS 8.0+ / tvOS 15.0+
- Swift 5.9+

## Related Repositories

This iOS implementation is part of a multi-platform SDK:

- **Flutter:** `synheart-core-flutter` (reference implementation)
- **iOS:** `synheart-core-ios` (this repository)
- **Android:** `synheart-core-android` (Kotlin implementation)

All three implementations share the same modular architecture. See the Flutter repository for comprehensive documentation.

## Documentation

- **[Architecture](docs/ARCHITECTURE.md)** - Detailed architecture documentation
- **[RFC](docs/rfc.md)** - Request for Comments specification
- **[HSV Tech Spec](docs/hsv-tech-spec.md)** - Human State Vector technical specification

## 📄 License

Apache 2.0 License - see [LICENSE](LICENSE) for details.

Copyright 2025 Synheart AI Inc.

## Author

Israel Goytom

## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.
