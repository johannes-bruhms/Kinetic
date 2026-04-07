**Kinetic**

### 1. App Name
**Primary Recommendation: Kinetic**  
Short, modern, memorable, and instantly communicates “motion / energy / gesture-driven control.” It feels artistic and professional without being overly literal, while still nodding to the kinetic energy in your live performances and installations. Easy to brand, pronounce, and search in the App Store. Logo concept: a stylized phone with flowing gesture trails.

### 2. Product Vision & Positioning
Kinetic is a $4.99 one-time-purchase iPhone-first (iPad-compatible) professional gesture controller that turns the device in your hand into a trainable IMU instrument. It streams high-frequency motion data and recognizes custom gestures you train yourself, sending everything cleanly over OSC to your laptop.  

The only laptop-side requirement is one free companion Max for Live device (or tiny Max Runtime patch) provided. No extra software, no bridges, no subscriptions.  

Target users 'peers': contemporary composers, electroacoustic performers, new-music ensembles, multimedia artists, and students who attend festivals like Mise-En, Darmstädter Ferienkurse, or Northwestern New Music Conference.  

Unique selling points:  
- Built by a working composer-performer for the exact workflow already used in existing works.  
- Zero-friction OSC + trainable gestures that feel like a natural extension of your artistic practice.  
- Performance-ready, battery-efficient, and instantly personalizable.

### 3. Detailed Feature List
**MVP (v1.0 – launch-ready):**
- Real-time IMU streaming (100–200 Hz) over OSC.
- Full custom gesture training workflow with auto-segmentation and review.
- Multi-gesture recognition (Core ML primary; DTW lightweight fallback).
- OSC address prefix, IP, port, and Bonjour auto-discovery.
- Performance dashboard with live waveform, gesture probability bars, and one-tap start/stop.
- Test/Rehearsal mode.
- Dark, glove-friendly UI with large controls and orientation lock option.
- Local storage of gesture models and examples.
- Permissions handling with clear artistic explanations.

**Post-launch (v1.1+):**
- Preset gesture library.
- Gesture preset import/export (shareable .kinetic files).
- Lightweight built-in synth for standalone testing.
- Background streaming mode for installations.
- Expanded mapping templates inside the companion M4L device.
- Optional MIDI fallback output.

### 4. User Flows & Screen-by-Screen Breakdown
**Home / Performance Screen** (main screen on launch)  
- Large “Stream” toggle (green when active).  
- Live IMU waveform (scrolling 3-axis plot).  
- Gesture probability bars (one per trained gesture + “None”).  
- Quick-tap list of recent gestures fired.  
- Bottom bar: Library | Train | Settings | Test.

**Gesture Library Screen**  
- List of trained gestures with name, sample count, last trained date.  
- Swipe to delete or rename.  
- “+ Add New Gesture” button → enters training flow.

**Training Flow:**  
1. “Add Gesture” → user types name (e.g. “Circle Wave”).  
2. “Start Training” → high-rate CoreMotion recording begins; big on-screen countdown and live energy meter.  
3. User performs the gesture multiple times with natural pauses.  
4. App auto-segments on low-energy “rest” thresholds, shows thumbnail waveform previews of each extracted sample.  
5. User can delete bad samples or re-record.  
6. “Train Model” → processes examples (Create ML export or on-device personalization).  
7. Returns to Library with the new gesture ready.

**Settings Screen**  
- OSC: IP address (auto-fill last used), Port (default 8000), Prefix (default `/kinetic/`).  
- Bonjour discovery toggle + list of discovered hosts.  
- IMU sample rate slider (100/150/200 Hz).  
- Model type selector (Core ML vs. DTW).  
- Export all data button.

**Test / Rehearsal Mode**  
- Full-screen mode with exaggerated probability bars and audio click on detection (optional).  
- Used for rehearsing before a gig or installation.

### 5. Technical Architecture & Implementation Details
**Overall pattern:** MVVM + Swift 6 concurrency + SwiftUI. All processing off main thread where possible.

**Key components:**
- **Sensor Layer:** `CMMotionManager` in batched high-frequency mode (DeviceMotion for fused attitude, gravity, user acceleration, rotation rate).  
- **Gesture Pipeline:**  
  - Recording → raw JSON/CSV of timestamped vectors.  
  - Auto-segmentation: rolling window energy (magnitude of accel + gyro) with hysteresis state machine to detect “rest” vs. “motion.”  
  - Training: segmented examples fed to Create ML Activity Classifier (on Mac for MVP) or Core ML on-device personalization (iOS 17+). Output: tiny .mlmodel (~1–3 MB).  
  - Inference: Core ML on Neural Engine → real-time classification at sensor rate.  
- **Networking:** OSCKit (Swift package) for UDP OSC sender.  
- **Storage:** FileManager + Codable JSON for gesture library; .mlmodel files in Documents.  
- **Background behavior:** Continues streaming in background for up to ~30–60 min (CoreMotion + low-power mode).  
- **Data Flow (text diagram):**  
  CoreMotion → SensorManager (background queue) → [optional GestureClassifier] → OSC Sender → UDP network.  
  UI updates throttled on main actor.

**Performance targets:**  
- App binary < 15 MB.  
- Continuous use: 4–6 hours on modern iPhone.  
- Latency: < 20 ms from gesture to OSC packet.

### 6. OSC Output Schema
Default prefix: `/kinetic/` (user-editable).

**Continuous IMU stream (sent every packet while streaming):**
- `/kinetic/imu/attitude/quat` (x, y, z, w)  
- `/kinetic/imu/rotation/rate` (x, y, z)  
- `/kinetic/imu/accel/user` (x, y, z)  
- `/kinetic/imu/gravity` (x, y, z)

**Gesture events (fired on detection):**
- `/kinetic/gesture/[name]` (float 0.0–1.0 probability)  
- `/kinetic/gesture/[name]/trigger` (int 1 on new detection, optional velocity 0–127)

Addresses update automatically when user renames a gesture. All messages are timestamped where useful.

### 7. Companion Laptop Receiver
ship one free `.amxd` Max for Live device named “Kinetic Receiver” (plus a tiny standalone Max patch for non-Ableton users).

**Device contents:**
- Single “Listen Port” number box (matches app).  
- Big labeled toggles for each common mapping (raw IMU → MIDI CCs, gesture probabilities → triggers).  
- Pre-loaded example mappings.  
- Editable mapping matrix (gesture name → MIDI/OSC output).  
- Raw IMU passthrough section for advanced users.  
- Visual feedback LEDs that light up when gestures fire.

### 8. Non-Functional Requirements
- iOS 17.0+ target.  
- App Store category: Music / Utilities.  
- Keywords: gesture controller, IMU OSC, motion sensor, live electronics, Max for Live, contemporary music, monolith, portals.  
- Full dark mode, Dynamic Type, VoiceOver support.  
- No analytics or tracking.  
- Privacy policy focused on motion data never leaving the device except OSC.

### 9. Future-Proofing & Update Roadmap
- v1.1: Preset library + export.  
- v1.2: Built-in synth + background mode.  
- v2.0: AUv3 instrument host + more advanced ML (transformer-based if Apple releases better APIs).  
- All core OSC addresses and training data format will remain backward-compatible.

### 10. Risks & Mitigations
- **Risk:** Core ML training feels too technical → Mitigation: Clear in-app tutorial video (demoing the exact flow) + one-tap “Use DTW instead” fallback.  
- **Risk:** Network latency on stage WiFi → Mitigation: Local network only + Bonjour + optional wired Ethernet adapter support.  
- **Risk:** Scope creep → Mitigation: Strict MVP definition above; everything else is post-launch.
