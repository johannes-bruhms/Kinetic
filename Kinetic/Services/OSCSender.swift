import Foundation
import Network
import Combine

@MainActor
final class OSCSender: ObservableObject {
    @Published var configuration: OSCConfiguration = .default
    @Published var isConnected = false

    private var connection: NWConnection?
    private let sendQueue = DispatchQueue(label: "com.kinetic.osc", qos: .userInteractive)

    func connect() {
        let host = NWEndpoint.Host(configuration.host)
        let port = NWEndpoint.Port(rawValue: configuration.port)!
        connection = NWConnection(host: host, port: port, using: .udp)

        connection?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                switch state {
                case .ready:
                    self?.isConnected = true
                case .failed, .cancelled:
                    self?.isConnected = false
                default:
                    break
                }
            }
        }

        connection?.start(queue: sendQueue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    func sendIMU(_ sample: MotionSample) {
        let prefix = configuration.prefix
        guard let connection = self.connection else { return }

        sendQueue.async {
            self.performSend(connection: connection, address: "\(prefix)imu/attitude/quat",
                           values: [sample.attitude.x, sample.attitude.y, sample.attitude.z, sample.attitude.w])
            self.performSend(connection: connection, address: "\(prefix)imu/rotation/rate",
                           values: [sample.rotationRate.x, sample.rotationRate.y, sample.rotationRate.z])
            self.performSend(connection: connection, address: "\(prefix)imu/accel/user",
                           values: [sample.userAcceleration.x, sample.userAcceleration.y, sample.userAcceleration.z])
            self.performSend(connection: connection, address: "\(prefix)imu/gravity",
                           values: [sample.gravity.x, sample.gravity.y, sample.gravity.z])
        }
    }

    func sendGestureEvent(name: String, probability: Float) {
        let prefix = configuration.prefix
        guard let connection = self.connection else { return }

        sendQueue.async {
            self.performSend(connection: connection, address: "\(prefix)gesture/\(name)", values: [Double(probability)])
        }
    }

    func sendGestureTrigger(name: String, velocity: Int = 127) {
        let prefix = configuration.prefix
        guard let connection = self.connection else { return }

        sendQueue.async {
            self.performSend(connection: connection, address: "\(prefix)gesture/\(name)/trigger", values: [Double(velocity)])
        }
    }

    /// Send continuous/posture gesture state transition (0 or 1).
    func sendGestureState(name: String, isActive: Bool) {
        let prefix = configuration.prefix
        guard let connection = self.connection else { return }

        sendQueue.async {
            self.performSendInt(connection: connection, address: "\(prefix)gesture/\(name)/state", value: isActive ? 1 : 0)
        }
    }

    /// Send continuous gesture intensity (0.0–1.0), sent while active.
    func sendGestureIntensity(name: String, intensity: Float) {
        let prefix = configuration.prefix
        guard let connection = self.connection else { return }

        sendQueue.async {
            self.performSend(connection: connection, address: "\(prefix)gesture/\(name)/intensity", values: [Double(intensity)])
        }
    }

    // MARK: - OSC Encoding

    nonisolated private func performSend(connection: NWConnection, address: String, values: [Double]) {
        let data = encodeOSCMessage(address: address, floats: values.map { Float($0) })
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    nonisolated private func performSendInt(connection: NWConnection, address: String, value: Int32) {
        let data = encodeOSCMessageInt(address: address, value: value)
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    nonisolated private func encodeOSCMessage(address: String, floats: [Float]) -> Data {
        var data = Data()

        // Address pattern (null-terminated, padded to 4-byte boundary)
        data.append(oscString(address))

        // Type tag string
        let typeTag = "," + String(repeating: "f", count: floats.count)
        data.append(oscString(typeTag))

        // Float arguments (big-endian)
        for value in floats {
            var big = value.bitPattern.bigEndian
            data.append(Data(bytes: &big, count: 4))
        }

        return data
    }

    nonisolated private func encodeOSCMessageInt(address: String, value: Int32) -> Data {
        var data = Data()
        data.append(oscString(address))
        data.append(oscString(",i"))
        var big = value.bigEndian
        data.append(Data(bytes: &big, count: 4))
        return data
    }

    nonisolated private func oscString(_ string: String) -> Data {
        var data = string.data(using: .utf8)!
        data.append(0) // null terminator
        while data.count % 4 != 0 {
            data.append(0) // pad to 4-byte boundary
        }
        return data
    }
}
