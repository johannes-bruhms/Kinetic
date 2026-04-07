import XCTest
@testable import Kinetic

final class DTWClassifierTests: XCTestCase {
    func testIdenticalSequencesHaveZeroDistance() {
        let classifier = DTWClassifier(distanceThreshold: 100)
        let samples = makeLine(length: 30, accelX: 1.0)

        classifier.addTemplate(name: "push", samples: samples)
        let results = classifier.classify(window: samples)

        XCTAssertFalse(results.isEmpty)
        XCTAssertEqual(results.first?.name, "push")
        XCTAssertEqual(results.first?.distance ?? 999, 0.0, accuracy: 0.001)
    }

    func testDifferentSequencesHaveLargerDistance() {
        let classifier = DTWClassifier(distanceThreshold: 100)
        let templateSamples = makeLine(length: 30, accelX: 2.0)
        let querySamples = makeLine(length: 30, accelX: -2.0)

        classifier.addTemplate(name: "push", samples: templateSamples)
        let results = classifier.classify(window: querySamples)

        if let first = results.first {
            XCTAssertGreaterThan(first.distance, 0.1)
        }
    }

    func testEmptyWindowReturnsNoResults() {
        let classifier = DTWClassifier()
        classifier.addTemplate(name: "wave", samples: makeLine(length: 20, accelX: 1.0))
        let results = classifier.classify(window: [])
        XCTAssertTrue(results.isEmpty)
    }

    func testClearTemplates() {
        let classifier = DTWClassifier(distanceThreshold: 100)
        classifier.addTemplate(name: "tap", samples: makeLine(length: 20, accelX: 1.0))
        classifier.clearTemplates()
        let results = classifier.classify(window: makeLine(length: 20, accelX: 1.0))
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Helpers

    private func makeLine(length: Int, accelX: Double) -> [MotionSample] {
        (0..<length).map { i in
            MotionSample(
                timestamp: Double(i) * 0.01,
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
                rotationRate: Vector3(x: 0, y: 0, z: 0),
                userAcceleration: Vector3(x: accelX, y: 0, z: 0),
                gravity: Vector3(x: 0, y: 0, z: -1)
            )
        }
    }
}
