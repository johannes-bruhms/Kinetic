import Foundation

/// Classifies postures by matching the current gravity vector against trained templates.
/// Simplest recognition layer — no ML, just angle comparison with hysteresis.
nonisolated final class PostureClassifier: @unchecked Sendable {
    struct Template: Sendable {
        let name: String
        let gravityVector: Vector3
        let toleranceAngle: Double // radians
    }

    struct PostureState: Sendable {
        var isActive: Bool = false
        var matchStartTime: TimeInterval = 0
        var unmatchStartTime: TimeInterval = 0
    }

    private var templates: [Template] = []
    private var states: [String: PostureState] = [:]

    // Hysteresis timing
    private let activationDelay: TimeInterval = 0.5
    private let deactivationDelay: TimeInterval = 0.3

    // Low-pass filter state
    private var filteredGravity: Vector3 = .zero
    private let filterAlpha: Double = 0.1

    var hasTemplates: Bool { !templates.isEmpty }

    func addTemplate(name: String, gravityVector: Vector3, toleranceAngle: Double = 0.3) {
        templates.append(Template(name: name, gravityVector: gravityVector, toleranceAngle: toleranceAngle))
        states[name] = PostureState()
    }

    func clearTemplates() {
        templates.removeAll()
        states.removeAll()
        filteredGravity = .zero
    }

    /// Classify a single gravity sample. Returns active/inactive state per posture.
    func classify(gravity: Vector3, timestamp: TimeInterval) -> [String: Bool] {
        guard !templates.isEmpty else { return [:] }

        // Low-pass filter the gravity vector
        if filteredGravity.magnitude < 0.01 {
            filteredGravity = gravity
        } else {
            filteredGravity = Vector3(
                x: filteredGravity.x * (1 - filterAlpha) + gravity.x * filterAlpha,
                y: filteredGravity.y * (1 - filterAlpha) + gravity.y * filterAlpha,
                z: filteredGravity.z * (1 - filterAlpha) + gravity.z * filterAlpha
            )
        }

        var result: [String: Bool] = [:]

        for template in templates {
            let angle = Vector3.angleBetween(filteredGravity, template.gravityVector)
            let isMatch = angle < template.toleranceAngle

            var state = states[template.name] ?? PostureState()

            if isMatch {
                state.unmatchStartTime = 0
                if !state.isActive {
                    if state.matchStartTime == 0 {
                        state.matchStartTime = timestamp
                    } else if timestamp - state.matchStartTime >= activationDelay {
                        state.isActive = true
                    }
                }
            } else {
                state.matchStartTime = 0
                if state.isActive {
                    if state.unmatchStartTime == 0 {
                        state.unmatchStartTime = timestamp
                    } else if timestamp - state.unmatchStartTime >= deactivationDelay {
                        state.isActive = false
                    }
                }
            }

            states[template.name] = state
            result[template.name] = state.isActive
        }

        return result
    }
}
