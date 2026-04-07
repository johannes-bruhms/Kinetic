import Foundation
import CoreML

@MainActor
final class GestureClassifier: ObservableObject {
    @Published var predictions: [String: Float] = [:]
    @Published var isModelLoaded = false

    private var model: MLModel?
    private let inferenceQueue = DispatchQueue(label: "com.kinetic.inference", qos: .userInteractive)

    // Sliding window of recent samples for classification
    private var sampleWindow: [MotionSample] = []
    private let windowSize = 50 // ~0.5s at 100Hz
    private let strideSize = 10

    private var samplesSinceLastPrediction = 0

    func loadModel(at url: URL) async throws {
        let compiled = try await MLModel.compileModel(at: url)
        model = try MLModel(contentsOf: compiled)
        isModelLoaded = true
    }

    func processSample(_ sample: MotionSample) {
        sampleWindow.append(sample)
        if sampleWindow.count > windowSize {
            sampleWindow.removeFirst()
        }

        samplesSinceLastPrediction += 1

        if sampleWindow.count == windowSize && samplesSinceLastPrediction >= strideSize {
            samplesSinceLastPrediction = 0
            classify(window: sampleWindow)
        }
    }

    func reset() {
        sampleWindow.removeAll()
        predictions.removeAll()
        samplesSinceLastPrediction = 0
    }

    // MARK: - Classification

    private func classify(window: [MotionSample]) {
        guard let model else { return }

        inferenceQueue.async { [weak self] in
            guard let self else { return }

            // Build MLMultiArray input from window
            guard let input = self.buildInput(from: window) else { return }

            do {
                let prediction = try model.prediction(from: input)
                // Extract label and probabilities from prediction output
                if let labelFeature = prediction.featureValue(for: "label"),
                   let label = labelFeature.stringValue {

                    var probs: [String: Float] = [:]
                    if let probsFeature = prediction.featureValue(for: "labelProbability"),
                       let probsDict = probsFeature.dictionaryValue as? [String: NSNumber] {
                        for (key, value) in probsDict {
                            probs[key] = value.floatValue
                        }
                    } else {
                        probs[label] = 1.0
                    }

                    Task { @MainActor [weak self] in
                        self?.predictions = probs
                    }
                }
            } catch {
                // Classification failed silently — don't interrupt performance
            }
        }
    }

    private func buildInput(from window: [MotionSample]) -> MLFeatureProvider? {
        // 6 features: accel (x,y,z) + rotation rate (x,y,z)
        let featureCount = 6
        guard let array = try? MLMultiArray(shape: [NSNumber(value: windowSize), NSNumber(value: featureCount)], dataType: .float32) else {
            return nil
        }

        for (i, sample) in window.enumerated() {
            array[[NSNumber(value: i), 0]] = NSNumber(value: sample.userAcceleration.x)
            array[[NSNumber(value: i), 1]] = NSNumber(value: sample.userAcceleration.y)
            array[[NSNumber(value: i), 2]] = NSNumber(value: sample.userAcceleration.z)
            array[[NSNumber(value: i), 3]] = NSNumber(value: sample.rotationRate.x)
            array[[NSNumber(value: i), 4]] = NSNumber(value: sample.rotationRate.y)
            array[[NSNumber(value: i), 5]] = NSNumber(value: sample.rotationRate.z)
        }

        let provider = try? MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: array)])
        return provider
    }
}
