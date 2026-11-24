import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

/// Accumulates world-space points from the AR session into a single map.
///
/// Points are de-duplicated on a voxel grid ([voxelSize] metres), so scanning
/// the same wall repeatedly doesn't grow memory – only new space adds points.
class PointCloud {
  PointCloud({this.voxelSize = 0.02, this.maxPoints = 2000000});

  final double voxelSize;
  final int maxPoints;

  static const int _bits = 21;
  static const int _offset = 1 << (_bits - 1);
  static const int _mask = (1 << _bits) - 1;

  final HashSet<int> _voxels = HashSet<int>();
  Float32List _xyz = Float32List(3 * 65536);
  int _count = 0;

  double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  double maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;

  int get count => _count;
  bool get isFull => _count >= maxPoints;

  /// Backing buffer; only the first `count * 3` values are valid.
  Float32List get rawXyz => _xyz;

  /// A tight copy-free view of the valid points (x, y, z, x, y, z, ...).
  Float32List get xyz => Float32List.sublistView(_xyz, 0, _count * 3);

  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
  double get centerZ => (minZ + maxZ) / 2;

  /// Half the bounding-box diagonal.
  double get radius {
    if (_count == 0) return 0;
    final dx = maxX - minX, dy = maxY - minY, dz = maxZ - minZ;
    return math.sqrt(dx * dx + dy * dy + dz * dz) / 2;
  }

  /// Adds interleaved xyz points. Returns how many were new.
  int add(Float32List pts) {
    final inv = 1.0 / voxelSize;
    var added = 0;
    for (var i = 0; i + 2 < pts.length; i += 3) {
      if (_count >= maxPoints) break;
      final x = pts[i], y = pts[i + 1], z = pts[i + 2];
      if (!x.isFinite || !y.isFinite || !z.isFinite) continue;

      final ix = (x * inv).floor() + _offset;
      final iy = (y * inv).floor() + _offset;
      final iz = (z * inv).floor() + _offset;
      if (ix < 0 || iy < 0 || iz < 0 || ix > _mask || iy > _mask || iz > _mask) {
        continue;
      }
      final key = (ix << (2 * _bits)) | (iy << _bits) | iz;
      if (!_voxels.add(key)) continue;

      if ((_count + 1) * 3 > _xyz.length) {
        final grown = Float32List(_xyz.length * 2);
        grown.setRange(0, _count * 3, _xyz);
        _xyz = grown;
      }
      final o = _count * 3;
      _xyz[o] = x;
      _xyz[o + 1] = y;
      _xyz[o + 2] = z;
      _count++;
      added++;

      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (z < minZ) minZ = z;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
      if (z > maxZ) maxZ = z;
    }
    return added;
  }

  void clear() {
    _voxels.clear();
    _xyz = Float32List(3 * 65536);
    _count = 0;
    minX = minY = minZ = double.infinity;
    maxX = maxY = maxZ = -double.infinity;
  }
}
