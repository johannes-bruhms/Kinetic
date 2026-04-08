import Foundation
import Combine

/// Maps PerformanceEvents to OSC output via OSCSender.
/// Default routing preserves the existing OSC schema exactly.
/// Custom MappingPreset routes can override or extend the defaults.
@MainActor
final class PerformanceRouter: ObservableObject {
    /// Active mapping preset (nil = default routing).
    @Published var activePreset: MappingPreset?

    /// Saved mapping presets.
    @Published var presets: [MappingPreset] = []

    /// Callback fired when a discrete gesture triggers (for haptics/UI).
    var onTrigger: ((PerformanceEvent) -> Void)?

    private let oscSender: OSCSender

    // State tracking for transition detection
    private var previousContinuousActive: Set<String> = []
    private var previousPostureActive: Set<String> = []

    // Latch state for latch-mode routes
    private var latchStates: [String: Bool] = [:]

    private let storageURL: URL

    init(oscSender: OSCSender) {
        self.oscSender = oscSender
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documents.appendingPathComponent("kinetic_mappings")
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadPresets()
    }

    // MARK: - Event Routing

    /// Route a batch of events from the fusion engine.
    func route(_ events: [PerformanceEvent]) {
        for event in events {
            if let preset = activePreset, !preset.isDefault {
                routeWithPreset(event, preset: preset)
            } else {
                routeDefault(event)
            }
        }
    }

    /// Default routing: produces exactly the same OSC output as the original PerformanceView.
    private func routeDefault(_ event: PerformanceEvent) {
        switch event.lane {
        case .discrete:
            routeDiscreteDefault(event)
        case .continuous:
            routeContinuousDefault(event)
        case .posture:
            routePostureDefault(event)
        }
    }

    private func routeDiscreteDefault(_ event: PerformanceEvent) {
        // Send probability for any event above candidate floor
        switch event.phase {
        case .candidate, .ambiguous, .suppressed:
            oscSender.sendGestureEvent(name: event.gestureName, probability: event.confidence)
        case .active:
            oscSender.sendGestureEvent(name: event.gestureName, probability: event.confidence)
            oscSender.sendGestureTrigger(name: event.gestureName)
            onTrigger?(event)
        case .release, .cooldown:
            break
        }
    }

    private func routeContinuousDefault(_ event: PerformanceEvent) {
        let isActive = event.phase == .active
        let wasActive = previousContinuousActive.contains(event.gestureName)

        // Send state transitions
        if isActive != wasActive {
            oscSender.sendGestureState(name: event.gestureName, isActive: isActive)
            if isActive {
                previousContinuousActive.insert(event.gestureName)
            } else {
                previousContinuousActive.remove(event.gestureName)
            }
        }

        // Send intensity while active
        if isActive, let intensity = event.intensity {
            oscSender.sendGestureIntensity(name: event.gestureName, intensity: intensity)
        }
    }

    private func routePostureDefault(_ event: PerformanceEvent) {
        let isActive = event.phase == .active
        let wasActive = previousPostureActive.contains(event.gestureName)

        if isActive != wasActive {
            oscSender.sendGestureState(name: event.gestureName, isActive: isActive)
            if isActive {
                previousPostureActive.insert(event.gestureName)
            } else {
                previousPostureActive.remove(event.gestureName)
            }
        }
    }

    // MARK: - Preset-Based Routing

    private func routeWithPreset(_ event: PerformanceEvent, preset: MappingPreset) {
        var matched = false
        for route in preset.routes where route.eventFilter.matches(event) {
            matched = true
            executeRoute(route, event: event)
        }
        // Fall through to default for unmatched events
        if !matched {
            routeDefault(event)
        }
    }

    private func executeRoute(_ route: MappingRoute, event: PerformanceEvent) {
        let prefix = oscSender.configuration.prefix
        let address = route.oscAddress ?? "\(prefix)gesture/\(event.gestureName)"

        switch route.action {
        case .trigger:
            if event.phase == .active {
                let value = route.valueTransform.apply(to: event.confidence)
                oscSender.sendGestureEvent(name: event.gestureName, probability: value)
                oscSender.sendGestureTrigger(name: event.gestureName)
                onTrigger?(event)
            }

        case .state:
            let isActive = event.phase == .active
            oscSender.sendGestureState(name: event.gestureName, isActive: isActive)

        case .intensity:
            if let intensity = event.intensity {
                let value = route.valueTransform.apply(to: intensity)
                oscSender.sendGestureIntensity(name: event.gestureName, intensity: value)
            }

        case .latch:
            if event.phase == .active {
                let key = address
                let current = latchStates[key] ?? false
                latchStates[key] = !current
                oscSender.sendGestureState(name: event.gestureName, isActive: !current)
                if !current { onTrigger?(event) }
            }

        case .envelopeStart:
            if event.phase == .active {
                let value = route.valueTransform.apply(to: event.confidence)
                oscSender.sendGestureEvent(name: event.gestureName, probability: value)
            }

        case .envelopeEnd:
            if event.phase == .release {
                oscSender.sendGestureEvent(name: event.gestureName, probability: 0)
            }

        case .macro:
            let value = route.valueTransform.apply(to: event.confidence)
            oscSender.sendGestureEvent(name: event.gestureName, probability: value)
        }
    }

    // MARK: - Reset

    func reset() {
        previousContinuousActive.removeAll()
        previousPostureActive.removeAll()
        latchStates.removeAll()
    }

    // MARK: - Preset Management

    @discardableResult
    func savePreset(_ preset: MappingPreset) -> MappingPreset {
        var updated = preset
        updated.lastModified = .now
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = updated
        } else {
            presets.append(updated)
        }
        persistPresets()
        return updated
    }

    func deletePreset(_ preset: MappingPreset) {
        presets.removeAll { $0.id == preset.id }
        if activePreset?.id == preset.id {
            activePreset = nil
        }
        persistPresets()
    }

    private var presetsURL: URL {
        storageURL.appendingPathComponent("presets.json")
    }

    private func persistPresets() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(presets) {
            try? data.write(to: presetsURL)
        }
    }

    private func loadPresets() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: presetsURL),
           let loaded = try? decoder.decode([MappingPreset].self, from: data) {
            presets = loaded
        }
    }
}
