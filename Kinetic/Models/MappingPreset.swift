import Foundation

/// How a routed event should be expressed as OSC output.
nonisolated enum RouteAction: String, Codable, Sendable, CaseIterable {
    /// Send probability float (standard discrete output).
    case trigger
    /// Send state int (0/1) on transitions.
    case state
    /// Send intensity float (0-1) while active.
    case intensity
    /// Toggle on first active, off on next active.
    case latch
    /// Send value on active start.
    case envelopeStart
    /// Send value on release.
    case envelopeEnd
    /// Send normalized confidence as a continuous control value.
    case macro
}

/// Transforms applied to the event value before OSC output.
nonisolated struct ValueTransform: Codable, Sendable {
    /// Multiply the value by this factor.
    var scale: Float
    /// Add this offset after scaling.
    var offset: Float
    /// Clamp output to this range.
    var clampMin: Float
    var clampMax: Float

    static let identity = ValueTransform(scale: 1.0, offset: 0.0, clampMin: 0.0, clampMax: 1.0)

    func apply(to value: Float) -> Float {
        let scaled = value * scale + offset
        return min(max(scaled, clampMin), clampMax)
    }
}

/// Filters which events a route applies to.
nonisolated struct EventFilter: Codable, Sendable {
    /// Match specific gesture name (nil = match all).
    var gestureName: String?
    /// Match specific lane (nil = match all).
    var lane: EventLane?
    /// Match specific phases (empty = match all).
    var phases: [EventPhase]

    init(gestureName: String? = nil, lane: EventLane? = nil, phases: [EventPhase] = []) {
        self.gestureName = gestureName
        self.lane = lane
        self.phases = phases
    }

    func matches(_ event: PerformanceEvent) -> Bool {
        if let name = gestureName, event.gestureName != name { return false }
        if let lane = lane, event.lane != lane { return false }
        if !phases.isEmpty && !phases.contains(event.phase) { return false }
        return true
    }
}

/// A single mapping route: when an event matches the filter, perform the action
/// on the given OSC address with the given value transform.
nonisolated struct MappingRoute: Identifiable, Codable, Sendable {
    let id: UUID
    var eventFilter: EventFilter
    var action: RouteAction
    /// Custom OSC address (nil = use default schema).
    var oscAddress: String?
    var valueTransform: ValueTransform

    init(
        id: UUID = UUID(),
        eventFilter: EventFilter,
        action: RouteAction,
        oscAddress: String? = nil,
        valueTransform: ValueTransform = .identity
    ) {
        self.id = id
        self.eventFilter = eventFilter
        self.action = action
        self.oscAddress = oscAddress
        self.valueTransform = valueTransform
    }
}

/// A named collection of mapping routes that can be saved, loaded, and switched
/// between performances. Empty routes array means "use default routing."
nonisolated struct MappingPreset: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var routes: [MappingRoute]
    var notes: String
    var lastModified: Date

    init(
        id: UUID = UUID(),
        name: String,
        routes: [MappingRoute] = [],
        notes: String = "",
        lastModified: Date = .now
    ) {
        self.id = id
        self.name = name
        self.routes = routes
        self.notes = notes
        self.lastModified = lastModified
    }

    /// Whether this preset uses default routing (no custom routes).
    var isDefault: Bool { routes.isEmpty }
}
