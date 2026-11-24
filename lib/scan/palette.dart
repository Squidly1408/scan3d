/// Height colour ramp shared by the on-screen renderer and the PLY exporter.
///
/// Returns 0xRRGGBB for [t] in 0..1, going blue (low) → cyan → green →
/// yellow → red (high). Pure Dart so it also works inside background isolates.
int heightRgb(double t) {
  if (t.isNaN) t = 0;
  t = t.clamp(0.0, 1.0);
  const v = 1.0, s = 0.85;
  final h = (1 - t) * 4.0; // hue 240°..0° expressed in 60° sectors
  final i = h.floor().clamp(0, 4);
  final f = h - i;
  final p = v * (1 - s);
  final q = v * (1 - s * f);
  final u = v * (1 - s * (1 - f));
  double r, g, b;
  switch (i) {
    case 0:
      (r, g, b) = (v, u, p);
    case 1:
      (r, g, b) = (q, v, p);
    case 2:
      (r, g, b) = (p, v, u);
    case 3:
      (r, g, b) = (p, q, v);
    default:
      (r, g, b) = (u, p, v);
  }
  return ((r * 255).round() << 16) | ((g * 255).round() << 8) | (b * 255).round();
}
