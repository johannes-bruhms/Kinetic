import SwiftUI

struct TrainingView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var gestureLibrary: GestureLibrary

    @State private var selectedGesture: TrainedGesture?
    @State private var isRecording = false
    @State private var recordedSamples: [MotionSample] = []
    @State private var segments: [GestureSegmenter.Segment] = []
    @State private var showSegmentReview = false
    @State private var recordingStart: Date?
    @State private var liveEnergy: Double = 0

    private let segmenter = GestureSegmenter()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if gestureLibrary.gestures.isEmpty {
                    ContentUnavailableView("No Gestures", systemImage: "hand.wave", description: Text("Create a gesture in the Library first"))
                } else {
                    gesturePicker

                    if !isRecording && !showSegmentReview {
                        instructionsCard
                    }

                    recordingSection

                    if showSegmentReview {
                        segmentReviewSection
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Train")
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How to Train", systemImage: "info.circle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Select a gesture above")
                instructionRow(number: "2", text: "Tap Start Recording")
                instructionRow(number: "3", text: "Perform the gesture 3\u{2013}5 times")
                instructionRow(number: "4", text: "Pause ~1 second between each repetition")
                instructionRow(number: "5", text: "Tap Stop Recording")
                instructionRow(number: "6", text: "Review the detected segments and save")
            }

            Text("Repetitions are detected automatically from pauses in your motion. Train across multiple sessions for best results.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    // MARK: - Gesture Picker

    private var gesturePicker: some View {
        Picker("Gesture", selection: $selectedGesture) {
            Text("Select...").tag(nil as TrainedGesture?)
            ForEach(gestureLibrary.gestures) { gesture in
                Text(gesture.name).tag(gesture as TrainedGesture?)
            }
        }
        .pickerStyle(.menu)
    }

    // MARK: - Recording

    private var recordingSection: some View {
        VStack(spacing: 12) {
            if isRecording {
                VStack(spacing: 8) {
                    if let start = recordingStart {
                        Text(start, style: .timer)
                            .font(.title.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Text("Perform your gesture with pauses between each rep")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("\(recordedSamples.count) samples")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)

                    // Energy meter
                    energyMeter
                }
            }

            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .blue)
            .disabled(selectedGesture == nil)
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

    // MARK: - Segment Review

    private var segmentReviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if segments.isEmpty {
                VStack(spacing: 8) {
                    Text("No gestures detected")
                        .font(.headline)
                    Text("Make sure you move with enough energy and pause between repetitions. Try more pronounced movements.")
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

    // MARK: - Actions

    private func startRecording() {
        guard selectedGesture != nil else { return }
        recordedSamples.removeAll()
        segments.removeAll()
        showSegmentReview = false
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

        segments = segmenter.segment(recordedSamples)
        showSegmentReview = true
    }

    private func saveSamples() {
        guard let gesture = selectedGesture else { return }

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
