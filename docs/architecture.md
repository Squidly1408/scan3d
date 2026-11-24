# Architecture

Scan3D has two layers. The platform plugin (`packages/scan3d_native`) owns the camera and the AR session, and turns what the device sees into world-space points. The Flutter app (`lib/`) accumulates those points, draws them, and exports them.

```
 ┌──────────── native (Kotlin / Swift) ────────────┐        ┌──────────────── Flutter (Dart) ───────────────┐
 │                                                 │        │                                                │
 │  ARCore / ARKit session                         │ frames │  ScanScreen                                    │
 │    │                                            │ ~4 Hz  │    │  PointCloud.add()  (2 cm voxel de-dup)    │
 │    ├─ camera image ──► AR view (platform view)  │ ─────► │    │  camera trail                             │
 │    └─ depth / mesh / features                   │        │    ▼                                           │
 │         └─► world-space xyz Float32 ────────────┼────────┤  CloudPainter  (mini-map, 3D viewer)          │
 │                                                 │        │  exportPly()   (background isolate → .ply)    │
 │  ◄────── requestPermission / prepare /          │control │                                                │
 │          setScanning / pause / resume ──────────┼◄───────┤                                                │
 └─────────────────────────────────────────────────┘        └────────────────────────────────────────────────┘
```

## Native side

Each platform has a `Scan3dNativePlugin` and a `ScanEngine`. The plugin registers the method and event channels and the `scan3d/ar_view` platform view, then hands the work to the engine.

### Android: `ScanEngine.kt`

- `prepare()` installs ARCore if needed, creates the `Session`, and turns on `DepthMode.AUTOMATIC` when the device supports it. That choice sets the mode reported to Dart: `depth` or `features`.
- The AR view is a `GLSurfaceView`, embedded with hybrid composition (`initExpensiveAndroidView`) because ARCore draws to a GL texture. `BackgroundRenderer` draws the camera image.
- Every 250 ms on the GL thread, `emit()` builds a payload:
  - **Depth mode:** `acquireDepthImage16Bits()` reads every second pixel. Depths between 0.2 m and 4 m are unprojected with the camera intrinsics, scaled to the depth image's resolution, and transformed by the camera pose into world space.
  - **Feature mode:** ARCore's point cloud, keeping points with confidence of at least 0.3.
- Payloads go to Flutter through the main thread.

### iOS: `ScanEngine.swift`

- Runs an `ARWorldTrackingConfiguration` inside a RealityKit `ARView`, with plane detection on.
- **LiDAR:** turns on `sceneReconstruction = .mesh`, and the live mesh shows over the camera through `.showSceneUnderstanding`. The engine tracks which `ARMeshAnchor`s changed. Every 250 ms it transforms the vertices of the changed anchors into world space on a background queue and sends them. When recording starts, every anchor is marked dirty, so geometry seen before you pressed record isn't lost.
- **No LiDAR:** sends `rawFeaturePoints` and shows them over the camera.
- The whole engine is compiled out for the simulator with `#if !targetEnvironment(simulator)`.

Both platforms use the same convention: metres, Y up, origin where the session started.

## Flutter side

### `ScanScreen`

Drives the session: permission, then `prepare`, then subscribing to `frames()`. It also pauses and resumes the session on app lifecycle changes and when the viewer opens. While recording, each frame's points go into `PointCloud.add()`, but only when tracking is `normal`. Points captured while tracking is limited tend to be misplaced. The camera position is added to a trail whenever it has moved more than 5 cm.

### `PointCloud` (`lib/scan/point_cloud.dart`)

An append-only buffer with a voxel hash set to remove duplicates:

- Each point is quantised to a 2 cm cell, and the three 21-bit cell indices are packed into one 63-bit `int` key. That covers about ±20 km at 2 cm, far more than a room needs.
- If the key is already in the set, the point is dropped. Sweeping the same wall again costs CPU but no memory.
- Points live in a growable `Float32List`. The capacity doubles as needed, starting at 65,536 points.
- At 2,000,000 points the cloud is full, and `ScanScreen` stops recording.
- The bounding box is kept up to date as points arrive, for camera framing and height colouring.

### `CloudPainter` (`lib/ui/cloud_painter.dart`)

A `CustomPainter` that projects the cloud with an orthographic orbit camera (yaw, pitch, zoom, pan) and draws it with `Canvas.drawRawPoints`, coloured by height using `heightRgb` from `palette.dart`. The mini-map on the scan screen and the full viewer both use it. The top-down view is the same painter with pitch at 90°.

### Export (`lib/scan/ply_export.dart`)

`exportPly()` copies the valid part of the buffer and builds the file inside `Isolate.run`, so a cloud of several million points doesn't block the UI. It writes the result to the temp directory, and the viewer passes it to `share_plus`. The format is described in [export-format.md](export-format.md).

## Design choices

- **Points rather than meshes.** ARCore has no mesh API and feature points are always sparse, so a point cloud is the one format every device can produce. LiDAR mesh export is a natural next step. See the roadmap in the [changelog](../CHANGELOG.md#roadmap).
- **About 4 Hz updates.** Sending every frame (30 to 60 Hz) would flood the platform channel with large `Float32List`s for little gain. Depth and mesh data change slowly compared with the frame rate.
- **De-duplication in Dart, not native code.** It keeps the platform code thin and both platforms consistent, and it can be unit-tested.
