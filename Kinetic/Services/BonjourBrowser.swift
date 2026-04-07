import Foundation
import Network

@MainActor
final class BonjourBrowser: ObservableObject {
    struct DiscoveredHost: Identifiable, Hashable {
        let id: String
        let name: String
        let host: String
        let port: UInt16
    }

    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published var isBrowsing = false

    private var browser: NWBrowser?

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_osc._udp", domain: nil), using: params)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.discoveredHosts = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint {
                        return DiscoveredHost(id: name, name: name, host: "", port: 0)
                    }
                    return nil
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
        isBrowsing = false
        discoveredHosts.removeAll()
    }
}
