import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../scan/palette.dart';
import '../scan/point_cloud.dart';

/// Renders a [PointCloud] with an orbit camera (orthographic projection).
///
/// `pitch = pi/2` gives a top-down floor-plan style map; smaller values tilt
/// into a 3D view. Points are coloured by height.
class CloudPainter extends CustomPainter {
  CloudPainter({
    required this.cloud,
    required this.revision,
    this.yaw = 0,
    this.pitch = math.pi / 2,
    this.zoom = 1,
    this.pan = Offset.zero,
    this.pointSize = 2,
    this.maxDrawPoints = 150000,
    this.trail,
    this.camera,
    this.forward,
  });

  final PointCloud cloud;

  /// Bump whenever the cloud changes so the painter repaints.
  final int revision;
  final double yaw, pitch, zoom, pointSize;
  final Offset pan;
  final int maxDrawPoints;

  /// Camera path as flat xyz list.
  final List<double>? trail;
  final List<double>? camera;
  final List<double>? forward;

  static const int _bands = 24;
  static final List<Color> _bandColors = List.generate(
    _bands,
    (i) => Color(0xFF000000 | heightRgb(i / (_bands - 1))),
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);

    final n = cloud.count;
    final double cx, cy, cz, radius;
    if (n > 0) {
      cx = cloud.centerX;
      cy = cloud.centerY;
      cz = cloud.centerZ;
      radius = math.max(0.75, cloud.radius);
    } else if (camera != null) {
      cx = camera![0];
      cy = camera![1];
      cz = camera![2];
      radius = 1.5;
    } else {
      return;
    }

    final ox = size.width / 2 + pan.dx;
    final oy = size.height / 2 + pan.dy;
    final scale = 0.5 * math.min(size.width, size.height) / radius * zoom;
    final cyw = math.cos(yaw), syw = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);

    Offset project(double x, double y, double z) {
      final dx = x - cx, dy = y - cy, dz = z - cz;
      final x1 = dx * cyw - dz * syw;
      final z1 = dx * syw + dz * cyw;
      final y2 = dy * cp - z1 * sp;
      return Offset(ox + x1 * scale, oy - y2 * scale);
    }

    if (n > 0) {
      final xyz = cloud.rawXyz;
      final step = math.max(1, (n / maxDrawPoints).ceil());
      final m = (n + step - 1) ~/ step;
      final pos = Float32List(m * 2);
      final band = Uint8List(m);
      final counts = Int32List(_bands);
      final minY = cloud.minY;
      final invRange = 1 / math.max(1e-3, cloud.maxY - cloud.minY);

      var k = 0;
      for (var i = 0; i < n; i += step) {
        final j = i * 3;
        final dx = xyz[j] - cx, dy = xyz[j + 1] - cy, dz = xyz[j + 2] - cz;
        final x1 = dx * cyw - dz * syw;
        final z1 = dx * syw + dz * cyw;
        final y2 = dy * cp - z1 * sp;
        pos[k * 2] = ox + x1 * scale;
        pos[k * 2 + 1] = oy - y2 * scale;
        final b = ((xyz[j + 1] - minY) * invRange * (_bands - 1))
            .round()
            .clamp(0, _bands - 1);
        band[k] = b;
        counts[b]++;
        k++;
      }

      // Bucket by colour so each band is a single drawRawPoints call.
      final offsets = Int32List(_bands + 1);
      for (var b = 0; b < _bands; b++) {
        offsets[b + 1] = offsets[b] + counts[b];
      }
      final cursor = Int32List.fromList(offsets.sublist(0, _bands));
      final sorted = Float32List(k * 2);
      for (var i = 0; i < k; i++) {
        final d = cursor[band[i]]++ * 2;
        sorted[d] = pos[i * 2];
        sorted[d + 1] = pos[i * 2 + 1];
      }

      final paint = Paint()
        ..strokeWidth = pointSize
        ..strokeCap = StrokeCap.round;
      for (var b = 0; b < _bands; b++) {
        if (counts[b] == 0) continue;
        paint.color = _bandColors[b];
        canvas.drawRawPoints(
          PointMode.points,
          Float32List.sublistView(sorted, offsets[b] * 2, offsets[b + 1] * 2),
          paint,
        );
      }
    }

    // Camera path.
    final t = trail;
    if (t != null && t.length >= 6) {
      final path = Path();
      final first = project(t[0], t[1], t[2]);
      path.moveTo(first.dx, first.dy);
      for (var i = 3; i + 2 < t.length; i += 3) {
        final p = project(t[i], t[i + 1], t[i + 2]);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white70,
      );
    }

    // Current camera position + heading.
    final c = camera;
    if (c != null) {
      final p = project(c[0], c[1], c[2]);
      final f = forward;
      if (f != null) {
        final tip = project(c[0] + f[0] * 0.3, c[1] + f[1] * 0.3, c[2] + f[2] * 0.3);
        var d = tip - p;
        if (d.distance > 0.01) {
          d = d / d.distance;
          final normal = Offset(-d.dy, d.dx);
          final cone = Path()
            ..moveTo(p.dx, p.dy)
            ..lineTo(p.dx + d.dx * 18 + normal.dx * 8, p.dy + d.dy * 18 + normal.dy * 8)
            ..lineTo(p.dx + d.dx * 18 - normal.dx * 8, p.dy + d.dy * 18 - normal.dy * 8)
            ..close();
          canvas.drawPath(cone, Paint()..color = Colors.white38);
        }
      }
      canvas.drawCircle(p, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black,
      );
    }
  }

  @override
  bool shouldRepaint(CloudPainter old) =>
      old.revision != revision ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.pointSize != pointSize ||
      old.camera != camera;
}
