import Foundation

nonisolated struct ContinuousGestureProfile: Codable, Hashable, Sendable {
    var dominantFrequency: Double
    var frequencyBandEnergy: [Double]
    var axisDistribution: Vector3
    var amplitudeMin: Double
    var amplitudeMax: Double

    var amplitudeRange: ClosedRange<Double> {
        amplitudeMin...amplitudeMax
    }
}
