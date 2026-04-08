# Kinetic

> **Living document** — update this file whenever architecture, thresholds, schemas, or conventions change.

iOS gesture controller for live music performance. IMU → OSC over UDP. Three-layer recognition: discrete (DTW), continuous (FFT), posture (gravity).

## Build & Test
```bash
xcodebuild -project Kinetic.xcodeproj -scheme Kinetic -destination 'generic/platform=iOS'
xcodebuild test -project Kinetic.xcodeproj -scheme Kinetic -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:KineticTests
```
No external deps (CoreMotion, Network, CoreML, Accelerate). No IMU in simulator.

## Architecture
- MVVM + SwiftUI, iOS 17.0+, Swift 6 strict concurrency
- `@MainActor` project-wide default isolation
- `nonisolated` + `Sendable` for background-queue types (DTWClassifier, GestureSegmenter, FrequencyAnalyzer, ContinuousClassifier, PostureClassifier)
- `@unchecked Sendable` for mutable classes crossing isolation boundaries

## Recognition Layers
Three layers run in parallel on the same IMU sample stream, each tuned to a different temporal scale:
- **Discrete** (0.5s window, stride 10): DTW + Random Forest, trigger events. Per-gesture debounce cooldown (default 500ms). Per-gesture sensitivity controls DTW distance threshold (2.5–6.0) and trigger probability threshold (0.70–0.30).
- **Continuous** (1.5s window, stride 25): FFT frequency analysis via `FrequencyAnalyzer` (Accelerate vDSP). State machine with hysteresis: idle → candidate (0.5s) → active (1.0s) → cooldown (0.5s) → idle. Per-gesture match threshold (0.80–0.35). Outputs state + intensity.
- **Posture** (0.5s window, stride 50): Gravity vector matching with low-pass filter. Per-gesture angle tolerance (0.15–0.50 rad, ~9°–29°). Hysteresis: 500ms to activate, 300ms to deactivate.

`GestureClassifier` orchestrates all three layers with separate buffers and classification cadences. Energy gate threshold: 0.2.

### Per-Gesture Sensitivity
`TrainedGesture.sensitivity` (0.0–1.0, default 0.5) controls per-type thresholds:
- Discrete: `dtwDistanceThreshold` = 2.5 + sensitivity × 3.5; `triggerThreshold` = 0.70 - sensitivity × 0.40
- Continuous: `matchThreshold` = 0.80 - sensitivity × 0.45
- Posture: `toleranceAngle` = 0.15 + sensitivity × 0.35 (radians)

### Latency Measurement
`GestureClassifier` measures end-to-end classification latency (processSample dispatch → MainActor result) for all three layers. Logged in CSV, displayed in PerformanceView as colored pills (green <5ms, yellow <15ms, red >15ms).

### Gyro Calibration
`SensorManager.calibrate()` captures the current `CMAttitude` as reference. All subsequent attitude data is relative to this zero point via `multiply(byInverseOf:)`. Exposed as "Zero" button in PerformanceView.

## OSC Schema
Prefix: `/kinetic/` (user-editable)
- IMU: `.../attitude/quat` `.../rotation/rate` `.../accel/user` `.../gravity`
- Discrete: `.../gesture/[name]` (float prob>0.3), `.../gesture/[name]/trigger` (int velocity, per-gesture threshold, debounced)
- Continuous: `.../gesture/[name]/state` (int 0/1, on transitions), `.../gesture/[name]/intensity` (float 0–1, while active)
- Posture: `.../gesture/[name]/state` (int 0/1, on transitions)

## Session Logging & Analysis
- `PerformanceLogger` records CSV to `Documents/kinetic_sessions/` (persists on device)
- CSV columns: Time, AccXYZ, RotXYZ, Trigger, Probabilities, ContinuousState, PostureState, LatencyMs
- `SessionAnalyzer` parses CSVs and produces reports: trigger counts, rapid-fire detection, untriggered probability peaks, continuous/posture active durations, latency percentiles (p50/p95/p99)
- `SessionAnalysisView` lists on-device sessions, auto-analyzes most recent, with actionable recommendations

## Training
- **Discrete**: Hold-to-record, auto-segmented by `GestureSegmenter` (energy thresholds). Multiple recordings per gesture, reviewed before saving.
- **Continuous**: 10-second auto-timed recording. Extracts `ContinuousGestureProfile` (dominant frequency, band energies, axis distribution, amplitude range) via FFT. Multiple recordings averaged.
- **Posture**: 3-second countdown, captures average gravity vector.

## Constraints
- Dark mode only, large touch targets (stage use with gloves)
- No analytics/tracking. Motion data stays on-device except user-configured OSC.
- Zero external dependencies — Apple frameworks only
- JSON persistence in `Documents/kinetic_gestures/`, session CSVs in `Documents/kinetic_sessions/`

## Workflow
After each `TODO.md` phase:
1. Build — zero warnings
2. Test — full KineticTests + new phase tests
3. `/simplify` — check for unnecessary complexity
4. Commit — one per phase, message references phase number

Use `xcodebuild` MCP server (`.mcp.json`) for build/test/project inspection. Follow `TODO.md` phase order.
