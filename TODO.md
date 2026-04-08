# Kinetic — Layered Gesture Recognition Architecture

## Status

All 10 architecture phases + post-launch refinements implemented. Build: zero warnings. Tests: 32/32 passing.

### Architecture Phases (complete)
- [x] Phase 1: Data Model & Gesture Types (`GestureType` enum, backward-compatible decoding)
- [x] Phase 2: Frequency-Domain Feature Extractor (`FrequencyAnalyzer` with vDSP FFT, `ContinuousClassifier` with hysteresis state machine)
- [x] Phase 3: Posture Recognition Layer (`PostureClassifier` with gravity vector matching + low-pass filter)
- [x] Phase 4: Unified Classifier Integration (3-buffer orchestrator in `GestureClassifier`, type-based template routing)
- [x] Phase 5: OSC Output for New Layers (`sendGestureState`, `sendGestureIntensity`, integer OSC encoding)
- [x] Phase 6: Training UI (type picker in library, `DiscreteTrainingSection`, `ContinuousTrainingSection`, `PostureTrainingSection`)
- [x] Phase 7: Performance & Test UI Updates (continuous state indicators, posture badges, type-colored probability bars)
- [x] Phase 8: Session Logging Updates (CSV columns for continuous state + posture state)
- [x] Phase 9: Debounce & Cooldown (per-gesture `shouldTrigger()` with configurable cooldown on `TrainedGesture`)
- [x] Phase 10: Testing (`FrequencyAnalyzerTests`, `ContinuousClassifierTests`, `PostureClassifierTests`, `DebouncedTriggerTests`)

### Post-Launch Refinements (complete)
- [x] Latency measurement — end-to-end timing for all three classification layers, logged in CSV, shown in UI
- [x] Per-gesture sensitivity — `TrainedGesture.sensitivity` controls DTW threshold + trigger threshold (discrete), match threshold (continuous), angle tolerance (posture). `GestureDetailView` with slider.
- [x] Session analysis tooling — `SessionAnalyzer` + `SessionAnalysisView` with on-device session listing, trigger/probability/latency/activity stats, recommendations
- [x] Discrete detection fix — DTW distance threshold scaled by sensitivity (2.5–6.0), trigger threshold inverted (0.70–0.30), energy gate lowered to 0.2
- [x] Auto-stop continuous training — 10-second countdown timer with visual progress
- [x] Gyro calibration — reference attitude capture via `CMAttitude.multiply(byInverseOf:)`, "Zero" button in PerformanceView
- [x] On-device log storage — sessions persist in `Documents/kinetic_sessions/`, auto-analyzed in SessionAnalysisView

---

## Background

The current gesture pipeline uses a single strategy (DTW with 0.5s sliding window) for all gestures. This works well for short, discrete gestures (chops, flicks) but fails for longer continuous motions (shaking, arm circles) and static postures (phone held vertical). The agreed-upon solution is a **three-layer parallel recognition architecture** where each layer runs simultaneously on the same IMU sample stream, tuned to a different temporal scale.

Session analysis from `kinetic_session_1775582702.csv` confirmed:
- Gestures A-D are highly distinct (0 competitive frames)
- Gesture D has a wide trigger window (350ms) and many near-misses, suggesting it may be a longer motion poorly served by the short window
- Debounce/cooldown is needed to prevent rapid-fire trigger bursts

---

## Phase 1: Data Model & Gesture Types

### 1.1 Add `GestureType` enum
- **File**: `Kinetic/Models/GestureModel.swift`
- Add enum: `.discrete`, `.continuous`, `.posture`
- Add `gestureType: GestureType` property to `TrainedGesture` (default `.discrete` for backward compatibility)
- Ensure JSON encoding/decoding works with existing saved gestures (missing key = `.discrete`)

### 1.2 Update `GestureRecording` for continuous/posture data
- Continuous recordings are longer (~10s) — the model stores the full recording but the classifier extracts frequency-domain features from it
- Posture recordings are short (~3s) — the model stores a gravity vector snapshot (mean over the hold period)
- Add optional metadata: `recordingDuration: TimeInterval`, `extractedProfile: ContinuousGestureProfile?`, `postureVector: Vector3?`

### 1.3 Add `ContinuousGestureProfile` model
- **File**: `Kinetic/Models/ContinuousGestureProfile.swift` (new)
- Stores extracted frequency-domain signature from training recordings:
  - `dominantFrequency: Double` (Hz)
  - `frequencyBandEnergy: [Double]` (energy distribution across frequency bins)
  - `axisDistribution: Vector3` (which axes carry the most energy — distinguishes shake vs circle)
  - `amplitudeRange: ClosedRange<Double>` (expected energy level)
- This profile is what the continuous classifier matches against at runtime

---

## Phase 2: Frequency-Domain Feature Extractor

### 2.1 Build `FrequencyAnalyzer` service
- **File**: `Kinetic/Services/FrequencyAnalyzer.swift` (new)
- `nonisolated` + `Sendable` (same pattern as DTWClassifier)
- Implements FFT or autocorrelation-based frequency extraction on a buffer of MotionSamples
- Key functions:
  - `dominantFrequency(from samples: [MotionSample]) -> Double` — peak frequency in acceleration magnitude
  - `zeroCrossingRate(from samples: [MotionSample]) -> Double` — simpler alternative/complement to FFT
  - `frequencyBandEnergies(from samples: [MotionSample], bands: Int) -> [Double]`
  - `axisEnergyDistribution(from samples: [MotionSample]) -> Vector3` — normalized energy per axis
- Use Accelerate framework (`vDSP_fft`) for efficient FFT — this is still a pure Apple framework (no external deps)
- Buffer size: 150 samples (1.5s at 100Hz) gives frequency resolution down to ~0.67Hz, enough for arm circles (~1Hz)

### 2.2 Build `ContinuousClassifier` service
- **File**: `Kinetic/Services/ContinuousClassifier.swift` (new)
- `nonisolated` + `Sendable`
- Holds trained `ContinuousGestureProfile` templates
- Classification: compare live frequency features against each profile using weighted distance
- Hysteresis state machine per gesture: `idle → candidate → active → cooldown → idle`
  - `idle → candidate`: frequency match exceeds threshold for >0.5s
  - `candidate → active`: sustained match for full 1.0s (prevents false activation from transient motions)
  - `active → cooldown`: frequency match drops below threshold
  - `cooldown → idle`: stays below threshold for 0.5s (prevents flicker during brief pauses in shaking)
- Output: `(gestureName: String, isActive: Bool, intensity: Float)` — intensity derived from amplitude relative to training amplitude

### 2.3 Profile extraction during training
- When user records a continuous gesture for ~10s, extract the `ContinuousGestureProfile` automatically
- Average across multiple training recordings for robustness
- Validate: warn user if dominant frequency is unclear (motion too irregular) or if profile overlaps an existing continuous gesture

---

## Phase 3: Posture Recognition Layer

### 3.1 Build `PostureClassifier` service
- **File**: `Kinetic/Services/PostureClassifier.swift` (new)
- Simplest layer — no ML, no DTW, just gravity vector matching
- Holds trained posture templates: `(name: String, gravityVector: Vector3, toleranceAngle: Double)`
- Classification: compute angle between current gravity vector and each template; match if within tolerance (~15-20 degrees)
- Hysteresis: require stable match for ~500ms before activating, require ~300ms of deviation before deactivating
- Low-pass filter the gravity vector to reject transient wobble from discrete gestures

### 3.2 Posture training flow
- User holds phone in desired position for 3 seconds
- App records gravity vector, averages over the hold period
- Store as posture template with configurable tolerance

---

## Phase 4: Unified Classifier Integration

### 4.1 Refactor `GestureClassifier` as orchestrator
- **File**: `Kinetic/Services/GestureClassifier.swift` (modify)
- Maintain three internal buffers:
  - `discreteBuffer`: 50 samples (0.5s) — feeds DTW/RandomForest (existing)
  - `continuousBuffer`: 150 samples (1.5s) — feeds FrequencyAnalyzer + ContinuousClassifier
  - `postureBuffer`: 50 samples (0.5s) — feeds PostureClassifier (low-pass filtered gravity)
- `processSample()` pushes to all three buffers simultaneously
- Each layer runs its own classification cadence:
  - Discrete: every 10 samples (existing stride)
  - Continuous: every 25 samples (~250ms)
  - Posture: every 50 samples (~500ms)
- Merge predictions into unified output:
  - `@Published var discretePredictions: [String: Float]` — probabilities (existing `predictions`)
  - `@Published var continuousStates: [String: ContinuousGestureState]` — active/inactive + intensity
  - `@Published var postureStates: [String: Bool]` — active/inactive

### 4.2 Template loading
- `loadTemplates(from library:)` routes gestures by type:
  - `.discrete` → DTW templates + Random Forest training (existing path)
  - `.continuous` → ContinuousClassifier profiles
  - `.posture` → PostureClassifier gravity templates

---

## Phase 5: OSC Output for New Layers

### 5.1 Extend `OSCSender` with new message types
- **File**: `Kinetic/Services/OSCSender.swift` (modify)
- Continuous gestures:
  - `/kinetic/gesture/[name]/state` (int 0 or 1) — sent on state transitions only
  - `/kinetic/gesture/[name]/intensity` (float 0.0–1.0) — sent continuously while active
- Posture gestures:
  - `/kinetic/gesture/[name]/state` (int 0 or 1) — sent on state transitions only
- Discrete gestures: unchanged (existing `/trigger` and probability messages)
- Add debounce/cooldown for discrete triggers: configurable per-gesture, default 500ms

### 5.2 Update OSC schema in CLAUDE.md and Settings
- Document new address patterns
- Add user-configurable cooldown duration in SettingsView

---

## Phase 6: Training UI

### 6.1 Gesture type selection
- **File**: `Kinetic/Views/GestureLibraryView.swift` (modify)
- When creating a new gesture, present type picker: Discrete / Continuous / Posture
- Show appropriate icon/badge per type in the gesture list
- Type is set at creation and cannot be changed (would invalidate recordings)

### 6.2 Discrete training flow (existing, minor changes)
- No major changes — current flow works well
- Add cooldown/debounce setting per gesture

### 6.3 Continuous training flow
- **File**: `Kinetic/Views/TrainingView.swift` (modify, or new `ContinuousTrainingView.swift`)
- Recording UI: "Perform the gesture continuously for 10 seconds"
- Show real-time frequency visualization during recording (dominant frequency + energy)
- After recording: extract profile, show summary ("Detected: ~3.5Hz shake, primarily Y-axis")
- Allow multiple recordings, average the profiles
- Validation: warn if frequency is unstable or overlaps another continuous gesture

### 6.4 Posture training flow
- **File**: `Kinetic/Views/PostureTrainingView.swift` (new)
- "Hold the phone in position... 3... 2... 1... captured!"
- Show gravity vector visualization (simple 3D arrow or attitude indicator)
- Allow tolerance adjustment (slider: tight → loose)

---

## Phase 7: Performance & Test UI Updates

### 7.1 PerformanceView updates
- **File**: `Kinetic/Views/PerformanceView.swift`
- Show discrete gesture probability bars (existing)
- Add continuous gesture state indicators (pill-shaped badges: "shake: ACTIVE" with intensity bar)
- Add posture state indicators (smaller badges: "vertical: ON")
- Group by layer visually

### 7.2 TestModeView updates
- **File**: `Kinetic/Views/TestModeView.swift`
- Show all three layers in test mode
- Continuous gestures: large state indicator + intensity meter
- Posture: clear on/off indicator
- Haptic feedback: discrete = impact, continuous activation = notification, posture = light tap

### 7.3 GestureProbabilityBarsView updates
- **File**: `Kinetic/Views/GestureProbabilityBarsView.swift`
- Color-code by gesture type (e.g., blue = discrete, green = continuous, amber = posture)

---

## Phase 8: Session Logging Updates

### 8.1 Extend PerformanceLogger
- **File**: `Kinetic/Services/Logging/PerformanceLogger.swift`
- Log continuous gesture state transitions: timestamp, gesture name, state (active/inactive), intensity
- Log posture state transitions: timestamp, gesture name, state
- CSV format extension: add columns for continuous/posture state, or use separate log sections
- This enables the same kind of session analysis that revealed the D-gesture near-miss problem

---

## Phase 9: Debounce & Cooldown (Discrete Layer)

### 9.1 Add per-gesture cooldown
- **File**: `Kinetic/Services/GestureClassifier.swift` or new `DebouncedTrigger.swift`
- After a discrete gesture triggers (probability > 0.9), suppress re-triggering for a configurable cooldown period (default 500ms)
- Store `lastTriggerTime` per gesture name
- Expose cooldown duration in gesture settings (per-gesture, in GestureLibraryView detail)
- This directly addresses the "35 rapid-fire trigger messages for Gesture D" issue from session analysis

---

## Phase 10: Testing

### 10.1 Unit tests for new classifiers
- `FrequencyAnalyzerTests` — test FFT extraction on synthetic sinusoidal data
- `ContinuousClassifierTests` — test state machine transitions (idle → active → idle)
- `PostureClassifierTests` — test gravity vector matching and tolerance
- `DebouncedTriggerTests` — test cooldown timing

### 10.2 Integration tests
- Test that all three layers can run simultaneously without interference
- Test that a discrete gesture during a continuous gesture doesn't disrupt either
- Test backward compatibility: existing gesture libraries (all discrete) load and work without migration

---

## Implementation Order (Suggested)

1. **Phase 1** — Data model changes (foundation for everything)
2. **Phase 9** — Debounce/cooldown (quick win, addresses known session issue)
3. **Phase 3** — Posture layer (simplest new layer, no FFT needed)
4. **Phase 2** — Frequency analyzer + continuous classifier (most complex new code)
5. **Phase 4** — Unified classifier integration
6. **Phase 5** — OSC output extensions
7. **Phase 6** — Training UI for all layers
8. **Phase 7** — Performance/Test UI updates
9. **Phase 8** — Logging extensions
10. **Phase 10** — Testing throughout, but especially after phases 4 and 6
