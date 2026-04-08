import Testing
@testable import Kinetic

@MainActor
struct EventFusionEngineTests {
    private func makeEngine() -> EventFusionEngine {
        let engine = EventFusionEngine()
        // Manually configure for testing (no library needed)
        return engine
    }

    @Test func discreteCandidateEvent() {
        let engine = makeEngine()
        let events = engine.processDiscrete(
            predictions: ["punch": 0.4],
            latencyMs: 2.0
        )
        #expect(events.count == 1)
        #expect(events[0].gestureName == "punch")
        #expect(events[0].phase == .candidate)
        #expect(events[0].lane == .discrete)
    }

    @Test func discreteActiveEvent() {
        let engine = makeEngine()
        // With no configured threshold, default is 0.5
        let events = engine.processDiscrete(
            predictions: ["punch": 0.8],
            latencyMs: 1.5
        )
        #expect(events.count == 1)
        #expect(events[0].phase == .active)
        #expect(events[0].gestureName == "punch")
    }

    @Test func discreteAmbiguityDetection() {
        let engine = makeEngine()
        engine.ambiguityGap = 0.1
        let events = engine.processDiscrete(
            predictions: ["punch": 0.65, "chop": 0.60],
            latencyMs: 2.0
        )
        let ambiguousEvents = events.filter { $0.phase == .ambiguous }
        #expect(ambiguousEvents.count == 2)
        // Each ambiguous event should reference the other gesture
        let punchEvent = ambiguousEvents.first { $0.gestureName == "punch" }
        #expect(punchEvent?.ambiguityWith.contains("chop") == true)
    }

    @Test func discreteSuppressedByCooldown() {
        let engine = makeEngine()
        // First trigger should be active
        let first = engine.processDiscrete(predictions: ["punch": 0.8], latencyMs: 1.0)
        #expect(first[0].phase == .active)

        // Immediate second should be suppressed (cooldown)
        let second = engine.processDiscrete(predictions: ["punch": 0.8], latencyMs: 1.0)
        #expect(second[0].phase == .suppressed)
    }

    @Test func discreteBelowFloorNoEvent() {
        let engine = makeEngine()
        // First: create a candidate state
        _ = engine.processDiscrete(predictions: ["punch": 0.4], latencyMs: 1.0)
        // Then drop below floor — should get release
        let events = engine.processDiscrete(predictions: ["punch": 0.1], latencyMs: 1.0)
        #expect(events.count == 1)
        #expect(events[0].phase == .release)
        // Next cycle should produce no events (already idle)
        let idle = engine.processDiscrete(predictions: ["punch": 0.05], latencyMs: 1.0)
        #expect(idle.isEmpty)
    }

    @Test func confidenceSmoothing() {
        let engine = makeEngine()
        engine.smoothingAlpha = 0.5

        // Prime with several high-value cycles to build up smoothed confidence
        _ = engine.processDiscrete(predictions: ["punch": 0.8], latencyMs: 1.0)
        _ = engine.processDiscrete(predictions: ["punch": 0.8], latencyMs: 1.0)
        let primed = engine.processDiscrete(predictions: ["punch": 0.8], latencyMs: 1.0)
        let primedConfidence = primed[0].confidence

        // Now drop to a lower value — smoothed should lag behind
        let dropped = engine.processDiscrete(predictions: ["punch": 0.35], latencyMs: 1.0)
        let droppedConfidence = dropped[0].confidence

        // Smoothed confidence should be between raw 0.35 and the primed value
        #expect(droppedConfidence > 0.35)
        #expect(droppedConfidence < primedConfidence)
    }

    @Test func continuousEventPhases() {
        let engine = makeEngine()

        // Candidate phase
        let candidate = ContinuousGestureState(phase: .candidate, intensity: 0.3, phaseEntryTime: 0)
        let candidateEvents = engine.processContinuous(states: ["shake": candidate], latencyMs: 2.0)
        #expect(candidateEvents.count == 1)
        #expect(candidateEvents[0].phase == .candidate)

        // Active phase
        let active = ContinuousGestureState(phase: .active, intensity: 0.75, phaseEntryTime: 0)
        let activeEvents = engine.processContinuous(states: ["shake": active], latencyMs: 2.0)
        #expect(activeEvents.count == 1)
        #expect(activeEvents[0].phase == .active)
        #expect(activeEvents[0].intensity == 0.75)

        // Cooldown phase
        let cooldown = ContinuousGestureState(phase: .cooldown, intensity: 0.0, phaseEntryTime: 0)
        let cooldownEvents = engine.processContinuous(states: ["shake": cooldown], latencyMs: 2.0)
        #expect(cooldownEvents.count == 1)
        #expect(cooldownEvents[0].phase == .cooldown)
    }

    @Test func continuousIdleReleaseThenNoEvent() {
        let engine = makeEngine()

        // First active
        let active = ContinuousGestureState(phase: .active, intensity: 0.8, phaseEntryTime: 0)
        _ = engine.processContinuous(states: ["shake": active], latencyMs: 1.0)

        // Then idle — should produce release
        let idle = ContinuousGestureState(phase: .idle, intensity: 0.0, phaseEntryTime: 0)
        let releaseEvents = engine.processContinuous(states: ["shake": idle], latencyMs: 1.0)
        #expect(releaseEvents.count == 1)
        #expect(releaseEvents[0].phase == .release)

        // Another idle — no event
        let noEvents = engine.processContinuous(states: ["shake": idle], latencyMs: 1.0)
        #expect(noEvents.isEmpty)
    }

    @Test func postureActiveAndRelease() {
        let engine = makeEngine()

        // Active
        let activeEvents = engine.processPosture(states: ["vertical": true], latencyMs: 1.0)
        #expect(activeEvents.count == 1)
        #expect(activeEvents[0].phase == .active)
        #expect(activeEvents[0].intensity == 1.0)

        // Release
        let releaseEvents = engine.processPosture(states: ["vertical": false], latencyMs: 1.0)
        #expect(releaseEvents.count == 1)
        #expect(releaseEvents[0].phase == .release)

        // Subsequent false — no event
        let noEvents = engine.processPosture(states: ["vertical": false], latencyMs: 1.0)
        #expect(noEvents.isEmpty)
    }

    @Test func resetClearsState() {
        let engine = makeEngine()
        _ = engine.processDiscrete(predictions: ["punch": 0.8], latencyMs: 1.0)
        #expect(!engine.events.isEmpty)

        engine.reset()
        #expect(engine.events.isEmpty)
        #expect(engine.fusedState(for: "punch") == nil)
    }

    @Test func multiLaneEventsAccumulate() {
        let engine = makeEngine()

        // Discrete event
        engine.processDiscrete(predictions: ["punch": 0.8], latencyMs: 1.0)
        #expect(engine.events.count == 1)

        // Continuous event — should add to total
        let active = ContinuousGestureState(phase: .active, intensity: 0.7, phaseEntryTime: 0)
        engine.processContinuous(states: ["shake": active], latencyMs: 2.0)
        #expect(engine.events.count == 2)

        // Posture event — should add to total
        engine.processPosture(states: ["tilt": true], latencyMs: 0.5)
        #expect(engine.events.count == 3)

        // Verify lane distribution
        let lanes = Set(engine.events.map(\.lane))
        #expect(lanes.contains(.discrete))
        #expect(lanes.contains(.continuous))
        #expect(lanes.contains(.posture))
    }
}
