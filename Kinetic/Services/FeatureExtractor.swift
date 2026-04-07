import Foundation

/// Extracts fixed-length statistical feature vectors from variable-length
/// motion sample sequences for use with on-device tabular ML classifiers.
///
/// Also provides data augmentation (jitter, magnitude scaling, time
/// stretching) to expand small training sets and prevent overfitting.
nonisolated struct FeatureExtractor {

    private static let axes = ["accelX", "accelY", "accelZ", "gyroX", "gyroY", "gyroZ"]
    private static let stats = ["mean", "std", "min", "max", "rms"]

    /// Ordered feature names matching the output of `extract(from:)`.
    static let featureNames: [String] = {
        var names: [String] = []
        for axis in axes {
            for stat in stats {
                names.append("\(axis)_\(stat)")
            }
        }
        names.append(contentsOf: [
            "energy_mean",
            "energy_peak",
            "energy_peakTimeRatio",
            "energy_firstHalfRatio",
        ])
        return names
    }()

    // MARK: - Feature Extraction

    /// Extract a fixed-length feature dictionary from a variable-length
    /// motion sample array. Returns zeros for empty input.
    static func extract(from samples: [MotionSample]) -> [String: Double] {
        guard !samples.isEmpty else {
            return Dictionary(uniqueKeysWithValues: featureNames.map { ($0, 0.0) })
        }

        let raw: [[Double]] = samples.map { s in
            [s.userAcceleration.x, s.userAcceleration.y, s.userAcceleration.z,
             s.rotationRate.x, s.rotationRate.y, s.rotationRate.z]
        }

        let n = Double(raw.count)
        var features: [String: Double] = [:]

        // Per-axis statistics
        for (axisIdx, axisName) in axes.enumerated() {
            let values = raw.map { $0[axisIdx] }
            let mean = values.reduce(0, +) / n
            let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
            let std = max(variance.squareRoot(), 1e-8)
            let rms = (values.map { $0 * $0 }.reduce(0, +) / n).squareRoot()

            features["\(axisName)_mean"] = mean
            features["\(axisName)_std"] = std
            features["\(axisName)_min"] = values.min() ?? 0
            features["\(axisName)_max"] = values.max() ?? 0
            features["\(axisName)_rms"] = rms
        }

        // Per-sample energy (L2 norm of all 6 axes)
        let energies = raw.map { f -> Double in
            var sum = 0.0
            for v in f { sum += v * v }
            return sum.squareRoot()
        }

        features["energy_mean"] = energies.reduce(0, +) / n
        features["energy_peak"] = energies.max() ?? 0

        // Temporal shape: where the peak falls in the gesture
        if let peakIdx = energies.enumerated().max(by: { $0.element < $1.element })?.offset {
            features["energy_peakTimeRatio"] = Double(peakIdx) / max(n - 1, 1)
        } else {
            features["energy_peakTimeRatio"] = 0.5
        }

        // First-half vs total energy ratio (captures asymmetry)
        let half = raw.count / 2
        if half > 0 {
            let firstHalfEnergy = energies[0..<half].reduce(0, +)
            let totalEnergy = energies.reduce(0, +)
            features["energy_firstHalfRatio"] = totalEnergy > 1e-8 ? firstHalfEnergy / totalEnergy : 0.5
        } else {
            features["energy_firstHalfRatio"] = 0.5
        }

        return features
    }

    // MARK: - Data Augmentation

    /// Produce augmented feature vectors from a single recording.
    /// Applies random jitter, magnitude scaling, and time stretching to
    /// synthesize realistic variations, then extracts features from each.
    static func extractAugmented(from samples: [MotionSample], count: Int = 8) -> [[String: Double]] {
        guard samples.count >= 4 else { return [] }
        var results: [[String: Double]] = []
        results.reserveCapacity(count)

        for _ in 0..<count {
            var augmented = samples
            augmented = jitter(augmented, sigma: Double.random(in: 0.02...0.08))
            augmented = scaleMagnitude(augmented, factor: Double.random(in: 0.85...1.15))
            augmented = timeStretch(augmented, factor: Double.random(in: 0.9...1.1))
            results.append(extract(from: augmented))
        }
        return results
    }

    /// Add Gaussian noise to acceleration and rotation rate axes.
    /// Simulates sensor variance and hand tremor.
    private static func jitter(_ samples: [MotionSample], sigma: Double) -> [MotionSample] {
        samples.map { s in
            MotionSample(
                timestamp: s.timestamp,
                attitude: s.attitude,
                rotationRate: Vector3(
                    x: s.rotationRate.x + gaussianNoise(sigma),
                    y: s.rotationRate.y + gaussianNoise(sigma),
                    z: s.rotationRate.z + gaussianNoise(sigma)
                ),
                userAcceleration: Vector3(
                    x: s.userAcceleration.x + gaussianNoise(sigma),
                    y: s.userAcceleration.y + gaussianNoise(sigma),
                    z: s.userAcceleration.z + gaussianNoise(sigma)
                ),
                gravity: s.gravity
            )
        }
    }

    /// Scale acceleration and rotation rate by a uniform factor.
    /// Simulates performing the gesture softer or harder.
    private static func scaleMagnitude(_ samples: [MotionSample], factor: Double) -> [MotionSample] {
        samples.map { s in
            MotionSample(
                timestamp: s.timestamp,
                attitude: s.attitude,
                rotationRate: Vector3(
                    x: s.rotationRate.x * factor,
                    y: s.rotationRate.y * factor,
                    z: s.rotationRate.z * factor
                ),
                userAcceleration: Vector3(
                    x: s.userAcceleration.x * factor,
                    y: s.userAcceleration.y * factor,
                    z: s.userAcceleration.z * factor
                ),
                gravity: s.gravity
            )
        }
    }

    /// Resample the sequence to a different length via linear interpolation.
    /// Simulates performing the gesture faster or slower.
    private static func timeStretch(_ samples: [MotionSample], factor: Double) -> [MotionSample] {
        guard samples.count >= 2 else { return samples }
        let newLength = max(4, Int(Double(samples.count) * factor))
        var result: [MotionSample] = []
        result.reserveCapacity(newLength)

        for i in 0..<newLength {
            let t = Double(i) / Double(newLength - 1) * Double(samples.count - 1)
            let lower = Int(t)
            let upper = min(lower + 1, samples.count - 1)
            let f = t - Double(lower)
            let s1 = samples[lower]
            let s2 = samples[upper]

            result.append(MotionSample(
                timestamp: s1.timestamp + f * (s2.timestamp - s1.timestamp),
                attitude: s1.attitude,
                rotationRate: Vector3(
                    x: s1.rotationRate.x + f * (s2.rotationRate.x - s1.rotationRate.x),
                    y: s1.rotationRate.y + f * (s2.rotationRate.y - s1.rotationRate.y),
                    z: s1.rotationRate.z + f * (s2.rotationRate.z - s1.rotationRate.z)
                ),
                userAcceleration: Vector3(
                    x: s1.userAcceleration.x + f * (s2.userAcceleration.x - s1.userAcceleration.x),
                    y: s1.userAcceleration.y + f * (s2.userAcceleration.y - s1.userAcceleration.y),
                    z: s1.userAcceleration.z + f * (s2.userAcceleration.z - s1.userAcceleration.z)
                ),
                gravity: s1.gravity
            ))
        }
        return result
    }

    /// Box-Muller transform for Gaussian random values.
    private static func gaussianNoise(_ sigma: Double) -> Double {
        let u1 = Double.random(in: 1e-10...1.0)
        let u2 = Double.random(in: 0.0...1.0)
        return sigma * (-2.0 * log(u1)).squareRoot() * cos(2.0 * .pi * u2)
    }
}
