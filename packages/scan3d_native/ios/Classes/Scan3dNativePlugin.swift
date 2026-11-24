import ARKit
import AVFoundation
import Flutter
import UIKit

public class Scan3dNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let engine = ScanEngine()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = Scan3dNativePlugin()
    let channel = FlutterMethodChannel(name: "scan3d/control", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "scan3d/frames", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
    registrar.register(ArViewFactory(engine: instance.engine), withId: "scan3d/ar_view")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkSupport":
      let ok = ARWorldTrackingConfiguration.isSupported
      result(["status": ok ? "SUPPORTED" : "UNSUPPORTED", "supported": ok])

    case "requestPermission":
      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
        result(true)
      case .notDetermined:
        AVCaptureDevice.requestAccess(for: .video) { granted in
          DispatchQueue.main.async { result(granted) }
        }
      default:
        result(false)
      }

    case "prepare":
      #if targetEnvironment(simulator)
        result(["ok": false, "message": "AR scanning needs a physical iPhone or iPad."])
      #else
        if ARWorldTrackingConfiguration.isSupported {
          result(["ok": true, "mode": ScanEngine.hasLidar ? "lidar" : "features"])
        } else {
          result(["ok": false, "message": "ARKit world tracking is not supported on this device."])
        }
      #endif

    case "setScanning":
      engine.scanning = (call.arguments as? Bool) ?? false
      result(nil)

    case "resumeSession":
      engine.resume()
      result(nil)

    case "pauseSession":
      engine.pause()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    engine.sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    engine.sink = nil
    return nil
  }
}

// MARK: - Platform view

final class ArViewFactory: NSObject, FlutterPlatformViewFactory {
  private let engine: ScanEngine

  init(engine: ScanEngine) {
    self.engine = engine
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    ArPlatformView(frame: frame, engine: engine)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class ArPlatformView: NSObject, FlutterPlatformView {
  private let content: UIView

  init(frame: CGRect, engine: ScanEngine) {
    #if targetEnvironment(simulator)
      let label = UILabel(frame: frame)
      label.text = "AR needs a physical device"
      label.textAlignment = .center
      label.textColor = .white
      content = label
    #else
      content = engine.makeView(frame: frame)
    #endif
    super.init()
  }

  func view() -> UIView { content }
}

#if targetEnvironment(simulator)
  /// Simulator stub: ARKit/RealityKit AR views are device-only.
  final class ScanEngine: NSObject {
    var sink: FlutterEventSink?
    var scanning = false
    func resume() {}
    func pause() {}
  }
#endif
