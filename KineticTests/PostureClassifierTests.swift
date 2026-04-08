import XCTest
@testable import Kinetic

final class PostureClassifierTests: XCTestCase {
    func testMatchingGravityActivates() {
        let classifier = PostureClassifier()
        classifier.addTemplate(name: "vertical", gravityVector: Vector3(x: 0, y: -1, z: 0), toleranceAngle: 0.3)

        // Simulate stable matching for >0.5s
        let matchingGravity = [Vector3(x: 0, y: -1, z: 0)]
        for i in 0..<60 {
            let t = Double(i) * 0.01
            _ = classifier.classify(gravity: matchingGravity[0], timestamp: t)
        }

        let result = classifier.classify(gravity: matchingGravity[0], timestamp: 0.6)
        XCTAssertTrue(result["vertical"] ?? false)
    }

    func testNonMatchingStaysInactive() {
        let classifier = PostureClassifier()
        classifier.addTemplate(name: "vertical", gravityVector: Vector3(x: 0, y: -1, z: 0), toleranceAngle: 0.3)

        // Completely different orientation
        let nonMatching = [Vector3(x: 1, y: 0, z: 0)]
        let result = classifier.classify(gravity: nonMatching[0], timestamp: 0)
        XCTAssertFalse(result["vertical"] ?? true)
    }

    func testToleranceAngle() {
        let classifier = PostureClassifier()
        // Tight tolerance (0.1 radians ~ 5.7 degrees)
        classifier.addTemplate(name: "faceUp", gravityVector: Vector3(x: 0, y: 0, z: -1), toleranceAngle: 0.1)

        // Slightly off (should not match with tight tolerance)
        let slightlyOff = [Vector3(x: 0.2, y: 0.2, z: -0.96)]
        let result = classifier.classify(gravity: slightlyOff[0], timestamp: 0)
        XCTAssertFalse(result["faceUp"] ?? true)
    }

    func testClearTemplates() {
        let classifier = PostureClassifier()
        classifier.addTemplate(name: "test", gravityVector: Vector3(x: 0, y: 0, z: -1))
        XCTAssertTrue(classifier.hasTemplates)

        classifier.clearTemplates()
        XCTAssertFalse(classifier.hasTemplates)
    }

    func testVector3AngleBetween() {
        let up = Vector3(x: 0, y: 1, z: 0)
        let right = Vector3(x: 1, y: 0, z: 0)
        let angle = Vector3.angleBetween(up, right)
        XCTAssertEqual(angle, .pi / 2, accuracy: 0.001)
    }

    func testVector3AngleBetweenSame() {
        let v = Vector3(x: 0, y: 0, z: -1)
        let angle = Vector3.angleBetween(v, v)
        XCTAssertEqual(angle, 0, accuracy: 0.001)
    }

    func testVector3AngleBetweenOpposite() {
        let v1 = Vector3(x: 0, y: 1, z: 0)
        let v2 = Vector3(x: 0, y: -1, z: 0)
        let angle = Vector3.angleBetween(v1, v2)
        XCTAssertEqual(angle, .pi, accuracy: 0.001)
    }
}
