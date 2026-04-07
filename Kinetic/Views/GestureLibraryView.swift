import SwiftUI

struct GestureLibraryView: View {
    @EnvironmentObject var gestureLibrary: GestureLibrary
    @State private var showingAddGesture = false
    @State private var newGestureName = ""

    var body: some View {
        List {
            ForEach(gestureLibrary.gestures) { gesture in
                VStack(alignment: .leading, spacing: 4) {
                    Text(gesture.name)
                        .font(.headline)
                    HStack {
                        Text("\(gesture.sampleCount) samples")
                        Text("·")
                        Text(gesture.lastTrained, style: .relative)
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
        .overlay {
            if gestureLibrary.gestures.isEmpty {
                ContentUnavailableView("No Gestures", systemImage: "hand.wave", description: Text("Tap + to train your first gesture"))
            }
        }
    }
}
