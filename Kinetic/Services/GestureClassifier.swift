import Foundation
@preconcurrency import CoreML
import Combine

@MainActor
final class GestureClassifier: ObservableObject {
    @Published var predictions: [String: Float] = [:]
    @Published var isModelLoaded = false

    private var coreMLModel: MLModel?
    private let dtwClassifier = DTWClassifier()
    private let inferenceQueue = DispatchQueue(label: "com.kinetic.inference", qos: .userInteractive)

    // Sliding window of recent samples for classification
    private var sampleWindow: [MotionSample] = []
    private let windowSize = 50 // ~0.5s at 100Hz
    private let strideSize = 10

    private var samplesSinceLastPrediction = 0

    /// Whether the classifier has any recognition capability (Core ML model or DTW templates).
    var isReady: Bool {
        coreMLModel != nil || dtwClassifier.hasTemplates
    }

    // MARK: - Model Loading

    func loadCoreMLModel(at url: URL) async throws {
        let compiled = try await MLModel.compileModel(at: url)
        coreMLModel = try MLModel(contentsOf: compiled)
        isModelLoaded = true
    }

    /// Load DTW templates from saved recordings in the gesture library.
    func loadTemplates(from library: GestureLibrary) {
        dtwClassifier.clearTemplates()
        for gesture in library.gestures {
            let recordings = library.loadRecordings(for: gesture.id)
            for recording in recordings {
                dtwClassifier.addTemplate(name: gesture.name, samples: recording.samples)
            }
        }
        isModelLoaded = dtwClassifier.hasTemplates
    }

    // MARK: - Processing

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
        // Prefer Core ML if available, otherwise use DTW
        if let model = coreMLModel {
            classifyWithCoreML(model: model, window: window)
        } else if dtwClassifier.hasTemplates {
            classifyWithDTW(window: window)
        }
    }

    private func classifyWithCoreML(model: MLModel, window: [MotionSample]) {
        let ws = windowSize
        guard let input = Self.buildInput(from: window, windowSize: ws) else { return }

        inferenceQueue.async { [weak self] in
            do {
                let prediction = try model.prediction(from: input)
                if let labelFeature = prediction.featureValue(for: "label") {
                    let label = labelFeature.stringValue

                    var probs: [String: Float] = [:]
                    if let probsFeature = prediction.featureValue(for: "labelProbability"),
                       let probsDict = probsFeature.dictionaryValue as? [String: NSNumber] {
                        for (key, value) in probsDict {
                            probs[key] = value.floatValue
                        }
                    } else {
                        probs[label] = 1.0
                    }

                    let result = probs
                    Task { @MainActor [weak self] in
                        self?.predictions = result
                    }
                }
            } catch {
                // Classification failed silently — don't interrupt performance
            }
        }
    }

    private func classifyWithDTW(window: [MotionSample]) {
        let classifier = dtwClassifier
        let thresh = classifier.threshold
        inferenceQueue.async { [weak self] in
            let results = classifier.classify(window: window)

            // Convert DTW distances to pseudo-probabilities
            var probs: [String: Float] = [:]
            for result in results {
                let prob = Float(max(0, 1.0 - result.distance / thresh))
                if let existing = probs[result.name] {
                    probs[result.name] = max(existing, prob)
                } else {
                    probs[result.name] = prob
                }
            }

            let result = probs
            Task { @MainActor [weak self] in
                self?.predictions = result
            }
        }
    }

    /// Build Core ML input array. Nonisolated so it can be called from background queues.
    nonisolated private static func buildInput(from window: [MotionSample], windowSize: Int) -> MLFeatureProvider? {
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
