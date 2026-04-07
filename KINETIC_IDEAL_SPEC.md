# Kinetic v1.0: Professional iOS Gesture Controller Spec

This document outlines the ideal, ship-ready version of **Kinetic**. It serves as a North Star for development, defining the architecture, core logic, and user experience.

---

## 1. Visual Identity: "Performance-First" UI
Designed for high-pressure stage environments (dark rooms, fast movement, one-handed use).

*   **Aesthetic:** "Stealth-Tech" Glassmorphism.
    *   **True Black (`#000000`):** Optimizes battery on OLED screens and minimizes stage light "bleed."
    *   **High-Contrast Accents:** Neon Green (Active), Amber (Warning), Electric Blue (Processing).
*   **Interaction Design:**
    *   **Large Hit Areas:** Oversized buttons for thumb-triggering while holding the device firmly.
    *   **Haptic Engine:** Distinctive Taptic patterns for Start/Stop/Trigger events for eyes-free feedback.
    *   **Live Waveforms:** A 100Hz real-time "Seismograph" (Accel/Gyro) providing immediate visual sensor confirmation.

---

## 2. System Architecture: The "Four Pillars"
Organized using the **MVVM-S (Model-View-ViewModel-Service)** pattern for stability and testability.

### Pillar 1: The Sensor Engine (`SensorManager`)
*   **Logic:** Pulls data from `CMMotionManager` at 100Hz (10ms intervals).
*   **Implementation:** 
    *   Filters raw data into **Linear Acceleration** (gravity-removed) and **Attitude** (Quaternions).
    *   Ensures "Rotation-Invariance": gestures work identically regardless of device orientation.

### Pillar 2: The OSC Pipeline (`OSCSender`)
*   **Logic:** Zero-latency UDP streaming via Apple’s `Network.framework`.
*   **Implementation:**
    *   Custom binary `OSCEncoder` for minimal packet overhead.
    *   **Bonjour Auto-Discovery:** Seamlessly finds Mac/PC hosts on the local network without IP entry.

### Pillar 3: Gesture Intelligence (`GestureClassifier`)
*   **Logic:** Hybrid Inference Model.
    *   **DTW (Dynamic Time Warping):** For user-trained "one-shot" gestures (e.g., "The Karate Chop").
    *   **Core ML (Neural Network):** For continuous state detection (e.g., "Walking," "Shaking," "Still").
*   **Segmentation:** Energy-based triggers only "listen" when motion exceeds a calibrated threshold, preventing accidental triggers.

### Pillar 4: Persistence (`GestureLibrary`)
*   **Logic:** Manages trained gesture data and sensor logs.
*   **Implementation:**
    *   Saves gestures as JSON metadata + binary sensor buffers.
    *   iCloud Sync: Share "Gesture Packs" across multiple devices or with other performers.

---

## 3. Project Structure
```text
Kinetic/
├── App/                # App entry & Global State (EnvironmentObjects)
├── Models/             # MotionSample, Gesture, OSCConfiguration
├── ViewModels/         # Logic for each screen (The "Brain")
├── Services/           # Core Engines
│   ├── Network/        # UDP Transmission & Bonjour logic
│   ├── Motion/         # CoreMotion wrappers & Signal Processing
│   └── ML/             # CoreML Inference & DTW training logic
├── Views/              # SwiftUI Components
│   ├── Performance/    # Main stage view (Focus mode)
│   ├── Training/       # Gesture recording & calibration UI
│   └── Shared/         # Custom Neumorphic Buttons & Graphs
└── Resources/          # Assets, ML Models, Info.plist
```

---

## 4. Human Walkthrough: "The Concert Hall"

**User:** Alex (Electronic Musician)
**Setting:** A dark stage, 5 minutes before the performance.

1.  **Preparation:** Alex slides the iPhone into a wrist strap. They launch **Kinetic**. The screen is pitch black with a soft green "Ready" glow.
2.  **Connection:** Alex taps the **Settings** icon. The app displays "MacBook-Pro detected via Bonjour." They tap it; a small "Link" icon turns blue. 
3.  **The Sound Check:** Alex opens **Test Mode**. They move their arm in a slow circle. On their laptop (running Max/MSP), a filter sweep follows the motion perfectly with 0ms perceptible lag.
4.  **The Gesture:** Alex needs a "climax" sound. They enter **Training**, hit **Record**, and perform a violent "Air Punch" three times. Kinetic confirms: *"Gesture 'TitanPunch' Trained. Accuracy 98%."*
5.  **The Performance:**
    *   The lights dim. Alex hits the massive **STREAM** button.
    *   As they move, raw IMU data modulates a synthesizer in real-time.
    *   Suddenly, Alex performs the "TitanPunch."
    *   The phone delivers a **sharp haptic vibration**.
    *   The app sends the OSC trigger: `/kinetic/trigger/TitanPunch 1.0`.
    *   The hall explodes with a massive sub-bass drop. 
6.  **The Finish:** After the set, Alex taps **Stop**. The app shows a "Session Summary": *45,000 packets sent, 0 dropped.* Alex pockets the phone; the battery has only dropped 3%.

---

## 5. Deployment Checklist
- [ ] **Hardened Networking:** Automatic reconnection if Wi-Fi drops.
- [ ] **Lock Screen Support:** Keep streaming even when the screen is locked/off.
- [ ] **Low-Latency Mode:** Toggle to prioritize speed over data resolution.
- [ ] **External Display Support:** Mirror the IMU graphs to a projector for visual performances.
