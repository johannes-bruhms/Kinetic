import Foundation

struct TrainedGesture: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var sampleCount: Int
    var lastTrained: Date
    var modelFileName: String?

    init(id: UUID = UUID(), name: String, sampleCount: Int = 0, lastTrained: Date = .now, modelFileName: String? = nil) {
        self.id = id
        self.name = name
        self.sampleCount = sampleCount
        self.lastTrained = lastTrained
        self.modelFileName = modelFileName
    }
}

struct GestureRecording: Codable {
    let gestureId: UUID
    let samples: [MotionSample]
    let recordedAt: Date
}

struct MotionSample: Codable {
    let timestamp: TimeInterval
    let attitude: Quaternion
    let rotationRate: Vector3
    let userAcceleration: Vector3
    let gravity: Vector3
}

struct Quaternion: Codable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

struct Vector3: Codable {
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }
}
