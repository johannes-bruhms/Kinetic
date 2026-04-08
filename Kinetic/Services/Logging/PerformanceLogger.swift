import Foundation

/// Records performance sessions to a highly token-efficient CSV format.
/// By discarding silence/stationary samples and formatting compactly,
/// this generates logs that are easily digestible by LLMs for analysis.
actor PerformanceLogger {
    static let shared = PerformanceLogger()

    /// Directory where session CSVs are stored on device.
    static var sessionsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("kinetic_sessions")
    }

    /// List all saved session files, newest first.
    nonisolated static func savedSessions() -> [(name: String, url: URL, date: Date)] {
        let dir = sessionsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "csv" }
            .compactMap { url in
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let date = attrs?[.creationDate] as? Date ?? Date.distantPast
                return (name: url.lastPathComponent, url: url, date: date)
            }
            .sorted { $0.date > $1.date }
    }

    /// Delete a saved session file.
    nonisolated static func deleteSession(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private var csvLines: [String] = []
    private var isLogging = false
    private var sessionStartTime: Date?
    private var sampleCount = 0

    func startLogging() {
        guard !isLogging else { return }
        csvLines.removeAll()

        let header = "Time,AccX,AccY,AccZ,RotX,RotY,RotZ,Trigger,Probabilities,ContinuousState,PostureState,LatencyMs"
        csvLines.append(header)

        sessionStartTime = Date()
        sampleCount = 0
        isLogging = true
        print("Started performance logging (CSV mode)")
    }

    func stopLogging(trainingDataURL: URL? = nil) -> URL? {
        guard isLogging else { return nil }
        isLogging = false
        print("Stopped performance logging. Captured \(csvLines.count - 1) active frames out of \(sampleCount) total.")

        var finalString = ""

        if let url = trainingDataURL, let trainingDataStr = try? String(contentsOf: url, encoding: .utf8) {
            finalString += "# --- TRAINING DATA SEED SAMPLES ---\n"
            let commentedJson = trainingDataStr.split(separator: "\n").map { "# \($0)" }.joined(separator: "\n")
            finalString += commentedJson + "\n"
            finalString += "# --- END TRAINING DATA ---\n\n"
            try? FileManager.default.removeItem(at: url)
        }

        finalString += csvLines.joined(separator: "\n")

        csvLines.removeAll()
        sessionStartTime = nil
        sampleCount = 0

        // Save to Documents/kinetic_sessions/ for in-app analysis
        let sessionsDir = Self.sessionsDirectory
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        let filename = "kinetic_session_\(Int(Date().timeIntervalSince1970)).csv"
        let savedURL = sessionsDir.appendingPathComponent(filename)
        do {
            try finalString.write(to: savedURL, atomically: true, encoding: .utf8)
            return savedURL
        } catch {
            print("Failed to save performance log: \(error)")
            return nil
        }
    }

    func log(
        sample: MotionSample,
        probabilities: [String: Float]?,
        triggeredGesture: String?,
        continuousStates: [String: ContinuousGestureState] = [:],
        postureStates: [String: Bool] = [:],
        latencyMs: Double = 0
    ) {
        guard isLogging else { return }
        sampleCount += 1

        let energy = sample.userAcceleration.magnitude + sample.rotationRate.magnitude
        let maxProb = probabilities?.values.max() ?? 0.0
        let hasContinuousActive = continuousStates.values.contains { $0.isActive }
        let hasPostureActive = postureStates.values.contains { $0 }

        // Skip logging if everything is idle
        if triggeredGesture == nil && maxProb < 0.1 && energy < 0.2 && !hasContinuousActive && !hasPostureActive {
            return
        }

        // Format probabilities compactly
        let probString: String
        if let probs = probabilities, !probs.isEmpty {
            let activeProbs = probs.filter { $0.value > 0.05 }
            probString = activeProbs
                .sorted { $0.value > $1.value }
                .map { "\($0.key.replacingOccurrences(of: " ", with: "")):\(String(format: "%.2f", $0.value))" }
                .joined(separator: "|")
        } else {
            probString = ""
        }

        // Format continuous states: "shake:active:0.75|circle:idle:0.00"
        let continuousString: String
        if !continuousStates.isEmpty {
            continuousString = continuousStates
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value.isActive ? "on" : "off"):\(String(format: "%.2f", $0.value.intensity))" }
                .joined(separator: "|")
        } else {
            continuousString = ""
        }

        // Format posture states: "vertical:on|tilt:off"
        let postureString: String
        if !postureStates.isEmpty {
            postureString = postureStates
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value ? "on" : "off")" }
                .joined(separator: "|")
        } else {
            postureString = ""
        }

        let timeStr = String(format: "%.3f", sample.timestamp)
        let ax = String(format: "%.2f", sample.userAcceleration.x)
        let ay = String(format: "%.2f", sample.userAcceleration.y)
        let az = String(format: "%.2f", sample.userAcceleration.z)
        let rx = String(format: "%.2f", sample.rotationRate.x)
        let ry = String(format: "%.2f", sample.rotationRate.y)
        let rz = String(format: "%.2f", sample.rotationRate.z)
        let triggerStr = triggeredGesture?.replacingOccurrences(of: " ", with: "") ?? ""

        let latencyStr = latencyMs > 0 ? String(format: "%.1f", latencyMs) : ""
        let line = "\(timeStr),\(ax),\(ay),\(az),\(rx),\(ry),\(rz),\(triggerStr),\(probString),\(continuousString),\(postureString),\(latencyStr)"
        csvLines.append(line)
    }
}
