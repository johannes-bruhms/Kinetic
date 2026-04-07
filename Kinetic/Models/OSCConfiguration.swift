import Foundation

struct OSCConfiguration: Codable {
    var host: String
    var port: UInt16
    var prefix: String
    var sampleRate: Int
    var useBonjourDiscovery: Bool

    static let `default` = OSCConfiguration(
        host: "192.168.1.1",
        port: 8000,
        prefix: "/kinetic/",
        sampleRate: 100,
        useBonjourDiscovery: true
    )
}
