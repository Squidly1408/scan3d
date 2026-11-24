import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan3d/scan/palette.dart';
import 'package:scan3d/scan/ply_export.dart';
import 'package:scan3d/scan/point_cloud.dart';

void main() {
  test('voxel grid de-duplicates nearby points', () {
    final cloud = PointCloud(voxelSize: 0.05);
    final added = cloud.add(Float32List.fromList([
      0.00, 0.00, 0.00,
      0.01, 0.01, 0.01, // same voxel
      0.20, 0.00, 0.00, // new voxel
      -0.20, 1.00, -3.0, // new voxel (negative coords)
      double.nan, 0, 0, // ignored
    ]));
    expect(added, 3);
    expect(cloud.count, 3);
    expect(cloud.minY, 0);
    expect(cloud.maxY, 1);
    expect(cloud.add(Float32List.fromList([0.2, 0.0, 0.0])), 0);
  });

  test('respects maxPoints and grows its buffer', () {
    final cloud = PointCloud(voxelSize: 0.01, maxPoints: 100000);
    final pts = Float32List(3 * 120000);
    for (var i = 0; i < 120000; i++) {
      pts[i * 3] = i * 0.02;
    }
    cloud.add(pts);
    expect(cloud.count, 100000);
    expect(cloud.isFull, isTrue);
  });

  test('PLY has a valid header and payload size', () {
    final bytes = buildPly(Float32List.fromList([0, 0, 0, 1, 2, 3]), 0, 2);
    final text = latin1.decode(bytes);
    final headerEnd = text.indexOf('end_header\n') + 'end_header\n'.length;
    expect(text, startsWith('ply\nformat binary_little_endian 1.0'));
    expect(text, contains('element vertex 2'));
    expect(bytes.length - headerEnd, 2 * 15);
  });

  test('palette goes from blue to red', () {
    expect(heightRgb(0) & 0xFF, greaterThan(200)); // blue channel high
    expect((heightRgb(1) >> 16) & 0xFF, greaterThan(200)); // red channel high
  });
}
