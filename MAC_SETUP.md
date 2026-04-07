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

## Step 3: Create the Xcode Project

Since the `.xcodeproj` file can't be created on Windows, you'll create it once on Mac:

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
5. Xcode creates a `Kinetic.xcodeproj` — this is your project file

## Step 4: Replace the Generated Files with Ours

Xcode generates starter files that we need to replace with the ones in this repo:

1. In Xcode's left sidebar (Project Navigator), **delete** the auto-generated files:
   - `ContentView.swift`
   - `KineticApp.swift` (the generated one)
   - `Assets.xcassets` (the generated one)
2. When Xcode asks, choose **"Move to Trash"**

3. **Drag our source files into Xcode:**
   - Select all files/folders inside `Kinetic/` from Finder:
     - `App/`
     - `Models/`
     - `Views/`
     - `Services/`
     - `Resources/` (contains our Assets.xcassets)
   - Drag them into the Xcode Project Navigator under the "Kinetic" group
   - In the dialog that appears:
     - Check **"Copy items if needed"** (only if files aren't already in the project folder)
     - Check **"Create groups"**
     - Make sure **"Kinetic"** target is checked
     - Click **Finish**

4. **Drag test files:**
   - Drag everything in `KineticTests/` into the "KineticTests" group in Xcode
   - Same dialog options as above, but target should be **"KineticTests"**

## Step 5: Configure the Project

1. Click the **Kinetic** project (blue icon) in the sidebar
2. Under **General**:
   - **Minimum Deployments:** iOS 17.0
   - **Device Orientation:** Portrait (uncheck Landscape Left/Right for now)
3. Under **Signing & Capabilities**:
   - Select your **Team** (your Apple ID)
   - Xcode will create a provisioning profile automatically
4. Under **Info**:
   - The `Info.plist` entries (motion usage, network usage) should be picked up automatically
   - If not, add these keys manually:
     - `NSMotionUsageDescription` → "Kinetic uses motion sensors to capture your gestures..."
     - `NSLocalNetworkUsageDescription` → "Kinetic sends OSC messages over the local network..."
     - `NSBonjourServices` → Array with `_osc._udp`

## Step 6: Build and Run

1. **Connect your iPhone** via USB
2. On your iPhone: **Settings → Privacy & Security → Developer Mode** → turn ON (restart required)
3. In Xcode, select your iPhone from the device dropdown (top bar)
4. Press **Cmd+R** (or the Play button) to build and run
5. First time: your iPhone will ask you to trust the developer certificate:
   - **Settings → General → VPN & Device Management** → tap your developer profile → **Trust**
6. Run again — the app should launch on your phone

## Step 7: Test the Companion Max Patch

1. Open `Companion/KineticReceiver.maxpat` in Max (or Max for Live)
2. Make sure your Mac and iPhone are on the **same WiFi network**
3. Set the port in the Max patch to match the app's settings (default: 8000)
4. In the Kinetic app, enter your Mac's IP address (find it in System Settings → WiFi → Details)
5. Tap "Stream" — you should see the multisliders moving in Max

## Troubleshooting

- **"Untrusted Developer"**: See Step 6.5 above
- **Build errors about missing files**: Make sure all `.swift` files are added to the Kinetic target (check the file inspector on the right sidebar — "Target Membership" should have Kinetic checked)
- **No motion data in simulator**: The iOS Simulator has no IMU — you must use a real device
- **OSC not arriving**: Check that both devices are on the same WiFi, and the IP/port match. Try disabling your Mac's firewall temporarily to test.
- **Free Apple ID limitation**: Without a paid $99/year Apple Developer account, your app expires after 7 days and must be re-installed. This is fine for development — consider the paid account when you're ready to publish to the App Store.

## Next Steps

Once the basic app runs:
- Train your first gesture and test it with the Max patch
- Tweak the segmenter thresholds if auto-segmentation is too sensitive/insensitive
- Design your app icon (1024x1024 PNG) and drop it in `Resources/Assets.xcassets/AppIcon.appiconset/`
