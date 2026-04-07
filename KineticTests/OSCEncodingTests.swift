import XCTest
@testable import Kinetic

final class OSCEncodingTests: XCTestCase {
    func testVector3Magnitude() {
        let v = Vector3(x: 3, y: 4, z: 0)
        XCTAssertEqual(v.magnitude, 5.0, accuracy: 0.0001)
    }

    func testVector3ZeroMagnitude() {
        let v = Vector3(x: 0, y: 0, z: 0)
        XCTAssertEqual(v.magnitude, 0.0)
    }

    func testOSCConfigurationDefaults() {
        let config = OSCConfiguration.default
        XCTAssertEqual(config.port, 8000)
        XCTAssertEqual(config.prefix, "/kinetic/")
        XCTAssertEqual(config.sampleRate, 100)
        XCTAssertTrue(config.useBonjourDiscovery)
    }
}
