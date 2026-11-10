"""Build The Drive houses, vehicles, and rocks in the live Blender and write game buffers.

SceneKit is Y-up and drives toward -Z. Blender is Z-up. A point thought of in
SceneKit (x, y, z) is stored in Blender as (x, -z, y), then exported back with
(x, z, -y). That rotation keeps triangle winding facing outward.
"""

import json
import math
import struct
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path("/Users/vihaanshah/Documents/Github/the-drive/TheDrive/Assets")


def linear(r, g, b, a=1.0):
    def channel(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (channel(r), channel(g), channel(b), a)


def B(x, y, z):
    return Vector((x, -z, y))


def smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True


def link(name, bm):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    smooth(obj)
    return obj


def cube(name, center, size):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    sx, sy, sz = size
    origin = B(*center)
    for vert in bm.verts:
        vert.co.x = vert.co.x * sx + origin.x
        vert.co.y = vert.co.y * sz + origin.y
        vert.co.z = vert.co.z * sy + origin.z
    return link(name, bm)


def solid(name, bottom, top):
    """Closed box. bottom and top are 4 SceneKit corners in the same winding."""
    bm = bmesh.new()
    verts = [bm.verts.new(B(*p)) for p in list(bottom) + list(top)]
    bm.verts.ensure_lookup_table()
    faces = [
        (0, 1, 2, 3),
        (4, 7, 6, 5),
        (0, 4, 5, 1),
        (1, 5, 6, 2),
        (2, 6, 7, 3),
        (3, 7, 4, 0),
    ]
    for face in faces:
        bm.faces.new([verts[i] for i in face])
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return link(name, bm)


def profile_solid(name, yz, x0, x1):
    bm = bmesh.new()
    a = [bm.verts.new(B(x0, y, z)) for y, z in yz]
    b = [bm.verts.new(B(x1, y, z)) for y, z in yz]
    n = len(yz)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((a[i], b[i], b[j], a[j]))
    bm.faces.new(list(reversed(a)))
    bm.faces.new(b)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return link(name, bm)


def cone(name, center, radius, depth, axis):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=18, radius1=radius, radius2=radius, depth=depth)
    if axis == "X":
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=__import__("mathutils").Matrix.Rotation(math.pi / 2, 4, "Y"))
    elif axis == "Y":
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=__import__("mathutils").Matrix.Rotation(math.pi / 2, 4, "X"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=B(*center))
    return link(name, bm)


def bevel(obj, width, segments=2):
    mod = obj.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(42)


def cut_box(obj, center, size):
    cutter = cube(obj.name + "_cut", center, size)
    cutter.display_type = "WIRE"
    mod = obj.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "FLOAT"
    return cutter


def arch_rim(az, ay, radius, floor, segments=10):
    lift = max(-0.95, min(0.95, (floor - ay) / radius))
    start = math.asin(lift)
    end = math.pi - start
    points = []
    for i in range(segments + 1):
        angle = start + (end - start) * i / segments
        points.append((ay + math.sin(angle) * radius, az + math.cos(angle) * radius))
    return points


def side_profile(z0, z1, y0, y1, arches):
    points = [(y0, z0), (y1, z0), (y1, z1), (y0, z1)]
    cursor = z1
    for az, ay, radius in sorted(arches, key=lambda item: -item[0]):
        rim = arch_rim(az, ay, radius, y0)
        if rim[0][1] < cursor - 0.02:
            points.append((y0, rim[0][1]))
        points.extend(rim[1:])
        cursor = rim[-1][1]
    if cursor > z0 + 0.02:
        points.append((y0, z0))
    return points


def collect(obj, color):
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(deps)
    mesh = evaluated.to_mesh()
    mesh.calc_loop_triangles()
    world = evaluated.matrix_world
    normal_matrix = world.to_3x3()
    corners = mesh.corner_normals if len(mesh.corner_normals) else None
    tris = []
    for tri in mesh.loop_triangles:
        for loop, vertex in zip(tri.loops, tri.vertices):
            co = world @ mesh.vertices[vertex].co
            raw = corners[loop].vector if corners else tri.normal
            normal = (normal_matrix @ raw).normalized()
            sx, sy, sz = co.x, co.z, -co.y
            nx, ny, nz = normal.x, normal.z, -normal.y
            length = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
            tris.append((sx, sy, sz, nx / length, ny / length, nz / length, *color))
    evaluated.to_mesh_clear()
    return tris


class MeshBag:
    def __init__(self):
        self.objects = []
        self.cutters = []
        self.groups = []

    def add(self, obj, color, width=0.018, segments=2):
        if width:
            bevel(obj, width, segments)
        self.objects.append(obj)
        self.groups.append((obj, color))
        return obj

    def cut(self, obj, center, size):
        self.cutters.append(cut_box(obj, center, size))

    def bake(self):
        bpy.context.view_layer.update()
        baked = []
        for obj, color in self.groups:
            baked.extend(collect(obj, color))
        return baked


def purge_work():
    for obj in list(bpy.data.objects):
        if obj.name in {"Camera", "Light"}:
            continue
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def shift_ground(groups):
    verts = [vert for group in groups for vert in group]
    if not verts:
        return groups
    low = min(vert[1] for vert in verts)
    if low >= 0:
        return groups
    lifted = []
    for group in groups:
        lifted.append([
            (x, y - low, z, nx, ny, nz, r, g, b, a)
            for x, y, z, nx, ny, nz, r, g, b, a in group
        ])
    return lifted


def center_xz(groups):
    verts = [vert for group in groups for vert in group]
    xs = [vert[0] for vert in verts]
    zs = [vert[2] for vert in verts]
    mx = (min(xs) + max(xs)) * 0.5
    mz = (min(zs) + max(zs)) * 0.5
    centered = []
    for group in groups:
        centered.append([
            (x - mx, y, z - mz, nx, ny, nz, r, g, b, a)
            for x, y, z, nx, ny, nz, r, g, b, a in group
        ])
    return centered


def bounds_of(groups):
    verts = [vert for group in groups for vert in group]
    low = [min(vert[i] for vert in verts) for i in range(3)]
    high = [max(vert[i] for vert in verts) for i in range(3)]
    return low, high


def pack_environment(models, path_json, path_bin):
    blob = bytearray()
    payload = []
    for name, groups in models:
        parts = []
        for part_name, verts in groups:
            parts.append({"name": part_name, "offset": len(blob), "count": len(verts)})
            for vert in verts:
                blob += struct.pack("<10f", *vert)
        low, high = bounds_of([verts for _, verts in groups])
        payload.append({"name": name, "parts": parts, "bounds": [low, high]})
    path_bin.write_bytes(blob)
    path_json.write_text(json.dumps(payload))
    return payload


def pack_vehicle(name, parts):
    """parts: (name, position, verts). Verts are local for wheels and vehicle-space for the body."""
    geo = bytearray()
    colors = bytearray()
    payload = []
    for part_name, position, verts in parts:
        payload.append({
            "name": part_name,
            "offset": len(geo),
            "count": len(verts),
            "position": position,
        })
        for x, y, z, nx, ny, nz, r, g, b, a in verts:
            geo += struct.pack("<8f", x, y, z, nx, ny, nz, 0.0, 0.0)
            colors += struct.pack("<4f", r, g, b, a)
    (ROOT / f"Vehicle-{name}.json").write_text(json.dumps(payload))
    (ROOT / f"Vehicle-{name}.bin").write_bytes(geo)
    (ROOT / f"Vehicle-{name}-colors.bin").write_bytes(colors)
    return payload


def pack_sculpt(name, verts):
    blob = bytearray()
    for vert in verts:
        blob += struct.pack("<10f", *vert)
    low, high = bounds_of([verts])
    (ROOT / f"{name}.json").write_text(json.dumps({"count": len(verts), "bounds": [low, high]}))
    (ROOT / f"{name}.bin").write_bytes(blob)


def torus_bm(major, minor, major_segments=28, minor_segments=10):
    bm = bmesh.new()
    rings = []
    for i in range(major_segments):
        angle = math.tau * i / major_segments
        ring = []
        for j in range(minor_segments):
            beta = math.tau * j / minor_segments
            ring.append(bm.verts.new((
                (major + minor * math.cos(beta)) * math.cos(angle),
                (major + minor * math.cos(beta)) * math.sin(angle),
                minor * math.sin(beta),
            )))
        rings.append(ring)
    for i in range(major_segments):
        nxt = rings[(i + 1) % major_segments]
        for j in range(minor_segments):
            k = (j + 1) % minor_segments
            bm.faces.new((rings[i][j], nxt[j], nxt[k], rings[i][k]))
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    return bm


def wheel_tris(radius, width, tire, metal, axle="X"):
    bm = torus_bm(radius * 0.78, radius * 0.22)
    matrix = __import__("mathutils").Matrix.Rotation(math.pi / 2, 4, "Y")
    if axle == "Z":
        matrix = __import__("mathutils").Matrix.Rotation(-math.pi / 2, 4, "X")
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=matrix)
    tire_obj = link("tire", bm)
    bevel(tire_obj, radius * 0.02, 1)
    hub = cone("hub", (0, 0, 0), radius * 0.46, width * 1.15, "X" if axle == "X" else "Z")
    bevel(hub, radius * 0.015, 1)
    bpy.context.view_layer.update()
    painted = collect(tire_obj, tire) + collect(hub, metal)
    bpy.data.objects.remove(tire_obj, do_unlink=True)
    bpy.data.objects.remove(hub, do_unlink=True)
    return painted


def gable_roof(bag, w, d, base, rise, color, along="x", broken=False):
    hw = w * 0.5
    hd = d * 0.5
    peak = base + rise
    thick = 0.14
    if along == "x":
        bag.add(solid(
            "roof_f",
            [(-hw, base, -hd), (hw, base, -hd), (hw, base, 0), (-hw, base, 0)],
            [(-hw, base + thick, -hd), (hw, base + thick, -hd), (hw, peak, 0), (-hw, peak, 0)],
        ), color, 0.02, 1)
        if not broken:
            bag.add(solid(
                "roof_r",
                [(-hw, base, 0), (hw, base, 0), (hw, base, hd), (-hw, base, hd)],
                [(-hw, peak, 0), (hw, peak, 0), (hw, base + thick, hd), (-hw, base + thick, hd)],
            ), color, 0.02, 1)
        return
    bag.add(solid(
        "roof_l",
        [(-hw, base, -hd), (0, base, -hd), (0, base, hd), (-hw, base, hd)],
        [(-hw, base + thick, -hd), (0, peak, -hd), (0, peak, hd), (-hw, base + thick, hd)],
    ), color, 0.02, 1)
    if not broken:
        bag.add(solid(
            "roof_r",
            [(0, base, -hd), (hw, base, -hd), (hw, base, hd), (0, base, hd)],
            [(0, peak, -hd), (hw, base + thick, -hd), (hw, base + thick, hd), (0, peak, hd)],
        ), color, 0.02, 1)


def hip_roof(bag, w, d, base, rise, color, broken=False):
    hw = w * 0.5
    hd = d * 0.5
    peak = base + rise
    inset_x = hw * 0.42
    inset_z = hd * 0.28
    eaves = [(-hw, base, -hd), (hw, base, -hd), (hw, base, hd), (-hw, base, hd)]
    cap = [
        (-inset_x, peak, -inset_z), (inset_x, peak, -inset_z),
        (inset_x, peak, inset_z), (-inset_x, peak, inset_z),
    ]
    count = 3 if broken else 4
    for index in range(count):
        nxt = (index + 1) % 4
        e0, e1 = eaves[index], eaves[nxt]
        c0, c1 = cap[index], cap[nxt]
        bag.add(solid(
            f"hip{index}",
            [e0, e1, (c1[0], base + 0.02, c1[2]), (c0[0], base + 0.02, c0[2])],
            [(e0[0], base + 0.16, e0[2]), (e1[0], base + 0.16, e1[2]), c1, c0],
        ), color, 0.015, 1)
    if not broken:
        bag.add(solid("hipcap", cap, [(p[0], peak + 0.08, p[2]) for p in cap]), color, 0.01, 1)


def house(spec):
    bag = MeshBag()
    w = spec["w"]
    d = spec["d"]
    wall_h = spec["wall"]
    total = spec["h"]
    wall_c = linear(*spec["wall_color"])
    roof_c = linear(*spec["roof"])
    trim = linear(*spec["trim"])
    door_c = linear(*spec["door"])
    stone = linear(0.45, 0.38, 0.30)
    glass = (1, 1, 1, 1)
    thickness = 0.18
    hw = w * 0.5
    hd = d * 0.5
    porch = spec.get("porch", 0)
    ruin = spec.get("ruin", False)
    bag.add(cube("foundation", (0, 0.08, 0), (w + 0.28, 0.16, d + 0.2)), stone, 0.02, 1)
    bag.add(cube("interior", (0, wall_h * 0.48, 0.05), (w - 0.7, wall_h * 0.82, d - 0.7)), linear(0.10, 0.09, 0.08), 0)

    def wall(name, center, size, openings):
        obj = cube(name, center, size)
        for opening in openings:
            bag.cut(obj, opening[0], opening[1])
        bag.add(obj, wall_c, 0.025, 2)
        return obj

    front_z = -hd + thickness * 0.5
    back_z = hd - thickness * 0.5
    floors = spec.get("floors", 1)
    windows = []
    front_openings = []
    side_openings = {-1: [], 1: []}
    for level in range(floors):
        y = 0.85 + level * 2.15
        if y + 0.55 > wall_h - 0.15:
            break
        for x in spec.get("front_x", (-1.15, 1.15)):
            center = (x, y, front_z)
            front_openings.append((center, (0.78, 1.05, thickness + 0.28)))
            windows.append((center[0], center[1], -hd - 0.02, 0.62, 0.86, 0.02))
        if spec.get("side_windows", True):
            for z in (-hd * 0.35, hd * 0.35):
                for side in (-1, 1):
                    if ruin and side < 0:
                        continue
                    side_openings[side].append(((side * (hw - thickness * 0.5), y, z), (thickness + 0.28, 1.05, 0.78)))
                    windows.append((side * (hw + 0.02), y, z, 0.02, 0.86, 0.62))

    front_openings.append(((0, 0.95, front_z), (0.92, 1.9, thickness + 0.28)))
    wall("front", (0, wall_h * 0.5, front_z), (w, wall_h, thickness), front_openings)
    if not ruin:
        wall("back", (0, wall_h * 0.5, back_z), (w, wall_h, thickness), [])
    else:
        wall("back", (0.35, wall_h * 0.42, back_z), (w * 0.72, wall_h * 0.84, thickness), [])
    for side in (-1, 1):
        if ruin and side < 0:
            wall("side_broken", (side * hw, wall_h * 0.28, 0.4), (thickness, wall_h * 0.5, d * 0.55), [])
            continue
        wall(f"side{side}", (side * hw, wall_h * 0.5, 0), (thickness, wall_h, d), side_openings[side])

    bag.add(cube("door", (0, 0.95, front_z - 0.02), (0.78, 1.82, 0.06)), door_c, 0.012, 1)
    bag.add(cube("sill", (0, 0.08, front_z - 0.04), (1.05, 0.08, 0.1)), stone, 0.008, 1)

    rise = total - wall_h
    if spec["roof_kind"] == "hip":
        hip_roof(bag, w + 0.45, d + 0.4, wall_h - 0.05, rise, roof_c, ruin)
    elif spec["roof_kind"] == "front":
        gable_roof(bag, w + 0.2, d + 0.45, wall_h - 0.05, rise, roof_c, "z", ruin)
    elif spec["roof_kind"] == "flat":
        bag.add(cube("flat", (0, wall_h + 0.1, 0), (w + 0.4, 0.22, d + 0.35)), roof_c, 0.02, 1)
        bag.add(cube("parapet", (0, wall_h + 0.32, -hd), (w + 0.2, 0.28, 0.12)), wall_c, 0.01, 1)
    else:
        gable_roof(bag, w + 0.5, d + 0.45, wall_h - 0.05, rise, roof_c, "x", ruin)

    if spec.get("dormer") and not ruin:
        dormer_z = -hd * 0.15
        dormer_y = wall_h + rise * 0.35
        bag.add(cube("dormer", (0, dormer_y, dormer_z), (1.3, 0.9, 1.1)), wall_c, 0.015, 1)
        bag.add(solid(
            "dormer_roof",
            [(-0.8, dormer_y + 0.35, dormer_z - 0.6), (0.8, dormer_y + 0.35, dormer_z - 0.6),
             (0.8, dormer_y + 0.35, dormer_z + 0.6), (-0.8, dormer_y + 0.35, dormer_z + 0.6)],
            [(-0.15, dormer_y + 0.85, dormer_z - 0.6), (0.15, dormer_y + 0.85, dormer_z - 0.6),
             (0.15, dormer_y + 0.85, dormer_z + 0.6), (-0.15, dormer_y + 0.85, dormer_z + 0.6)],
        ), roof_c, 0.012, 1)
        windows.append((0, dormer_y, dormer_z - 0.58, 0.55, 0.48, 0.02))

    if spec.get("chimney", True) and not ruin:
        bag.add(cube("chimney", (hw * 0.55, wall_h + rise * 0.72, hd * 0.35), (0.42, rise * 0.9, 0.42)), stone, 0.01, 1)

    if porch > 0.2:
        porch_z = -hd - porch * 0.5
        bag.add(cube("porch", (0, 0.12, porch_z), (w * 0.72, 0.1, porch)), stone, 0.015, 1)
        bag.add(cube("porch_roof", (0, wall_h * 0.72, porch_z), (w * 0.78, 0.1, porch + 0.15)), roof_c, 0.012, 1)
        for x in (-w * 0.28, w * 0.28):
            bag.add(cube("post", (x, wall_h * 0.36, -hd - porch + 0.12), (0.14, wall_h * 0.7, 0.14)), trim, 0.01, 1)

    if ruin:
        bag.add(cube("rubble", (-hw * 0.45, 0.22, hd * 0.2), (1.4, 0.36, 1.1)), stone, 0.02, 1)
        bag.add(cube("rubble2", (hw * 0.2, 0.16, -hd * 0.2), (0.9, 0.24, 0.7)), linear(0.34, 0.28, 0.22), 0.015, 1)

    windows_tris = []
    for x, y, z, sx, sy, sz in windows:
        pane = cube("pane", (x, y, z), (sx, sy, sz))
        bevel(pane, 0.006, 1)
        bag.objects.append(pane)
        bag.groups.append((pane, glass))
        windows_tris.append(pane)

    bpy.context.view_layer.update()
    body = []
    glass_tris = []
    glass_ids = {id(pane) for pane in windows_tris}
    for obj, color in bag.groups:
        baked = collect(obj, color)
        if id(obj) in glass_ids:
            glass_tris.extend(baked)
        else:
            body.extend(baked)
    for cutter in bag.cutters:
        bpy.data.objects.remove(cutter, do_unlink=True)
    groups = center_xz(shift_ground([body, glass_tris]))
    return [("body", groups[0]), ("window", groups[1])]


def fence(open_gate):
    bag = MeshBag()
    wood = linear(0.32, 0.24, 0.16)
    metal = linear(0.22, 0.24, 0.26)
    span = 3.48
    for x in (-1.74, -0.87, 0.87, 1.74):
        if open_gate and abs(x) < 0.4:
            continue
        bag.add(cube("post", (x, 0.42, 0), (0.1, 0.84, 0.1)), wood, 0.008, 1)
    rail_y = (0.28, 0.62)
    segments = [(-1.74, -0.55), (0.55, 1.74)] if open_gate else [(-1.74, 1.74)]
    for y in rail_y:
        for a, b in segments:
            bag.add(cube("rail", ((a + b) * 0.5, y, 0), (abs(b - a), 0.08, 0.06)), metal, 0.006, 1)
    if open_gate:
        bag.add(solid(
            "gate",
            [(-0.42, 0.12, 0.05), (-0.42, 0.12, 0.9), (-0.34, 0.12, 0.9), (-0.34, 0.12, 0.05)],
            [(-0.42, 0.78, 0.05), (-0.42, 0.78, 0.9), (-0.34, 0.78, 0.9), (-0.34, 0.78, 0.05)],
        ), metal, 0.006, 1)
    bpy.context.view_layer.update()
    body = []
    for obj, color in bag.groups:
        body.extend(collect(obj, color))
    return [("body", shift_ground([body])[0])]


def rock():
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=3, radius=0.55)
    for index, vert in enumerate(bm.verts):
        wobble = 0.82 + 0.22 * abs(math.sin(index * 12.9898) * 43758.5453 % 1)
        vert.co *= wobble
        if vert.co.z < 0.05:
            vert.co.z *= 0.35
    low = min(vert.co.z for vert in bm.verts)
    for vert in bm.verts:
        vert.co.z -= low
    obj = link("rock", bm)
    bevel(obj, 0.03, 2)
    bpy.context.view_layer.update()
    return [("body", collect(obj, linear(0.55, 0.42, 0.30)))]


def car_body(kind):
    bag = MeshBag()
    rally = kind == "rally"
    paint = linear(0.62, 0.16, 0.08) if rally else linear(0.16, 0.20, 0.22)
    dark = linear(0.07, 0.08, 0.09)
    trim = linear(0.55, 0.50, 0.42)
    warm = linear(1.0, 0.78, 0.35)
    red = linear(0.65, 0.05, 0.03)
    seat = linear(0.12, 0.11, 0.10)
    rubber = linear(0.02, 0.02, 0.02)
    if rally:
        arches = [(-1.18, 0.38, 0.50), (1.18, 0.38, 0.50)]
        profile = side_profile(-1.72, 1.62, 0.30, 0.92, arches)
        bag.add(profile_solid("side_l", profile, -0.90, -0.78), paint, 0.012, 1)
        bag.add(profile_solid("side_r", profile, 0.78, 0.90), paint, 0.012, 1)
        bag.add(cube("floor", (0, 0.36, -0.05), (1.5, 0.12, 3.2)), dark, 0.01, 1)
        bag.add(solid(
            "hood",
            [(-0.78, 0.55, -1.95), (0.78, 0.55, -1.95), (0.86, 0.72, -0.4), (-0.86, 0.72, -0.4)],
            [(-0.74, 0.66, -1.9), (0.74, 0.66, -1.9), (0.84, 0.96, -0.42), (-0.84, 0.96, -0.42)],
        ), paint, 0.016, 2)
        bag.add(solid(
            "deck",
            [(-0.82, 0.7, 0.85), (0.82, 0.7, 0.85), (0.78, 0.58, 1.7), (-0.78, 0.58, 1.7)],
            [(-0.8, 0.9, 0.9), (0.8, 0.9, 0.9), (0.74, 0.78, 1.65), (-0.74, 0.78, 1.65)],
        ), paint, 0.014, 1)
        bag.add(cube("roof", (0, 1.28, 0.42), (1.45, 0.1, 1.15)), paint, 0.02, 2)
        bag.add(cube("bumper_f", (0, 0.4, -2.02), (1.7, 0.28, 0.22)), trim, 0.012, 1)
        bag.add(cube("bumper_r", (0, 0.42, 1.82), (1.68, 0.26, 0.2)), trim, 0.012, 1)
        bag.add(cube("spoiler", (0, 1.12, 1.62), (1.35, 0.06, 0.28)), dark, 0.008, 1)
        bag.add(cube("spoiler_up", (0, 1.2, 1.74), (1.25, 0.16, 0.05)), dark, 0.006, 1)
        for x in (-0.55, 0.55):
            bag.add(cube("lamp", (x, 0.62, -2.02), (0.32, 0.14, 0.08)), warm, 0.006, 1)
            bag.add(cube("tail", (x, 0.7, 1.9), (0.28, 0.12, 0.06)), red, 0.004, 1)
            bag.add(cube("door", (x * 1.55, 0.78, 0.25), (0.06, 0.55, 1.15)), paint, 0.01, 1)
            bag.add(cube("mirror", (x * 1.7, 1.02, -0.15), (0.16, 0.08, 0.1)), dark, 0.006, 1)
        bag.add(cube("grille", (0, 0.48, -2.04), (0.7, 0.16, 0.06)), dark, 0.004, 1)
        for x in (-0.38, 0.38):
            bag.add(cube("cushion", (x, 0.62, -0.15), (0.42, 0.16, 0.42)), seat, 0.01, 1)
            bag.add(cube("back", (x, 0.95, 0.08), (0.4, 0.48, 0.1)), seat, 0.008, 1)
        glass_parts = [
            solid("wind", [(-0.7, 0.94, -0.48), (0.7, 0.94, -0.48), (0.62, 1.24, -0.05), (-0.62, 1.24, -0.05)],
                  [(-0.68, 0.96, -0.46), (0.68, 0.96, -0.46), (0.6, 1.26, -0.06), (-0.6, 1.26, -0.06)]),
            cube("side_l", (-0.8, 1.08, 0.35), (0.04, 0.32, 0.9)),
            cube("side_r", (0.8, 1.08, 0.35), (0.04, 0.32, 0.9)),
            cube("rear_glass", (0, 1.12, 1.02), (1.15, 0.28, 0.04)),
        ]
    else:
        arches = [(-1.32, 0.42, 0.56), (1.32, 0.42, 0.56)]
        profile = side_profile(-1.85, 1.85, 0.32, 1.15, arches)
        bag.add(profile_solid("side_l", profile, -0.98, -0.84), paint, 0.014, 1)
        bag.add(profile_solid("side_r", profile, 0.84, 0.98), paint, 0.014, 1)
        bag.add(cube("floor", (0, 0.4, 0), (1.6, 0.14, 3.5)), dark, 0.01, 1)
        bag.add(solid(
            "hood",
            [(-0.9, 0.7, -2.05), (0.9, 0.7, -2.05), (0.95, 0.9, -0.45), (-0.95, 0.9, -0.45)],
            [(-0.86, 0.95, -2.0), (0.86, 0.95, -2.0), (0.92, 1.18, -0.45), (-0.92, 1.18, -0.45)],
        ), paint, 0.016, 2)
        bag.add(cube("roof", (0, 1.68, 0.35), (1.6, 0.1, 1.7)), paint, 0.02, 2)
        bag.add(cube("bumper_f", (0, 0.48, -2.15), (1.9, 0.36, 0.28)), dark, 0.014, 1)
        bag.add(cube("bumper_r", (0, 0.5, 2.05), (1.88, 0.34, 0.24)), dark, 0.014, 1)
        for x in (-0.62, 0.62):
            bag.add(cube("lamp", (x, 0.82, -2.16), (0.34, 0.16, 0.08)), warm, 0.006, 1)
            bag.add(cube("tail", (x, 0.9, 2.12), (0.3, 0.16, 0.06)), red, 0.004, 1)
            bag.add(cube("door", (x * 1.55, 1.0, 0.25), (0.07, 0.7, 1.2)), paint, 0.01, 1)
            bag.add(cube("mirror", (x * 1.85, 1.25, -0.25), (0.18, 0.1, 0.12)), dark, 0.006, 1)
        bag.add(cube("grille", (0, 0.62, -2.2), (0.9, 0.28, 0.08)), dark, 0.006, 1)
        bag.add(cube("rail_l", (-0.55, 1.78, 0.3), (0.08, 0.06, 1.4)), dark, 0.004, 1)
        bag.add(cube("rail_r", (0.55, 1.78, 0.3), (0.08, 0.06, 1.4)), dark, 0.004, 1)
        for x in (-0.4, 0.4):
            bag.add(cube("cushion", (x, 0.85, -0.15), (0.46, 0.18, 0.46)), seat, 0.01, 1)
            bag.add(cube("back", (x, 1.2, 0.1), (0.44, 0.55, 0.12)), seat, 0.008, 1)
        glass_parts = [
            solid("wind", [(-0.78, 1.16, -0.5), (0.78, 1.16, -0.5), (0.7, 1.62, -0.08), (-0.7, 1.62, -0.08)],
                  [(-0.76, 1.18, -0.48), (0.76, 1.18, -0.48), (0.68, 1.64, -0.1), (-0.68, 1.64, -0.1)]),
            cube("side_l", (-0.9, 1.38, 0.4), (0.04, 0.4, 1.15)),
            cube("side_r", (0.9, 1.38, 0.4), (0.04, 0.4, 1.15)),
            cube("rear_glass", (0, 1.4, 1.2), (1.3, 0.36, 0.04)),
        ]
    for part in glass_parts:
        bag.add(part, (1, 1, 1, 1), 0.006, 1)
    # A dark cabin shell keeps the desert from showing through both side windows.
    cabin = cube("cabin", (0, 1.05 if rally else 1.3, 0.25), (1.35 if rally else 1.5, 0.45 if rally else 0.55, 1.0 if rally else 1.3))
    bag.add(cabin, rubber, 0)
    bpy.context.view_layer.update()
    body = []
    glass = []
    glass_ids = {id(part) for part in glass_parts}
    for obj, color in bag.groups:
        baked = collect(obj, color)
        if id(obj) in glass_ids:
            glass.extend(baked)
        else:
            body.extend(baked)
    return body, glass


def bike_body():
    bag = MeshBag()
    frame = linear(0.45, 0.18, 0.08)
    dark = linear(0.08, 0.08, 0.09)
    metal = linear(0.55, 0.56, 0.58)
    seat = linear(0.04, 0.04, 0.045)
    warm = linear(1.0, 0.75, 0.3)
    bag.add(cube("engine", (0, 0.58, 0.02), (0.32, 0.32, 0.46)), dark, 0.02, 2)
    bag.add(solid(
        "tank",
        [(-0.16, 0.74, -0.28), (0.16, 0.74, -0.28), (0.18, 0.74, 0.18), (-0.18, 0.74, 0.18)],
        [(-0.12, 0.98, -0.22), (0.12, 0.98, -0.22), (0.14, 0.9, 0.16), (-0.14, 0.9, 0.16)],
    ), frame, 0.016, 2)
    bag.add(solid(
        "seat",
        [(-0.14, 0.78, 0.05), (0.14, 0.78, 0.05), (0.12, 0.78, 0.58), (-0.12, 0.78, 0.58)],
        [(-0.13, 0.9, 0.08), (0.13, 0.9, 0.08), (0.1, 0.86, 0.55), (-0.1, 0.86, 0.55)],
    ), seat, 0.01, 1)
    bag.add(cube("swing", (0, 0.4, 0.42), (0.1, 0.08, 0.7)), metal, 0.008, 1)
    bag.add(cube("fork_l", (-0.08, 0.72, -0.78), (0.04, 0.55, 0.04)), metal, 0.004, 1)
    bag.add(cube("fork_r", (0.08, 0.72, -0.78), (0.04, 0.55, 0.04)), metal, 0.004, 1)
    bag.add(cube("bar", (0, 1.02, -0.48), (0.62, 0.04, 0.04)), metal, 0.006, 1)
    bag.add(cube("grip_l", (-0.34, 1.02, -0.48), (0.14, 0.05, 0.05)), dark, 0.004, 1)
    bag.add(cube("grip_r", (0.34, 1.02, -0.48), (0.14, 0.05, 0.05)), dark, 0.004, 1)
    bag.add(cube("spine", (0, 0.7, -0.28), (0.06, 0.06, 0.55)), frame, 0.006, 1)
    bag.add(cube("peg_l", (-0.22, 0.4, -0.05), (0.16, 0.03, 0.08)), metal, 0.003, 1)
    bag.add(cube("peg_r", (0.22, 0.4, -0.05), (0.16, 0.03, 0.08)), metal, 0.003, 1)
    bag.add(cube("lamp", (0, 0.88, -0.72), (0.16, 0.16, 0.1)), warm, 0.008, 1)
    bag.add(cube("fender_f", (0, 0.78, -0.95), (0.12, 0.08, 0.36)), frame, 0.006, 1)
    bag.add(cube("exhaust", (0.22, 0.38, 0.15), (0.07, 0.07, 0.7)), metal, 0.004, 1)
    bpy.context.view_layer.update()
    body = []
    for obj, color in bag.groups:
        body.extend(collect(obj, color))
    return body


def jeep_body():
    bag = MeshBag()
    paint = linear(0.24, 0.32, 0.16)
    dark = linear(0.08, 0.09, 0.08)
    canvas = linear(0.40, 0.34, 0.22)
    metal = linear(0.45, 0.46, 0.44)
    warm = linear(1.0, 0.72, 0.28)
    red = linear(0.55, 0.08, 0.04)
    arches = [(-1.0, 0.45, 0.62), (1.0, 0.45, 0.62)]
    profile = side_profile(-1.7, 1.7, 0.72, 1.08, arches)
    bag.add(profile_solid("fender_l", profile, -1.22, -0.72), paint, 0.014, 1)
    bag.add(profile_solid("fender_r", profile, 0.72, 1.22), paint, 0.014, 1)
    bag.add(cube("tub_floor", (0, 0.66, 0.35), (1.45, 0.12, 2.3)), paint, 0.012, 1)
    bag.add(cube("tub_l", (-0.78, 0.9, 0.4), (0.1, 0.42, 2.15)), paint, 0.01, 1)
    bag.add(cube("tub_r", (0.78, 0.9, 0.4), (0.1, 0.42, 2.15)), paint, 0.01, 1)
    bag.add(cube("tail", (0, 0.9, 1.48), (1.45, 0.42, 0.1)), paint, 0.01, 1)
    bag.add(solid(
        "hood",
        [(-0.72, 0.9, -1.72), (0.72, 0.9, -1.72), (0.78, 1.02, -0.4), (-0.78, 1.02, -0.4)],
        [(-0.68, 1.08, -1.68), (0.68, 1.08, -1.68), (0.74, 1.22, -0.42), (-0.74, 1.22, -0.42)],
    ), paint, 0.016, 2)
    bag.add(cube("grille", (0, 0.95, -1.74), (0.7, 0.42, 0.08)), dark, 0.008, 1)
    for x in (-0.42, 0.42):
        bag.add(cube("seat", (x, 1.05, 0.05), (0.46, 0.16, 0.46)), canvas, 0.01, 1)
        bag.add(cube("back", (x, 1.32, 0.26), (0.44, 0.42, 0.1)), canvas, 0.008, 1)
    for x in (-0.72, 0.72):
        for z in (-0.15, 0.85):
            bag.add(cube("post", (x, 1.65, z), (0.07, 1.05, 0.07)), dark, 0.004, 1)
    bag.add(cube("rail_f", (0, 2.15, -0.15), (1.5, 0.07, 0.07)), dark, 0.004, 1)
    bag.add(cube("rail_r", (0, 2.05, 0.85), (1.5, 0.07, 0.07)), dark, 0.004, 1)
    bag.add(cube("rail_l", (-0.72, 2.1, 0.35), (0.07, 0.07, 1.05)), dark, 0.004, 1)
    bag.add(cube("rail_r2", (0.72, 2.1, 0.35), (0.07, 0.07, 1.05)), dark, 0.004, 1)
    for x in (-0.48, 0.48):
        bag.add(cube("bezel", (x, 0.95, -1.7), (0.3, 0.18, 0.06)), metal, 0.004, 1)
        bag.add(cube("lamp", (x, 0.95, -1.66), (0.18, 0.12, 0.04)), warm, 0.003, 1)
    bag.add(cube("tail_l", (-0.55, 0.9, 1.56), (0.16, 0.1, 0.04)), red, 0.003, 1)
    bag.add(cube("tail_r", (0.55, 0.9, 1.56), (0.16, 0.1, 0.04)), red, 0.003, 1)
    spare = wheel_tris(0.36, 0.18, linear(0.03, 0.03, 0.03), metal, axle="Z")
    bpy.context.view_layer.update()
    body = []
    for obj, color in bag.groups:
        body.extend(collect(obj, color))
    body.extend((x, y + 0.82, z + 1.62, nx, ny, nz, r, g, b, a) for x, y, z, nx, ny, nz, r, g, b, a in spare)
    return shift_ground([body])[0]


def validate_tris(name, verts):
    if len(verts) % 3 != 0 or len(verts) < 3:
        raise RuntimeError(f"{name} has {len(verts)} vertices")
    for vert in verts:
        if not all(math.isfinite(channel) for channel in vert[:6]):
            raise RuntimeError(f"{name} has a bad vertex")


def gallery(objects, location):
    empty = bpy.data.objects.new(objects[0].name + "_root", None)
    bpy.context.scene.collection.objects.link(empty)
    empty.location = Vector(location)
    for obj in objects:
        if obj.name.endswith("_cut"):
            continue
        obj.parent = empty
    return empty


def build():
    purge_work()
    house_specs = [
        ("house_type01", dict(w=5.3, d=3.7, wall=2.35, h=3.25, floors=1, roof_kind="gable", porch=0.9,
                              front_x=(-1.2, 1.2), wall_color=(0.78, 0.70, 0.58), roof=(0.45, 0.18, 0.12),
                              trim=(0.85, 0.80, 0.70), door=(0.28, 0.16, 0.09), chimney=True)),
        ("house_type02", dict(w=5.4, d=4.5, wall=3.9, h=5.0, floors=2, roof_kind="gable", porch=1.5,
                              front_x=(-1.35, 1.35), wall_color=(0.86, 0.82, 0.74), roof=(0.30, 0.18, 0.12),
                              trim=(0.75, 0.68, 0.55), door=(0.22, 0.13, 0.08), chimney=True)),
        ("house_type06", dict(w=5.3, d=4.6, wall=3.55, h=5.0, floors=2, roof_kind="gable", porch=0.4, dormer=True,
                              front_x=(-1.45, 0, 1.45), wall_color=(0.72, 0.62, 0.40), roof=(0.18, 0.16, 0.15),
                              trim=(0.88, 0.84, 0.76), door=(0.33, 0.20, 0.10), chimney=True)),
        ("house_type08", dict(w=7.1, d=3.9, wall=3.7, h=5.25, floors=2, roof_kind="front", porch=0.8,
                              front_x=(-2.2, -0.7, 0.8, 2.2), wall_color=(0.70, 0.55, 0.38), roof=(0.40, 0.16, 0.10),
                              trim=(0.90, 0.86, 0.78), door=(0.25, 0.14, 0.08), side_windows=True)),
        ("house_type10", dict(w=7.4, d=5.4, wall=4.15, h=5.0, floors=2, roof_kind="flat", porch=1.8,
                              front_x=(-2.3, -0.8, 0.8, 2.3), wall_color=(0.62, 0.42, 0.36), roof=(0.34, 0.30, 0.26),
                              trim=(0.80, 0.72, 0.58), door=(0.20, 0.12, 0.08), chimney=False)),
        ("house_type17", dict(w=5.8, d=4.3, wall=3.6, h=5.0, floors=2, roof_kind="hip", porch=0.6,
                              front_x=(-1.5, 1.5), wall_color=(0.64, 0.58, 0.42), roof=(0.48, 0.28, 0.16),
                              trim=(0.82, 0.74, 0.60), door=(0.30, 0.17, 0.09), chimney=True)),
    ]
    environment = []
    display = []
    for index, (name, spec) in enumerate(house_specs):
        intact = house(spec)
        ruined_spec = dict(spec)
        ruined_spec["ruin"] = True
        ruined_spec["dormer"] = False
        ruined = house(ruined_spec)
        environment.append((name, intact))
        environment.append((name + "-ruin", ruined))
        print(name, "body", len(intact[0][1]) // 3, "glass", len(intact[1][1]) // 3,
              "ruin", len(ruined[0][1]) // 3)
    environment.append(("fence_large", fence(False)))
    environment.append(("fence_open", fence(True)))
    environment.append(("rock", rock()))
    for name, groups in environment:
        for part, verts in groups:
            validate_tris(name + " " + part, verts)
    payload = pack_environment(environment, ROOT / "EnvironmentMesh.json", ROOT / "EnvironmentMesh.bin")
    print("environment models", len(payload), "bytes", (ROOT / "EnvironmentMesh.bin").stat().st_size)

    rubber = linear(0.03, 0.03, 0.035)
    alloy = linear(0.62, 0.63, 0.64)
    rally_body, rally_glass = car_body("rally")
    suv_body, suv_glass = car_body("suv")
    bike = bike_body()
    jeep = jeep_body()
    for label, verts in (("rally", rally_body), ("rally glass", rally_glass), ("suv", suv_body),
                         ("suv glass", suv_glass), ("bike", bike), ("jeep", jeep)):
        validate_tris(label, verts)
        print(label, len(verts) // 3)

    rally_wheels = [
        ("wheel-front-left", [-0.78, 0.42, -1.18], wheel_tris(0.36, 0.26, rubber, alloy)),
        ("wheel-front-right", [0.78, 0.42, -1.18], wheel_tris(0.36, 0.26, rubber, alloy)),
        ("wheel-back-left", [-0.78, 0.42, 1.18], wheel_tris(0.36, 0.26, rubber, alloy)),
        ("wheel-back-right", [0.78, 0.42, 1.18], wheel_tris(0.36, 0.26, rubber, alloy)),
    ]
    suv_wheels = [
        ("wheel-front-left", [-0.9, 0.42, -1.32], wheel_tris(0.4, 0.3, rubber, alloy)),
        ("wheel-front-right", [0.9, 0.42, -1.32], wheel_tris(0.4, 0.3, rubber, alloy)),
        ("wheel-back-left", [-0.9, 0.42, 1.32], wheel_tris(0.4, 0.3, rubber, alloy)),
        ("wheel-back-right", [0.9, 0.42, 1.32], wheel_tris(0.4, 0.3, rubber, alloy)),
    ]
    bike_wheels = [
        ("wheel-front", [0, 0.42, -0.95], wheel_tris(0.34, 0.14, rubber, alloy)),
        ("wheel-rear", [0, 0.42, 0.72], wheel_tris(0.34, 0.16, rubber, alloy)),
    ]
    pack_vehicle("hatchback-sports", [("body", [0, 0, 0], rally_body), ("glass", [0, 0, 0], rally_glass), *rally_wheels])
    pack_vehicle("suv", [("body", [0, 0, 0], suv_body), ("glass", [0, 0, 0], suv_glass), *suv_wheels])
    pack_vehicle("bike", [("body", [0, 0, 0], bike), *bike_wheels])
    pack_sculpt("JeepBody", jeep)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT.parent.parent / "Tools" / "TheDriveAssets.blend"))
    print("saved", ROOT.parent.parent / "Tools" / "TheDriveAssets.blend")


if __name__ == "__main__":
    build()
