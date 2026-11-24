"""Generates every Scan3D brand asset from one piece of geometry.

The mark is a room corner (floor + two walls) sampled as a regular point grid
and projected with a real perspective camera, the same kind of data the app
captures. Dots are coloured by height and scaled by depth. The wordmark is a
hand-drawn 5x7 dot-matrix face, so nothing depends on an installed font except
the banner tagline, which is outlined from Cascadia Mono (SIL OFL) at build
time.

    python tool/brand/generate.py

Writes:
    assets/brand/mark.svg, logo.svg, banner.svg, banner.png, mark.png
    android/app/src/main/res/mipmap-*/ic_launcher.png
    ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png

Needs Pillow; fontTools only for the banner tagline.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "brand"

# --- palette -----------------------------------------------------------------
BG = "#0D1117"
INK = "#E6EDF3"
MUTED = "#7D8590"
# Height ramp: floor -> top of wall. Teal in the middle is the app's seed colour.
RAMP = [(0.0, (0x3B, 0x5B, 0xFF)), (0.55, (0x00, 0xBF, 0xA5)), (1.0, (0xFF, 0xC2, 0x47))]


def ramp(t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    for (t0, c0), (t1, c1) in zip(RAMP, RAMP[1:]):
        if t <= t1:
            f = (t - t0) / (t1 - t0)
            return tuple(round(a + (b - a) * f) for a, b in zip(c0, c1))
    return RAMP[-1][1]


def hexc(c: tuple[int, int, int]) -> str:
    return "#%02X%02X%02X" % c


# --- the mark: a perspective point cloud of a room corner ---------------------
N = 7  # samples per edge


def corner_points():
    """Floor (y=0) and two walls (x=0, z=0), unit size, deduplicated."""
    pts = set()
    r = range(N)
    s = 1.0 / (N - 1)
    for a in r:
        for b in r:
            pts.add((a * s, 0.0, b * s))  # floor
            pts.add((0.0, a * s, b * s))  # left wall
            pts.add((a * s, b * s, 0.0))  # right wall
    return sorted(pts)


def project(points, size: float):
    """Perspective camera inside the room looking back into the corner."""
    eye = (2.7, 1.45, 1.85)
    target = (0.42, 0.42, 0.30)
    fwd = [t - e for t, e in zip(target, eye)]
    fl = math.sqrt(sum(v * v for v in fwd))
    fwd = [v / fl for v in fwd]
    up = (0.0, 1.0, 0.0)
    right = [fwd[1] * up[2] - fwd[2] * up[1], fwd[2] * up[0] - fwd[0] * up[2], fwd[0] * up[1] - fwd[1] * up[0]]
    rl = math.sqrt(sum(v * v for v in right))
    right = [v / rl for v in right]
    cup = [right[1] * fwd[2] - right[2] * fwd[1], right[2] * fwd[0] - right[0] * fwd[2], right[0] * fwd[1] - right[1] * fwd[0]]
    focal = 2.9

    out = []
    for p in points:
        d = [pi - ei for pi, ei in zip(p, eye)]
        x = sum(a * b for a, b in zip(d, right))
        y = sum(a * b for a, b in zip(d, cup))
        z = sum(a * b for a, b in zip(d, fwd))
        out.append((x * focal / z, -y * focal / z, z, p[1]))

    xs = [o[0] for o in out]
    ys = [o[1] for o in out]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys))
    k = size / span
    zmin = min(o[2] for o in out)
    dots = []
    for x, y, z, h in out:
        dots.append(((x - cx) * k, (y - cy) * k, zmin / z, h))
    # far first so near dots overlap them
    dots.sort(key=lambda d: d[2])
    return dots


def mark_dots(size: float, dot: float):
    """[(x, y, r, colour)] centred on 0,0 within a size x size box."""
    res = []
    for x, y, near, h in project(corner_points(), size):
        r = dot * (0.32 + 0.68 * near**2.2)
        res.append((x, y, r, ramp(h)))
    return res


# --- dot-matrix wordmark ------------------------------------------------------
GLYPHS = {
    "s": [
        ".....",
        ".....",
        ".####",
        "#....",
        ".###.",
        "....#",
        "####.",
    ],
    "c": [
        ".....",
        ".....",
        ".####",
        "#....",
        "#....",
        "#....",
        ".####",
    ],
    "a": [
        ".....",
        ".....",
        ".###.",
        "....#",
        ".####",
        "#...#",
        ".####",
    ],
    "n": [
        ".....",
        ".....",
        "####.",
        "#...#",
        "#...#",
        "#...#",
        "#...#",
    ],
    "3": [
        "####.",
        "....#",
        "....#",
        ".###.",
        "....#",
        "....#",
        "####.",
    ],
    "d": [
        "....#",
        "....#",
        ".####",
        "#...#",
        "#...#",
        "#...#",
        ".####",
    ],
}


def wordmark_dots(text: str, pitch: float):
    """[(x, y, accent)] top-left origin. Digits and what follows are accented."""
    dots = []
    x0 = 0.0
    accent = False
    for ch in text:
        if ch.isdigit():
            accent = True
        for row, line in enumerate(GLYPHS[ch]):
            for col, c in enumerate(line):
                if c == "#":
                    dots.append((x0 + col * pitch, row * pitch, accent))
        x0 += 6 * pitch
    width = x0 - 2 * pitch
    return dots, width, 6 * pitch


# --- tagline outlined from Cascadia Mono --------------------------------------
def text_path(text: str, font_file: Path, px: float, x: float, y: float) -> str | None:
    try:
        from fontTools.pens.svgPathPen import SVGPathPen
        from fontTools.pens.transformPen import TransformPen
        from fontTools.ttLib import TTFont
    except ImportError:
        return None
    if not font_file.exists():
        return None
    font = TTFont(str(font_file))
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = px / font["head"].unitsPerEm
    pen = SVGPathPen(gs)
    cursor = 0.0
    for ch in text:
        name = cmap.get(ord(ch))
        if name is None:
            continue
        g = gs[name]
        g.draw(TransformPen(pen, (scale, 0, 0, -scale, x + cursor * scale, y)))
        cursor += g.width
    return pen.getCommands()


def font_path() -> Path:
    env = os.environ.get("SCAN3D_BRAND_FONT")
    if env:
        return Path(env)
    for p in (
        Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts" / "CascadiaMono.ttf",
        Path("/usr/share/fonts/truetype/cascadia-code/CascadiaMono.ttf"),
        Path.home() / "Library/Fonts/CascadiaMono.ttf",
    ):
        if p.exists():
            return p
    return Path("CascadiaMono.ttf")


# --- writers ------------------------------------------------------------------
def f(v: float) -> str:
    return f"{v:.2f}".rstrip("0").rstrip(".")


def svg_dots(dots, ox: float, oy: float) -> str:
    return "\n".join(
        f'  <circle cx="{f(ox + x)}" cy="{f(oy + y)}" r="{f(r)}" fill="{hexc(c)}"/>' for x, y, r, c in dots
    )


def write_mark_svg():
    s = 512
    dots = mark_dots(330, 15)
    body = svg_dots(dots, s / 2, s / 2 + 6)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {s} {s}" width="{s}" height="{s}">\n'
        f"  <title>Scan3D</title>\n"
        f'  <rect width="{s}" height="{s}" rx="112" fill="{BG}"/>\n{body}\n</svg>\n'
    )
    (OUT / "mark.svg").write_text(svg, encoding="utf-8")


def wordmark_svg(ox, oy, pitch, r, ink=INK) -> str:
    dots, _, _ = wordmark_dots("scan3d", pitch)
    teal = hexc(ramp(0.55))
    return "\n".join(
        f'  <circle cx="{f(ox + x)}" cy="{f(oy + y)}" r="{f(r)}" fill="{teal if a else ink}"/>' for x, y, a in dots
    )


def write_logo_svg():
    """Horizontal lockup: tile + wordmark, transparent background."""
    tile = 160
    pitch = 13.5
    _, ww, _ = wordmark_dots("scan3d", pitch)
    gap = 40
    w = tile + gap + ww + 12
    h = tile
    tile_dots = svg_dots(mark_dots(104, 4.8), tile / 2, tile / 2 + 2)
    word = wordmark_svg(tile + gap + 6, (h - 6 * pitch) / 2, pitch, pitch * 0.36, ink="currentColor")
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {f(w)} {h}" width="{f(w)}" height="{h}" color="{INK}">\n'
        f"  <title>Scan3D</title>\n"
        f'  <rect width="{tile}" height="{tile}" rx="35" fill="{BG}"/>\n{tile_dots}\n{word}\n</svg>\n'
    )
    (OUT / "logo.svg").write_text(svg, encoding="utf-8")


def banner_scatter(w, h):
    """Faint far-field dots across the banner, like a sparse feature-point map."""
    import random

    rnd = random.Random(7)
    out = []
    for _ in range(170):
        x, y = rnd.uniform(0, w), rnd.uniform(0, h)
        if 70 < x < 560 and 70 < y < h - 70:
            continue
        out.append((x, y, rnd.uniform(0.9, 2.1), rnd.uniform(0.08, 0.22)))
    return out


def write_banner_svg():
    w, h = 1280, 640
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">',
        "  <title>Scan3D: a 3D map from your phone camera</title>",
        f'  <rect width="{w}" height="{h}" fill="{BG}"/>',
    ]
    for x, y, r, a in banner_scatter(w, h):
        parts.append(f'  <circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{INK}" fill-opacity="{f(a)}"/>')
    parts.append(svg_dots(mark_dots(400, 17), 318, h / 2 + 8))

    pitch = 17.0
    tx = 620
    ty = 222
    parts.append(wordmark_svg(tx, ty, pitch, pitch * 0.37))

    font = font_path()
    lines = [("Walk a room. Get a point cloud.", INK, 31, ty + 7 * pitch + 62),
             ("ARKit LiDAR  ·  ARCore Depth  ·  PLY export", MUTED, 21, ty + 7 * pitch + 108)]
    for text, colour, px, y in lines:
        d = text_path(text, font, px, tx - pitch * 0.37, y)
        if d:
            parts.append(f'  <path d="{d}" fill="{colour}"/>')
        else:
            parts.append(
                f'  <text x="{tx}" y="{y}" fill="{colour}" font-size="{px}" '
                f'font-family="Cascadia Mono, ui-monospace, Menlo, Consolas, monospace">{text}</text>'
            )
    parts.append("</svg>\n")
    (OUT / "banner.svg").write_text("\n".join(parts), encoding="utf-8")


# --- raster (PIL, supersampled) ------------------------------------------------
def render_tile(px: int, full_bleed: bool) -> Image.Image:
    ss = 4
    S = px * ss
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    bg = tuple(int(BG[i : i + 2], 16) for i in (1, 3, 5)) + (255,)
    if full_bleed:
        d.rectangle([0, 0, S, S], fill=bg)
    else:
        d.rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.22), fill=bg)
    scale = S / 512
    for x, y, r, c in mark_dots(330 * scale, 15 * scale):
        cx, cy = S / 2 + x, S / 2 + 6 * scale + y
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c + (255,))
    img = img.resize((px, px), Image.LANCZOS)
    return img.convert("RGB") if full_bleed else img


def render_banner_png():
    """Rasterises banner.svg dots with PIL; the tagline uses the TTF directly."""
    from PIL import ImageFont

    w, h, ss = 1280, 640, 2
    img = Image.new("RGB", (w * ss, h * ss), BG)
    d = ImageDraw.Draw(img, "RGBA")
    ink = tuple(int(INK[i : i + 2], 16) for i in (1, 3, 5))
    for x, y, r, a in banner_scatter(w, h):
        d.ellipse([(x - r) * ss, (y - r) * ss, (x + r) * ss, (y + r) * ss], fill=ink + (int(a * 255),))
    for x, y, r, c in mark_dots(400, 17):
        cx, cy = 318 + x, h / 2 + 8 + y
        d.ellipse([(cx - r) * ss, (cy - r) * ss, (cx + r) * ss, (cy + r) * ss], fill=c)
    pitch, tx, ty = 17.0, 620, 222
    dots, _, _ = wordmark_dots("scan3d", pitch)
    r = pitch * 0.37
    for x, y, a in dots:
        cx, cy = tx + x, ty + y
        d.ellipse([(cx - r) * ss, (cy - r) * ss, (cx + r) * ss, (cy + r) * ss], fill=ramp(0.55) if a else ink)
    font = font_path()
    if font.exists():
        muted = tuple(int(MUTED[i : i + 2], 16) for i in (1, 3, 5))
        for text, colour, px, y in [("Walk a room. Get a point cloud.", ink, 31, ty + 7 * pitch + 62),
                                    ("ARKit LiDAR  ·  ARCore Depth  ·  PLY export", muted, 21, ty + 7 * pitch + 108)]:
            ft = ImageFont.truetype(str(font), px * ss)
            d.text(((tx - r) * ss, y * ss), text, font=ft, fill=colour, anchor="ls")
    img.resize((w, h), Image.LANCZOS).save(OUT / "banner.png", optimize=True)


def write_app_icons():
    android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for dens, px in android.items():
        p = ROOT / "android/app/src/main/res" / f"mipmap-{dens}" / "ic_launcher.png"
        if p.parent.exists():
            render_tile(px, full_bleed=False).save(p, optimize=True)

    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    contents = ios / "Contents.json"
    if contents.exists():
        cache: dict[int, Image.Image] = {}
        for entry in json.loads(contents.read_text())["images"]:
            name = entry.get("filename")
            if not name:
                continue
            base = float(entry["size"].split("x")[0])
            px = round(base * int(entry["scale"].rstrip("x")))
            if px not in cache:
                cache[px] = render_tile(px, full_bleed=True)  # iOS masks the corners itself
            cache[px].save(ios / name, optimize=True)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    write_mark_svg()
    write_logo_svg()
    write_banner_svg()
    render_banner_png()
    render_tile(512, full_bleed=False).save(OUT / "mark.png", optimize=True)
    write_app_icons()
    print("brand assets written to", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
