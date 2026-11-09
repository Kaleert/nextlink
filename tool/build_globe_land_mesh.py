"""Generate a static mobile land mesh from the bundled Natural Earth outlines.

Dev-only: pip install --target build/map-tools mapbox-earcut==2.1.0 numpy==2.5.4
Run: PYTHONPATH=build/map-tools python3 tool/build_globe_land_mesh.py
No Python or triangulation dependency is shipped in the application.
"""
import json
import math
from pathlib import Path

import mapbox_earcut
import numpy as np

root = Path(__file__).resolve().parents[1]
rings = json.loads((root / "assets/map/land.json").read_text())
triangles = []


def refine(a, b, c):
    edges = [(math.dist(a, b), a, b, c), (math.dist(b, c), b, c, a),
             (math.dist(c, a), c, a, b)]
    length, x, y, other = max(edges, key=lambda edge: edge[0])
    if length <= 10:
        triangles.append([[round(p[0], 5), round(p[1], 5)] for p in (a, b, c)])
        return
    midpoint = [(x[0] + y[0]) / 2, (x[1] + y[1]) / 2]
    refine(x, midpoint, other)
    refine(midpoint, y, other)


for ring in rings:
    if ring[0] == ring[-1]:
        ring = ring[:-1]
    vertices = np.asarray(ring, dtype=np.float64)
    indices = mapbox_earcut.triangulate_float64(vertices, np.array([len(ring)], dtype=np.uint32))
    for i in range(0, len(indices), 3):
        refine(*(ring[index] for index in indices[i:i + 3]))

output = root / "assets/map/land_mesh.json"
output.write_text(json.dumps(triangles, separators=(",", ":")))
print(f"Generated {len(triangles)} triangles ({output.stat().st_size} bytes)")
