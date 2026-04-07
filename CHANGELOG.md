# Changelog

## [Unreleased]
### Changed
- **Concurrency & Performance:** Fixed Swift 6 `@MainActor` concurrency violations by wrapping UI updates and `GestureClassifier` processing inside `Task { @MainActor in }` within `SensorManager` callbacks (`PerformanceView`, `TestModeView`, `TrainingView`).
- **OSC Encoding Optimization:** Moved OSC message encoding logic off the main thread to `sendQueue` in `OSCSender.swift`. `encodeOSCMessage` and related formatting methods are now explicitly `nonisolated`. This significantly reduces main-thread CPU load at high sample rates (100-200Hz).
