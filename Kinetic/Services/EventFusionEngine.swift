import Foundation
import Combine

/// Converts raw classifier outputs into typed PerformanceEvents.
/// Tracks per-gesture fused state, handles debounce, confidence smoothing,
/// and ambiguity detection across recognition lanes.
///
/// This is the central new component in the event architecture:
/// `sensors → preprocessing → recognition lanes → [EventFusionEngine] → routing/logging/ui`
@MainActor
final class EventFusionEngine: ObservableObject {
    // MARK: - Published Output

    /// Latest events from all three lanes combined.
    @Published var events: [PerformanceEvent] = []

    // MARK: - Configuration

    /// Per-gesture lane assignment (loaded from library).
    private var gestureLanes: [String: EventLane] = [:]

    /// Per-gesture trigger thresholds for discrete gestures.
    private var triggerThresholds: [String: Float] = [:]

    /// Per-gesture cooldown durations for discrete gestures (seconds).
    private var cooldowns: [String: TimeInterval] = [:]

    /// Gesture families for ambiguity resolution.
    private(set) var families: [GestureFamily] = []

    /// Confidence smoothing factor (EMA alpha). Higher = more responsive.
    var smoothingAlpha: Float = 0.35

    /// Ambiguity threshold: if top two discrete predictions differ by less than this, flag ambiguous.
    var ambiguityGap: Float = 0.15

    /// Minimum confidence to emit a candidate event.
    var candidateFloor: Float = 0.3

    // MARK: - Internal State

    /// Per-gesture fused state tracking.
    private var fusedStates: [String: FusedGestureState] = [:]

    /// Latest events per lane (combined into `events` after each update).
    private var discreteEvents: [PerformanceEvent] = []
    private var continuousEvents: [PerformanceEvent] = []
    private var postureEvents: [PerformanceEvent] = []

    // MARK: - Configuration Loading

    /// Load gesture configuration from the library. Call when templates change.
    func loadConfiguration(from library: GestureLibrary) {
        fusedStates.removeAll()
        gestureLanes.removeAll()
        triggerThresholds.removeAll()
        cooldowns.removeAll()

        for gesture in library.gestures {
            let lane: EventLane
            switch gesture.gestureType {
            case .discrete: lane = .discrete
            case .continuous: lane = .continuous
            case .posture: lane = .posture
            }
            gestureLanes[gesture.name] = lane

            if gesture.gestureType == .discrete {
                triggerThresholds[gesture.name] = gesture.discreteTriggerThreshold
                cooldowns[gesture.name] = gesture.cooldownDuration
            }

            fusedStates[gesture.name] = FusedGestureState(dominantLane: lane)
        }
    }

    /// Update gesture families for ambiguity resolution.
    func loadFamilies(_ families: [GestureFamily]) {
        self.families = families
    }

    // MARK: - Discrete Lane Processing

    /// Process discrete classifier output into events.
    /// Returns events for this cycle; also updates `self.events`.
    @discardableResult
    func processDiscrete(predictions: [String: Float], latencyMs: Double) -> [PerformanceEvent] {
        let now = CFAbsoluteTimeGetCurrent()
        var newEvents: [PerformanceEvent] = []

        // Sort predictions to detect ambiguity
        let significant = predictions
            .filter { $0.value > candidateFloor }
            .sorted { $0.value > $1.value }
        let topTwo = Array(significant.prefix(2))
        let isAmbiguous = topTwo.count >= 2 && (topTwo[0].value - topTwo[1].value) < ambiguityGap

        // Check if any gestures in the same family are competing
        let competingNames = isAmbiguous ? topTwo.map(\.key) : []

        for (name, rawProb) in predictions {
            // Only process discrete gestures (or unknown gestures, defaulting to discrete)
            let lane = gestureLanes[name]
            if let lane, lane != .discrete { continue }

            var state = fusedStates[name] ?? FusedGestureState(dominantLane: .discrete)
            let previousPhase = state.currentPhase

            // Confidence smoothing (exponential moving average)
            state.smoothedConfidence = smoothingAlpha * rawProb + (1 - smoothingAlpha) * state.smoothedConfidence

            let threshold = triggerThresholds[name] ?? 0.5
            let cooldown = cooldowns[name] ?? 0.5

            // Determine phase
            let phase: EventPhase
            var eventCompeting: [String] = []

            if rawProb > candidateFloor {
                if isAmbiguous && competingNames.contains(name) {
                    // Ambiguous: two gestures competing
                    phase = .ambiguous
                    eventCompeting = competingNames.filter { $0 != name }
                } else if rawProb > threshold {
                    // Above trigger threshold — check cooldown
                    if let lastTrigger = state.lastTriggerTime,
                       Date.now.timeIntervalSince(lastTrigger) < cooldown {
                        let remaining = cooldown - Date.now.timeIntervalSince(lastTrigger)
                        phase = .suppressed
                        state.cooldownRemainingMs = remaining * 1000
                    } else {
                        // Trigger!
                        phase = .active
                        if previousPhase != .active {
                            state.lastTriggerTime = .now
                            state.activeSince = now
                        }
                    }
                } else {
                    phase = .candidate
                }
            } else {
                // Below noise floor
                if previousPhase == .active || previousPhase == .candidate || previousPhase == .ambiguous {
                    phase = .release
                } else {
                    // Idle — don't emit an event
                    state.currentPhase = .release // will go idle next cycle
                    state.smoothedConfidence = max(0, state.smoothedConfidence - 0.1)
                    fusedStates[name] = state
                    continue
                }
            }

            state.currentPhase = phase
            state.competingGestures = eventCompeting
            state.lastEventAt = now
            fusedStates[name] = state

            var metrics: [String: Double] = ["rawProbability": Double(rawProb)]
            if let remaining = state.cooldownRemainingMs {
                metrics["cooldownRemainingMs"] = remaining
            }

            let event = PerformanceEvent(
                timestamp: now,
                gestureName: name,
                lane: .discrete,
                phase: phase,
                confidence: state.smoothedConfidence,
                latencyMs: latencyMs,
                ambiguityWith: eventCompeting,
                cooldownRemainingMs: phase == .suppressed ? state.cooldownRemainingMs : nil,
                sourceMetrics: metrics
            )
            newEvents.append(event)
        }

        discreteEvents = newEvents
        events = discreteEvents + continuousEvents + postureEvents
        return newEvents
    }

    // MARK: - Continuous Lane Processing

    /// Process continuous classifier output into events.
    @discardableResult
    func processContinuous(states: [String: ContinuousGestureState], latencyMs: Double) -> [PerformanceEvent] {
        let now = CFAbsoluteTimeGetCurrent()
        var newEvents: [PerformanceEvent] = []

        for (name, contState) in states {
            let phase: EventPhase
            switch contState.phase {
            case .idle:
                // Check for release transition
                let prev = fusedStates[name]?.currentPhase
                if prev == .active || prev == .candidate {
                    phase = .release
                } else {
                    // Truly idle — update state but don't emit
                    var state = fusedStates[name] ?? FusedGestureState(dominantLane: .continuous)
                    state.currentPhase = .release
                    state.activeSince = nil
                    fusedStates[name] = state
                    continue
                }
            case .candidate:
                phase = .candidate
            case .active:
                phase = .active
            case .cooldown:
                phase = .cooldown
            }

            var state = fusedStates[name] ?? FusedGestureState(dominantLane: .continuous)
            state.currentPhase = phase
            state.smoothedConfidence = contState.intensity

            if phase == .active && state.activeSince == nil {
                state.activeSince = now
            } else if phase == .release || phase == .cooldown {
                state.activeSince = nil
            }

            state.lastEventAt = now
            fusedStates[name] = state

            let event = PerformanceEvent(
                timestamp: now,
                gestureName: name,
                lane: .continuous,
                phase: phase,
                confidence: contState.intensity,
                intensity: contState.intensity,
                latencyMs: latencyMs,
                sourceMetrics: ["matchIntensity": Double(contState.intensity)]
            )
            newEvents.append(event)
        }

        continuousEvents = newEvents
        events = discreteEvents + continuousEvents + postureEvents
        return newEvents
    }

    // MARK: - Posture Lane Processing

    /// Process posture classifier output into events.
    @discardableResult
    func processPosture(states: [String: Bool], latencyMs: Double) -> [PerformanceEvent] {
        let now = CFAbsoluteTimeGetCurrent()
        var newEvents: [PerformanceEvent] = []

        for (name, isActive) in states {
            var state = fusedStates[name] ?? FusedGestureState(dominantLane: .posture)
            let previousPhase = state.currentPhase

            let phase: EventPhase
            if isActive {
                phase = .active
                state.smoothedConfidence = 1.0
                if state.activeSince == nil { state.activeSince = now }
            } else {
                if previousPhase == .active {
                    phase = .release
                } else {
                    // Already idle
                    state.currentPhase = .release
                    state.activeSince = nil
                    fusedStates[name] = state
                    continue
                }
                state.smoothedConfidence = 0
                state.activeSince = nil
            }

            state.currentPhase = phase
            state.lastEventAt = now
            fusedStates[name] = state

            let event = PerformanceEvent(
                timestamp: now,
                gestureName: name,
                lane: .posture,
                phase: phase,
                confidence: state.smoothedConfidence,
                intensity: isActive ? 1.0 : 0.0,
                latencyMs: latencyMs
            )
            newEvents.append(event)
        }

        postureEvents = newEvents
        events = discreteEvents + continuousEvents + postureEvents
        return newEvents
    }

    // MARK: - Query

    /// Get the current fused state for a gesture.
    func fusedState(for gestureName: String) -> FusedGestureState? {
        fusedStates[gestureName]
    }

    /// Check if a gesture was just triggered (active phase, first cycle).
    func wasTrigger(_ event: PerformanceEvent) -> Bool {
        event.phase == .active && event.lane == .discrete
    }

    // MARK: - Reset

    func reset() {
        fusedStates.removeAll()
        discreteEvents.removeAll()
        continuousEvents.removeAll()
        postureEvents.removeAll()
        events.removeAll()
    }
}

