import Foundation

enum GestureType: String, Codable, CaseIterable, Sendable {
    case discrete
    case continuous
    case posture

    var iconName: String {
        switch self {
        case .discrete: "hand.tap"
        case .continuous: "waveform.path"
        case .posture: "iphone.gen3"
        }
    }
}

struct TrainedGesture: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var gestureType: GestureType
    var sampleCount: Int
    var lastTrained: Date
    var modelFileName: String?
    var cooldownDuration: TimeInterval
    /// Per-gesture sensitivity (0.0–1.0). Interpretation varies by type:
    /// - Discrete: trigger probability threshold (0.0→0.70, 0.5→0.85, 1.0→0.98)
    /// - Continuous: frequency match threshold (0.0→0.80, 0.5→0.60, 1.0→0.35)
    /// - Posture: angle tolerance (0.0→0.15rad/~9°, 0.5→0.30rad/~17°, 1.0→0.50rad/~29°)
    var sensitivity: Double

    init(id: UUID = UUID(), name: String, gestureType: GestureType = .discrete, sampleCount: Int = 0, lastTrained: Date = .now, modelFileName: String? = nil, cooldownDuration: TimeInterval = 0.5, sensitivity: Double = 0.5) {
        self.id = id
        self.name = name
        self.gestureType = gestureType
        self.sampleCount = sampleCount
        self.lastTrained = lastTrained
        self.modelFileName = modelFileName
        self.cooldownDuration = cooldownDuration
        self.sensitivity = sensitivity
    }

    // Backward compatibility: decode missing keys with defaults
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        gestureType = try container.decodeIfPresent(GestureType.self, forKey: .gestureType) ?? .discrete
        sampleCount = try container.decode(Int.self, forKey: .sampleCount)
        lastTrained = try container.decode(Date.self, forKey: .lastTrained)
        modelFileName = try container.decodeIfPresent(String.self, forKey: .modelFileName)
        cooldownDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldownDuration) ?? 0.5
        sensitivity = try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 0.5
    }

    /// Compute the trigger probability threshold for discrete gestures.
    var discreteTriggerThreshold: Float {
        // sensitivity 0→0.70, 0.5→0.50, 1.0→0.30
        Float(0.70 - sensitivity * 0.40)
    }

    /// DTW distance normalization threshold for discrete gestures.
    /// Higher = more generous probability scores.
    var dtwDistanceThreshold: Double {
        // sensitivity 0→2.5 (strict), 0.5→4.0, 1.0→6.0 (lenient)
        2.5 + sensitivity * 3.5
    }

    /// Compute the frequency match threshold for continuous gestures.
    var continuousMatchThreshold: Double {
        // sensitivity 0→0.80 (harder to match), 0.5→0.60, 1.0→0.35 (easier)
        0.80 - sensitivity * 0.45
    }

    /// Compute the angle tolerance for posture gestures (radians).
    var postureToleranceAngle: Double {
        // sensitivity 0→0.15rad (~9°), 0.5→0.30rad (~17°), 1.0→0.50rad (~29°)
        0.15 + sensitivity * 0.35
    }
}

struct GestureRecording: Codable {
    let gestureId: UUID
    let samples: [MotionSample]
    let recordedAt: Date
    var recordingDuration: TimeInterval?
    var extractedProfile: ContinuousGestureProfile?
    var postureVector: Vector3?

    init(gestureId: UUID, samples: [MotionSample], recordedAt: Date, recordingDuration: TimeInterval? = nil, extractedProfile: ContinuousGestureProfile? = nil, postureVector: Vector3? = nil) {
        self.gestureId = gestureId
        self.samples = samples
        self.recordedAt = recordedAt
        self.recordingDuration = recordingDuration
        self.extractedProfile = extractedProfile
        self.postureVector = postureVector
    }

    // Backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gestureId = try container.decode(UUID.self, forKey: .gestureId)
        samples = try container.decode([MotionSample].self, forKey: .samples)
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        recordingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .recordingDuration)
        extractedProfile = try container.decodeIfPresent(ContinuousGestureProfile.self, forKey: .extractedProfile)
        postureVector = try container.decodeIfPresent(Vector3.self, forKey: .postureVector)
    }
}

nonisolated struct MotionSample: Codable, Sendable {
    let timestamp: TimeInterval
    let attitude: Quaternion
    let rotationRate: Vector3
    let userAcceleration: Vector3
    let gravity: Vector3
}

nonisolated struct Quaternion: Codable, Sendable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double
}

nonisolated struct Vector3: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let z: Double

    nonisolated var magnitude: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    nonisolated static func dot(_ a: Vector3, _ b: Vector3) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    nonisolated static func angleBetween(_ a: Vector3, _ b: Vector3) -> Double {
        let dotProduct = dot(a, b)
        let magnitudes = a.magnitude * b.magnitude
        guard magnitudes > 1e-10 else { return 0 }
        return acos(min(max(dotProduct / magnitudes, -1.0), 1.0))
    }

    static let zero = Vector3(x: 0, y: 0, z: 0)

    nonisolated static func average(_ vectors: [Vector3]) -> Vector3 {
        guard !vectors.isEmpty else { return .zero }
        let n = Double(vectors.count)
        return Vector3(
            x: vectors.map(\.x).reduce(0, +) / n,
            y: vectors.map(\.y).reduce(0, +) / n,
            z: vectors.map(\.z).reduce(0, +) / n
        )
    }
}
