import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One update from the native AR session (~4 per second).
class ScanFrame {
  ScanFrame({
    required this.tracking,
    this.points,
    this.camera,
    this.forward,
    this.source,
  });

  /// normal | initializing | insufficient_features | insufficient_light |
  /// excessive_motion | relocalizing | unavailable
  final String tracking;

  /// New world-space points (x, y, z interleaved, metres, Y up). Only sent
  /// while scanning is enabled.
  final Float32List? points;

  /// Camera position in world space.
  final List<double>? camera;

  /// Unit vector the camera is looking along.
  final List<double>? forward;

  /// mesh | depth | features
  final String? source;

  factory ScanFrame.fromMap(Object? event) {
    final m = (event as Map).cast<Object?, Object?>();
    List<double>? vec(Object? v) =>
        v == null ? null : (v as List).map((e) => (e as num).toDouble()).toList();
    return ScanFrame(
      tracking: (m['tracking'] as String?) ?? 'unavailable',
      points: m['points'] as Float32List?,
      camera: vec(m['camera']),
      forward: vec(m['forward']),
      source: m['source'] as String?,
    );
  }
}

class PrepareResult {
  PrepareResult({required this.ok, required this.mode, this.message});
  final bool ok;

  /// lidar | depth | features
  final String mode;
  final String? message;
}

class Scan3dNative {
  static const MethodChannel _control = MethodChannel('scan3d/control');
  static const EventChannel _frames = EventChannel('scan3d/frames');
  static const String viewType = 'scan3d/ar_view';

  static Stream<ScanFrame> frames() =>
      _frames.receiveBroadcastStream().map(ScanFrame.fromMap);

  static Future<bool> requestPermission() async =>
      (await _control.invokeMethod<bool>('requestPermission')) ?? false;

  /// Checks support / installs ARCore if needed and creates the AR session.
  static Future<PrepareResult> prepare() async {
    final r = (await _control.invokeMapMethod<String, Object?>('prepare')) ?? {};
    return PrepareResult(
      ok: r['ok'] == true,
      mode: (r['mode'] as String?) ?? '',
      message: r['message'] as String?,
    );
  }

  static Future<void> setScanning(bool on) => _control.invokeMethod('setScanning', on);
  static Future<void> pauseSession() => _control.invokeMethod('pauseSession');
  static Future<void> resumeSession() => _control.invokeMethod('resumeSession');
}

/// Full-screen camera preview with the AR session running inside it.
class ScanArView extends StatelessWidget {
  const ScanArView({super.key});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    if (Platform.isAndroid) {
      // Hybrid composition: required for ARCore's GLSurfaceView.
      return PlatformViewLink(
        viewType: Scan3dNative.viewType,
        surfaceFactory: (context, controller) => AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        ),
        onCreatePlatformView: (params) => PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: Scan3dNative.viewType,
          layoutDirection: TextDirection.ltr,
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create(),
      );
    }
    if (Platform.isIOS) {
      return const UiKitView(
        viewType: Scan3dNative.viewType,
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    return const Center(child: Text('AR scanning needs an Android or iOS device.'));
  }
}
