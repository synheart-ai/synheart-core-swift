# HSI iOS

Human State Interface (HSI) iOS SDK - A Swift implementation for processing biosignals, behavior, and context to produce Human State Vectors (HSV).

## Overview

HSI iOS implements a layered architecture that:

1. **Ingests** raw signals from wearables, phone sensors, and context adapters
2. **Processes** signals through normalization, cleaning, and derived metrics calculation
3. **Fuses** processed signals into base HSV with embedding representation
4. **Enriches** HSV with emotion state (via `synheart_emotion` module)
5. **Enriches** HSV with focus state (via `synheart_focus` module)
6. **Emits** final HSV to subscribers via Combine Publishers

## Installation

### Swift Package Manager

Add HSI to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/synheart/hsi-ios", from: "1.0.0")
]
```

## Usage

### Basic Setup

```swift
import HSI
import Combine

// Configure HSI with your app key
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

// Start the pipeline
HSI.shared.start()

// Later, stop when done
HSI.shared.stop()
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

## Architecture

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture documentation.

## Data Models

### HumanStateVector (HSV)

The main data structure containing:

- **Biometric signals**: Heart rate, HRV, RMSSD, SDNN
- **Behavior**: Typing rate, scrolling rate, app switch rate
- **Context**: Conversation, device state, user patterns
- **Emotion**: Stress, calm, engagement, activation, valence
- **Focus**: Score, cognitive load, clarity, distraction
- **Metadata**: Device info, session ID, timestamp, embeddings

## Privacy & Security

- All processing is on-device by default
- No raw biosignals stored or transmitted
- Cloud sync only for aggregated HSV (with consent)
- Non-medical use only

## Requirements

- iOS 15.0+ / macOS 12.0+ / watchOS 8.0+ / tvOS 15.0+
- Swift 5.9+

## License

[Add your license here]

## Author

Israel Goytom

