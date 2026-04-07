import SwiftUI
import UIKit

struct PerformanceView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var oscSender: OSCSender
    @EnvironmentObject var gestureLibrary: GestureLibrary
    @StateObject private var classifier = GestureClassifier()

    @State private var recentGestures: [(name: String, time: Date)] = []
    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Stream toggle
                streamToggle

                // Connection status
                if sensorManager.isStreaming {
                    HStack(spacing: 6) {
                        Image(systemName: oscSender.isConnected ? "wifi" : "wifi.slash")
                        Text(oscSender.isConnected ? "\(oscSender.configuration.host):\(oscSender.configuration.port)" : "Connecting...")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(oscSender.isConnected ? .green : .orange)
                }

                // Live IMU waveform
                IMUWaveformView(sample: sensorManager.latestSample)
                    .frame(height: 120)

                // Gesture probability bars
                if !classifier.predictions.isEmpty {
                    GestureProbabilityBarsView(predictions: classifier.predictions)
                }

                // Recent gestures
                if !recentGestures.isEmpty {
                    recentGesturesList
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Kinetic")
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    bottomBar
                }
            }
            .onAppear {
                classifier.loadTemplates(from: gestureLibrary)
            }
        }
    }

    // MARK: - Subviews

    private var streamToggle: some View {
        Button {
            toggleStreaming()
        } label: {
            HStack {
                Circle()
                    .fill(sensorManager.isStreaming ? .green : .gray)
                    .frame(width: 12, height: 12)
                Text(sensorManager.isStreaming ? "Streaming" : "Stream")
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(sensorManager.isStreaming ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sensorManager.isStreaming ? "Stop streaming" : "Start streaming")
    }

    private var recentGesturesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(recentGestures.suffix(5), id: \.time) { gesture in
                Text(gesture.name)
                    .font(.caption.monospaced())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        HStack {
            NavigationLink("Library") { GestureLibraryView() }
            Spacer()
            NavigationLink("Train") { TrainingView() }
            Spacer()
            NavigationLink("Settings") { SettingsView() }
            Spacer()
            NavigationLink("Test") { TestModeView() }
        }
    }

    // MARK: - Actions

    private func toggleStreaming() {
        if sensorManager.isStreaming {
            sensorManager.stopStreaming()
            oscSender.disconnect()
            classifier.reset()
        } else {
            // Reload templates in case user trained new gestures
            classifier.loadTemplates(from: gestureLibrary)
            haptic.prepare()

            oscSender.connect()
            sensorManager.startStreaming { sample in
                Task { @MainActor in
                    oscSender.sendIMU(sample)
                    classifier.processSample(sample)

                    // Check for gesture triggers
                    for (name, prob) in classifier.predictions where prob > 0.8 {
                        oscSender.sendGestureEvent(name: name, probability: prob)
                        if prob > 0.9 {
                            oscSender.sendGestureTrigger(name: name)
                            haptic.impactOccurred()
                            recentGestures.append((name: name, time: .now))
                            if recentGestures.count > 20 {
                                recentGestures.removeFirst()
                            }
                        }
                    }
                }
            }
        }
    }
}
