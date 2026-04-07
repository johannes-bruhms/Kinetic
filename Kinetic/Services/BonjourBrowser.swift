import Foundation
import Network
import Combine

@MainActor
final class BonjourBrowser: ObservableObject {
    struct DiscoveredHost: Identifiable, Hashable {
        let id: String
        let name: String
        var host: String
        var port: UInt16
    }

    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published var isBrowsing = false

    private var browser: NWBrowser?
    private var resolveConnections: [String: NWConnection] = [:]

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_osc._udp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Cancel old resolve connections
                for (_, conn) in self.resolveConnections { conn.cancel() }
                self.resolveConnections.removeAll()

                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        self.resolveEndpoint(result.endpoint, name: name)
                    }
                }
            }
        }

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.isBrowsing = (state == .ready)
            }
        }

        browser?.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        for (_, conn) in resolveConnections { conn.cancel() }
        resolveConnections.removeAll()
        isBrowsing = false
        discoveredHosts.removeAll()
    }

    /// Resolve a Bonjour endpoint to extract the actual IP address and port.
    private func resolveEndpoint(_ endpoint: NWEndpoint, name: String) {
        let conn = NWConnection(to: endpoint, using: .udp)
        resolveConnections[name] = conn

        conn.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                // Extract the resolved endpoint path
                if let resolved = conn.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = resolved {
                    let hostString: String
                    switch host {
                    case .ipv4(let addr):
                        hostString = "\(addr)"
                    case .ipv6(let addr):
                        hostString = "\(addr)"
                    case .name(let hostname, _):
                        hostString = hostname
                    @unknown default:
                        hostString = "\(host)"
                    }
                    let portValue = port.rawValue

                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let resolved = DiscoveredHost(
                            id: name,
                            name: name,
                            host: hostString,
                            port: portValue
                        )
                        if let idx = self.discoveredHosts.firstIndex(where: { $0.id == name }) {
                            self.discoveredHosts[idx] = resolved
                        } else {
                            self.discoveredHosts.append(resolved)
                        }
                    }
                }
                conn.cancel()
            }
        }

        // Add unresolved placeholder immediately
        let placeholder = DiscoveredHost(id: name, name: name, host: "", port: 0)
        if !discoveredHosts.contains(where: { $0.id == name }) {
            discoveredHosts.append(placeholder)
        }

        conn.start(queue: DispatchQueue(label: "com.kinetic.resolve.\(name)"))
    }
}
