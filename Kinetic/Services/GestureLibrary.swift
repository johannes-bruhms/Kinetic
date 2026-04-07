import Foundation
import Combine

@MainActor
final class GestureLibrary: ObservableObject {
    @Published var gestures: [TrainedGesture] = []

    private let storageURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documents.appendingPathComponent("kinetic_gestures")

        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        loadGestures()
    }

    func addGesture(name: String) -> TrainedGesture {
        let gesture = TrainedGesture(name: name)
        gestures.append(gesture)
        saveGestures()
        return gesture
    }

    func deleteGesture(_ gesture: TrainedGesture) {
        gestures.removeAll { $0.id == gesture.id }
        // Remove associated model file
        if let modelFile = gesture.modelFileName {
            let modelURL = storageURL.appendingPathComponent(modelFile)
            try? FileManager.default.removeItem(at: modelURL)
        }
        // Remove recordings
        let recordingsURL = storageURL.appendingPathComponent("recordings/\(gesture.id.uuidString)")
        try? FileManager.default.removeItem(at: recordingsURL)
        saveGestures()
    }

    func renameGesture(_ gesture: TrainedGesture, to newName: String) {
        guard let index = gestures.firstIndex(where: { $0.id == gesture.id }) else { return }
        gestures[index].name = newName
        saveGestures()
    }

    func updateGesture(_ gesture: TrainedGesture) {
        guard let index = gestures.firstIndex(where: { $0.id == gesture.id }) else { return }
        gestures[index] = gesture
        saveGestures()
    }

    func saveRecording(_ recording: GestureRecording) {
        let recordingsDir = storageURL.appendingPathComponent("recordings/\(recording.gestureId.uuidString)")
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let fileURL = recordingsDir.appendingPathComponent("\(UUID().uuidString).json")
        if let data = try? JSONEncoder().encode(recording) {
            try? data.write(to: fileURL)
        }
    }

    func loadRecordings(for gestureId: UUID) -> [GestureRecording] {
        let recordingsDir = storageURL.appendingPathComponent("recordings/\(gestureId.uuidString)")
        guard let files = try? FileManager.default.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: nil) else {
            return []
        }

        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(GestureRecording.self, from: data)
        }
    }

    /// Export all gesture data as a JSON archive to a temporary file, returns the URL.
    func exportAllData() -> URL? {
        struct ExportBundle: Encodable {
            let exportDate: Date
            let gestures: [TrainedGesture]
            let recordings: [String: [GestureRecording]] // keyed by gesture name
        }

        var recordingsMap: [String: [GestureRecording]] = [:]
        for gesture in gestures {
            let recs = loadRecordings(for: gesture.id)
            if !recs.isEmpty {
                recordingsMap[gesture.name] = recs
            }
        }

        let bundle = ExportBundle(
            exportDate: .now,
            gestures: gestures,
            recordings: recordingsMap
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(bundle) else { return nil }

        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kinetic_export_\(Int(Date.now.timeIntervalSince1970)).json")
        guard (try? data.write(to: exportURL)) != nil else { return nil }
        return exportURL
    }

    // MARK: - Persistence

    private var indexURL: URL {
        storageURL.appendingPathComponent("gestures.json")
    }

    private func saveGestures() {
        if let data = try? JSONEncoder().encode(gestures) {
            try? data.write(to: indexURL)
        }
    }

    private func loadGestures() {
        guard let data = try? Data(contentsOf: indexURL),
              let loaded = try? JSONDecoder().decode([TrainedGesture].self, from: data) else { return }
        gestures = loaded
    }
}
