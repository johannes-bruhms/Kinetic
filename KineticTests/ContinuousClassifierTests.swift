import XCTest
@testable import Kinetic

final class ContinuousClassifierTests: XCTestCase {
    private func makeSinusoidalSamples(frequency: Double, sampleRate: Double = 100.0, duration: Double = 1.5, startTime: Double = 0) -> [MotionSample] {
        let sampleCount = Int(sampleRate * duration)
        return (0..<sampleCount).map { i in
            let t = startTime + Double(i) / sampleRate
            let value = sin(2.0 * .pi * frequency * t)
            return MotionSample(
                timestamp: t,
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
                rotationRate: Vector3(x: 0, y: 0, z: 0),
                userAcceleration: Vector3(x: value, y: 0, z: 0),
                gravity: Vector3(x: 0, y: 0, z: -1)
            )
        }
    }

    func testIdleToCandidate() {
        let classifier = ContinuousClassifier()
        let trainingSamples = makeSinusoidalSamples(frequency: 3.0, duration: 3.0)
        let profile = FrequencyAnalyzer.extractProfile(from: trainingSamples)
        classifier.addTemplate(name: "shake", profile: profile)

        // Feed matching samples — should move to candidate
        let liveSamples = makeSinusoidalSamples(frequency: 3.0, startTime: 0)
        let states = classifier.classify(samples: liveSamples, timestamp: 1.5)

        XCTAssertNotNil(states["shake"])
        // After first classify, should be candidate (not yet active — needs 1.0s sustained)
        XCTAssertEqual(states["shake"]?.phase, .candidate)
    }

    func testCandidateToActive() {
        let classifier = ContinuousClassifier()
        let trainingSamples = makeSinusoidalSamples(frequency: 3.0, duration: 3.0)
        let profile = FrequencyAnalyzer.extractProfile(from: trainingSamples)
        classifier.addTemplate(name: "shake", profile: profile)

        // Simulate sustained matching over >1 second
        for i in 0..<5 {
            let t = Double(i) * 0.3
            let samples = makeSinusoidalSamples(frequency: 3.0, duration: 1.5, startTime: t)
            _ = classifier.classify(samples: samples, timestamp: t + 1.5)
        }

        let finalStates = classifier.classify(
            samples: makeSinusoidalSamples(frequency: 3.0, duration: 1.5, startTime: 2.0),
            timestamp: 3.5
        )

        // After enough sustained matching, should reach active
        XCTAssertEqual(finalStates["shake"]?.phase, .active)
    }

    func testNoMatchStaysIdle() {
        let classifier = ContinuousClassifier()
        let trainingSamples = makeSinusoidalSamples(frequency: 3.0, duration: 3.0)
        let profile = FrequencyAnalyzer.extractProfile(from: trainingSamples)
        classifier.addTemplate(name: "shake", profile: profile)

        // Feed very different frequency
        let liveSamples = makeSinusoidalSamples(frequency: 20.0, startTime: 0)
        let states = classifier.classify(samples: liveSamples, timestamp: 1.5)

        XCTAssertEqual(states["shake"]?.phase, .idle)
    }

    func testClearTemplates() {
        let classifier = ContinuousClassifier()
        let profile = FrequencyAnalyzer.extractProfile(from: makeSinusoidalSamples(frequency: 3.0, duration: 3.0))
        classifier.addTemplate(name: "shake", profile: profile)
        XCTAssertTrue(classifier.hasTemplates)

        classifier.clearTemplates()
        XCTAssertFalse(classifier.hasTemplates)
    }
}
