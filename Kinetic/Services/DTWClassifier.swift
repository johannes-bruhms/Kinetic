import Foundation

/// Dynamic Time Warping gesture classifier — lightweight fallback that works
/// without Core ML training. Compares incoming gesture windows against stored
/// reference recordings using DTW distance.
///
/// Pipeline: extract features → trim active region → resample to fixed
/// length → z-score normalize → DTW distance.
nonisolated final class DTWClassifier: @unchecked Sendable {
    struct Template: Sendable {
        let gestureName: String
        let rawFeatures: [[Double]]
        let normalizedFeatures: [[Double]] // resampled + z-score normalized
    }

    private var templates: [Template] = []
    let threshold: Double
    private let resampleLength = 32

    var hasTemplates: Bool { !templates.isEmpty }

    init(distanceThreshold: Double = 3.0) {
        self.threshold = distanceThreshold
    }

    /// Register a recorded gesture segment as a reference template.
    func addTemplate(name: String, samples: [MotionSample]) {
        let features = samples.map { extractFeatures($0) }
        let processed = normalize(resample(features, targetLength: resampleLength))
        templates.append(Template(gestureName: name, rawFeatures: features, normalizedFeatures: processed))
    }

    func clearTemplates() {
        templates.removeAll()
    }

    /// Classify a window of samples. Returns (gestureName, normalizedDistance)
    /// pairs sorted by best match. Empty if nothing is within threshold.
    func classify(window: [MotionSample]) -> [(name: String, distance: Double)] {
        let rawFeatures = window.map { extractFeatures($0) }
        let active = extractActiveRegion(rawFeatures)
        guard active.count >= 4, !templates.isEmpty else { return [] }

        let query = normalize(resample(active, targetLength: resampleLength))
        var results: [(name: String, distance: Double)] = []

        for template in templates {
            let dist = dtwDistance(query, template.normalizedFeatures)
            let normalized = dist / Double(resampleLength)
            if normalized < threshold {
                results.append((name: template.gestureName, distance: normalized))
            }
        }

        return results.sorted { $0.distance < $1.distance }
    }

    // MARK: - Active Region Extraction

    /// Trims quiet leading/trailing portions of a window so DTW only compares
    /// the part that actually contains movement.
    private func extractActiveRegion(_ features: [[Double]]) -> [[Double]] {
        guard features.count >= 4 else { return features }

        let energies = features.map { f -> Double in
            var sum = 0.0
            for v in f { sum += v * v }
            return sum.squareRoot()
        }

        guard let peak = energies.max(), peak > 0.01 else { return features }
        let cutoff = peak * 0.15

        var start = 0
        var end = features.count - 1

        for i in 0..<energies.count where energies[i] > cutoff {
            start = max(0, i - 2)
            break
        }
        for i in stride(from: energies.count - 1, through: 0, by: -1) where energies[i] > cutoff {
            end = min(features.count - 1, i + 2)
            break
        }

        guard start < end else { return features }
        return Array(features[start...end])
    }

    // MARK: - Resampling

    /// Linearly interpolates a feature sequence to a fixed length so DTW
    /// comparisons are scale-invariant with respect to gesture speed.
    private func resample(_ features: [[Double]], targetLength: Int) -> [[Double]] {
        guard features.count >= 2 else { return features }
        var result: [[Double]] = []
        result.reserveCapacity(targetLength)

        for i in 0..<targetLength {
            let t = Double(i) / Double(targetLength - 1) * Double(features.count - 1)
            let lower = Int(t)
            let upper = min(lower + 1, features.count - 1)
            let frac = t - Double(lower)
            let interpolated = zip(features[lower], features[upper]).map {
                $0.0 * (1.0 - frac) + $0.1 * frac
            }
            result.append(interpolated)
        }
        return result
    }

    // MARK: - Z-Score Normalization

    /// Per-axis z-score normalization so that acceleration and rotation rate
    /// contribute equally regardless of their raw scale.
    private func normalize(_ features: [[Double]]) -> [[Double]] {
        guard let first = features.first else { return features }
        let featureCount = first.count
        let n = Double(features.count)

        var means = [Double](repeating: 0, count: featureCount)
        for f in features {
            for j in 0..<featureCount { means[j] += f[j] }
        }
        for j in 0..<featureCount { means[j] /= n }

        var stds = [Double](repeating: 0, count: featureCount)
        for f in features {
            for j in 0..<featureCount {
                let d = f[j] - means[j]
                stds[j] += d * d
            }
        }
        for j in 0..<featureCount {
            stds[j] = max((stds[j] / n).squareRoot(), 1e-6)
        }

        return features.map { f in
            f.enumerated().map { (j, v) in (v - means[j]) / stds[j] }
        }
    }

    // MARK: - DTW Core

    private func dtwDistance(_ a: [[Double]], _ b: [[Double]]) -> Double {
        let n = a.count
        let m = b.count

        // Cost matrix — only keep two rows to save memory
        var prev = [Double](repeating: .infinity, count: m + 1)
        var curr = [Double](repeating: .infinity, count: m + 1)
        prev[0] = 0

        for i in 1...n {
            curr[0] = .infinity
            for j in 1...m {
                let cost = euclidean(a[i - 1], b[j - 1])
                curr[j] = cost + min(prev[j], curr[j - 1], prev[j - 1])
            }
            swap(&prev, &curr)
        }

        return prev[m]
    }

    private func euclidean(_ a: [Double], _ b: [Double]) -> Double {
        var sum = 0.0
        for i in 0..<min(a.count, b.count) {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        return sum.squareRoot()
    }

    // MARK: - Feature Extraction

    private func extractFeatures(_ sample: MotionSample) -> [Double] {
        [
            sample.userAcceleration.x,
            sample.userAcceleration.y,
            sample.userAcceleration.z,
            sample.rotationRate.x,
            sample.rotationRate.y,
            sample.rotationRate.z,
        ]
    }
}
