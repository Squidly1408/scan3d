# Getting started

## Requirements

| | Minimum |
|---|---|
| Flutter | 3.22 (Dart 3.4) |
| Android | 7.0 / API 24, with [ARCore support](https://developers.google.com/ar/devices) |
| iOS | 14.0, on an ARKit device (A9 chip or newer) |
| Xcode | 15 or newer, for iOS builds |
| JDK | 17, for Android builds |

You need a physical phone or tablet. Simulators and emulators don't provide an AR camera, so the scan screen will show an error on them.

## Clone and run

```bash
git clone https://github.com/Squidly1408/scan3d.git
cd scan3d
flutter pub get
flutter devices          # check that your phone is listed
flutter run              # add -d <device-id> if more than one is connected
```

`flutter run` builds in debug mode. Point-cloud accumulation runs on the UI isolate, so use `flutter run --release` to see real performance on a dense LiDAR or depth scan.

### iOS signing

1. Open `ios/Runner.xcworkspace` in Xcode. Open the workspace, not the `.xcodeproj`.
2. Select the **Runner** target, then **Signing & Capabilities**.
3. Choose your team. With a free Apple ID, also change the bundle identifier from `com.example.scan3d` to something unique.
4. The first time you install on a device, trust the developer profile under **Settings → General → VPN & Device Management**.

### Android

Nothing to configure. On first launch, ARCore may ask you to install or update **Google Play Services for AR**. Accept, then tap **Try again** in the app.

## Regenerating the native runner projects

`android/` and `ios/` are committed, so you don't normally need this. If you delete them, or want to pick up a newer Flutter template:

```bash
flutter create --org com.example --project-name scan3d --platforms android,ios .
bash tool/configure_native.sh
python tool/brand/generate.py      # restores the app icons
```

`configure_native.sh` is safe to run more than once. It:

- raises Android `minSdk` to 24, which ARCore requires
- sets the iOS deployment target to 14.0, which ARKit scene reconstruction and RealityKit need
- adds `NSCameraUsageDescription` and the `arkit` required device capability to `Info.plist`

On Windows, run it from Git Bash. It needs `python3` on the PATH for the plist step.

## Running the tests

```bash
flutter analyze
flutter test
```

The tests cover the voxel accumulator, the PLY writer, the colour ramp and a home-screen smoke test. None of the AR code can run in a test environment, so changes to the plugin have to be checked on a device. See [CONTRIBUTING.md](../CONTRIBUTING.md#testing-on-a-device).
