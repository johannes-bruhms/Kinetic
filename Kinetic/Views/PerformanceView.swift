import SwiftUI
import UIKit

struct PerformanceView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var oscSender: OSCSender
    @EnvironmentObject var gestureLibrary: GestureLibrary
    @StateObject private var classifier = GestureClassifier()

    @State private var recentGestures: [(name: String, time: Date)] = []
    private let hapticImpact = UIImpactFeedbackGenerator(style: .heavy)

    @State private var isLogging = false
    @State private var exportItem: ExportItem?

    // Track previous continuous/posture states for transition detection
    @State private var previousContinuousActive: Set<String> = []
    @State private var previousPostureActive: Set<String> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                streamToggle
                loggingToggle

                if sensorManager.isStreaming {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: oscSender.isConnected ? "wifi" : "wifi.slash")
                            Text(oscSender.isConnected ? "\(oscSender.configuration.host):\(oscSender.configuration.port)" : "Connecting...")
                        }
                        .font(.caption.monospaced())
                        .foregroundStyle(oscSender.isConnected ? .green : .orange)

                        Spacer()

                        Button {
                            if sensorManager.isCalibrated {
                                sensorManager.clearCalibration()
                            } else {
                                sensorManager.calibrate()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: sensorManager.isCalibrated ? "checkmark.circle.fill" : "scope")
                                Text(sensorManager.isCalibrated ? "Zeroed" : "Zero")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(sensorManager.isCalibrated ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                IMUWaveformView(sample: sensorManager.latestSample)
                    .frame(height: 120)

                // Discrete gesture probability bars
                if !classifier.predictions.isEmpty {
                    GestureProbabilityBarsView(predictions: classifier.predictions, gestureType: .discrete)
                }

                // Continuous gesture states
                if !classifier.continuousStates.isEmpty {
                    continuousStateSection
                }

                // Posture states
                if !classifier.postureStates.isEmpty {
                    postureStateSection
                }

                // Latency monitor
                if sensorManager.isStreaming && classifier.isReady {
                    latencySection
                }

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
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
    }

    // MARK: - Continuous State Display

    private var continuousStateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Continuous")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(classifier.continuousStates.sorted(by: { $0.key < $1.key }), id: \.key) { name, state in
                HStack(spacing: 8) {
                    Text(name)
                        .font(.caption.monospaced())
                        .frame(width: 80, alignment: .trailing)
                    Text(state.isActive ? "ACTIVE" : "idle")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(state.isActive ? Color.green : Color.gray.opacity(0.3))
                        .foregroundColor(state.isActive ? .black : .secondary)
                        .clipShape(Capsule())
                    if state.isActive {
                        ProgressView(value: Double(state.intensity))
                            .tint(.green)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Posture State Display

    private var postureStateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Posture")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(classifier.postureStates.sorted(by: { $0.key < $1.key }), id: \.key) { name, isActive in
                    Text("\(name): \(isActive ? "ON" : "off")")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isActive ? Color.orange : Color.gray.opacity(0.3))
                        .foregroundColor(isActive ? .black : .secondary)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Latency Display

    private var latencySection: some View {
        HStack(spacing: 16) {
            latencyPill("D", ms: classifier.discreteLatencyMs)
            latencyPill("C", ms: classifier.continuousLatencyMs)
            latencyPill("P", ms: classifier.postureLatencyMs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func latencyPill(_ label: String, ms: Double) -> some View {
        let color: Color = ms < 5 ? .green : ms < 15 ? .yellow : .red
        return HStack(spacing: 4) {
            Text(label)
                .font(.caption2.bold())
            Text(String(format: "%.1fms", ms))
                .font(.caption2.monospaced())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
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
            previousContinuousActive.removeAll()
            previousPostureActive.removeAll()
            if isLogging {
                toggleLogging()
            }
        } else {
            classifier.loadTemplates(from: gestureLibrary)
            hapticImpact.prepare()

            oscSender.connect()
            sensorManager.startStreaming { sample in
                Task { @MainActor in
                    oscSender.sendIMU(sample)
                    classifier.processSample(sample)

                    var triggeredGesture: String?

                    // Discrete gesture triggers with per-gesture thresholds
                    for (name, prob) in classifier.predictions where prob > 0.3 {
                        oscSender.sendGestureEvent(name: name, probability: prob)
                        let threshold = classifier.triggerThreshold(for: name)
                        if prob > threshold && classifier.shouldTrigger(gestureName: name) {
                            oscSender.sendGestureTrigger(name: name)
                            hapticImpact.impactOccurred()
                            recentGestures.append((name: name, time: .now))
                            triggeredGesture = name
                            if recentGestures.count > 20 {
                                recentGestures.removeFirst()
                            }
                        }
                    }

                    // Continuous gesture OSC output
                    if !classifier.continuousStates.isEmpty {
                        let currentContinuousActive = Set(classifier.continuousStates.filter { $0.value.isActive }.map(\.key))
                        for (name, state) in classifier.continuousStates {
                            let wasActive = previousContinuousActive.contains(name)
                            if state.isActive != wasActive {
                                oscSender.sendGestureState(name: name, isActive: state.isActive)
                            }
                            if state.isActive {
                                oscSender.sendGestureIntensity(name: name, intensity: state.intensity)
                            }
                        }
                        previousContinuousActive = currentContinuousActive
                    }

                    // Posture gesture OSC output
                    if !classifier.postureStates.isEmpty {
                        let currentPostureActive = Set(classifier.postureStates.filter { $0.value }.map(\.key))
                        for (name, isActive) in classifier.postureStates {
                            let wasActive = previousPostureActive.contains(name)
                            if isActive != wasActive {
                                oscSender.sendGestureState(name: name, isActive: isActive)
                            }
                        }
                        previousPostureActive = currentPostureActive
                    }

                    if isLogging {
                        await PerformanceLogger.shared.log(
                            sample: sample,
                            probabilities: classifier.predictions,
                            triggeredGesture: triggeredGesture,
                            continuousStates: classifier.continuousStates,
                            postureStates: classifier.postureStates,
                            latencyMs: classifier.discreteLatencyMs
                        )
                    }
                }
            }
        }
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
}
