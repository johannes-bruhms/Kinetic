# Kinetic: iOS Gesture Controller for Live Music

Kinetic is a professional, high-performance iOS application designed for contemporary composers, performers, and multimedia artists. It transforms an iPhone into a trainable IMU (Inertial Measurement Unit) instrument, streaming real-time motion data and custom gesture recognition events over OSC to laptop-side environments like Max for Live, Pure Data, or SuperCollider.

## Project Overview

- **Core Purpose**: Real-time IMU data streaming and gesture classification for artistic performance.
- **Main Technologies**:
  - **Swift & SwiftUI**: Modern iOS development.
  - **CoreMotion**: High-frequency sensor data (100–200 Hz).
  - **Core ML / Create ML**: Gesture classification and model inference.
  - **NWConnection (Network Framework)**: Low-latency OSC over UDP (no external dependencies).
  - **Swift 6 Concurrency**: Safe, off-main-thread processing for sensor data and networking.
- **Architecture**: MVVM (transitioning from logic in views to dedicated ViewModels).
- **Unique Features**: Energy-based auto-segmentation for gesture training, Bonjour auto-discovery for OSC hosts, and a "glove-friendly" dark-mode UI.

## Project Structure

- `Kinetic/`: Main application source.
  - `App/`: Entry point (`KineticApp.swift`).
  - `Models/`: Data structures (`GestureModel.swift`, `OSCConfiguration.swift`).
  - `Services/`: Core logic providers.
    - `SensorManager.swift`: Handles CoreMotion updates.
    - `OSCSender.swift`: Manual OSC encoding and UDP transmission.
    - `GestureClassifier.swift`: Core ML integration for real-time inference.
    - `GestureLibrary.swift`: Persistence and management of trained gestures.
    - `GestureSegmenter.swift`: Energy-based motion segmentation.
  - `Views/`: SwiftUI interface components (`PerformanceView.swift`, `TrainingView.swift`, etc.).
  - `Resources/`: Assets and configuration.
- `KineticTests/`: Unit tests for classifier, segmenter, and OSC encoding.
- `Companion/`: (Planned) Laptop-side receiver patches (e.g., Max for Live).

## Building and Running

### Prerequisites
- **macOS 14+** (Sonoma) and **Xcode 15+**.
- **iPhone** running **iOS 17+** (Real device required for IMU features).

### Setup Instructions
1. **Clone the Repo**: `git clone <repo-url>`
2. **Create Xcode Project**: Since `.xcodeproj` is not tracked, create a new iOS App project named `Kinetic` in the root directory.
3. **Add Files**:
   - Drag the `Kinetic/` and `KineticTests/` folders into the Xcode project.
   - Ensure "Copy items if needed" is NOT checked if files are already in the project directory.
   - Verify "Kinetic" target membership for source files and "KineticTests" for tests.
4. **Capabilities**:
   - Add **Motion Usage** (`NSMotionUsageDescription`) to `Info.plist`.
   - Add **Local Network** (`NSLocalNetworkUsageDescription`) and **Bonjour Services** (`_osc._udp`) to `Info.plist`.
5. **Run**: Connect your iPhone, enable Developer Mode, and build/run (Cmd+R).

## Development Conventions

- **Performance First**: Sensor processing and OSC encoding must happen off the main thread.
- **Native APIs**: Prefer native frameworks (CoreMotion, Network, Core ML) over external dependencies.
- **UI/UX**: Dark mode only. Large, accessible controls for live performance contexts.
- **Data Privacy**: No tracking or analytics. Motion data is ephemeral and only leaves the device via the user-configured OSC stream.
- **Testing**: Ensure all OSC encoding and segmentation logic is verified in `KineticTests`.

## Key Commands (Mental Map)
- **Run App**: `Cmd + R` (in Xcode)
- **Run Tests**: `Cmd + U` (in Xcode)
- **Clean Build**: `Cmd + Shift + K` (in Xcode)
- **Swift Package Manager**: Used for future dependencies, managed via `Package.swift`.
