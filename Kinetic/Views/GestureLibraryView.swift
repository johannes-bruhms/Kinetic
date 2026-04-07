import SwiftUI

struct GestureLibraryView: View {
    @EnvironmentObject var gestureLibrary: GestureLibrary
    @State private var showingAddGesture = false
    @State private var newGestureName = ""
    @State private var gestureToRename: TrainedGesture?
    @State private var renameText = ""

    var body: some View {
        List {
            ForEach(gestureLibrary.gestures) { gesture in
                VStack(alignment: .leading, spacing: 4) {
                    Text(gesture.name)
                        .font(.headline)
                    HStack {
                        if gesture.sampleCount > 0 {
                            Text("\(gesture.sampleCount) samples")
                            Text("·")
                            Text("Trained \(gesture.lastTrained, style: .relative) ago")
                        } else {
                            Text("Not trained")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .alert("New Gesture", isPresented: $showingAddGesture) {
            TextField("Gesture name", text: $newGestureName)
            Button("Add") {
                if !newGestureName.isEmpty {
                    _ = gestureLibrary.addGesture(name: newGestureName)
                    newGestureName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newGestureName = ""
            }
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
}
