# Native bridge

The Dart API is in `packages/scan3d_native/lib/scan3d_native.dart`. It wraps two channels and one platform view.

| Name | Type | Purpose |
|---|---|---|
| `scan3d/control` | `MethodChannel` | Commands from Dart to native code |
| `scan3d/frames` | `EventChannel` | Stream of session updates from native code to Dart |
| `scan3d/ar_view` | Platform view | Camera preview with the AR session running inside it |

All messages use Flutter's `StandardMessageCodec`.

## `scan3d/control`

| Method | Argument | Returns | Notes |
|---|---|---|---|
| `requestPermission` | none | `bool` | Asks for camera access. `false` if denied. |
| `prepare` | none | `{ok: bool, mode: String, message: String?}` | Checks support and creates the session. Android may start the ARCore install flow and return `ok: false` with a message telling the user to try again. |
| `setScanning` | `bool` | `null` | Turns point output on or off in `frames`. Tracking events keep coming either way. |
| `pauseSession` | none | `null` | Stops the camera and AR session. World tracking is kept where the platform allows it. |
| `resumeSession` | none | `null` | Resumes without resetting the world origin. |
| `checkSupport` | none | `{status: String, supported: bool}` | **Android only, unused by the app.** Returns the raw `ArCoreApk.Availability`. |

`mode` is one of:

| Value | Platform | Meaning |
|---|---|---|
| `lidar` | iOS | Scene reconstruction mesh available |
| `depth` | Android | ARCore Depth API available |
| `features` | both | Sparse feature points only |

Dart wraps these as `Scan3dNative.requestPermission()`, `prepare()`, `setScanning(bool)`, `pauseSession()` and `resumeSession()`.

## `scan3d/frames`

Native code sends one map about every 250 ms while the session runs. Dart receives it as a `ScanFrame`.

| Key | Type | Present | Meaning |
|---|---|---|---|
| `tracking` | `String` | always | `normal`, `initializing`, `insufficient_features`, `insufficient_light`, `excessive_motion`, `relocalizing` (iOS) or `unavailable` |
| `camera` | `List<double>` (3) | when tracking | Camera position in world space, metres |
| `forward` | `List<double>` (3) | when tracking | Unit vector the camera is looking along |
| `points` | `Float32List` | when scanning and new points exist | Interleaved `x, y, z` in world space |
| `source` | `String` | with `points` | `mesh`, `depth` or `features` |

On Android, `camera` and `forward` are only sent while tracking is `normal`. iOS always sends them.

### Coordinate system

- Units are metres.
- Right-handed, **+Y up** (gravity-aligned on both platforms).
- The origin is the device position when the session started, so each session is its own map.

### Volume

| Source | Points per event, typical |
|---|---|
| `depth` (ARCore, ~160×120 depth image, every 2nd pixel) | up to about 4,800 |
| `mesh` (LiDAR, changed anchors only) | from a few hundred to tens of thousands |
| `features` | tens to a few hundred |

The Dart-side voxel grid removes overlap between events, so native code doesn't need to.

## Errors

- A camera failure on resume is sent as an error on the event stream with code `camera` (Android). `ScanScreen` shows it as a session error.
- `requestPermission` on Android with no foreground activity fails with code `no_activity`.
- On a platform without the plugin, such as desktop or a widget test, the calls throw `MissingPluginException`. `ScanScreen` catches it and shows an error.

## Adding a field

1. Add it to the payload in `ScanEngine.kt` (`emit`) and `ScanEngine.swift` (`session(_:didUpdate:)`), using the same key on both.
2. Add it to `ScanFrame` and `ScanFrame.fromMap`. Parse it defensively, because native maps arrive as `Map<Object?, Object?>`.
3. Document it in the table above.
