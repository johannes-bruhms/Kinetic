import Foundation

/// Which recognition layer produced an event.
nonisolated enum EventLane: String, Codable, Sendable, CaseIterable {
    case discrete
    case continuous
    case posture
}

/// Lifecycle phase of a gesture event.
nonisolated enum EventPhase: String, Codable, Sendable {
    /// Gesture detected above noise floor but below trigger threshold.
    case candidate
    /// Gesture confirmed and triggered (discrete) or sustained (continuous/posture).
    case active
    /// Gesture ended — transitioning out of active.
    case release
    /// Post-trigger cooldown period (discrete) or post-active cooldown (continuous).
    case cooldown
    /// Two or more gestures competing with similar confidence.
    case ambiguous
    /// Trigger threshold met but suppressed by cooldown.
    case suppressed
}

/// The canonical runtime event object. Every downstream consumer (UI, OSC, logger)
/// speaks this language instead of reconstructing meaning from raw classifier outputs.
nonisolated struct PerformanceEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let gestureName: String
    let lane: EventLane
    let phase: EventPhase

    /// Smoothed confidence (0-1). For discrete: probability. For continuous: match score.
    /// For posture: 1.0 when active, 0.0 otherwise.
    let confidence: Float

    /// Normalized intensity (0-1). Only meaningful for continuous gestures.
    let intensity: Float?

    /// End-to-end classification latency in milliseconds.
    let latencyMs: Double?

    /// Names of competing gestures when phase is `.ambiguous`.
    let ambiguityWith: [String]

    /// Remaining cooldown in milliseconds when phase is `.suppressed` or `.cooldown`.
    let cooldownRemainingMs: Double?

    /// Raw per-lane metrics for debugging/logging.
    let sourceMetrics: [String: Double]

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval = CFAbsoluteTimeGetCurrent(),
        gestureName: String,
        lane: EventLane,
        phase: EventPhase,
        confidence: Float,
        intensity: Float? = nil,
        latencyMs: Double? = nil,
        ambiguityWith: [String] = [],
        cooldownRemainingMs: Double? = nil,
        sourceMetrics: [String: Double] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.gestureName = gestureName
        self.lane = lane
        self.phase = phase
        self.confidence = confidence
        self.intensity = intensity
        self.latencyMs = latencyMs
        self.ambiguityWith = ambiguityWith
        self.cooldownRemainingMs = cooldownRemainingMs
        self.sourceMetrics = sourceMetrics
    }

    /// Whether this event represents a confirmed trigger (discrete) or active state.
    var isTriggered: Bool { phase == .active }

    /// Whether this event carries ambiguity information.
    var isAmbiguous: Bool { phase == .ambiguous }
}

/// Tracks the fused state of a single gesture across recognition cycles.
nonisolated struct FusedGestureState: Sendable {
    var currentPhase: EventPhase = .candidate
    var smoothedConfidence: Float = 0
    var dominantLane: EventLane = .discrete
    var competingGestures: [String] = []
    var activeSince: TimeInterval?
    var lastEventAt: TimeInterval?
    var lastTriggerTime: Date?
    var cooldownRemainingMs: Double?
}
