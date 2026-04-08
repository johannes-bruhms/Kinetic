import SwiftUI
import UIKit

struct TestModeView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var oscSender: OSCSender
    @EnvironmentObject var gestureLibrary: GestureLibrary
    @StateObject private var classifier = GestureClassifier()

    @State private var hapticEnabled = true
    @State private var lastDetected: String?

    @State private var isLogging = false
    @State private var exportItem: ExportItem?

    private let hapticImpact = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        VStack(spacing: 24) {
            Text("Test Mode")
                .font(.largeTitle.bold())

            // Discrete probability bars
            if !classifier.predictions.isEmpty {
                VStack(spacing: 12) {
                    ForEach(classifier.predictions.sorted(by: { $0.value > $1.value }), id: \.key) { name, probability in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(.title3.bold())
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(probability > 0.8 ? Color.green : probability > 0.5 ? Color.yellow : Color.gray.opacity(0.4))
                                        .frame(width: geo.size.width * CGFloat(probability))
                                        .animation(.easeOut(duration: 0.1), value: probability)
                                }
                            }
                            .frame(height: 40)
                        }
                    }
                }
                .padding()
            } else if !classifier.isReady {
                ContentUnavailableView("No Gestures Trained", systemImage: "waveform.badge.exclamationmark", description: Text("Record gesture samples in the Training tab first"))
            } else {
                ContentUnavailableView("Waiting for Motion", systemImage: "waveform", description: Text("Start the test and perform a gesture"))
            }

            // Continuous gesture indicators
            if !classifier.continuousStates.isEmpty {
                VStack(spacing: 8) {
                    ForEach(classifier.continuousStates.sorted(by: { $0.key < $1.key }), id: \.key) { name, state in
                        HStack(spacing: 12) {
                            Text(name)
                                .font(.title3.bold())
                            Text(state.isActive ? "ACTIVE" : "idle")
                                .font(.headline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(state.isActive ? Color.green : Color.gray.opacity(0.3))
                                .foregroundColor(state.isActive ? .black : .secondary)
                                .clipShape(Capsule())
                            if state.isActive {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.gray.opacity(0.2))
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.green)
                                            .frame(width: geo.size.width * CGFloat(state.intensity))
                                    }
                                }
                                .frame(height: 24)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Posture indicators
            if !classifier.postureStates.isEmpty {
                HStack(spacing: 12) {
                    ForEach(classifier.postureStates.sorted(by: { $0.key < $1.key }), id: \.key) { name, isActive in
                        VStack(spacing: 4) {
                            Image(systemName: isActive ? "iphone.gen3" : "iphone.gen3.slash")
                                .font(.title2)
                                .foregroundStyle(isActive ? .orange : .gray)
                            Text(name)
                                .font(.caption.bold())
                            Text(isActive ? "ON" : "OFF")
                                .font(.caption2)
                                .foregroundStyle(isActive ? .orange : .secondary)
                        }
                        .padding()
                        .background(isActive ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            if let detected = lastDetected {
                Text(detected)
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            Toggle("Haptic Feedback", isOn: $hapticEnabled)
                .padding(.horizontal)

            loggingToggle
                .padding(.horizontal)

            Button(sensorManager.isStreaming ? "Stop" : "Start Test") {
                toggleTest()
            }
            .font(.title2.bold())
            .buttonStyle(.borderedProminent)
            .tint(sensorManager.isStreaming ? .red : .green)
            .padding()
        }
        .navigationTitle("Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            classifier.loadTemplates(from: gestureLibrary)
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
    }

    private var loggingToggle: some View {
        Button {
            toggleLogging()
        } label: {
            HStack {
                Image(systemName: isLogging ? "stop.circle" : "record.circle")
                    .foregroundStyle(isLogging ? .red : .blue)
                Text(isLogging ? "Stop Logging" : "Log Performance")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isLogging ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private func toggleLogging() {
        Task {
            if isLogging {
                let trainingData = await MainActor.run { gestureLibrary.exportAllData() }
                if let url = await PerformanceLogger.shared.stopLogging(trainingDataURL: trainingData) {
                    await MainActor.run {
                        exportItem = ExportItem(url: url)
                    }
                }
                await MainActor.run {
                    isLogging = false
                }
            } else {
                await PerformanceLogger.shared.startLogging()
                await MainActor.run {
                    isLogging = true
                }
            }
        }
    }

    private func toggleTest() {
        if sensorManager.isStreaming {
            sensorManager.stopStreaming()
            classifier.reset()
            if isLogging {
                toggleLogging()
            }
        } else {
            classifier.loadTemplates(from: gestureLibrary)
            hapticImpact.prepare()

            sensorManager.startStreaming { sample in
                Task { @MainActor in
                    classifier.processSample(sample)

                    // Use fusion engine events for trigger detection
                    let triggeredEvent = classifier.performanceEvents
                        .first { $0.lane == .discrete && $0.phase == .active }

                    if let event = triggeredEvent {
                        lastDetected = event.gestureName
                        if hapticEnabled {
                            hapticImpact.impactOccurred()
                        }
                    }

                    if isLogging {
                        await PerformanceLogger.shared.log(
                            sample: sample,
                            probabilities: classifier.predictions,
                            triggeredGesture: triggeredEvent?.gestureName,
                            continuousStates: classifier.continuousStates,
                            postureStates: classifier.postureStates
                        )
                    }
                }
            }
        }
    }
}
