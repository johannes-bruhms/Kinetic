import SwiftUI

struct GestureLibraryView: View {
    @EnvironmentObject var gestureLibrary: GestureLibrary
    @State private var showingAddGesture = false
    @State private var newGestureName = ""
    @State private var newGestureType: GestureType = .discrete
    @State private var gestureToRename: TrainedGesture?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(gestureLibrary.gestures) { gesture in
                NavigationLink(destination: GestureDetailView(gesture: gesture)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: gesture.gestureType.iconName)
                                .foregroundStyle(typeColor(for: gesture.gestureType))
                            Text(gesture.name)
                                .font(.headline)
                            Text(gesture.gestureType.rawValue.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(typeColor(for: gesture.gestureType).opacity(0.2))
                                .clipShape(Capsule())
                        }
                        HStack {
                            if gesture.sampleCount > 0 {
                                Text("\(gesture.sampleCount) samples")
                                Text("\u{00b7}")
                                Text("Trained \(gesture.lastTrained, style: .relative) ago")
                            } else {
                                Text("Not trained")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        gestureLibrary.deleteGesture(gesture)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        renameText = gesture.name
                        gestureToRename = gesture
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .navigationTitle("Gesture Library")
        .toolbar {
            Button {
                showingAddGesture = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $showingAddGesture) {
            NavigationStack {
                Form {
                    TextField("Gesture name", text: $newGestureName)

                    Picker("Type", selection: $newGestureType) {
                        ForEach(GestureType.allCases, id: \.self) { type in
                            Label(type.rawValue.capitalized, systemImage: type.iconName)
                                .tag(type)
                        }
                    }

                    Section {
                        switch newGestureType {
                        case .discrete:
                            Text("Short, one-shot gestures like chops, flicks, or taps. Recognized using DTW pattern matching.")
                        case .continuous:
                            Text("Ongoing motions like shaking, arm circles, or waving. Recognized using frequency analysis. Train with ~10 seconds of continuous motion.")
                        case .posture:
                            Text("Static phone positions like vertical, horizontal, or tilted. Recognized using gravity vector matching. Train by holding the phone steady for 3 seconds.")
                        }
                    } header: {
                        Text("Description")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .navigationTitle("New Gesture")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            newGestureName = ""
                            newGestureType = .discrete
                            showingAddGesture = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            if !newGestureName.isEmpty {
                                _ = gestureLibrary.addGesture(name: newGestureName, type: newGestureType)
                                newGestureName = ""
                                newGestureType = .discrete
                                showingAddGesture = false
                            }
                        }
                        .disabled(newGestureName.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert("Rename Gesture", isPresented: Binding(
            get: { gestureToRename != nil },
            set: { if !$0 { gestureToRename = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                if let gesture = gestureToRename, !renameText.isEmpty {
                    gestureLibrary.renameGesture(gesture, to: renameText)
                }
                gestureToRename = nil
                renameText = ""
            }
            Button("Cancel", role: .cancel) {
                gestureToRename = nil
                renameText = ""
            }
        }
        .overlay {
            if gestureLibrary.gestures.isEmpty {
                ContentUnavailableView("No Gestures", systemImage: "hand.wave", description: Text("Tap + to create your first gesture"))
            }
        }
    }

    private func typeColor(for type: GestureType) -> Color {
        switch type {
        case .discrete: .blue
        case .continuous: .green
        case .posture: .orange
        }
    }
}

// MARK: - Gesture Detail View

struct GestureDetailView: View {
    @EnvironmentObject var gestureLibrary: GestureLibrary
    let gesture: TrainedGesture

    @State private var sensitivity: Double
    @State private var cooldown: Double

    init(gesture: TrainedGesture) {
        self.gesture = gesture
        _sensitivity = State(initialValue: gesture.sensitivity)
        _cooldown = State(initialValue: gesture.cooldownDuration)
    }

    var body: some View {
        Form {
            Section("Info") {
                HStack {
                    Text("Type")
                    Spacer()
                    Label(gesture.gestureType.rawValue.capitalized, systemImage: gesture.gestureType.iconName)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Samples")
                    Spacer()
                    Text("\(gesture.sampleCount)")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text(sensitivityLabel)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $sensitivity, in: 0...1, step: 0.05)
                        .onChange(of: sensitivity) { _, newValue in
                            save(sensitivity: newValue, cooldown: cooldown)
                        }
                    Text(sensitivityDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Recognition")
            }

            if gesture.gestureType == .discrete {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Cooldown")
                            Spacer()
                            Text(String(format: "%.0fms", cooldown * 1000))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $cooldown, in: 0.1...2.0, step: 0.1)
                            .onChange(of: cooldown) { _, newValue in
                                save(sensitivity: sensitivity, cooldown: newValue)
                            }
                        Text("Time between repeated triggers")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Debounce")
                }
            }
        }
        .navigationTitle(gesture.name)
    }

    private var sensitivityLabel: String {
        switch gesture.gestureType {
        case .discrete:
            let triggerThreshold = 0.70 - sensitivity * 0.40
            let dtwThreshold = 2.5 + sensitivity * 3.5
            return String(format: "Trigger>%.0f%% DTW:%.1f", triggerThreshold * 100, dtwThreshold)
        case .continuous:
            let threshold = 0.80 - sensitivity * 0.45
            return String(format: "Match > %.0f%%", threshold * 100)
        case .posture:
            let degrees = (0.15 + sensitivity * 0.35) * 180 / .pi
            return String(format: "%.0f° tolerance", degrees)
        }
    }

    private var sensitivityDescription: String {
        switch gesture.gestureType {
        case .discrete:
            return sensitivity < 0.3 ? "Very selective — only strong matches trigger"
                 : sensitivity > 0.7 ? "Loose — triggers on weaker matches"
                 : "Balanced trigger threshold"
        case .continuous:
            return sensitivity < 0.3 ? "Tight frequency match required"
                 : sensitivity > 0.7 ? "Loose frequency match — easier to activate"
                 : "Balanced frequency matching"
        case .posture:
            return sensitivity < 0.3 ? "Tight — must hold phone very precisely"
                 : sensitivity > 0.7 ? "Loose — allows more angle variation"
                 : "Balanced angle tolerance"
        }
    }

    private func save(sensitivity: Double, cooldown: Double) {
        var updated = gesture
        updated.sensitivity = sensitivity
        updated.cooldownDuration = cooldown
        gestureLibrary.updateGesture(updated)
    }
}
