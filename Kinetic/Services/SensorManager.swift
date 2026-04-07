import Foundation
import CoreMotion
import Combine

@MainActor
final class SensorManager: ObservableObject {
    @Published var isStreaming = false
    @Published var latestSample: MotionSample?
    @Published var sampleRate: Int = 100

    private let motionManager = CMMotionManager()
    private let sensorQueue = OperationQueue()
    private var onSample: ((MotionSample) -> Void)?

    init() {
        sensorQueue.name = "com.kinetic.sensor"
        sensorQueue.qualityOfService = .userInteractive
    }

    func startStreaming(onSample: @escaping (MotionSample) -> Void) {
        guard motionManager.isDeviceMotionAvailable else { return }
        self.onSample = onSample

        let interval = 1.0 / Double(sampleRate)
        motionManager.deviceMotionUpdateInterval = interval
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: sensorQueue) { [weak self] motion, error in
            guard let motion, error == nil else { return }

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
