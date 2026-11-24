import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scan3d_native/scan3d_native.dart';

import '../scan/point_cloud.dart';
import 'cloud_painter.dart';
import 'viewer_screen.dart';

enum _Phase { starting, ready, error }

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  final PointCloud _cloud = PointCloud(voxelSize: 0.02);
  final List<double> _trail = [];
  StreamSubscription<ScanFrame>? _sub;

  _Phase _phase = _Phase.starting;
  String _error = '';
  String _mode = '';
  String _tracking = 'initializing';
  bool _scanning = false;
  bool _inViewer = false;
  int _revision = 0;
  List<double>? _camera;
  List<double>? _forward;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    Scan3dNative.setScanning(false);
    Scan3dNative.pauseSession();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_phase != _Phase.ready || _inViewer) return;
    if (state == AppLifecycleState.paused) {
      Scan3dNative.pauseSession();
    } else if (state == AppLifecycleState.resumed) {
      Scan3dNative.resumeSession();
    }
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.starting);
    try {
      if (!await Scan3dNative.requestPermission()) {
        return _fail('Camera permission is needed to scan. '
            'Enable it in Settings, then try again.');
      }
      final r = await Scan3dNative.prepare();
      if (!r.ok) return _fail(r.message ?? 'AR is not available on this device.');
      _mode = r.mode;
      _sub ??= Scan3dNative.frames().listen(
        _onFrame,
        onError: (Object e) => _fail('AR session error: $e'),
      );
      if (mounted) setState(() => _phase = _Phase.ready);
    } on PlatformException catch (e) {
      _fail(e.message ?? e.code);
    } on MissingPluginException {
      _fail('The native AR plugin is not available on this platform.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _error = message;
    });
  }

  void _onFrame(ScanFrame f) {
    if (!mounted) return;
    final pts = f.points;
    if (_scanning && pts != null && f.tracking == 'normal') {
      _cloud.add(pts);
      if (_cloud.isFull) _setScanning(false);
    }
    final c = f.camera;
    if (_scanning && c != null) {
      final n = _trail.length;
      if (n < 3 ||
          _dist(c, _trail[n - 3], _trail[n - 2], _trail[n - 1]) > 0.05) {
        _trail.addAll(c);
      }
    }
    setState(() {
      _tracking = f.tracking;
      _camera = c;
      _forward = f.forward;
      _revision++;
    });
  }

  static double _dist(List<double> a, double x, double y, double z) {
    final dx = a[0] - x, dy = a[1] - y, dz = a[2] - z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  Future<void> _setScanning(bool on) async {
    setState(() => _scanning = on);
    await Scan3dNative.setScanning(on);
  }

  void _reset() {
    setState(() {
      _cloud.clear();
      _trail.clear();
      _revision++;
    });
  }

  Future<void> _finish() async {
    if (_cloud.count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing captured yet – tap record and move around.')),
      );
      return;
    }
    await _setScanning(false);
    await Scan3dNative.pauseSession();
    _inViewer = true;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ViewerScreen(cloud: _cloud, trail: List.of(_trail)),
    ));
    _inViewer = false;
    if (mounted) await Scan3dNative.resumeSession();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_phase) {
        _Phase.starting => const Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Starting AR session…'),
            ]),
          ),
        _Phase.error => _errorView(),
        _Phase.ready => _scanView(),
      },
    );
  }

  Widget _errorView() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 16),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(onPressed: _start, child: const Text('Try again')),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ]),
          ),
        ),
      );

  Widget _scanView() {
    final theme = Theme.of(context);
    return Stack(children: [
      const Positioned.fill(child: ScanArView()),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Chip(
                    icon: _tracking == 'normal' ? Icons.check_circle : Icons.info_outline,
                    color: _tracking == 'normal' ? Colors.greenAccent : Colors.amberAccent,
                    text: _trackingLabel(_tracking),
                  ),
                  const SizedBox(height: 6),
                  _Chip(icon: Icons.sensors, text: _modeLabel(_mode)),
                  const SizedBox(height: 6),
                  _Chip(
                    icon: Icons.scatter_plot_outlined,
                    text: '${_formatCount(_cloud.count)} points'
                        '${_cloud.isFull ? ' (limit reached)' : ''}',
                  ),
                ]),
              ),
              _MiniMap(
                cloud: _cloud,
                revision: _revision,
                trail: _trail,
                camera: _camera,
                forward: _forward,
              ),
            ]),
            const Spacer(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              IconButton.filledTonal(
                iconSize: 28,
                tooltip: 'Clear',
                onPressed: _cloud.count == 0 ? null : _reset,
                icon: const Icon(Icons.delete_outline),
              ),
              GestureDetector(
                onTap: () => _setScanning(!_scanning),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _scanning ? Colors.redAccent : theme.colorScheme.primary,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: Icon(
                    _scanning ? Icons.pause : Icons.fiber_manual_record,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton.filledTonal(
                iconSize: 28,
                tooltip: 'View 3D map',
                onPressed: _finish,
                icon: const Icon(Icons.view_in_ar),
              ),
            ]),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    ]);
  }

  static String _formatCount(int n) =>
      n >= 1000000 ? '${(n / 1e6).toStringAsFixed(2)}M' : n >= 1000 ? '${(n / 1e3).toStringAsFixed(1)}k' : '$n';

  static String _modeLabel(String m) => switch (m) {
        'lidar' => 'LiDAR mesh',
        'depth' => 'ARCore depth',
        'features' => 'Feature points (sparse)',
        _ => 'AR',
      };

  static String _trackingLabel(String t) => switch (t) {
        'normal' => 'Tracking',
        'initializing' => 'Move the phone slowly to start',
        'insufficient_features' => 'Point at textured surfaces',
        'insufficient_light' => 'Need more light',
        'excessive_motion' => 'Slow down',
        'relocalizing' => 'Relocalizing…',
        _ => 'Tracking unavailable',
      };
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.color = Colors.white});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

/// Live top-down preview of the map being built.
class _MiniMap extends StatelessWidget {
  const _MiniMap({
    required this.cloud,
    required this.revision,
    required this.trail,
    this.camera,
    this.forward,
  });

  final PointCloud cloud;
  final int revision;
  final List<double> trail;
  final List<double>? camera;
  final List<double>? forward;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 140,
          height: 140,
          color: Colors.black.withValues(alpha: 0.6),
          child: CustomPaint(
            painter: CloudPainter(
              cloud: cloud,
              revision: revision,
              pointSize: 1.5,
              maxDrawPoints: 40000,
              zoom: 0.9,
              trail: trail,
              camera: camera,
              forward: forward,
            ),
          ),
        ),
      );
}
