import XCTest
@testable import Kinetic

final class DTWClassifierTests: XCTestCase {
    func testIdenticalSequencesHaveZeroDistance() {
        let classifier = DTWClassifier(distanceThreshold: 100)
        let samples = makeGesture(length: 30, accelPattern: { i in sin(Double(i) * 0.3) })

        classifier.addTemplate(name: "push", samples: samples)
        let results = classifier.classify(window: samples)

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.name, "push")
        XCTAssertEqual(results.first?.distance ?? 999, 0.0, accuracy: 0.01)
    }

    func testDifferentSequencesHaveLargerDistance() {
        let classifier = DTWClassifier(distanceThreshold: 100)
        // Two distinct motion patterns
        let templateSamples = makeGesture(length: 30, accelPattern: { i in sin(Double(i) * 0.3) })
        let querySamples = makeGesture(length: 30, accelPattern: { i in cos(Double(i) * 0.8) * 2.0 })

        classifier.addTemplate(name: "push", samples: templateSamples)
        let results = classifier.classify(window: querySamples)

        if let first = results.first {
            XCTAssertGreaterThan(first.distance, 0.1)
        }
    }

    func testEmptyWindowReturnsNoResults() {
        let classifier = DTWClassifier()
        classifier.addTemplate(name: "wave", samples: makeGesture(length: 20, accelPattern: { i in sin(Double(i) * 0.5) }))
        let results = classifier.classify(window: [])
        XCTAssertTrue(results.isEmpty)
    }

    func testClearTemplates() {
        let classifier = DTWClassifier(distanceThreshold: 100)
        classifier.addTemplate(name: "tap", samples: makeGesture(length: 20, accelPattern: { i in sin(Double(i) * 0.5) }))
        classifier.clearTemplates()
        let results = classifier.classify(window: makeGesture(length: 20, accelPattern: { i in sin(Double(i) * 0.5) }))
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Helpers

    /// Create samples with a varying acceleration pattern so normalization
    /// doesn't collapse them to zero.
    private func makeGesture(length: Int, accelPattern: (Int) -> Double) -> [MotionSample] {
        (0..<length).map { i in
            MotionSample(
                timestamp: Double(i) * 0.01,
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
                rotationRate: Vector3(x: accelPattern(i) * 0.5, y: 0, z: 0),
                userAcceleration: Vector3(x: accelPattern(i), y: 0, z: 0),
                gravity: Vector3(x: 0, y: 0, z: -1)
            )
        }
    }
}
