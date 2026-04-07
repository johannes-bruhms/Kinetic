import Foundation

/// Dynamic Time Warping gesture classifier — lightweight fallback that works
/// without Core ML training. Compares incoming gesture windows against stored
/// reference recordings using DTW distance.
nonisolated final class DTWClassifier: @unchecked Sendable {
    struct Template: Sendable {
        let gestureName: String
        let features: [[Double]] // [timeStep][feature]
    }

    private var templates: [Template] = []
    let threshold: Double

    var hasTemplates: Bool { !templates.isEmpty }

    init(distanceThreshold: Double = 15.0) {
        self.threshold = distanceThreshold
    }

    /// Register a recorded gesture segment as a reference template.
    func addTemplate(name: String, samples: [MotionSample]) {
        let features = samples.map { extractFeatures($0) }
        templates.append(Template(gestureName: name, features: features))
    }

    func clearTemplates() {
        templates.removeAll()
    }

    /// Classify a window of samples. Returns (gestureName, normalizedDistance)
    /// pairs sorted by best match. Empty if nothing is within threshold.
    func classify(window: [MotionSample]) -> [(name: String, distance: Double)] {
        let query = window.map { extractFeatures($0) }
        guard !query.isEmpty, !templates.isEmpty else { return [] }

        var results: [(name: String, distance: Double)] = []

        for template in templates {
            let dist = dtwDistance(query, template.features)
            let normalized = dist / Double(max(query.count, template.features.count))
            if normalized < threshold {
                results.append((name: template.gestureName, distance: normalized))
            }
        }

        return results.sorted { $0.distance < $1.distance }
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
