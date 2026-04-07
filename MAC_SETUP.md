# Setting Up Kinetic on Your Mac

Step-by-step guide to get from this repo to a running app on your iPhone.

## Prerequisites

- **Mac** with macOS 14 (Sonoma) or later
- **Xcode 15+** — free from the Mac App Store (large download, ~12 GB)
- **Apple ID** — you already have one if you use any Apple device
- **iPhone** running iOS 17+ with a USB cable

## Step 1: Install Xcode

1. Open the **Mac App Store**, search "Xcode", install it
2. Launch Xcode once and let it install additional components when prompted
3. Accept the license agreement

## Step 2: Clone the Repo

Open Terminal on your Mac and run:

```bash
git clone <your-repo-url> ~/Kinetic
cd ~/Kinetic
```

Or transfer the folder from your PC via USB drive, AirDrop, or cloud storage.

## Step 3: Open the Project

The repo includes a `Kinetic.xcodeproj` file. Simply double-click it or:

```bash
open Kinetic.xcodeproj
```

If you need to recreate the Xcode project from scratch (e.g., after a fresh clone without the xcodeproj):

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App** → Next
3. Fill in:
   - **Product Name:** `Kinetic`
   - **Team:** Your Apple ID (Xcode will prompt you to sign in)
   - **Organization Identifier:** something like `com.yourname` (e.g., `com.kinetic`)
   - **Interface:** SwiftUI
   - **Language:** Swift
   - Leave "Include Tests" checked
4. Save it **inside the cloned repo folder** (e.g., `~/Kinetic`)
5. Delete the auto-generated `ContentView.swift` and `KineticApp.swift`
6. Drag the `Kinetic/App/`, `Kinetic/Models/`, `Kinetic/Views/`, `Kinetic/Services/`, `Kinetic/Resources/` folders into the Xcode Project Navigator under the "Kinetic" group
7. Drag `KineticTests/*.swift` into the "KineticTests" group

## Step 4: Configure Signing

1. Click the **Kinetic** project (blue icon) in the sidebar
2. Under **Signing & Capabilities**:
   - Select your **Team** (your Apple ID)
   - Xcode will create a provisioning profile automatically
3. Under **General**:
   - **Minimum Deployments:** iOS 17.0
   - **Device Orientation:** Portrait (uncheck Landscape Left/Right for now)

## Step 5: Build and Run

1. **Connect your iPhone** via USB
2. On your iPhone: **Settings → Privacy & Security → Developer Mode** → turn ON (restart required)
3. In Xcode, select your iPhone from the device dropdown (top bar)
4. Press **Cmd+R** (or the Play button) to build and run
5. First time: your iPhone will ask you to trust the developer certificate:
   - **Settings → General → VPN & Device Management** → tap your developer profile → **Trust**
6. Run again — the app should launch on your phone

## Step 6: Test Gesture Recognition

1. In the app, go to **Library** → tap **+** → name a gesture (e.g., "Punch")
2. Go to **Train** → select the gesture → tap **Start Recording**
3. Perform the gesture 3-5 times with pauses between each
4. Tap **Stop Recording** → review the detected segments → tap **Save Samples**
5. Go back to **Performance** → tap **Stream** — the app will recognize the gesture

## Step 7: Test OSC Output

1. Make sure your Mac and iPhone are on the **same WiFi network**
2. In the Kinetic app, go to **Settings** → enter your Mac's IP address
   - Find your Mac's IP in System Settings → WiFi → Details
   - Or enable Bonjour auto-discovery if your OSC host advertises `_osc._udp`
3. Set the port to match your receiving software (default: 8000)
4. Open your OSC receiver (Max/MSP, SuperCollider, Pure Data, etc.)
5. Tap **Stream** in the app — you should see IMU data flowing

## Troubleshooting

- **"Untrusted Developer"**: See Step 5.5 above
- **Build errors about missing files**: Make sure all `.swift` files are added to the Kinetic target (check the file inspector on the right sidebar — "Target Membership" should have Kinetic checked)
- **No motion data in simulator**: The iOS Simulator has no IMU — you must use a real device
- **OSC not arriving**: Check that both devices are on the same WiFi, and the IP/port match. Try disabling your Mac's firewall temporarily to test.
- **Free Apple ID limitation**: Without a paid $99/year Apple Developer account, your app expires after 7 days and must be re-installed. This is fine for development — consider the paid account when you're ready to publish to the App Store.

## Next Steps

Once the basic app runs:
- Train multiple gestures and test classification accuracy
- Experiment with the DTW distance threshold by training more samples
- Design your app icon (1024x1024 PNG) and drop it in `Resources/Assets.xcassets/AppIcon.appiconset/`
