import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'palette.dart';
import 'point_cloud.dart';

/// Builds a binary little-endian PLY (x, y, z float + height-coloured RGB).
/// Opens in Blender, MeshLab, CloudCompare, etc.
Uint8List buildPly(Float32List xyz, double minY, double maxY) {
  final n = xyz.length ~/ 3;
  final header = utf8.encode(
    'ply\n'
    'format binary_little_endian 1.0\n'
    'comment Created by Scan3D (units: metres, Y up)\n'
    'element vertex $n\n'
    'property float x\n'
    'property float y\n'
    'property float z\n'
    'property uchar red\n'
    'property uchar green\n'
    'property uchar blue\n'
    'end_header\n',
  );
  final out = Uint8List(header.length + n * 15);
  out.setAll(0, header);
  final bd = ByteData.sublistView(out);
  final range = math.max(1e-6, maxY - minY);
  var o = header.length;
  for (var i = 0; i < n; i++) {
    final x = xyz[i * 3], y = xyz[i * 3 + 1], z = xyz[i * 3 + 2];
    bd.setFloat32(o, x, Endian.little);
    bd.setFloat32(o + 4, y, Endian.little);
    bd.setFloat32(o + 8, z, Endian.little);
    final rgb = heightRgb((y - minY) / range);
    out[o + 12] = (rgb >> 16) & 0xFF;
    out[o + 13] = (rgb >> 8) & 0xFF;
    out[o + 14] = rgb & 0xFF;
    o += 15;
  }
  return out;
}

/// Writes the cloud to a temp .ply file off the UI thread and returns it.
Future<File> exportPly(PointCloud cloud) async {
  final xyz = Float32List.fromList(cloud.xyz);
  final minY = cloud.minY, maxY = cloud.maxY;
  final bytes = await Isolate.run(() => buildPly(xyz, minY, maxY));
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  final file = File('${dir.path}/scan3d_$stamp.ply');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
