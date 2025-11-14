# HSI iOS Architecture

This document describes the architecture of the Human State Interface (HSI) iOS/Swift implementation, based on the RFC.

## Overview

HSI iOS implements a layered architecture where:

1. **HSI Core (State Engine)** processes raw signals and produces base HSV
2. **Emotion Head** (using `synheart_emotion` module) populates emotion state
3. **Focus Head** (using `synheart_focus` module) populates focus state
4. **Final HSV** is emitted to subscribers via Combine Publishers

## Architecture Layers

### 1. HSI Core (`HSI/Core/`)

#### State Engine (`StateEngine.swift`)
- Orchestrates ingestion, processing, and fusion
- Produces base HSV Publisher (`CurrentValueSubject<HSV>` or `@Published` property)
- Manages lifecycle (start/stop)
- Uses Swift async/await and Combine for async processing
- Lifecycle-aware component (integrates with iOS app lifecycle)

#### Ingestion Service (`IngestionService.swift`)
- Background Task or Background Processing for background collection
- Collects signals from:
  - Synheart Wear SDK/Service (HR, HRV, motion, sleep)
  - Synheart Phone SDK (typing, scrolling, app switches)
  - Context Adapters (conversation timing, device state, user patterns)
- Emits raw `SignalData` via Combine Publisher
- Uses iOS Sensor APIs, HealthKit, CoreMotion, or custom SDKs

#### Signal Processor (`SignalProcessor.swift`)
- Synchronization and windowing
- Noise reduction and artifact handling
- Vendor-agnostic normalization
- Baseline alignment
- Calculates derived metrics (RMSSD, SDNN, burstiness indices)
- Processes signals in background async tasks

#### Fusion Engine (`FusionEngine.swift`)
- Computes low-level derived metrics
- Generates `hsi_embedding` (latent representation)
- Creates base HSV from processed signals
- May use Core ML for on-device inference

### 2. Model Heads (`HSI/Heads/`)

#### Emotion Head (`EmotionHead.swift`)
- Subscribes to base HSV Publisher from State Engine
- Extracts features from HSV
- Calls `synheart_emotion` module/library to predict emotion
- Populates `hsv.emotion` with:
  - stress, calm, engagement, activation, valence
- Emits HSV with emotion populated via Publisher

#### Focus Head (`FocusHead.swift`)
- Subscribes to emotion Publisher (or base HSV Publisher)
- Extracts features from HSV (including emotion)
- Calls `synheart_focus` module/library to predict focus
- Populates `hsv.focus` with:
  - score, cognitive_load, clarity, distraction
- Emits final HSV via Publisher

### 3. Data Models (`HSI/Models/`)

#### HSV (`Hsv.swift`)
- `HumanStateVector`: Main struct (Swift struct)
- `MetaState`: Device, session, embeddings
- `DeviceInfo`: Platform information
- Uses Swift structs with Codable support for serialization

#### Emotion (`Emotion.swift`)
- `EmotionState`: Emotion metrics struct

#### Focus (`Focus.swift`)
- `FocusState`: Focus metrics struct

#### Behavior (`Behavior.swift`)
- `BehaviorState`: Behavioral metrics struct

#### Context (`Context.swift`)
- `ContextState`: Context information struct
- `ConversationContext`: Conversation timing
- `DeviceStateContext`: Device state
- `UserPatternsContext`: User patterns

### 4. Main HSI Class (`HSI/HSI.swift`)

- Singleton pattern (`HSI.shared` static property)
- Orchestrates State Engine and Heads
- Provides public API:
  - `configure(appKey: String)`: Initialize with app key
  - `start()`: Start the pipeline
  - `stop()`: Stop the pipeline
  - `statePublisher: AnyPublisher<HSV, Never>`: Publisher of final HSV
  - `currentState: HSV?`: Latest HSV (optional)
  - `enableCloudSync()`: Enable cloud sync (future)
- Integrates with iOS app lifecycle

## Data Flow

```
Raw Signals (Wear SDK, Phone SDK, Context)
    ↓
Ingestion Service
    ↓
Signal Processor (normalization, cleaning)
    ↓
Fusion Engine (hsi_embedding, base HSV)
    ↓
Emotion Head (synheart_emotion) → HSV with emotion
    ↓
Focus Head (synheart_focus) → Final HSV
    ↓
Subscribers (apps, Syni LLM layer)
```

## Integration Points

### synheart_emotion Module/Library
- Expected interface: `EmotionModel.predict(features: [String: Float]) -> [String: Float]`
- Features extracted from HSV: hsi_embedding, HR, HRV, behavioral metrics, context
- Returns: stress, calm, engagement, activation, valence
- May use Core ML or custom native model
- Runs inference on background queue using async/await

### synheart_focus Module/Library
- Expected interface: `FocusModel.predict(features: [String: Float]) -> [String: Float]`
- Features extracted from HSV: hsi_embedding, behavioral metrics, emotion state
- Returns: score, cognitive_load, clarity, distraction
- May use Core ML or custom native model
- Runs inference on background queue using async/await

## iOS-Specific Considerations

### Background Processing
- Use Background Tasks (BGTaskScheduler) for periodic background tasks
- Use Background Processing capability for continuous signal collection
- Consider battery optimization and background app refresh settings
- Handle app state transitions (foreground, background, suspended)

### Lifecycle Management
- Integrate with iOS app lifecycle (UIApplicationDelegate/SceneDelegate)
- Handle app state changes (active, inactive, background, terminated)
- Proper cleanup on app termination
- Use Combine to maintain state across lifecycle events

### Permissions
- Health data permissions (HealthKit authorization)
- Motion & Fitness permissions (CoreMotion)
- Background location (if needed for context)
- Background modes (Background Processing, Background Fetch)

## Next Steps

1. **Connect to actual SDKs**:
   - Integrate with Synheart Wear SDK/Service (via watchOS or companion app)
   - Integrate with Synheart Phone SDK
   - Implement Context Adapters (HealthKit, CoreMotion, Screen Time API)

2. **Implement fusion model**:
   - Replace placeholder embedding with actual Tiny Transformer or CNN-LSTM
   - Train model to fuse biosignals, behavior, and context
   - Convert to Core ML format (.mlmodel) for on-device inference

3. **Integrate model modules**:
   - Implement `synheart_emotion` iOS library/module (Swift Package or CocoaPods)
   - Implement `synheart_focus` iOS library/module
   - Adjust feature extraction based on model requirements
   - Optimize model loading and inference

4. **Cloud sync**:
   - Implement `enableCloudSync()` method
   - Use Background Tasks for sync jobs
   - Ensure only aggregated HSV is synced (no raw biosignals)
   - Implement encryption for sensitive data

5. **Testing**:
   - Unit tests for processors (XCTest)
   - Integration tests for full pipeline
   - Mock SDKs for testing
   - UI tests for integration (XCUITest)

6. **Performance optimization**:
   - Optimize sampling rates
   - Optimize model inference (use Neural Engine if available)
   - Battery usage considerations
   - Memory management (avoid retain cycles with Combine subscriptions)

## Privacy & Security

- All processing is on-device by default
- No raw biosignals stored or transmitted
- Cloud sync only for aggregated HSV (with consent)
- Non-medical use only

