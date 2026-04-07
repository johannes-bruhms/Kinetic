import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var oscSender: OSCSender
    @EnvironmentObject var gestureLibrary: GestureLibrary
    @StateObject private var bonjourBrowser = BonjourBrowser()

    @State private var showingExportSheet = false
    @State private var exportURL: URL?

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
                            if !host.host.isEmpty {
                                oscSender.configuration.host = host.host
                            }
                            if host.port > 0 {
                                oscSender.configuration.port = host.port
                            }
                        } label: {
                            HStack {
                                Label(host.name, systemImage: "network")
                                Spacer()
                                if !host.host.isEmpty {
                                    Text("\(host.host):\(host.port)")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                } else {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
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
                Button("Export All Gesture Data") {
                    exportGestureData()
                }
                .disabled(gestureLibrary.gestures.isEmpty)
            }

            Section("About") {
                HStack {
                    Text("Gestures")
                    Spacer()
                    Text("\(gestureLibrary.gestures.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Total Samples")
                    Spacer()
                    Text("\(gestureLibrary.gestures.reduce(0) { $0 + $1.sampleCount })")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportGestureData() {
        guard let url = gestureLibrary.exportAllData() else { return }
        exportURL = url
        showingExportSheet = true
    }
}

/// UIKit share sheet wrapper for SwiftUI.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
