#if !targetEnvironment(simulator)
  import ARKit
  import Flutter
  import RealityKit
  import UIKit

  /// Runs the ARKit session inside a RealityKit ARView.
  ///
  /// * LiDAR devices: scene reconstruction meshes are shown live over the
  ///   camera, and their vertices (in world space) are streamed to Flutter.
  /// * Other devices: ARKit's raw feature points are streamed (sparse map).
  final class ScanEngine: NSObject, ARSessionDelegate {
    static var hasLidar: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }

    var sink: FlutterEventSink?
    var scanning = false {
      didSet {
        // Re-send every mesh when recording starts so nothing seen before is lost.
        if scanning && !oldValue, let anchors = arView?.session.currentFrame?.anchors {
          markDirty(anchors)
        }
      }
    }

    private weak var arView: ARView?
    private var running = false
    private var lastEmit: TimeInterval = 0
    private var dirtyAnchors = Set<UUID>()
    private var busy = false
    private let work = DispatchQueue(label: "scan3d.mesh", qos: .userInitiated)

    func makeView(frame: CGRect) -> ARView {
      if let old = arView { old.session.pause() }
      let view = ARView(frame: frame, cameraMode: .ar, automaticallyConfigureSession: false)
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.renderOptions.insert(.disableMotionBlur)
      if Self.hasLidar {
        view.debugOptions.insert(.showSceneUnderstanding)
      } else {
        view.debugOptions.insert(.showFeaturePoints)
      }
      view.session.delegate = self
      arView = view
      running = false
      dirtyAnchors.removeAll()
      resume()
      return view
    }

    func resume() {
      guard let view = arView, !running else { return }
      let config = ARWorldTrackingConfiguration()
      config.planeDetection = [.horizontal, .vertical]
      config.environmentTexturing = .none
      if Self.hasLidar {
        config.sceneReconstruction = .mesh
      }
      // Running the same config again resumes without resetting the world origin.
      view.session.run(config)
      running = true
    }

    func pause() {
      guard running else { return }
      arView?.session.pause()
      running = false
    }

    // MARK: ARSessionDelegate (called on the main queue)

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { markDirty(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { markDirty(anchors) }

    private func markDirty(_ anchors: [ARAnchor]) {
      for anchor in anchors where anchor is ARMeshAnchor {
        dirtyAnchors.insert(anchor.identifier)
      }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
      guard frame.timestamp - lastEmit >= 0.25 else { return }
      lastEmit = frame.timestamp

      let t = frame.camera.transform
      var payload: [String: Any] = [
        "tracking": Self.trackingName(frame.camera.trackingState),
        "camera": [Double(t.columns.3.x), Double(t.columns.3.y), Double(t.columns.3.z)],
        "forward": [Double(-t.columns.2.x), Double(-t.columns.2.y), Double(-t.columns.2.z)],
      ]

      guard scanning, case .normal = frame.camera.trackingState else {
        sink?(payload)
        return
      }

      if Self.hasLidar {
        // Pull out only what we need so the ARFrame itself isn't retained.
        let meshes: [ARMeshAnchor] = busy ? [] : frame.anchors
          .compactMap { $0 as? ARMeshAnchor }
          .filter { dirtyAnchors.contains($0.identifier) }
        guard !meshes.isEmpty else {
          sink?(payload)
          return
        }
        dirtyAnchors.subtract(meshes.map { $0.identifier })
        busy = true
        let basePayload = payload
        work.async { [weak self] in
          let data = ScanEngine.worldVertices(meshes)
          DispatchQueue.main.async {
            guard let self else { return }
            self.busy = false
            var out = basePayload
            out["points"] = FlutterStandardTypedData(float32: data)
            out["source"] = "mesh"
            self.sink?(out)
          }
        }
      } else {
        if let fp = frame.rawFeaturePoints, !fp.points.isEmpty {
          var arr = [Float]()
          arr.reserveCapacity(fp.points.count * 3)
          for p in fp.points {
            arr.append(p.x)
            arr.append(p.y)
            arr.append(p.z)
          }
          payload["points"] = FlutterStandardTypedData(float32: arr.withUnsafeBufferPointer { Data(buffer: $0) })
          payload["source"] = "features"
        }
        sink?(payload)
      }
    }

    /// Transforms mesh vertices from anchor space into world space.
    private static func worldVertices(_ anchors: [ARMeshAnchor]) -> Data {
      var out = [Float]()
      for anchor in anchors {
        let src = anchor.geometry.vertices
        let base = src.buffer.contents().advanced(by: src.offset)
        let m = anchor.transform
        out.reserveCapacity(out.count + src.count * 3)
        for i in 0..<src.count {
          let v = base.advanced(by: i * src.stride).assumingMemoryBound(to: Float.self)
          let w = m * SIMD4<Float>(v[0], v[1], v[2], 1)
          out.append(w.x)
          out.append(w.y)
          out.append(w.z)
        }
      }
      return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func trackingName(_ state: ARCamera.TrackingState) -> String {
      switch state {
      case .normal: return "normal"
      case .notAvailable: return "unavailable"
      case .limited(let reason):
        switch reason {
        case .initializing: return "initializing"
        case .excessiveMotion: return "excessive_motion"
        case .insufficientFeatures: return "insufficient_features"
        case .relocalizing: return "relocalizing"
        @unknown default: return "initializing"
        }
      }
    }
  }
#endif
