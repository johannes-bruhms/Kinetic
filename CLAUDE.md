# Kinetic

iOS gesture controller app for live music performance. Streams IMU data over OSC and recognizes trainable custom gestures via DTW (Dynamic Time Warping) with Core ML as optional upgrade path.

## Architecture
- **Pattern**: MVVM + Swift 6 concurrency + SwiftUI
- **Target**: iOS 17.0+, iPhone-first (iPad-compatible)
- **Pricing**: $4.99 one-time purchase
- **Default isolation**: `@MainActor` (project-wide Swift 6 setting)

## Project Structure
```
Kinetic/
  App/           - App entry point (KineticApp.swift)
  Models/        - Data models
    GestureModel.swift      - TrainedGesture, GestureRecording, MotionSample, Quaternion, Vector3
    OSCConfiguration.swift  - OSC host/port/prefix/sampleRate config
  Views/         - SwiftUI views
    PerformanceView.swift         - Main dashboard: stream toggle, waveform, probability bars, recent gestures
    GestureLibraryView.swift      - CRUD for gestures (add, rename via swipe-left, delete via swipe-right)
    TrainingView.swift            - Record gesture samples, auto-segment, review & save
    SettingsView.swift            - OSC config, Bonjour discovery, sample rate, data export
    TestModeView.swift            - Full-screen rehearsal with large probability bars + haptic feedback
    IMUWaveformView.swift         - Canvas-based real-time 3-axis acceleration plot
    GestureProbabilityBarsView.swift - Color-coded probability bar display
  Services/      - Core services
    SensorManager.swift     - CoreMotion wrapper, 100-200 Hz IMU streaming on background queue
    OSCSender.swift         - OSC binary encoding + UDP via NWConnection, 4 IMU streams + gesture events
    GestureClassifier.swift - Hybrid classifier: DTW primary, Core ML optional. Sliding window (50 samples)
    DTWClassifier.swift     - Dynamic Time Warping distance with 2-row memory optimization. nonisolated + Sendable
    GestureSegmenter.swift  - Energy-based hysteresis state machine for auto-segmenting recordings
    GestureLibrary.swift    - JSON persistence in Documents/kinetic_gestures/, recording storage, data export
    BonjourBrowser.swift    - NWBrowser for _osc._udp discovery with endpoint resolution to IP:port
  Resources/     - Assets.xcassets (AppIcon, AccentColor)
KineticTests/    - Unit tests (DTW, Segmenter, OSC encoding)
```

## Key Technical Details
- IMU streaming at 100-200 Hz via CoreMotion (.xArbitraryZVertical reference frame)
- OSC over UDP using NWConnection (no external dependencies)
- Gesture recognition via DTW as primary method (works immediately after training)
- Core ML as optional upgrade (requires external model training)
- Auto-segmentation via energy-based hysteresis state machine
- All sensor processing off main thread
- OSC prefix default: `/kinetic/`
- Haptic feedback (UIImpactFeedbackGenerator) on gesture triggers

## OSC Output Schema
Default prefix: `/kinetic/` (user-editable)
- `/kinetic/imu/attitude/quat` (x, y, z, w) — quaternion attitude
- `/kinetic/imu/rotation/rate` (x, y, z) — gyroscope
- `/kinetic/imu/accel/user` (x, y, z) — gravity-removed acceleration
- `/kinetic/imu/gravity` (x, y, z) — gravity vector
- `/kinetic/gesture/[name]` (float probability) — gesture event (>0.8)
- `/kinetic/gesture/[name]/trigger` (int velocity) — gesture trigger (>0.9)

## Conventions
- Dark mode only (enforced in KineticApp.swift)
- Large, glove-friendly touch targets for stage use
- No analytics or tracking
- Motion data never leaves device except via user-configured OSC stream
- `nonisolated` annotation required for types used from background queues (DTWClassifier, GestureSegmenter)
- `@unchecked Sendable` for mutable classes accessed across isolation boundaries

## Build & Test
- **Build**: `xcodebuild -project Kinetic.xcodeproj -scheme Kinetic -destination 'generic/platform=iOS'`
- **Test**: `xcodebuild test -project Kinetic.xcodeproj -scheme Kinetic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KineticTests`
- Simulator has no IMU — real device required for motion testing
- No external dependencies (pure Apple frameworks: CoreMotion, Network, CoreML)
