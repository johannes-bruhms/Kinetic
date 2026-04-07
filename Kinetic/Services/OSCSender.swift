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
        sendOSCMessage(address: "\(prefix)imu/attitude/quat",
                       values: [sample.attitude.x, sample.attitude.y, sample.attitude.z, sample.attitude.w])
        sendOSCMessage(address: "\(prefix)imu/rotation/rate",
                       values: [sample.rotationRate.x, sample.rotationRate.y, sample.rotationRate.z])
        sendOSCMessage(address: "\(prefix)imu/accel/user",
                       values: [sample.userAcceleration.x, sample.userAcceleration.y, sample.userAcceleration.z])
        sendOSCMessage(address: "\(prefix)imu/gravity",
                       values: [sample.gravity.x, sample.gravity.y, sample.gravity.z])
    }

    func sendGestureEvent(name: String, probability: Float) {
        let prefix = configuration.prefix
        sendOSCMessage(address: "\(prefix)gesture/\(name)", values: [Double(probability)])
    }

    func sendGestureTrigger(name: String, velocity: Int = 127) {
        let prefix = configuration.prefix
        sendOSCMessage(address: "\(prefix)gesture/\(name)/trigger", values: [Double(velocity)])
    }

    // MARK: - OSC Encoding

    private func sendOSCMessage(address: String, values: [Double]) {
        guard let connection else { return }

        let data = encodeOSCMessage(address: address, floats: values.map { Float($0) })
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func encodeOSCMessage(address: String, floats: [Float]) -> Data {
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

    private func oscString(_ string: String) -> Data {
        var data = string.data(using: .utf8)!
        data.append(0) // null terminator
        while data.count % 4 != 0 {
            data.append(0) // pad to 4-byte boundary
        }
        return data
    }
}
