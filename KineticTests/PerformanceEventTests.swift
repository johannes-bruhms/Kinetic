import Testing
import Foundation
@testable import Kinetic

struct PerformanceEventTests {
    @Test func eventLaneCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for lane in EventLane.allCases {
            let data = try encoder.encode(lane)
            let decoded = try decoder.decode(EventLane.self, from: data)
            #expect(decoded == lane)
        }
    }

    @Test func performanceEventCreation() {
        let event = PerformanceEvent(
            gestureName: "punch",
            lane: .discrete,
            phase: .active,
            confidence: 0.85,
            intensity: nil,
            latencyMs: 3.2,
            ambiguityWith: ["chop"]
        )

        #expect(event.gestureName == "punch")
        #expect(event.lane == .discrete)
        #expect(event.phase == .active)
        #expect(event.confidence == 0.85)
        #expect(event.isTriggered == true)
        #expect(event.isAmbiguous == false)
        #expect(event.ambiguityWith == ["chop"])
    }

    @Test func eventIsTriggered() {
        let active = PerformanceEvent(gestureName: "test", lane: .discrete, phase: .active, confidence: 0.9)
        let candidate = PerformanceEvent(gestureName: "test", lane: .discrete, phase: .candidate, confidence: 0.5)
        let ambiguous = PerformanceEvent(gestureName: "test", lane: .discrete, phase: .ambiguous, confidence: 0.6)

        #expect(active.isTriggered == true)
        #expect(candidate.isTriggered == false)
        #expect(ambiguous.isTriggered == false)
        #expect(ambiguous.isAmbiguous == true)
    }

    @Test func eventCodableRoundTrip() throws {
        let event = PerformanceEvent(
            gestureName: "shake",
            lane: .continuous,
            phase: .active,
            confidence: 0.75,
            intensity: 0.6,
            latencyMs: 5.0,
            ambiguityWith: [],
            sourceMetrics: ["matchScore": 0.82]
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(event)
        let decoded = try decoder.decode(PerformanceEvent.self, from: data)

        #expect(decoded.gestureName == event.gestureName)
        #expect(decoded.lane == event.lane)
        #expect(decoded.phase == event.phase)
        #expect(decoded.confidence == event.confidence)
        #expect(decoded.intensity == event.intensity)
    }

    @Test func fusedGestureStateDefaults() {
        let state = FusedGestureState()
        #expect(state.currentPhase == .candidate)
        #expect(state.smoothedConfidence == 0)
        #expect(state.dominantLane == .discrete)
        #expect(state.competingGestures.isEmpty)
        #expect(state.activeSince == nil)
        #expect(state.lastTriggerTime == nil)
    }

    @Test func gestureFamilyCreation() {
        let family = GestureFamily(
            name: "strikes",
            members: [UUID(), UUID()],
            confusionSet: ["punch", "chop"],
            suppressesFamilies: ["waves"],
            preferredLane: .discrete
        )

        #expect(family.name == "strikes")
        #expect(family.members.count == 2)
        #expect(family.confusionSet == ["punch", "chop"])
        #expect(family.preferredLane == .discrete)
    }

    @Test func calibrationProfileDefaults() {
        let profile = CalibrationProfile(name: "Default")
        #expect(profile.name == "Default")
        #expect(profile.accelGain == 1.0)
        #expect(profile.rotationGain == 1.0)
        #expect(profile.energyGateThreshold == 0.2)
        #expect(profile.defaultCooldown == 0.5)
        #expect(profile.perGestureSensitivity.isEmpty)
    }

    @Test func mappingPresetDefault() {
        let preset = MappingPreset(name: "Live Set")
        #expect(preset.isDefault == true) // no routes = default routing
        #expect(preset.name == "Live Set")
    }

    @Test func eventFilterMatching() {
        let event = PerformanceEvent(gestureName: "punch", lane: .discrete, phase: .active, confidence: 0.9)

        let matchAll = EventFilter()
        #expect(matchAll.matches(event) == true)

        let matchName = EventFilter(gestureName: "punch")
        #expect(matchName.matches(event) == true)

        let wrongName = EventFilter(gestureName: "chop")
        #expect(wrongName.matches(event) == false)

        let matchLane = EventFilter(lane: .discrete)
        #expect(matchLane.matches(event) == true)

        let wrongLane = EventFilter(lane: .continuous)
        #expect(wrongLane.matches(event) == false)

        let matchPhase = EventFilter(phases: [.active, .candidate])
        #expect(matchPhase.matches(event) == true)

        let wrongPhase = EventFilter(phases: [.release])
        #expect(wrongPhase.matches(event) == false)
    }

    @Test func valueTransformIdentity() {
        let identity = ValueTransform.identity
        #expect(identity.apply(to: 0.5) == 0.5)
        #expect(identity.apply(to: 0.0) == 0.0)
        #expect(identity.apply(to: 1.0) == 1.0)
    }

    @Test func valueTransformScaleAndClamp() {
        let transform = ValueTransform(scale: 2.0, offset: -0.5, clampMin: 0.0, clampMax: 1.0)
        #expect(transform.apply(to: 0.5) == 0.5) // 0.5 * 2.0 - 0.5 = 0.5
        #expect(transform.apply(to: 0.0) == 0.0) // 0.0 * 2.0 - 0.5 = -0.5, clamped to 0.0
        #expect(transform.apply(to: 1.0) == 1.0) // 1.0 * 2.0 - 0.5 = 1.5, clamped to 1.0
    }
}
