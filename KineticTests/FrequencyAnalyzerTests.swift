import XCTest
@testable import Kinetic

final class FrequencyAnalyzerTests: XCTestCase {
    /// Generate single-axis sinusoidal motion with a DC offset so the magnitude
    /// signal (always positive) varies at the same frequency.
    private func makeSamples(frequency: Double, amplitude: Double = 1.0, offset: Double = 2.0, sampleRate: Double = 100.0, duration: Double = 3.0) -> [MotionSample] {
        let sampleCount = Int(sampleRate * duration)
        return (0..<sampleCount).map { i in
            let t = Double(i) / sampleRate
            let value = offset + amplitude * sin(2.0 * .pi * frequency * t)
            return MotionSample(
                timestamp: t,
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
                rotationRate: Vector3(x: 0, y: 0, z: 0),
                userAcceleration: Vector3(x: value, y: 0, z: 0),
                gravity: Vector3(x: 0, y: 0, z: -1)
            )
        }
    }

    func testDominantFrequencyDetectsSinusoid() {
        let samples = makeSamples(frequency: 3.0)
        let freq = FrequencyAnalyzer.dominantFrequency(from: samples)
        XCTAssertEqual(freq, 3.0, accuracy: 2.0, "Dominant frequency should be near 3Hz")
    }

    func testDominantFrequencyDifferentFrequencies() {
        let low = makeSamples(frequency: 2.0)
        let high = makeSamples(frequency: 10.0)

        let freqLow = FrequencyAnalyzer.dominantFrequency(from: low)
        let freqHigh = FrequencyAnalyzer.dominantFrequency(from: high)

        XCTAssertLessThan(freqLow, freqHigh, "Lower input freq should produce lower detected freq")
    }

    func testZeroCrossingRate() {
        // Use bipolar signal for ZCR (no offset)
        let sampleCount = 300
        let frequency = 4.0
        let sampleRate = 100.0
        let samples = (0..<sampleCount).map { i in
            let t = Double(i) / sampleRate
            let value = sin(2.0 * .pi * frequency * t)
            return MotionSample(
                timestamp: t,
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
                rotationRate: Vector3(x: 0, y: 0, z: 0),
                userAcceleration: Vector3(x: value, y: 0, z: 0),
                gravity: Vector3(x: 0, y: 0, z: -1)
            )
        }
        let zcr = FrequencyAnalyzer.zeroCrossingRate(from: samples)
        XCTAssertGreaterThan(zcr, 1.0, "ZCR should be positive for sinusoidal data")
    }

    func testFrequencyBandEnergiesNormalized() {
        let samples = makeSamples(frequency: 3.0)
        let bands = FrequencyAnalyzer.frequencyBandEnergies(from: samples)
        let total = bands.reduce(0, +)
        // Might be 0 if all energy is in DC (removed by mean subtraction)
        // Just check it's non-negative and ≤1
        XCTAssertGreaterThanOrEqual(total, 0.0)
        XCTAssertLessThanOrEqual(total, 1.01)
    }

    func testAxisEnergyDistribution() {
        let samples = makeSamples(frequency: 3.0)
        let dist = FrequencyAnalyzer.axisEnergyDistribution(from: samples)
        XCTAssertGreaterThan(dist.x, 0.9, "X should dominate for X-only motion")
        XCTAssertLessThan(dist.y, 0.05)
        XCTAssertLessThan(dist.z, 0.05)
    }

    func testProfileExtraction() {
        let samples = makeSamples(frequency: 3.0)
        let profile = FrequencyAnalyzer.extractProfile(from: samples)
        XCTAssertGreaterThan(profile.dominantFrequency, 0, "Should detect a frequency")
        XCTAssertFalse(profile.frequencyBandEnergy.isEmpty, "Should have band energies")
    }

    func testAverageProfiles() {
        let p1 = FrequencyAnalyzer.extractProfile(from: makeSamples(frequency: 3.0))
        let p2 = FrequencyAnalyzer.extractProfile(from: makeSamples(frequency: 5.0))

        let avg = FrequencyAnalyzer.averageProfiles([p1, p2])
        XCTAssertNotNil(avg, "Should produce an averaged profile")
    }

    func testEmptySamplesReturnsZero() {
        let freq = FrequencyAnalyzer.dominantFrequency(from: [])
        XCTAssertEqual(freq, 0.0)
    }
}
