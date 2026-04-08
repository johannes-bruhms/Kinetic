# Kinetic Roadmap

> Priority order. Phases 1-4 are the minimum viable "next Kinetic."

## Completed Phases

### Phase 0: Baseline Freeze
- [x] All existing tests passing (32 original + 22 new = 54 total)
- [x] Zero build warnings with Swift 6 strict concurrency
- [x] Latency/session instrumentation in place

### Phase 1: Semantic Event Layer
- [x] `PerformanceEvent` model (EventLane, EventPhase, confidence, intensity, latency, ambiguity)
- [x] `FusedGestureState` for per-gesture state tracking
- [x] `EventFusionEngine` converts classifier outputs to typed events
- [x] Confidence smoothing (EMA, alpha 0.35)
- [x] Ambiguity detection (gap < 0.15 between top two predictions)
- [x] Debounce integrated into fusion (`.suppressed` phase for cooldown-blocked triggers)
- [x] `GestureClassifier.performanceEvents` published after each classification cycle
- [x] All three lanes (discrete, continuous, posture) produce events

### Phase 2: Calibration Profiles
- [x] `CalibrationProfile` model (reference attitude, gains, per-gesture sensitivity/cooldown)
- [x] `CalibrationManager` service (CRUD, JSON persistence in Documents/kinetic_calibrations/)
- [x] Capture current state into profile, apply profile to gesture library
- [x] `CalibrationManager` wired as environment object

### Phase 3: Fusion & Ambiguity
- [x] `GestureFamily` model (members, confusion sets, suppression rules, preferred lane)
- [x] `EventFusionEngine.loadFamilies()` for ambiguity resolution configuration
- [x] `.ambiguous` event phase with competing gesture names
- [x] `.suppressed` event phase for cooldown-blocked triggers
- [x] Explicit `.release` events on state transitions

### Phase 4: Routing & Presets
- [x] `MappingPreset` model (named collection of MappingRoute rules)
- [x] `MappingRoute` with EventFilter, RouteAction, ValueTransform
- [x] Route actions: trigger, state, intensity, latch, envelopeStart, envelopeEnd, macro
- [x] `PerformanceRouter` service (default routing + preset-based routing)
- [x] Default routing produces identical OSC output to pre-event architecture
- [x] PerformanceView uses router instead of manual OSC dispatch
- [x] TestModeView uses fusion engine events for trigger detection
- [x] Preset persistence (JSON in Documents/kinetic_mappings/)

## Future Phases

### Phase 5: Library v2
- [ ] Extend `GestureLibrary` with family metadata, tags, mapping defaults per gesture
- [ ] UI for creating/editing gesture families and confusion sets
- [ ] Gesture roles in performance vocabulary

### Phase 6: Session Analysis v2
- [ ] Structured event log alongside CSV (preserves fused event semantics)
- [ ] Analyzer reports: ambiguity duration, suppressed events, candidate-to-active conversion rate
- [ ] Per-lane confidence stability metrics
- [ ] Calibration drift detection

### Phase 7: Model Interchange
- [ ] Gesture packs (export/import gesture libraries with recordings)
- [ ] Versioned presets (calibration + mapping bundles)
- [ ] "Piece model" vs "practice model" switching

### Phase 8: Multi-Device / Companion
- [ ] Desktop companion viewer (Bonjour + OSC)
- [ ] Shared session monitoring
- [ ] Only after phases 1-6 are solid
