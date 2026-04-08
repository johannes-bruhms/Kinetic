import SwiftUI

struct TrainingView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var gestureLibrary: GestureLibrary

    @State private var selectedGesture: TrainedGesture?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if gestureLibrary.gestures.isEmpty {
                    ContentUnavailableView("No Gestures", systemImage: "hand.wave", description: Text("Create a gesture in the Library first"))
                } else {
                    gesturePicker

                    if let gesture = selectedGesture {
                        switch gesture.gestureType {
                        case .discrete:
                            DiscreteTrainingSection(gesture: gesture)
                                .environmentObject(sensorManager)
                                .environmentObject(gestureLibrary)
                        case .continuous:
                            ContinuousTrainingSection(gesture: gesture)
                                .environmentObject(sensorManager)
                                .environmentObject(gestureLibrary)
                        case .posture:
                            PostureTrainingSection(gesture: gesture)
                                .environmentObject(sensorManager)
                                .environmentObject(gestureLibrary)
                        }
                    } else {
                        instructionsCard
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Train")
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Select a Gesture", systemImage: "info.circle")
                .font(.headline)

            Text("Choose a gesture above to start training. The training method depends on the gesture type (discrete, continuous, or posture).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var gesturePicker: some View {
        Picker("Gesture", selection: $selectedGesture) {
            Text("Select...").tag(nil as TrainedGesture?)
            ForEach(gestureLibrary.gestures) { gesture in
                Text(gesture.name).tag(gesture as TrainedGesture?)
            }
        }
        .pickerStyle(.menu)
    }
}

// MARK: - Discrete Training

struct DiscreteTrainingSection: View {
    let gesture: TrainedGesture
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var gestureLibrary: GestureLibrary

    @State private var isRecording = false
    @State private var recordedSamples: [MotionSample] = []
    @State private var segments: [GestureSegmenter.Segment] = []
    @State private var showSegmentReview = false
    @State private var recordingStart: Date?
    @State private var liveEnergy: Double = 0

    private let segmenter = GestureSegmenter()

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Discrete Training", systemImage: "hand.tap")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    instructionRow(number: "1", text: "Press and hold 'Record'")
                    instructionRow(number: "2", text: "Perform the gesture once")
                    instructionRow(number: "3", text: "Release to finish")
                    instructionRow(number: "4", text: "Repeat 3\u{2013}5 times")
                    instructionRow(number: "5", text: "Review the segments and save")
                }

                Text("Silences before and after your motion are automatically removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            recordingSection

            if showSegmentReview {
                segmentReviewSection
            }
        }
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption2.bold())
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.2))
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }

    private var recordingSection: some View {
        VStack(spacing: 12) {
            if isRecording {
                VStack(spacing: 8) {
                    if let start = recordingStart {
                        Text(start, style: .timer)
                            .font(.title.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text("Perform your gesture once")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(recordedSamples.count) samples")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)

                    energyMeter
                }
            }

            Text(isRecording ? "Recording..." : "Hold to Record")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isRecording ? Color.red : Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .scaleEffect(isRecording ? 0.96 : 1.0)
                .animation(.interactiveSpring, value: isRecording)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isRecording {
                                startRecording()
                            }
                        }
                        .onEnded { _ in
                            if isRecording {
                                stopRecording()
                            }
                        }
                )
        }
    }

    private var energyMeter: some View {
        VStack(spacing: 4) {
            ProgressView(value: min(liveEnergy / 5.0, 1.0))
                .tint(liveEnergy > 0.8 ? .green : .gray)
            HStack {
                Text("Still")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("Moving")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal)
    }

    private var segmentReviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if segments.isEmpty {
                VStack(spacing: 8) {
                    Text("No gestures detected")
                        .font(.headline)
                    Text("Make sure you move with enough energy and pause between repetitions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Detected \(segments.count) gesture\(segments.count == 1 ? "" : "s")")
                    .font(.headline)

                Text("Remove any that look wrong, then save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    HStack {
                        Text("Repetition \(index + 1)")
                        Spacer()
                        Text("\(segment.samples.count) points")
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            segments.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                Button("Save Samples") {
                    saveSamples()
                }
                .buttonStyle(.borderedProminent)
                .disabled(segments.isEmpty)

                Button("Discard") {
                    segments.removeAll()
                    showSegmentReview = false
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func startRecording() {
        recordedSamples.removeAll()
        recordingStart = .now

        sensorManager.startStreaming { sample in
            Task { @MainActor in
                recordedSamples.append(sample)
                liveEnergy = sample.userAcceleration.magnitude + sample.rotationRate.magnitude
            }
        }
        isRecording = true
    }

    private func stopRecording() {
        sensorManager.stopStreaming()
        isRecording = false
        recordingStart = nil

        let newSegments = segmenter.segment(recordedSamples)
        if !newSegments.isEmpty {
            segments.append(contentsOf: newSegments)
            showSegmentReview = true
        } else if recordedSamples.count > 0 && segments.isEmpty {
            showSegmentReview = true
        }
    }

    private func saveSamples() {
        for segment in segments {
            let recording = GestureRecording(
                gestureId: gesture.id,
                samples: segment.samples,
                recordedAt: .now
            )
            gestureLibrary.saveRecording(recording)
        }

        var updated = gesture
        updated.sampleCount += segments.count
        updated.lastTrained = .now
        gestureLibrary.updateGesture(updated)

        segments.removeAll()
        showSegmentReview = false
    }
}

// MARK: - Continuous Training

struct ContinuousTrainingSection: View {
    let gesture: TrainedGesture
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var gestureLibrary: GestureLibrary

    @State private var isRecording = false
    @State private var recordedSamples: [MotionSample] = []
    @State private var recordingStart: Date?
    @State private var liveEnergy: Double = 0
    @State private var extractedProfile: ContinuousGestureProfile?
    @State private var recordingCount = 0
    @State private var autoStopTimer: Timer?
    @State private var elapsedSeconds: Int = 0
    @State private var countdownTimer: Timer?

    private let recordingDuration: TimeInterval = 10.0

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Continuous Training", systemImage: "waveform.path")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text("Perform the gesture continuously for 10 seconds. The app will analyze the frequency and intensity of your motion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            if isRecording {
                VStack(spacing: 8) {
                    Text("\(10 - elapsedSeconds)")
                        .font(.system(size: 48, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                        .animation(.easeInOut, value: elapsedSeconds)

                    Text("Keep performing the gesture...")
                        .font(.subheadline)
                        .foregroundStyle(.green)

                    ProgressView(value: Double(elapsedSeconds) / 10.0)
                        .tint(.green)
                        .padding(.horizontal)

                    ProgressView(value: min(liveEnergy / 5.0, 1.0))
                        .tint(.green.opacity(0.5))
                        .padding(.horizontal)

                    Text("\(recordedSamples.count) samples")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            Button(isRecording ? "Stop Early" : "Start 10s Recording") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .font(.title3.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isRecording ? Color.red : Color.green)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let profile = extractedProfile {
                profileSummary(profile)
            }

            if recordingCount > 0 {
                Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s") saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func profileSummary(_ profile: ContinuousGestureProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Profile Extracted")
                .font(.headline)

            HStack {
                Text("Dominant Frequency:")
                Spacer()
                Text(String(format: "%.1f Hz", profile.dominantFrequency))
                    .monospaced()
            }
            HStack {
                Text("Primary Axis:")
                Spacer()
                Text(dominantAxisLabel(profile.axisDistribution))
                    .monospaced()
            }
            HStack {
                Text("Amplitude Range:")
                Spacer()
                Text(String(format: "%.1f\u{2013}%.1f", profile.amplitudeMin, profile.amplitudeMax))
                    .monospaced()
            }
        }
        .font(.subheadline)
        .padding()
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func dominantAxisLabel(_ dist: Vector3) -> String {
        if dist.x > dist.y && dist.x > dist.z { return "X-axis" }
        if dist.y > dist.x && dist.y > dist.z { return "Y-axis" }
        return "Z-axis"
    }

    private func startRecording() {
        recordedSamples.removeAll()
        recordingStart = .now
        elapsedSeconds = 0

        sensorManager.startStreaming { sample in
            Task { @MainActor in
                recordedSamples.append(sample)
                liveEnergy = sample.userAcceleration.magnitude + sample.rotationRate.magnitude
            }
        }
        isRecording = true

        // Countdown timer (updates every second)
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                elapsedSeconds += 1
            }
        }

        // Auto-stop after 10 seconds
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: recordingDuration, repeats: false) { _ in
            Task { @MainActor in
                if isRecording {
                    stopRecording()
                }
            }
        }
    }

    private func stopRecording() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        countdownTimer?.invalidate()
        countdownTimer = nil
        sensorManager.stopStreaming()
        isRecording = false
        recordingStart = nil

        guard recordedSamples.count >= 50 else { return }

        let profile = FrequencyAnalyzer.extractProfile(from: recordedSamples)
        extractedProfile = profile

        let recording = GestureRecording(
            gestureId: gesture.id,
            samples: recordedSamples,
            recordedAt: .now,
            recordingDuration: Double(recordedSamples.count) / 100.0,
            extractedProfile: profile
        )
        gestureLibrary.saveRecording(recording)

        var updated = gesture
        updated.sampleCount += 1
        updated.lastTrained = .now
        gestureLibrary.updateGesture(updated)

        recordingCount += 1
    }
}

// MARK: - Posture Training

struct PostureTrainingSection: View {
    let gesture: TrainedGesture
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var gestureLibrary: GestureLibrary

    @State private var isRecording = false
    @State private var recordedSamples: [MotionSample] = []
    @State private var countdown = 3
    @State private var capturedVector: Vector3?
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Posture Training", systemImage: "iphone.gen3")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text("Hold the phone in the desired position. The app will capture the gravity vector after a 3-second countdown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            if isRecording {
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .heavy))
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())
                    .animation(.easeInOut, value: countdown)

                Text("Hold steady...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(isRecording ? "Cancel" : "Capture Position") {
                if isRecording {
                    cancelCapture()
                } else {
                    startCapture()
                }
            }
            .font(.title3.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isRecording ? Color.red : Color.orange)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let vec = capturedVector {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position Captured")
                        .font(.headline)

                    HStack {
                        Text("Gravity:")
                        Spacer()
                        Text(String(format: "(%.2f, %.2f, %.2f)", vec.x, vec.y, vec.z))
                            .monospaced()
                    }

                    let orientation = describeOrientation(vec)
                    HStack {
                        Text("Orientation:")
                        Spacer()
                        Text(orientation)
                    }
                }
                .font(.subheadline)
                .padding()
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func describeOrientation(_ g: Vector3) -> String {
        let absX = abs(g.x), absY = abs(g.y), absZ = abs(g.z)
        if absZ > absX && absZ > absY {
            return g.z < 0 ? "Face up" : "Face down"
        } else if absY > absX {
            return g.y < 0 ? "Portrait" : "Portrait (inverted)"
        } else {
            return g.x < 0 ? "Landscape left" : "Landscape right"
        }
    }

    private func startCapture() {
        recordedSamples.removeAll()
        countdown = 3
        isRecording = true

        sensorManager.startStreaming { sample in
            Task { @MainActor in
                recordedSamples.append(sample)
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                countdown -= 1
                if countdown <= 0 {
                    finishCapture()
                }
            }
        }
    }

    private func cancelCapture() {
        timer?.invalidate()
        timer = nil
        sensorManager.stopStreaming()
        isRecording = false
    }

    private func finishCapture() {
        timer?.invalidate()
        timer = nil
        sensorManager.stopStreaming()
        isRecording = false

        guard !recordedSamples.isEmpty else { return }

        let avgGravity = Vector3.average(recordedSamples.map(\.gravity))
        capturedVector = avgGravity

        let recording = GestureRecording(
            gestureId: gesture.id,
            samples: recordedSamples,
            recordedAt: .now,
            postureVector: avgGravity
        )
        gestureLibrary.saveRecording(recording)

        var updated = gesture
        updated.sampleCount += 1
        updated.lastTrained = .now
        gestureLibrary.updateGesture(updated)
    }
}
