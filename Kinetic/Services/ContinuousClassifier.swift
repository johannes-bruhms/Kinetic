import Foundation

/// State machine for continuous gesture recognition with hysteresis.
nonisolated struct ContinuousGestureState: Sendable {
    enum Phase: Sendable {
        case idle
        case candidate
        case active
        case cooldown
    }

    var phase: Phase = .idle
    var intensity: Float = 0
    var phaseEntryTime: TimeInterval = 0

    var isActive: Bool { phase == .active }
}

/// Classifies continuous gestures (shaking, arm circles) using frequency-domain
/// features matched against trained ContinuousGestureProfile templates.
nonisolated final class ContinuousClassifier: @unchecked Sendable {
    struct Template: Sendable {
        let name: String
        let profile: ContinuousGestureProfile
        let matchThreshold: Double
    }

    private var templates: [Template] = []
    private var states: [String: ContinuousGestureState] = [:]

    // Hysteresis timing
    private let candidateToActiveDelay: TimeInterval = 1.0
    private let cooldownToIdleDelay: TimeInterval = 0.5

    var hasTemplates: Bool { !templates.isEmpty }

    func addTemplate(name: String, profile: ContinuousGestureProfile, matchThreshold: Double = 0.6) {
        templates.append(Template(name: name, profile: profile, matchThreshold: matchThreshold))
        states[name] = ContinuousGestureState()
    }

    func clearTemplates() {
        templates.removeAll()
        states.removeAll()
    }

    /// Classify a buffer of samples against trained continuous gesture profiles.
    func classify(samples: [MotionSample], timestamp: TimeInterval) -> [String: ContinuousGestureState] {
        guard !templates.isEmpty, samples.count >= 50 else { return states }

        let liveFreq = FrequencyAnalyzer.dominantFrequency(from: samples)
        let liveBands = FrequencyAnalyzer.frequencyBandEnergies(from: samples)
        let liveAxis = FrequencyAnalyzer.axisEnergyDistribution(from: samples)
        let liveAmplitude = samples.map { $0.userAcceleration.magnitude }.reduce(0, +) / Double(samples.count)

        for template in templates {
            let matchScore = computeMatchScore(
                liveFreq: liveFreq,
                liveBands: liveBands,
                liveAxis: liveAxis,
                profile: template.profile
            )

            let isMatch = matchScore > template.matchThreshold

            // Compute intensity from amplitude relative to training range
            let intensity: Float
            if template.profile.amplitudeRange.upperBound > template.profile.amplitudeRange.lowerBound {
                let normalized = (liveAmplitude - template.profile.amplitudeRange.lowerBound) /
                    (template.profile.amplitudeRange.upperBound - template.profile.amplitudeRange.lowerBound)
                intensity = Float(min(max(normalized, 0), 1.0))
            } else {
                intensity = isMatch ? 1.0 : 0.0
            }

            var state = states[template.name] ?? ContinuousGestureState()

            switch state.phase {
            case .idle:
                if isMatch {
                    state.phase = .candidate
                    state.phaseEntryTime = timestamp
                    state.intensity = intensity
                }

            case .candidate:
                if isMatch {
                    state.intensity = intensity
                    if timestamp - state.phaseEntryTime >= candidateToActiveDelay {
                        state.phase = .active
                        state.phaseEntryTime = timestamp
                    }
                } else {
                    state.phase = .idle
                    state.intensity = 0
                }

            case .active:
                if isMatch {
                    state.intensity = intensity
                } else {
                    state.phase = .cooldown
                    state.phaseEntryTime = timestamp
                }

            case .cooldown:
                if isMatch {
                    state.phase = .active
                    state.phaseEntryTime = timestamp
                    state.intensity = intensity
                } else if timestamp - state.phaseEntryTime >= cooldownToIdleDelay {
                    state.phase = .idle
                    state.intensity = 0
                }
            }

            states[template.name] = state
        }

        return states
    }

    // MARK: - Match Scoring

    private func computeMatchScore(liveFreq: Double, liveBands: [Double], liveAxis: Vector3, profile: ContinuousGestureProfile) -> Double {
        // Frequency similarity (gaussian distance)
        let freqDiff = abs(liveFreq - profile.dominantFrequency)
        let freqScore = exp(-freqDiff * freqDiff / (2.0 * 1.0)) // sigma = 1Hz

        // Band energy correlation
        let bandScore: Double
        if liveBands.count == profile.frequencyBandEnergy.count && !liveBands.isEmpty {
            var dotProduct = 0.0
            var liveNorm = 0.0
            var profileNorm = 0.0
            for i in 0..<liveBands.count {
                dotProduct += liveBands[i] * profile.frequencyBandEnergy[i]
                liveNorm += liveBands[i] * liveBands[i]
                profileNorm += profile.frequencyBandEnergy[i] * profile.frequencyBandEnergy[i]
            }
            let denom = (liveNorm.squareRoot() * profileNorm.squareRoot())
            bandScore = denom > 1e-10 ? dotProduct / denom : 0
        } else {
            bandScore = 0
        }

        // Axis distribution similarity (cosine similarity)
        let axisDot = Vector3.dot(liveAxis, profile.axisDistribution)
        let axisNorm = liveAxis.magnitude * profile.axisDistribution.magnitude
        let axisScore = axisNorm > 1e-10 ? axisDot / axisNorm : 0

        // Weighted combination
        return freqScore * 0.4 + bandScore * 0.35 + axisScore * 0.25
    }
}
