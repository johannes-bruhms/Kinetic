import SwiftUI

struct TrainingView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var gestureLibrary: GestureLibrary

    @State private var selectedGesture: TrainedGesture?
    @State private var isRecording = false
    @State private var recordedSamples: [MotionSample] = []
    @State private var segments: [GestureSegmenter.Segment] = []
    @State private var showSegmentReview = false

    private let segmenter = GestureSegmenter()

    var body: some View {
        VStack(spacing: 20) {
            // Gesture picker
            if gestureLibrary.gestures.isEmpty {
                ContentUnavailableView("No Gestures", systemImage: "hand.wave", description: Text("Create a gesture in the Library first"))
            } else {
                gesturePicker
                recordingSection
                if showSegmentReview {
                    segmentReviewSection
                }
            }
        }
        .padding()
        .navigationTitle("Train")
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

    private var recordingSection: some View {
        VStack(spacing: 12) {
            if isRecording {
                // Live energy meter
                VStack {
                    Text("Perform your gesture...")
                        .font(.title3)
                    Text("\(recordedSamples.count) samples")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    if let latest = sensorManager.latestSample {
                        let energy = latest.userAcceleration.magnitude + latest.rotationRate.magnitude
                        ProgressView(value: min(energy / 5.0, 1.0))
                            .tint(energy > 0.8 ? .green : .gray)
                    }
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

    private var segmentReviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected \(segments.count) gesture(s)")
                .font(.headline)

            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                HStack {
                    Text("Sample \(index + 1)")
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

            Button("Save Samples") {
                saveSamples()
            }
            .buttonStyle(.borderedProminent)
            .disabled(segments.isEmpty)
        }
    }

    // MARK: - Actions

    private func startRecording() {
        guard selectedGesture != nil else { return }
        recordedSamples.removeAll()
        segments.removeAll()
        showSegmentReview = false

        sensorManager.startStreaming { sample in
            recordedSamples.append(sample)
        }
        isRecording = true
    }

    private func stopRecording() {
        sensorManager.stopStreaming()
        isRecording = false

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
