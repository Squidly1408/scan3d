# Troubleshooting

## Scanning

**Status stays on "Initializing".**
Tracking needs parallax. Move the phone sideways a little, rather than just rotating it, and point it at something with texture.

**"Insufficient features".**
The camera is looking at a blank surface such as a white wall, glass or a glossy floor. Include some furniture, a door frame or a rug in the view.

**"Insufficient light".**
Turn the lights on. ARCore in particular loses tracking quickly in dim rooms.

**Points appear doubled or offset.**
Tracking drifted and then corrected itself. Usually the session lost tracking and relocalised. Scan in smaller loops, and come back past areas you've already scanned so the tracker can close the loop. If the cloud is badly broken, tap reset and start again.

**The scan stopped recording on its own.**
The cloud reached its 2,000,000-point limit. Open the viewer and export. You can raise `maxPoints` in `ScanScreen`, but drawing gets slower.

**On Android, the camera view shows no points.**
This is expected. The Android preview only draws the camera image, and progress shows in the mini-map.

## Setup and permissions

**"Camera permission is needed to scan".**
You denied the prompt earlier. Allow camera access in system Settings → Apps → Scan3D, or Settings → Scan3D on iOS, then tap **Try again**.

**"Install or update Google Play Services for AR".**
Accept the Play Store prompt, wait for it to finish, return to the app and tap **Try again**. If no prompt appears, install *Google Play Services for AR* from the Play Store yourself.

**"This device does not support ARCore".**
Check the [supported device list](https://developers.google.com/ar/devices). Unsupported devices can't run the app.

**"The native AR plugin is not available on this platform".**
You're running on desktop, web or a simulator. Use a real phone.

## Build errors

**Android: `minSdkVersion 21 cannot be smaller than version 24 declared in library [:scan3d_native]`.**
Run `bash tool/configure_native.sh`, or set `minSdk = 24` in `android/app/build.gradle.kts`.

**iOS: `ARView` or `sceneReconstruction` unavailable / deployment target errors.**
The target needs to be iOS 14. Run `bash tool/configure_native.sh`, then `cd ios && pod install`.

**iOS: `Signing for "Runner" requires a development team`.**
See [iOS signing](getting-started.md#ios-signing).

**iOS: the app crashes the moment it opens the camera.**
`NSCameraUsageDescription` is missing from `Info.plist`. Run `bash tool/configure_native.sh`.

**`configure_native.sh` fails with `python3: command not found` on Windows.**
The Microsoft Store alias for `python3` is a stub. Turn it off under *Settings → Apps → Advanced app settings → App execution aliases*, then put a real Python on the PATH as `python3`. Alternatively, add the two `Info.plist` keys in Xcode by hand.

**Gradle: `Unsupported class file major version`.**
Use JDK 17: `flutter config --jdk-dir <path-to-jdk-17>`.
