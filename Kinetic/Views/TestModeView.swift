import SwiftUI
import UIKit

struct TestModeView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var oscSender: OSCSender
    @EnvironmentObject var gestureLibrary: GestureLibrary
    @StateObject private var classifier = GestureClassifier()

    @State private var hapticEnabled = true
    @State private var lastDetected: String?

    private let haptic = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        VStack(spacing: 24) {
            Text("Test Mode")
                .font(.largeTitle.bold())

            // Large probability bars
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

            if let detected = lastDetected {
                Text(detected)
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            Toggle("Haptic Feedback", isOn: $hapticEnabled)
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
    }

    private func toggleTest() {
        if sensorManager.isStreaming {
            sensorManager.stopStreaming()
            classifier.reset()
        } else {
            classifier.loadTemplates(from: gestureLibrary)
            haptic.prepare()

            sensorManager.startStreaming { sample in
                Task { @MainActor in
                    classifier.processSample(sample)

                    for (name, prob) in classifier.predictions where prob > 0.9 {
                        lastDetected = name
                        if hapticEnabled {
                            haptic.impactOccurred()
                        }
                    }
                }
            }
        }
    }
}
