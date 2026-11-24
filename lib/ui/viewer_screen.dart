import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../scan/ply_export.dart';
import '../scan/point_cloud.dart';
import 'cloud_painter.dart';

/// Interactive 3D viewer: drag to orbit, pinch to zoom, two fingers to pan.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.cloud, required this.trail});

  final PointCloud cloud;
  final List<double> trail;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  static const double _defaultYaw = 0.6, _defaultPitch = 0.55;

  double _yaw = _defaultYaw, _pitch = _defaultPitch, _zoom = 1, _pointSize = 2;
  Offset _pan = Offset.zero;
  double _startZoom = 1;
  bool _showPath = true;
  bool _exporting = false;

  void _setView({required double yaw, required double pitch}) => setState(() {
        _yaw = yaw;
        _pitch = pitch;
        _zoom = 1;
        _pan = Offset.zero;
      });

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final file = await exportPly(widget.cloud);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/octet-stream')],
        subject: '3D scan (${widget.cloud.count} points)',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = widget.cloud;
    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('3D map'),
        actions: [
          IconButton(
            tooltip: 'Top-down map',
            onPressed: () => _setView(yaw: 0, pitch: math.pi / 2),
            icon: const Icon(Icons.map_outlined),
          ),
          IconButton(
            tooltip: '3D view',
            onPressed: () => _setView(yaw: _defaultYaw, pitch: _defaultPitch),
            icon: const Icon(Icons.threed_rotation),
          ),
          IconButton(
            tooltip: 'Show camera path',
            onPressed: () => setState(() => _showPath = !_showPath),
            icon: Icon(_showPath ? Icons.route : Icons.route_outlined),
          ),
          IconButton(
            tooltip: 'Export .ply',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: GestureDetector(
            onScaleStart: (_) => _startZoom = _zoom,
            onScaleUpdate: (d) => setState(() {
              if (d.pointerCount == 1) {
                _yaw -= d.focalPointDelta.dx * 0.01;
                _pitch = (_pitch + d.focalPointDelta.dy * 0.01).clamp(-math.pi / 2, math.pi / 2);
              } else {
                _zoom = (_startZoom * d.scale).clamp(0.2, 30.0);
                _pan += d.focalPointDelta;
              }
            }),
            onDoubleTap: () => _setView(yaw: _defaultYaw, pitch: _defaultPitch),
            child: SizedBox.expand(
              child: CustomPaint(
                painter: CloudPainter(
                  cloud: cloud,
                  revision: cloud.count,
                  yaw: _yaw,
                  pitch: _pitch,
                  zoom: _zoom,
                  pan: _pan,
                  pointSize: _pointSize,
                  trail: _showPath ? widget.trail : null,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(children: [
              Text(
                '${cloud.count} pts · '
                '${(cloud.maxX - cloud.minX).toStringAsFixed(1)} × '
                '${(cloud.maxZ - cloud.minZ).toStringAsFixed(1)} × '
                '${(cloud.maxY - cloud.minY).toStringAsFixed(1)} m',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              const Icon(Icons.grain, size: 16),
              SizedBox(
                width: 120,
                child: Slider(
                  min: 1,
                  max: 6,
                  value: _pointSize,
                  onChanged: (v) => setState(() => _pointSize = v),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
