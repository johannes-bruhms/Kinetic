import Foundation
@preconcurrency import CoreML
#if !targetEnvironment(simulator)
import CreateML
import TabularData
#endif
import Combine

@MainActor
final class GestureClassifier: ObservableObject {
    @Published var predictions: [String: Float] = [:]
    @Published var isModelLoaded = false
    @Published var isTraining = false

    /// On-device trained model (Random Forest from user's gesture recordings).
    private var onDeviceModel: MLModel?
    /// Externally provided Core ML model (e.g. a pre-trained neural network).
    private var externalModel: MLModel?
    /// DTW fallback for when only one gesture class exists or model training fails.
    private let dtwClassifier = DTWClassifier()

    private let inferenceQueue = DispatchQueue(label: "com.kinetic.inference", qos: .userInteractive)
    #if !targetEnvironment(simulator)
    private let trainingQueue = DispatchQueue(label: "com.kinetic.training", qos: .userInitiated)
    #endif

    // Sliding window for real-time classification
    private var sampleWindow: [MotionSample] = []
    private let windowSize = 50 // ~0.5s at 100Hz
    private let strideSize = 10
    private var samplesSinceLastPrediction = 0

    /// Whether the classifier has any recognition capability.
    var isReady: Bool {
        onDeviceModel != nil || externalModel != nil || dtwClassifier.hasTemplates
    }

    // MARK: - Model Loading

    /// Load an externally trained Core ML model (expects raw time-series input).
    func loadCoreMLModel(at url: URL) async throws {
        let compiled = try await MLModel.compileModel(at: url)
        externalModel = try MLModel(contentsOf: compiled)
        isModelLoaded = true
    }

    /// Load DTW templates and train an on-device Core ML model from the
    /// gesture library's saved recordings.
    func loadTemplates(from library: GestureLibrary) {
        // Always load DTW templates as fallback
        dtwClassifier.clearTemplates()
        for gesture in library.gestures {
            let recordings = library.loadRecordings(for: gesture.id)
            for recording in recordings {
                dtwClassifier.addTemplate(name: gesture.name, samples: recording.samples)
            }
        }

        // Attempt on-device model training (needs ≥2 classes, device only)
        #if !targetEnvironment(simulator)
        trainOnDeviceModel(from: library)
        #endif

        isModelLoaded = isReady
    }

    // MARK: - On-Device Training

    #if !targetEnvironment(simulator)
    /// Train an MLRandomForestClassifier on the user's recorded gesture data.
    /// Runs on a background queue; DTW handles inference until the model is ready.
    private func trainOnDeviceModel(from library: GestureLibrary) {
        let gesturesWithSamples = library.gestures.filter { $0.sampleCount > 0 }
        guard gesturesWithSamples.count >= 2 else {
            onDeviceModel = nil
            return
        }

        var allFeatures: [[String: Double]] = []
        var allLabels: [String] = []

        for gesture in gesturesWithSamples {
            let recordings = library.loadRecordings(for: gesture.id)
            for recording in recordings {
                // Original recording
                let features = FeatureExtractor.extract(from: recording.samples)
                allFeatures.append(features)
                allLabels.append(gesture.name)

                // Augmented variants (8 per recording) — jitter, scale, time-stretch
                let augmented = FeatureExtractor.extractAugmented(from: recording.samples, count: 8)
                for aug in augmented {
                    allFeatures.append(aug)
                    allLabels.append(gesture.name)
                }
            }
        }

        guard allFeatures.count >= 4 else {
            onDeviceModel = nil
            return
        }

        isTraining = true

        let featureNames = FeatureExtractor.featureNames
        let features = allFeatures
        let labels = allLabels

        trainingQueue.async { [weak self] in
            do {
                var dataFrame = DataFrame()
                for name in featureNames {
                    let values = features.map { $0[name] ?? 0.0 }
                    dataFrame.append(column: Column<Double>(name: name, contents: values))
                }
                dataFrame.append(column: Column<String>(name: "label", contents: labels))

                let classifier = try MLRandomForestClassifier(
                    trainingData: dataFrame,
                    targetColumn: "label"
                )

                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("kinetic_gesture_model.mlmodel")
                try classifier.write(to: tempURL)
                let compiledURL = try MLModel.compileModel(at: tempURL)
                let model = try MLModel(contentsOf: compiledURL)

                try? FileManager.default.removeItem(at: tempURL)

                Task { @MainActor [weak self] in
                    self?.onDeviceModel = model
                    self?.isModelLoaded = true
                    self?.isTraining = false
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.onDeviceModel = nil
                    self?.isTraining = false
                }
            }
        }
    }
    #endif

    // MARK: - Real-Time Processing

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

    /// Minimum mean energy in a window to trigger classification.
    /// Prevents the Random Forest from confidently classifying idle movement.
    private let energyGateThreshold = 0.4

    private func classify(window: [MotionSample]) {
        // Energy gate: reject windows with insufficient motion
        let meanEnergy = window.reduce(0.0) { sum, s in
            sum + s.userAcceleration.magnitude + s.rotationRate.magnitude
        } / Double(window.count)

        guard meanEnergy > energyGateThreshold else {
            if !predictions.isEmpty {
                predictions.removeAll()
            }
            return
        }

        if let model = onDeviceModel {
            classifyWithOnDeviceModel(model: model, window: window)
        } else if let model = externalModel {
            classifyWithExternalModel(model: model, window: window)
        } else if dtwClassifier.hasTemplates {
            classifyWithDTW(window: window)
        }
    }

    /// Classify using the on-device trained Random Forest model.
    private func classifyWithOnDeviceModel(model: MLModel, window: [MotionSample]) {
        let windowCopy = window
        inferenceQueue.async { [weak self] in
            let features = FeatureExtractor.extract(from: windowCopy)
            var mlFeatures: [String: MLFeatureValue] = [:]
            for (key, value) in features {
                mlFeatures[key] = MLFeatureValue(double: value)
            }

            do {
                let input = try MLDictionaryFeatureProvider(dictionary: mlFeatures)
                let prediction = try model.prediction(from: input)

                var probs: [String: Float] = [:]
                if let probsFeature = prediction.featureValue(for: "labelProbability"),
                   let probsDict = probsFeature.dictionaryValue as? [String: NSNumber] {
                    for (key, value) in probsDict {
                        probs[key] = value.floatValue
                    }
                } else if let labelFeature = prediction.featureValue(for: "label") {
                    probs[labelFeature.stringValue] = 1.0
                }

                let result = probs
                Task { @MainActor [weak self] in
                    self?.predictions = result
                }
            } catch {
                // On-device model failed — fall back to DTW inline
                guard let self else { return }
                let classifier = self.dtwClassifier
                let thresh = classifier.threshold
                let results = classifier.classify(window: windowCopy)
                var probs: [String: Float] = [:]
                for result in results {
                    let prob = Float(max(0, 1.0 - result.distance / thresh))
                    if let existing = probs[result.name] {
                        probs[result.name] = max(existing, prob)
                    } else {
                        probs[result.name] = prob
                    }
                }
                let fallback = probs
                Task { @MainActor in
                    self.predictions = fallback
                }
            }
        }
    }

    /// Classify using an externally provided Core ML model (raw time-series input).
    private func classifyWithExternalModel(model: MLModel, window: [MotionSample]) {
        let ws = windowSize
        guard let input = Self.buildTimeSeriesInput(from: window, windowSize: ws) else { return }

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

    /// Classify using DTW distance matching (fallback).
    private func classifyWithDTW(window: [MotionSample]) {
        let classifier = dtwClassifier
        let thresh = classifier.threshold
        inferenceQueue.async { [weak self] in
            let results = classifier.classify(window: window)

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

    // MARK: - External Model Input

    nonisolated private static func buildTimeSeriesInput(from window: [MotionSample], windowSize: Int) -> MLFeatureProvider? {
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
