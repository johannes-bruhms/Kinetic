import SwiftUI

struct TestModeView: View {
    @EnvironmentObject var sensorManager: SensorManager
    @EnvironmentObject var oscSender: OSCSender
    @StateObject private var classifier = GestureClassifier()

    @State private var audioClickEnabled = false
    @State private var lastDetected: String?

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
            } else {
                ContentUnavailableView("No Model Loaded", systemImage: "waveform.badge.exclamationmark", description: Text("Train gestures first"))
            }

            if let detected = lastDetected {
                Text(detected)
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            Toggle("Audio Click on Detection", isOn: $audioClickEnabled)
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
    }

    private func toggleTest() {
        if sensorManager.isStreaming {
            sensorManager.stopStreaming()
            classifier.reset()
        } else {
            sensorManager.startStreaming { sample in
                classifier.processSample(sample)

                for (name, prob) in classifier.predictions where prob > 0.9 {
                    lastDetected = name
                    if audioClickEnabled {
                        // System haptic as feedback
                        // AudioServicesPlaySystemSound(1104)
                    }
                }
            }
        }
    }
}
