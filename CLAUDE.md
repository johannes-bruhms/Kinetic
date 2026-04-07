# Kinetic

iOS gesture controller app for live music performance. Streams IMU data over OSC and recognizes trainable custom gestures.

## Architecture
- **Pattern**: MVVM + Swift 6 concurrency + SwiftUI
- **Target**: iOS 17.0+, iPhone-first (iPad-compatible)
- **Pricing**: $4.99 one-time purchase

## Project Structure
```
Kinetic/
  App/           - App entry point
  Models/        - Data models (gestures, OSC config, motion samples)
  Views/         - SwiftUI views (Performance, Library, Training, Settings, Test)
  ViewModels/    - (future) extracted view logic
  Services/      - Core services (SensorManager, OSCSender, GestureClassifier, GestureLibrary, BonjourBrowser)
  Utilities/     - Helpers
  Resources/     - Assets
KineticTests/    - Unit tests
```

## Key Technical Details
- IMU streaming at 100-200 Hz via CoreMotion
- OSC over UDP using NWConnection (no external dependencies for MVP)
- Gesture auto-segmentation via energy-based hysteresis state machine
- Core ML for gesture classification
- All sensor processing off main thread
- OSC prefix default: `/kinetic/`

## Conventions
- Dark mode only
- Large, glove-friendly touch targets
- No analytics or tracking
- Motion data never leaves device except via OSC
