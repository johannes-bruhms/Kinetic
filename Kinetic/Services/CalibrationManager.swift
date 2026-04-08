import Foundation
import Combine

/// Manages calibration profiles: CRUD operations with JSON persistence.
/// Profiles are stored in Documents/kinetic_calibrations/.
@MainActor
final class CalibrationManager: ObservableObject {
    @Published var profiles: [CalibrationProfile] = []
    @Published var activeProfileID: UUID?

    private let storageURL: URL

    var activeProfile: CalibrationProfile? {
        guard let id = activeProfileID else { return nil }
        return profiles.first { $0.id == id }
    }

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documents.appendingPathComponent("kinetic_calibrations")
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadProfiles()
    }

    // MARK: - CRUD

    @discardableResult
    func createProfile(name: String) -> CalibrationProfile {
        let profile = CalibrationProfile(name: name)
        profiles.append(profile)
        saveProfiles()
        return profile
    }

    func updateProfile(_ profile: CalibrationProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profile
        updated.lastModified = .now
        profiles[index] = updated
        saveProfiles()
    }

    func deleteProfile(_ profile: CalibrationProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = nil
        }
        saveProfiles()
    }

    func duplicateProfile(_ profile: CalibrationProfile) -> CalibrationProfile {
        var copy = profile
        copy = CalibrationProfile(
            name: "\(profile.name) Copy",
            referenceAttitudeQuaternion: profile.referenceAttitudeQuaternion,
            accelGain: profile.accelGain,
            rotationGain: profile.rotationGain,
            energyGateThreshold: profile.energyGateThreshold,
            defaultCooldown: profile.defaultCooldown,
            perGestureSensitivity: profile.perGestureSensitivity,
            perGestureCooldown: profile.perGestureCooldown,
            notes: profile.notes
        )
        profiles.append(copy)
        saveProfiles()
        return copy
    }

    /// Activate a profile. Returns the profile for the caller to apply.
    func activate(_ profile: CalibrationProfile) {
        activeProfileID = profile.id
        saveProfiles()
    }

    func deactivate() {
        activeProfileID = nil
        saveProfiles()
    }

    /// Capture current state into a new or existing profile.
    func captureCurrentState(
        name: String,
        referenceQuaternion: [Double]?,
        gestureLibrary: GestureLibrary
    ) -> CalibrationProfile {
        var sensitivity: [String: Double] = [:]
        var cooldown: [String: TimeInterval] = [:]
        for gesture in gestureLibrary.gestures {
            sensitivity[gesture.id.uuidString] = gesture.sensitivity
            if gesture.gestureType == .discrete {
                cooldown[gesture.id.uuidString] = gesture.cooldownDuration
            }
        }

        let profile = CalibrationProfile(
            name: name,
            referenceAttitudeQuaternion: referenceQuaternion,
            perGestureSensitivity: sensitivity,
            perGestureCooldown: cooldown
        )
        profiles.append(profile)
        saveProfiles()
        return profile
    }

    /// Apply a profile's settings to the gesture library.
    func applyProfile(_ profile: CalibrationProfile, to library: GestureLibrary) {
        for gesture in library.gestures {
            var updated = gesture
            if let sens = profile.perGestureSensitivity[gesture.id.uuidString] {
                updated.sensitivity = sens
            }
            if let cd = profile.perGestureCooldown[gesture.id.uuidString] {
                updated.cooldownDuration = cd
            }
            library.updateGesture(updated)
        }
        activeProfileID = profile.id
        saveProfiles()
    }

    // MARK: - Persistence

    private var indexURL: URL {
        storageURL.appendingPathComponent("profiles.json")
    }

    private var stateURL: URL {
        storageURL.appendingPathComponent("state.json")
    }

    private func saveProfiles() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: indexURL)
        }
        // Save active profile ID
        let stateDict = ["activeProfileID": activeProfileID?.uuidString ?? ""]
        if let data = try? JSONEncoder().encode(stateDict) {
            try? data.write(to: stateURL)
        }
    }

    private func loadProfiles() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: indexURL),
           let loaded = try? decoder.decode([CalibrationProfile].self, from: data) {
            profiles = loaded
        }
        if let data = try? Data(contentsOf: stateURL),
           let stateDict = try? JSONDecoder().decode([String: String].self, from: data),
           let idStr = stateDict["activeProfileID"], !idStr.isEmpty {
            activeProfileID = UUID(uuidString: idStr)
        }
    }
}
