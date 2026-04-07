import XCTest
@testable import Kinetic

final class GestureSegmenterTests: XCTestCase {
    let segmenter = GestureSegmenter()

    func testEmptySamplesReturnsNoSegments() {
        let segments = segmenter.segment([])
        XCTAssertTrue(segments.isEmpty)
    }

    func testSingleMotionBurst() {
        // Simulate rest → motion → rest
        var samples: [MotionSample] = []
        let rest = makeSample(timestamp: 0, accelMag: 0.1, gyroMag: 0.05)
        let motion = makeSample(timestamp: 0.3, accelMag: 2.0, gyroMag: 1.5)

        // Rest period
        for i in 0..<20 {
            samples.append(makeSample(timestamp: Double(i) * 0.01, accelMag: 0.1, gyroMag: 0.05))
        }
        // Motion period
        for i in 20..<50 {
            samples.append(makeSample(timestamp: Double(i) * 0.01, accelMag: 2.0, gyroMag: 1.5))
        }
        // Rest period
        for i in 50..<80 {
            samples.append(makeSample(timestamp: Double(i) * 0.01, accelMag: 0.1, gyroMag: 0.05))
        }

        let segments = segmenter.segment(samples)
        XCTAssertEqual(segments.count, 1)
    }

    // MARK: - Helpers

    private func makeSample(timestamp: TimeInterval, accelMag: Double, gyroMag: Double) -> MotionSample {
        MotionSample(
            timestamp: timestamp,
            attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
            rotationRate: Vector3(x: gyroMag, y: 0, z: 0),
            userAcceleration: Vector3(x: accelMag, y: 0, z: 0),
            gravity: Vector3(x: 0, y: 0, z: -1)
        )
    }
}
