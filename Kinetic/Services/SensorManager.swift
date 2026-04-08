import Foundation
import CoreMotion
import Combine

@MainActor
final class SensorManager: ObservableObject {
    @Published var isStreaming = false
    @Published var latestSample: MotionSample?
    @Published var sampleRate: Int = 100
    @Published var isCalibrated = false

    private let motionManager = CMMotionManager()
    private let sensorQueue = OperationQueue()
    private var onSample: ((MotionSample) -> Void)?

    // Reference attitude for calibration (zeroing)
    private var referenceAttitude: CMAttitude?

    init() {
        sensorQueue.name = "com.kinetic.sensor"
        sensorQueue.qualityOfService = .userInteractive
    }

    /// Capture the current attitude as the zero reference point.
    /// Must be called while streaming.
    func calibrate() {
        guard let latest = motionManager.deviceMotion else { return }
        referenceAttitude = latest.attitude.copy() as? CMAttitude
        isCalibrated = true
    }

    /// Clear calibration, return to absolute reference frame.
    func clearCalibration() {
        referenceAttitude = nil
        isCalibrated = false
    }

    func startStreaming(onSample: @escaping (MotionSample) -> Void) {
        guard motionManager.isDeviceMotionAvailable else { return }
        self.onSample = onSample

        let interval = 1.0 / Double(sampleRate)
        motionManager.deviceMotionUpdateInterval = interval
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: sensorQueue) { [weak self] motion, error in
            guard let motion, error == nil else { return }

            // Apply reference attitude if calibrated
            if let ref = self?.referenceAttitude {
                motion.attitude.multiply(byInverseOf: ref)
            }

            let sample = MotionSample(
                timestamp: motion.timestamp,
                attitude: Quaternion(
                    x: motion.attitude.quaternion.x,
                    y: motion.attitude.quaternion.y,
                    z: motion.attitude.quaternion.z,
                    w: motion.attitude.quaternion.w
                ),
                rotationRate: Vector3(
                    x: motion.rotationRate.x,
                    y: motion.rotationRate.y,
                    z: motion.rotationRate.z
                ),
                userAcceleration: Vector3(
                    x: motion.userAcceleration.x,
                    y: motion.userAcceleration.y,
                    z: motion.userAcceleration.z
                ),
                gravity: Vector3(
                    x: motion.gravity.x,
                    y: motion.gravity.y,
                    z: motion.gravity.z
                )
            )

            onSample(sample)

            Task { @MainActor [weak self] in
                self?.latestSample = sample
            }
        }

        isStreaming = true
    }

    func stopStreaming() {
        motionManager.stopDeviceMotionUpdates()
        onSample = nil
        isStreaming = false
    }
}
