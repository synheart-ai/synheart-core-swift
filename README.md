# Synheart Core SDK - iOS

**Synheart Core SDK** is the single, unified integration point for developers who want to collect HSI-compatible data, process human state on-device, generate focus/emotion signals, and integrate with Syni.

## Overview

The Synheart Core SDK consolidates all Synheart signal channels into one SDK:

- **Wear Module** → Biosignals (HR, HRV, sleep, motion)
- **Phone Module** → Motion + context signals
- **Behavior Module** → Digital interaction patterns
- **HSI Runtime** → Signal fusion + state computation
- **Consent Module** → User permission management
- **Capabilities Module** → Feature gating (core/extended/research)
- **Cloud Connector** → Secure HSI snapshot uploads (planned)
- **Syni Hooks** → LLM conditioning (planned)

**Key principle:**
> One SDK, many modules, unified human-state model

## Architecture

The Core SDK consists of **7 core modules** working together:

1. **Capabilities Module** - Feature gating (core/extended/research)
2. **Consent Module** - User permission management
3. **Wear Module** - Biosignal collection from wearables
4. **Phone Module** - Device motion and context signals
5. **Behavior Module** - User-device interaction patterns
6. **HSI Runtime** - Signal fusion and state computation (produces Human State Vector)
7. **Cloud Connector** - Secure HSI snapshot uploads (planned)

The **HSI Runtime** module:
- Ingests signals from Wear, Phone, and Behavior modules
- Fuses them into a unified **Human State Vector (HSV)**
- Feeds higher-level models (Emotion Engine, Focus Engine)
- Powers Syni's LLM layer for human-aware AI

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

```swift
import HSI
import Combine

// Configure Core SDK with your app key
HSI.shared.configure(appKey: "your-app-key")

// Subscribe to state updates
var cancellables = Set<AnyCancellable>()

HSI.shared.statePublisher
    .sink { hsv in
        print("Heart Rate: \(hsv.heartRate ?? 0)")
        print("Emotion - Stress: \(hsv.emotion?.stress ?? 0)")
        print("Focus Score: \(hsv.focus?.score ?? 0)")
    }
    .store(in: &cancellables)

// Start the SDK
HSI.shared.start()

// Later, stop when done
HSI.shared.stop()
```

### Module-Based Architecture

The SDK also provides a modular architecture for windowed feature collection:

```swift
import HSI

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

// Create HSI Runtime
let runtime = HSIRuntimeModule(collector: collector)

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
if let currentState = HSI.shared.currentState {
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

// Initialize HSI with custom models
let emotionHead = EmotionHead(emotionModel: MyEmotionModel())
let focusHead = FocusHead(focusModel: MyFocusModel())
let hsi = HSI(stateEngine: nil, emotionHead: emotionHead, focusHead: focusHead)
```

## Architecture Details

Synheart Core SDK provides two complementary architectures:

### Core Architecture (`HSI/Core/`)

The primary architecture used by `HSI.shared`:

- **StateEngine**: Orchestrates ingestion, processing, and fusion
- **IngestionService**: Collects raw signals from HealthKit, CoreMotion, and behavior adapters
- **SignalProcessor**: Normalizes, cleans, and calculates derived metrics (RMSSD, SDNN)
- **FusionEngine**: Generates embeddings and creates base HSV
- **EmotionHead**: Populates emotion state using emotion models
- **FocusHead**: Populates focus state using focus models

### Modular Architecture (`HSI/Modules/`)

A module-based system for windowed feature collection:

- **HSIRuntimeModule**: Orchestrates window-based processing (30s, 5m, 1h, 24h windows)
- **WearModule**: Collects biosignal features from wearables
- **PhoneModule**: Collects phone context features (motion, app switches, screen time)
- **BehaviorModule**: Extracts behavioral patterns (typing, scrolling, interactions)
- **ModuleManager**: Manages module lifecycle and dependencies
- **CapabilityModule**: Handles feature flags and capability levels
- **ConsentModule**: Manages user consent for data collection

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture documentation.

## Data Models

### HumanStateVector (HSV)

The main data structure (`HSI/Models/Hsv.swift`) containing:

- **Biometric signals**: Heart rate, HRV, RMSSD, SDNN
- **Behavior**: Typing rate, scrolling rate, app switch rate (via `BehaviorState`)
- **Context**: Conversation timing, device state, user patterns (via `ContextState`)
- **Emotion**: Stress, calm, engagement, activation, valence (via `EmotionState`)
- **Focus**: Score, cognitive load, clarity, distraction (via `FocusState`)
- **Metadata**: Device info, session ID, timestamp, embeddings (via `MetaState`)

### Window Features (`HSI/Modules/Interfaces/FeatureProviders.swift`)

For the modular architecture, features are collected in time windows:

- **WearWindowFeatures**: HR, HRV, motion, sleep stage, respiration
- **PhoneWindowFeatures**: Motion level, app switch rate, screen on ratio, notification rate
- **BehaviorWindowFeatures**: Typing cadence, scroll velocity, burstiness, distraction score, focus hints

## Project Structure

```
HSI/
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
│   ├── HSIRuntime/         # Runtime orchestration
│   ├── Wear/               # Wearable data collection
│   ├── Phone/              # Phone context collection
│   ├── Behavior/            # Behavior pattern extraction
│   ├── Capabilities/       # Feature flags and capabilities
│   ├── Consent/            # Consent management
│   └── Interfaces/         # Feature provider protocols
└── HSI.swift               # Main public API (singleton)
```

## Platform Integration

### HealthKit Integration (Planned)

The Wear Module will integrate with iOS HealthKit for biosignal collection:

- Heart rate monitoring
- Heart rate variability (HRV)
- Respiratory rate
- Sleep stage detection
- Motion/activity data

### CoreMotion Integration (Planned)

The Phone Module will integrate with CoreMotion for device motion:

- Accelerometer data
- Gyroscope data
- Device motion (attitude, rotation rate)

### UITouch Integration (Planned)

The Behavior Module will integrate with UITouch for interaction tracking:

- Tap events
- Scroll gestures
- App switching detection

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

## License

[Add your license here]

## Author

Israel Goytom
