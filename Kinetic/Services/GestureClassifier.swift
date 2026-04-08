import Foundation
@preconcurrency import CoreML
#if !targetEnvironment(simulator)
import CreateML
import TabularData
#endif
import Combine

@MainActor
final class GestureClassifier: ObservableObject {
    // Discrete layer output
    @Published var predictions: [String: Float] = [:]
    // Continuous layer output
    @Published var continuousStates: [String: ContinuousGestureState] = [:]
    // Posture layer output
    @Published var postureStates: [String: Bool] = [:]

    @Published var isModelLoaded = false
    @Published var isTraining = false

    // Latency measurement (ms)
    @Published var discreteLatencyMs: Double = 0
    @Published var continuousLatencyMs: Double = 0
    @Published var postureLatencyMs: Double = 0

    /// On-device trained model (Random Forest from user's gesture recordings).
    private var onDeviceModel: MLModel?
    /// Externally provided Core ML model (e.g. a pre-trained neural network).
    private var externalModel: MLModel?
    /// DTW fallback for when only one gesture class exists or model training fails.
    private let dtwClassifier = DTWClassifier()
    /// Continuous gesture classifier (frequency-domain matching).
    private let continuousClassifier = ContinuousClassifier()
    /// Posture classifier (gravity vector matching).
    private let postureClassifier = PostureClassifier()

    private let inferenceQueue = DispatchQueue(label: "com.kinetic.inference", qos: .userInteractive)
    #if !targetEnvironment(simulator)
    private let trainingQueue = DispatchQueue(label: "com.kinetic.training", qos: .userInitiated)
    #endif

    // Three-layer sliding windows
    private var discreteBuffer: [MotionSample] = []
    private let discreteWindowSize = 50 // ~0.5s at 100Hz
    private var continuousBuffer: [MotionSample] = []
    private let continuousWindowSize = 150 // ~1.5s at 100Hz
    private var postureBuffer: [MotionSample] = []
    private let postureWindowSize = 50 // ~0.5s at 100Hz

    // Classification cadence
    private let discreteStride = 10
    private let continuousStride = 25
    private let postureStride = 50
    private var samplesSinceDiscrete = 0
    private var samplesSinceContinuous = 0
    private var samplesSincePosture = 0

    // Debounce: per-gesture cooldown for discrete triggers
    private var lastTriggerTimes: [String: Date] = [:]
    private var gestureCooldowns: [String: TimeInterval] = [:]

    // Per-gesture sensitivity: trigger thresholds for discrete gestures
    private var discreteTriggerThresholds: [String: Float] = [:]
    private var dtwDistanceThresholds: [String: Double] = [:]

    /// Whether the classifier has any recognition capability.
    var isReady: Bool {
        onDeviceModel != nil || externalModel != nil || dtwClassifier.hasTemplates ||
        continuousClassifier.hasTemplates || postureClassifier.hasTemplates
    }

    // MARK: - Model Loading

    /// Load an externally trained Core ML model (expects raw time-series input).
    func loadCoreMLModel(at url: URL) async throws {
        let compiled = try await MLModel.compileModel(at: url)
        externalModel = try MLModel(contentsOf: compiled)
        isModelLoaded = true
    }

    /// Load templates from the gesture library, routing by gesture type.
    func loadTemplates(from library: GestureLibrary) {
        dtwClassifier.clearTemplates()
        continuousClassifier.clearTemplates()
        postureClassifier.clearTemplates()
        lastTriggerTimes.removeAll()
        gestureCooldowns.removeAll()
        discreteTriggerThresholds.removeAll()
        dtwDistanceThresholds.removeAll()

        for gesture in library.gestures {
            let recordings = library.loadRecordings(for: gesture.id)

            switch gesture.gestureType {
            case .discrete:
                gestureCooldowns[gesture.name] = gesture.cooldownDuration
                discreteTriggerThresholds[gesture.name] = gesture.discreteTriggerThreshold
                dtwDistanceThresholds[gesture.name] = gesture.dtwDistanceThreshold
                for recording in recordings {
                    dtwClassifier.addTemplate(name: gesture.name, samples: recording.samples)
                }

            case .continuous:
                // Extract profiles from recordings and average them
                var profiles: [ContinuousGestureProfile] = []
                for recording in recordings {
                    if let profile = recording.extractedProfile {
                        profiles.append(profile)
                    } else if recording.samples.count >= 50 {
                        profiles.append(FrequencyAnalyzer.extractProfile(from: recording.samples))
                    }
                }
                if let avgProfile = FrequencyAnalyzer.averageProfiles(profiles) {
                    continuousClassifier.addTemplate(
                        name: gesture.name,
                        profile: avgProfile,
                        matchThreshold: gesture.continuousMatchThreshold
                    )
                }

            case .posture:
                for recording in recordings {
                    if let postureVec = recording.postureVector {
                        postureClassifier.addTemplate(
                            name: gesture.name,
                            gravityVector: postureVec,
                            toleranceAngle: gesture.postureToleranceAngle
                        )
                        break // Only need one template per posture
                    } else if !recording.samples.isEmpty {
                        // Extract average gravity from samples
                        let avgGravity = averageGravity(from: recording.samples)
                        postureClassifier.addTemplate(
                            name: gesture.name,
                            gravityVector: avgGravity,
                            toleranceAngle: gesture.postureToleranceAngle
                        )
                        break
                    }
                }
            }
        }

        // Attempt on-device model training for discrete gestures
        #if !targetEnvironment(simulator)
        trainOnDeviceModel(from: library)
        #endif

        isModelLoaded = isReady
    }

    private func averageGravity(from samples: [MotionSample]) -> Vector3 {
        Vector3.average(samples.map(\.gravity))
    }

    // MARK: - On-Device Training

    #if !targetEnvironment(simulator)
    private func trainOnDeviceModel(from library: GestureLibrary) {
        let discreteGestures = library.gestures.filter { $0.gestureType == .discrete && $0.sampleCount > 0 }
        guard discreteGestures.count >= 2 else {
            onDeviceModel = nil
            return
        }

        var allFeatures: [[String: Double]] = []
        var allLabels: [String] = []

        for gesture in discreteGestures {
            let recordings = library.loadRecordings(for: gesture.id)
            for recording in recordings {
                let features = FeatureExtractor.extract(from: recording.samples)
                allFeatures.append(features)
                allLabels.append(gesture.name)

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
        // Push to all three buffers
        discreteBuffer.append(sample)
        if discreteBuffer.count > discreteWindowSize {
            discreteBuffer.removeFirst()
        }

        continuousBuffer.append(sample)
        if continuousBuffer.count > continuousWindowSize {
            continuousBuffer.removeFirst()
        }

        postureBuffer.append(sample)
        if postureBuffer.count > postureWindowSize {
            postureBuffer.removeFirst()
        }

        // Discrete layer
        samplesSinceDiscrete += 1
        if discreteBuffer.count == discreteWindowSize && samplesSinceDiscrete >= discreteStride {
            samplesSinceDiscrete = 0
            classifyDiscrete(window: discreteBuffer)
        }

        // Continuous layer
        samplesSinceContinuous += 1
        if continuousBuffer.count >= 50 && samplesSinceContinuous >= continuousStride {
            samplesSinceContinuous = 0
            classifyContinuous(buffer: continuousBuffer)
        }

        // Posture layer
        samplesSincePosture += 1
        if postureBuffer.count == postureWindowSize && samplesSincePosture >= postureStride {
            samplesSincePosture = 0
            classifyPosture(buffer: postureBuffer)
        }
    }

    func reset() {
        discreteBuffer.removeAll()
        continuousBuffer.removeAll()
        postureBuffer.removeAll()
        predictions.removeAll()
        continuousStates.removeAll()
        postureStates.removeAll()
        samplesSinceDiscrete = 0
        samplesSinceContinuous = 0
        samplesSincePosture = 0
    }

    // MARK: - Debounce & Sensitivity

    /// Check if a discrete gesture trigger should be suppressed by cooldown.
    func shouldTrigger(gestureName: String) -> Bool {
        let cooldown = gestureCooldowns[gestureName] ?? 0.5
        if let lastTime = lastTriggerTimes[gestureName] {
            if Date.now.timeIntervalSince(lastTime) < cooldown {
                return false
            }
        }
        lastTriggerTimes[gestureName] = .now
        return true
    }

    /// Per-gesture trigger threshold (probability above which to fire).
    func triggerThreshold(for gestureName: String) -> Float {
        discreteTriggerThresholds[gestureName] ?? 0.85
    }

    // MARK: - Discrete Classification

    private let energyGateThreshold = 0.2

    private func classifyDiscrete(window: [MotionSample]) {
        let meanEnergy = window.reduce(0.0) { sum, s in
            sum + s.userAcceleration.magnitude + s.rotationRate.magnitude
        } / Double(window.count)

        guard meanEnergy > energyGateThreshold else {
            if !predictions.isEmpty {
                predictions.removeAll()
            }
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        if let model = onDeviceModel {
            classifyWithOnDeviceModel(model: model, window: window, startTime: startTime)
        } else if let model = externalModel {
            classifyWithExternalModel(model: model, window: window, startTime: startTime)
        } else if dtwClassifier.hasTemplates {
            classifyWithDTW(window: window, startTime: startTime)
        }
    }

    /// Convert DTW distance to probability using per-gesture distance threshold.
    /// Returns a closure that can be called from the inference queue.
    private func makeDtwProbabilityFn() -> @Sendable (String, Double) -> Float {
        let thresholds = dtwDistanceThresholds
        return { name, distance in
            let thresh = thresholds[name] ?? 4.0
            return Float(max(0, 1.0 - distance / thresh))
        }
    }

    private func classifyWithOnDeviceModel(model: MLModel, window: [MotionSample], startTime: CFAbsoluteTime) {
        let windowCopy = window
        let dtwProb = makeDtwProbabilityFn()
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
                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                Task { @MainActor [weak self] in
                    self?.predictions = result
                    self?.discreteLatencyMs = latency
                }
            } catch {
                guard let self else { return }
                let classifier = self.dtwClassifier
                let results = classifier.classify(window: windowCopy)
                var probs: [String: Float] = [:]
                for result in results {
                    let prob = dtwProb(result.name, result.distance)
                    if let existing = probs[result.name] {
                        probs[result.name] = max(existing, prob)
                    } else {
                        probs[result.name] = prob
                    }
                }
                let fallback = probs
                let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                Task { @MainActor in
                    self.predictions = fallback
                    self.discreteLatencyMs = latency
                }
            }
        }
    }

    private func classifyWithExternalModel(model: MLModel, window: [MotionSample], startTime: CFAbsoluteTime) {
        let ws = discreteWindowSize
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
                    let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
                    Task { @MainActor [weak self] in
                        self?.predictions = result
                        self?.discreteLatencyMs = latency
                    }
                }
            } catch {
                // Classification failed silently
            }
        }
    }

    private func classifyWithDTW(window: [MotionSample], startTime: CFAbsoluteTime) {
        let classifier = dtwClassifier
        let dtwProb = makeDtwProbabilityFn()
        inferenceQueue.async { [weak self] in
            let results = classifier.classify(window: window)

            var probs: [String: Float] = [:]
            for result in results {
                let prob = dtwProb(result.name, result.distance)
                if let existing = probs[result.name] {
                    probs[result.name] = max(existing, prob)
                } else {
                    probs[result.name] = prob
                }
            }

            let result = probs
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            Task { @MainActor [weak self] in
                self?.predictions = result
                self?.discreteLatencyMs = latency
            }
        }
    }

    // MARK: - Continuous Classification

    private func classifyContinuous(buffer: [MotionSample]) {
        guard continuousClassifier.hasTemplates else { return }
        let bufferCopy = buffer
        let timestamp = buffer.last?.timestamp ?? 0
        let startTime = CFAbsoluteTimeGetCurrent()

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            let states = self.continuousClassifier.classify(samples: bufferCopy, timestamp: timestamp)
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            Task { @MainActor [weak self] in
                self?.continuousStates = states
                self?.continuousLatencyMs = latency
            }
        }
    }

    // MARK: - Posture Classification

    private func classifyPosture(buffer: [MotionSample]) {
        guard postureClassifier.hasTemplates else { return }
        let gravity = buffer.last!.gravity
        let timestamp = buffer.last!.timestamp
        let startTime = CFAbsoluteTimeGetCurrent()

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            let states = self.postureClassifier.classify(gravity: gravity, timestamp: timestamp)
            let latency = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            Task { @MainActor [weak self] in
                self?.postureStates = states
                self?.postureLatencyMs = latency
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
