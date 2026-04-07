import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var oscSender: OSCSender
    @StateObject private var bonjourBrowser = BonjourBrowser()

    var body: some View {
        Form {
            Section("OSC Connection") {
                TextField("IP Address", text: $oscSender.configuration.host)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()

                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", value: $oscSender.configuration.port, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                TextField("Prefix", text: $oscSender.configuration.prefix)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section("Bonjour Discovery") {
                Toggle("Auto-discover", isOn: $oscSender.configuration.useBonjourDiscovery)
                    .onChange(of: oscSender.configuration.useBonjourDiscovery) { _, enabled in
                        if enabled {
                            bonjourBrowser.startBrowsing()
                        } else {
                            bonjourBrowser.stopBrowsing()
                        }
                    }

                if bonjourBrowser.isBrowsing {
                    ForEach(bonjourBrowser.discoveredHosts) { host in
                        Button {
                            oscSender.configuration.host = host.host
                            if host.port > 0 {
                                oscSender.configuration.port = host.port
                            }
                        } label: {
                            Label(host.name, systemImage: "network")
                        }
                    }

                    if bonjourBrowser.discoveredHosts.isEmpty {
                        Text("Searching...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("IMU") {
                Picker("Sample Rate", selection: $oscSender.configuration.sampleRate) {
                    Text("100 Hz").tag(100)
                    Text("150 Hz").tag(150)
                    Text("200 Hz").tag(200)
                }
            }

            Section("Data") {
                Button("Export All Data") {
                    // TODO: Share sheet with gesture data archive
                }
            }
        }
        .navigationTitle("Settings")
    }
}
