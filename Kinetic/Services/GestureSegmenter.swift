import Foundation

/// Auto-segments continuous motion recordings into individual gesture samples
/// using energy-based thresholding with hysteresis.
nonisolated struct GestureSegmenter {
    var energyThresholdHigh: Double = 0.8
    var energyThresholdLow: Double = 0.3
    var minimumGestureDuration: TimeInterval = 0.15
    var minimumRestDuration: TimeInterval = 0.1

    enum State {
        case rest
        case motion
    }

    struct Segment {
        let startIndex: Int
        let endIndex: Int
        let samples: [MotionSample]
    }

    func segment(_ samples: [MotionSample]) -> [Segment] {
        guard !samples.isEmpty else { return [] }

        var state: State = .rest
        var segments: [Segment] = []
        var motionStartIndex = 0
        var restStartTime: TimeInterval = 0

        for (i, sample) in samples.enumerated() {
            let energy = sampleEnergy(sample)

            switch state {
            case .rest:
                if energy > energyThresholdHigh {
                    state = .motion
                    motionStartIndex = i
                }

            case .motion:
                if energy < energyThresholdLow {
                    if restStartTime == 0 {
                        restStartTime = sample.timestamp
                    }

                    let restDuration = sample.timestamp - restStartTime
                    if restDuration >= minimumRestDuration {
                        // End of gesture — check minimum duration
                        let gestureDuration = samples[i].timestamp - samples[motionStartIndex].timestamp
                        if gestureDuration >= minimumGestureDuration {
                            let segmentSamples = Array(samples[motionStartIndex...i])
                            segments.append(Segment(
                                startIndex: motionStartIndex,
                                endIndex: i,
                                samples: segmentSamples
                            ))
                        }
                        state = .rest
                        restStartTime = 0
                    }
                } else {
                    restStartTime = 0
                }
            }
        }

        // Handle case where recording ends during motion
        if case .motion = state {
            let gestureDuration = samples.last!.timestamp - samples[motionStartIndex].timestamp
            if gestureDuration >= minimumGestureDuration {
                let segmentSamples = Array(samples[motionStartIndex...])
                segments.append(Segment(
                    startIndex: motionStartIndex,
                    endIndex: samples.count - 1,
                    samples: segmentSamples
                ))
            }
        }

        return segments
    }

    private func sampleEnergy(_ sample: MotionSample) -> Double {
        sample.userAcceleration.magnitude + sample.rotationRate.magnitude
    }
}
