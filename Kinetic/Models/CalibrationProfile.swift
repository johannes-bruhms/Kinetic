import Foundation

/// A reusable calibration preset capturing sensor reference, per-gesture sensitivity,
/// cooldown overrides, and energy gate tuning. Profiles can be saved per performer,
/// venue, or piece and loaded before a performance.
nonisolated struct CalibrationProfile: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String

    /// Reference attitude quaternion for gyro zeroing (nil = absolute frame).
    var referenceAttitudeQuaternion: [Double]?

    /// Global gain multiplier for accelerometer data (default 1.0).
    var accelGain: Double

    /// Global gain multiplier for rotation rate data (default 1.0).
    var rotationGain: Double

    /// Energy gate threshold — samples below this are ignored by the classifier.
    var energyGateThreshold: Double

    /// Default cooldown duration for discrete gestures (seconds).
    var defaultCooldown: TimeInterval

    /// Per-gesture sensitivity overrides (gesture UUID → sensitivity 0.0-1.0).
    var perGestureSensitivity: [String: Double]

    /// Per-gesture cooldown overrides (gesture UUID → cooldown in seconds).
    var perGestureCooldown: [String: TimeInterval]

    /// Free-form notes (e.g., "Warm-up profile for outdoor venue").
    var notes: String

    /// When this profile was last modified.
    var lastModified: Date

    init(
        id: UUID = UUID(),
        name: String,
        referenceAttitudeQuaternion: [Double]? = nil,
        accelGain: Double = 1.0,
        rotationGain: Double = 1.0,
        energyGateThreshold: Double = 0.2,
        defaultCooldown: TimeInterval = 0.5,
        perGestureSensitivity: [String: Double] = [:],
        perGestureCooldown: [String: TimeInterval] = [:],
        notes: String = "",
        lastModified: Date = .now
    ) {
        self.id = id
        self.name = name
        self.referenceAttitudeQuaternion = referenceAttitudeQuaternion
        self.accelGain = accelGain
        self.rotationGain = rotationGain
        self.energyGateThreshold = energyGateThreshold
        self.defaultCooldown = defaultCooldown
        self.perGestureSensitivity = perGestureSensitivity
        self.perGestureCooldown = perGestureCooldown
        self.notes = notes
        self.lastModified = lastModified
    }
}
