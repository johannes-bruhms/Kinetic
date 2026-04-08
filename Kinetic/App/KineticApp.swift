import SwiftUI

@main
struct KineticApp: App {
    @StateObject private var sensorManager = SensorManager()
    @StateObject private var oscSender = OSCSender()
    @StateObject private var gestureLibrary = GestureLibrary()
    @StateObject private var calibrationManager = CalibrationManager()

    var body: some Scene {
        WindowGroup {
            PerformanceView()
                .environmentObject(sensorManager)
                .environmentObject(oscSender)
                .environmentObject(gestureLibrary)
                .environmentObject(calibrationManager)
                .preferredColorScheme(.dark)
        }
    }
}
