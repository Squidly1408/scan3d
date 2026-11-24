# Export format

The share button in the 3D viewer writes `scan3d_<timestamp>.ply` to the app's temp directory and opens the system share sheet.

## Layout

A binary little-endian [PLY](https://paulbourke.net/dataformats/ply/) with one vertex element and no faces:

```
ply
format binary_little_endian 1.0
comment Created by Scan3D (units: metres, Y up)
element vertex <N>
property float x
property float y
property float z
property uchar red
property uchar green
property uchar blue
end_header
<N × 15 bytes>
```

| Field | Type | Notes |
|---|---|---|
| `x`, `y`, `z` | float32 | World position in metres, Y up, origin at session start |
| `red`, `green`, `blue` | uint8 | **Height colour**, not the camera colour. Blue at the lowest point, red at the highest. |

The size is the header (about 230 bytes) plus 15 bytes per point. A full 2M-point cloud is about 29 MB.

## Opening the file

### Blender (4.x)

**File → Import → Stanford PLY (.ply)**. Blender imports it as a mesh with vertices only, which you can't see in a render. To display it:

- In the viewport, vertices show in Edit Mode, or set **Viewport Display → Wireframe**.
- For a render, add a Geometry Nodes modifier: *Mesh to Points → Set Material*. The colours are in the `Col` attribute.
- Blender is Z-up, but the import's default *Forward/Up* axes handle Scan3D's Y-up data correctly.

### MeshLab

**File → Import Mesh**. Points and colours appear right away. Useful next steps:

- *Filters → Point Set → Compute normals for point sets*, then *Surface Reconstruction: Screened Poisson* to get a mesh.
- *Filters → Cleaning and Repairing → Remove Isolated pieces* to clear stray depth noise.

### CloudCompare

Drag the file in. CloudCompare reads the RGB as a scalar field. Useful tools: **Tools → Clean → SOR filter** for outliers, **Edit → Subsample** to reduce point count, and *Plugins → Poisson Recon* for meshing.

### Python

```python
import numpy as np
from plyfile import PlyData          # pip install plyfile

v = PlyData.read("scan3d_2026-11-24T12-00-00-000.ply")["vertex"]
xyz = np.stack([v["x"], v["y"], v["z"]], axis=1)
print(xyz.shape, xyz.min(0), xyz.max(0))
```

Open3D works too: `open3d.io.read_point_cloud(path)`.

## Accuracy

The cloud is only as good as the device's tracking. Expect:

- **LiDAR:** about ±1 to 2 cm close up, with little drift over a single room.
- **ARCore Depth:** about ±2 to 5 cm under 2 m, getting noisier with distance. The app ignores depth beyond 4 m.
- **Feature points:** a sparse outline of the room. Good for a floor plan, not for measuring.

Each point is also snapped to the 2 cm voxel it first landed in. The first sample in a voxel is kept and later ones are dropped.
