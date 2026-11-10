"""Original desert-set vehicles and background compounds.

Sketchfab files are reference silhouettes only. These meshes are built here
and share one sand, olive, rust, and charcoal palette.
"""
import json
import struct
from pathlib import Path

import bmesh

HELPERS = Path("/Users/vihaanshah/Documents/Github/the-drive/Tools/blender_build_assets.py")
ns = {"__name__": "assets"}
exec(compile(HELPERS.read_text(), str(HELPERS), "exec"), ns)

linear = ns["linear"]
cube = ns["cube"]
profile_solid = ns["profile_solid"]
side_profile = ns["side_profile"]
bevel = ns["bevel"]
collect = ns["collect"]
wheel_tris = ns["wheel_tris"]
shift_ground = ns["shift_ground"]
center_xz = ns["center_xz"]
pack_sculpt = ns["pack_sculpt"]
pack_vehicle = ns["pack_vehicle"]
validate = ns["validate_tris"]
link = ns["link"]
B = ns["B"]
ROOT = ns["ROOT"]

OLIVE = linear(0.34, 0.36, 0.24)
CANVAS = linear(0.78, 0.66, 0.48)
DARK = linear(0.11, 0.11, 0.10)
SAND = linear(0.78, 0.64, 0.44)
CHAR = linear(0.20, 0.18, 0.16)
RUST = linear(0.58, 0.26, 0.12)
PLASTER = linear(0.84, 0.73, 0.56)
SHADE = linear(0.70, 0.56, 0.40)
MUD = linear(0.48, 0.33, 0.22)
WOOD = linear(0.40, 0.25, 0.14)
GLASS = (1.0, 1.0, 1.0, 1.0)
LAMP = linear(0.96, 0.78, 0.42)
RUBBER = linear(0.04, 0.04, 0.045)
ALLOY = linear(0.55, 0.52, 0.46)


def put(bucket, obj, color, width=0.012):
    if width:
        bevel(obj, width, 1)
    bucket.extend(collect(obj, color))


def crowned(name, x0, x1, y, z0, z1, crown, columns=8, rows=10):
    mesh = bmesh.new()

    def grid(drop):
        rows_of = []
        for row in range(rows + 1):
            v = row / rows
            line = []
            for column in range(columns + 1):
                u = column / columns
                px = x0 + (x1 - x0) * u
                pz = z0 + (z1 - z0) * v
                bulge = crown * (1 - (u * 2 - 1) ** 2) * (1 - (v * 2 - 1) ** 2)
                line.append(mesh.verts.new(B(px, y + bulge - drop, pz)))
            rows_of.append(line)
        return rows_of

    top = grid(0)
    bottom = grid(0.035)
    for row in range(rows):
        for column in range(columns):
            a, b = top[row][column], top[row][column + 1]
            c, d = top[row + 1][column], top[row + 1][column + 1]
            mesh.faces.new((a, c, d, b))
            e, f = bottom[row][column], bottom[row][column + 1]
            g, h = bottom[row + 1][column], bottom[row + 1][column + 1]
            mesh.faces.new((e, f, h, g))
    bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
    return link(name, mesh)


def lamp(name, center, radius):
    mesh = bmesh.new()
    bmesh.ops.create_icosphere(mesh, subdivisions=2, radius=radius)
    bmesh.ops.translate(mesh, verts=list(mesh.verts), vec=B(*center))
    return link(name, mesh)


def report(label, verts):
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    print(
        label,
        "x", round(min(xs), 2), round(max(xs), 2),
        "y", round(min(ys), 2), round(max(ys), 2),
        "z", round(min(zs), 2), round(max(zs), 2),
        "tris", len(verts) // 3,
    )


def military_jeep():
    body = []
    put(body, cube("jeep-tub", (0, 0.78, 0.15), (1.7, 0.42, 3.15)), OLIVE, 0.018)
    put(body, cube("jeep-chassis", (0, 0.22, 0.1), (1.15, 0.28, 3.3)), DARK, 0.01)
    put(body, cube("jeep-hood", (0, 1.08, -1.05), (1.52, 0.16, 1.35)), OLIVE, 0.012)
    put(body, crowned("jeep-hood-crown", -0.68, 0.68, 1.18, -1.68, -0.42, 0.05, 6, 8), OLIVE, 0.004)
    for side in (-1, 1):
        put(
            body,
            profile_solid(
                f"jeep-fender-{side}",
                side_profile(-1.72, 1.62, 0.72, 1.12, ((-1.0, 0.45, 0.58), (1.0, 0.45, 0.58))),
                side * 0.62,
                side * 1.28,
            ),
            OLIVE,
            0.01,
        )
        put(body, cube(f"jeep-step-{side}", (side * 0.95, 0.52, 0.35), (0.16, 0.08, 1.15)), DARK, 0.004)
        put(body, lamp(f"jeep-lamp-{side}", (side * 0.48, 0.98, -1.72), 0.09), LAMP, 0.004)
    put(body, cube("jeep-grille", (0, 0.92, -1.78), (0.72, 0.42, 0.06)), DARK, 0.004)
    for slot, x in enumerate((-0.18, 0.0, 0.18)):
        put(body, cube(f"jeep-slat-{slot}", (x, 0.92, -1.82), (0.035, 0.34, 0.02)), OLIVE, 0)
    put(body, cube("jeep-screen", (0, 1.55, -0.48), (1.35, 0.08, 0.08)), DARK, 0.004)
    put(body, cube("jeep-post-l", (-0.62, 1.32, -0.48), (0.06, 0.48, 0.06)), DARK, 0)
    put(body, cube("jeep-post-r", (0.62, 1.32, -0.48), (0.06, 0.48, 0.06)), DARK, 0)
    put(body, cube("jeep-dash", (0, 1.02, -0.38), (1.35, 0.16, 0.28)), DARK, 0.008)
    for side in (-1, 1):
        put(body, cube(f"jeep-seat-{side}", (side * 0.38, 0.92, -0.05), (0.42, 0.12, 0.42)), CANVAS, 0.008)
        put(body, cube(f"jeep-back-{side}", (side * 0.38, 1.12, 0.16), (0.42, 0.42, 0.08)), CANVAS, 0.006)
    put(body, cube("jeep-tail", (0, 0.95, 1.68), (1.55, 0.55, 0.08)), OLIVE, 0.01)
    put(body, cube("jeep-can-a", (-0.62, 1.12, 1.42), (0.16, 0.32, 0.22)), RUST, 0.006)
    put(body, cube("jeep-can-b", (-0.42, 1.12, 1.42), (0.16, 0.32, 0.22)), OLIVE, 0.006)
    put(body, cube("jeep-canvas", (0, 1.72, -0.05), (1.25, 0.06, 0.85)), CANVAS, 0.008)
    put(body, cube("jeep-bow-l", (-0.58, 1.45, -0.05), (0.05, 0.55, 0.05)), DARK, 0)
    put(body, cube("jeep-bow-r", (0.58, 1.45, -0.05), (0.05, 0.55, 0.05)), DARK, 0)
    spare = [
        (x, y + 1.05, z + 1.78, nx, ny, nz, r, g, b, a)
        for x, y, z, nx, ny, nz, r, g, b, a in wheel_tris(0.28, 0.12, RUBBER, ALLOY, "Z")
    ]
    body.extend(spare)
    validate("jeep", body)
    report("jeep", body)
    pack_sculpt("JeepBody", body)


def rally(name, paint, arches):
    body = []
    glass = []
    put(body, cube(f"{name}-belly", (0, 0.2, 0.05), (1.2, 0.28, 3.55)), DARK, 0.01)
    put(body, cube(f"{name}-floor", (0, 0.42, 0.05), (1.35, 0.16, 3.7)), DARK, 0.01)
    put(body, crowned(f"{name}-hood", -0.68, 0.68, 1.02, -1.82, -0.38, 0.08, 8, 10), paint, 0.004)
    put(body, crowned(f"{name}-roof", -0.6, 0.6, 1.62, -0.22, 1.18, 0.055, 6, 10), paint, 0.004)
    put(body, crowned(f"{name}-stripe", -0.07, 0.07, 1.08, -1.7, 1.15, 0.01, 1, 8), RUST, 0)
    for side in (-1, 1):
        put(
            body,
            profile_solid(
                f"{name}-flare-{side}",
                side_profile(-1.95, 1.82, 0.4, 0.95, ((-1.22, 0.42, 0.58), (1.28, 0.42, 0.58))),
                side * 0.48,
                side * 1.04,
            ),
            arches,
            0.01,
        )
        put(body, cube(f"{name}-door-{side}", (side * 0.7, 1.15, 0.35), (0.08, 0.5, 1.2)), paint, 0.008)
        put(body, cube(f"{name}-skirt-{side}", (side * 0.74, 0.34, 0.1), (0.1, 0.1, 2.15)), arches, 0.004)
        put(body, cube(f"{name}-mirror-{side}", (side * 0.88, 1.2, -0.32), (0.16, 0.08, 0.1)), DARK, 0.004)
        put(glass, cube(f"{name}-glass-{side}", (side * 0.67, 1.32, 0.38), (0.03, 0.3, 0.72)), GLASS, 0)
    put(body, cube(f"{name}-nose", (0, 0.52, -1.95), (1.55, 0.28, 0.18)), arches, 0.008)
    put(body, cube(f"{name}-splitter", (0, 0.28, -2.02), (1.72, 0.05, 0.22)), DARK, 0.004)
    put(body, cube(f"{name}-tail", (0, 0.78, 1.84), (1.5, 0.42, 0.16)), arches, 0.008)
    put(body, cube(f"{name}-wing", (0, 1.52, 1.74), (1.48, 0.04, 0.32)), arches, 0.004)
    put(body, cube(f"{name}-wing-l", (-0.48, 1.34, 1.7), (0.04, 0.32, 0.08)), DARK, 0)
    put(body, cube(f"{name}-wing-r", (0.48, 1.34, 1.7), (0.04, 0.32, 0.08)), DARK, 0)
    put(body, cube(f"{name}-scoop", (0, 1.7, 0.2), (0.32, 0.12, 0.48)), arches, 0.006)
    for slot, x in enumerate((-0.28, 0.28)):
        put(body, cube(f"{name}-vent-{slot}", (x, 1.1, -1.15), (0.18, 0.02, 0.32)), DARK, 0)
        put(body, lamp(f"{name}-lamp-{slot}", (x, 0.72, -2.0), 0.07), LAMP, 0.004)
    put(glass, cube(f"{name}-windshield", (0, 1.28, -0.4), (1.15, 0.42, 0.04)), GLASS, 0)
    put(glass, cube(f"{name}-rear-glass", (0, 1.32, 1.28), (1.05, 0.34, 0.04)), GLASS, 0)
    for side in (-1, 1):
        put(body, cube(f"{name}-seat-{side}", (side * 0.34, 0.72, 0.05), (0.36, 0.1, 0.4)), DARK, 0.006)
    wheels = [
        ("wheel-front-left", [-0.82, 0.42, -1.22], wheel_tris(0.36, 0.16, RUBBER, ALLOY)),
        ("wheel-front-right", [0.82, 0.42, -1.22], wheel_tris(0.36, 0.16, RUBBER, ALLOY)),
        ("wheel-back-left", [-0.82, 0.42, 1.28], wheel_tris(0.36, 0.16, RUBBER, ALLOY)),
        ("wheel-back-right", [0.82, 0.42, 1.28], wheel_tris(0.36, 0.16, RUBBER, ALLOY)),
    ]
    validate(name, body)
    validate(name + " glass", glass)
    report(name, body)
    pack_vehicle(name, [("body", [0, 0, 0], body), ("glass", [0, 0, 0], glass), *wheels])


def desert_home(tag, width, depth, height, floors, tower):
    body = []
    windows = []
    put(body, cube(f"{tag}-mass", (0, height / 2, 0), (width, height, depth)), PLASTER, 0.02)
    put(body, cube(f"{tag}-roof", (0, height + 0.1, 0), (width + 0.5, 0.18, depth + 0.45)), MUD, 0.01)
    put(body, cube(f"{tag}-parapet", (0, height + 0.32, 0), (width + 0.15, 0.28, 0.16)), SHADE, 0.006)
    span = width + 1.1
    piece = (span - 1.5) * 0.5
    wall_z = -depth / 2 - 0.7
    put(body, cube(f"{tag}-yard-l", (-(0.75 + piece / 2), 0.62, wall_z), (piece, 1.2, 0.16)), SHADE, 0.008)
    put(body, cube(f"{tag}-yard-r", (0.75 + piece / 2, 0.62, wall_z), (piece, 1.2, 0.16)), SHADE, 0.008)
    put(body, cube(f"{tag}-door", (0, 0.9, -depth / 2 - 0.02), (0.72, 1.75, 0.08)), WOOD, 0.008)
    if floors > 1:
        put(body, cube(f"{tag}-upper", (0, height + height * 0.42, 0.15), (width * 0.7, height * 0.8, depth * 0.7)), PLASTER, 0.015)
        put(body, cube(f"{tag}-upper-roof", (0, height * 1.84, 0.15), (width * 0.78, 0.16, depth * 0.78)), MUD, 0.008)
    if tower:
        put(body, cube(f"{tag}-tower", (width * 0.28, (height + 2.6) / 2, depth * 0.2), (2.2, height + 2.6, 2.2)), SHADE, 0.012)
        put(body, cube(f"{tag}-tower-cap", (width * 0.28, height + 2.7, depth * 0.2), (2.55, 0.16, 2.55)), MUD, 0.008)
    for slot, x in enumerate((-width * 0.28, width * 0.28)):
        put(windows, cube(f"{tag}-win-{slot}", (x, height * 0.58, -depth / 2 - 0.03), (0.55, 0.7, 0.05)), GLASS, 0)
    if floors > 1:
        put(windows, cube(f"{tag}-win-up", (0, height * 1.35, -depth * 0.34), (0.5, 0.55, 0.05)), GLASS, 0)
    body, windows = center_xz(shift_ground([body, windows]))
    validate(tag, body)
    report(tag, body + windows)
    return [("body", body), ("window", windows)]


def append_compounds():
    path = ROOT / "EnvironmentMesh.json"
    binary = ROOT / "EnvironmentMesh.bin"
    models = json.loads(path.read_text())
    old = binary.read_bytes()
    kept = [model for model in models if not str(model["name"]).startswith("desert_bg")]
    blob = bytearray()
    for model in kept:
        parts = []
        for part in model["parts"]:
            count = part["count"]
            raw = old[part["offset"]:part["offset"] + count * 40]
            parts.append({"name": part["name"], "offset": len(blob), "count": count})
            blob += raw
        model["parts"] = parts
    specs = [
        ("desert_bg01", 9.2, 7.4, 3.6, 1, False),
        ("desert_bg02", 7.6, 6.8, 3.4, 2, False),
        ("desert_bg03", 8.4, 7.2, 3.5, 1, True),
        ("desert_bg04", 11.0, 6.0, 3.2, 1, False),
    ]
    for spec in specs:
        groups = desert_home(*spec)
        points = []
        parts = []
        for part_name, verts in groups:
            parts.append({"name": part_name, "offset": len(blob), "count": len(verts)})
            for vertex in verts:
                points.append(vertex[:3])
                blob += struct.pack("<10f", *vertex)
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        zs = [point[2] for point in points]
        kept.append({
            "name": spec[0],
            "parts": parts,
            "bounds": [[min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)]],
        })
    path.write_text(json.dumps(kept))
    binary.write_bytes(blob)
    print("environment", len(kept), "bytes", len(blob))


military_jeep()
rally("hatchback-sports", SAND, CHAR)
rally("suv", CHAR, SAND)
append_compounds()
print("STYLE_OK")
