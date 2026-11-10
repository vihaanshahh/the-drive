#!/usr/bin/env python3
"""Build surfaced town, jeep, and character meshes for The Drive.

Blender is not required. Buildings and the jeep are modeled as curved shells
with recessed openings, and the bundled character is Loop-subdivided once so
its limbs stay skinned to the original skeleton.
"""

import json
import math
import struct
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "TheDrive" / "Assets"


def linear(r, g, b, a=1.0):
    def channel(value):
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
    return (channel(r), channel(g), channel(b), a)


SAND = linear(0.78, 0.64, 0.48)
ADOBE = linear(0.74, 0.50, 0.34)
PLASTER = linear(0.84, 0.76, 0.64)
ROSE = linear(0.76, 0.58, 0.50)
LIMESTONE = linear(0.80, 0.75, 0.66)
OCHRE = linear(0.76, 0.56, 0.30)
CLAY = linear(0.62, 0.30, 0.20)
TERRACOTTA = linear(0.70, 0.36, 0.24)
TIMBER = linear(0.34, 0.22, 0.14)
TRIM = linear(0.28, 0.20, 0.14)
STONE = linear(0.52, 0.46, 0.38)
DARK = linear(0.16, 0.13, 0.11)
WHITE = (1.0, 1.0, 1.0, 1.0)
OLIVE = linear(0.40, 0.45, 0.26)
OLIVE_DARK = linear(0.28, 0.32, 0.18)
SEAT = linear(0.46, 0.32, 0.20)
STEEL = linear(0.62, 0.63, 0.58)
RUBBER = linear(0.10, 0.10, 0.09)
RUST = linear(0.55, 0.26, 0.13)
TAN = linear(0.62, 0.48, 0.32)


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def length(a):
    return math.sqrt(dot(a, a))


def norm(a):
    scale = length(a)
    if scale < 1e-8:
        return (0.0, 1.0, 0.0)
    return (a[0] / scale, a[1] / scale, a[2] / scale)


def lerp(a, b, t):
    return add(a, mul(sub(b, a), t))


def mix(a, b, t):
    return a * (1 - t) + b * t


class Mesh:
    def __init__(self):
        self.faces = []

    def add(self, a, b, c, color):
        area = length(cross(sub(b, a), sub(c, a)))
        if area < 1e-7:
            return
        self.faces.append((a, b, c, color))

    def quad(self, a, b, c, d, outward, color):
        normal = cross(sub(b, a), sub(c, a))
        if dot(normal, outward) < 0:
            a, b, c, d = a, d, c, b
        self.add(a, b, c, color)
        self.add(a, c, d, color)

    def box(self, mn, mx, color):
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        if x1 < x0:
            x0, x1 = x1, x0
        if y1 < y0:
            y0, y1 = y1, y0
        if z1 < z0:
            z0, z1 = z1, z0
        self.quad((x0, y1, z0), (x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (0, 1, 0), color)
        self.quad((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0), color)
        self.quad((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1), color)
        self.quad((x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (0, 0, -1), color)
        self.quad((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1), (1, 0, 0), color)
        self.quad((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (-1, 0, 0), color)

    def grid(self, points, outward, color, skip=None):
        rows = len(points) - 1
        cols = len(points[0]) - 1
        for j in range(rows):
            v = (j + 0.5) / rows
            for i in range(cols):
                u = (i + 0.5) / cols
                if skip and skip(u, v):
                    continue
                self.quad(points[j][i], points[j][i + 1], points[j + 1][i + 1], points[j + 1][i], outward, color)

    def cylinder(self, a, b, radius, color, sides=12, caps=True):
        axis = norm(sub(b, a))
        helper = (1.0, 0.0, 0.0) if abs(axis[0]) < 0.9 else (0.0, 1.0, 0.0)
        tangent = norm(cross(axis, helper))
        bitangent = cross(axis, tangent)
        ring0, ring1 = [], []
        for i in range(sides):
            angle = math.tau * i / sides
            offset = add(mul(tangent, math.cos(angle) * radius), mul(bitangent, math.sin(angle) * radius))
            ring0.append(add(a, offset))
            ring1.append(add(b, offset))
        for i in range(sides):
            j = (i + 1) % sides
            outward = norm(add(sub(ring0[i], a), sub(ring0[j], a)))
            self.quad(ring0[i], ring0[j], ring1[j], ring1[i], outward, color)
            if caps:
                self.add(a, ring0[j], ring0[i], color)
                self.add(b, ring1[i], ring1[j], color)

    def translate(self, offset):
        self.faces = [
            (add(a, offset), add(b, offset), add(c, offset), color)
            for a, b, c, color in self.faces
        ]

    def bounds(self):
        lows = [1e9, 1e9, 1e9]
        highs = [-1e9, -1e9, -1e9]
        for face in self.faces:
            for vertex in face[:3]:
                for axis in range(3):
                    lows[axis] = min(lows[axis], vertex[axis])
                    highs[axis] = max(highs[axis], vertex[axis])
        return lows, highs

    def bake(self, crease=42.0):
        limit = math.cos(math.radians(crease))
        normals = []
        buckets = defaultdict(list)
        for index, (a, b, c, _) in enumerate(self.faces):
            normals.append(norm(cross(sub(b, a), sub(c, a))))
            for corner, vertex in enumerate((a, b, c)):
                buckets[tuple(round(value, 4) for value in vertex)].append((index, corner))
        soup = []
        for index, face in enumerate(self.faces):
            for corner, vertex in enumerate(face[:3]):
                key = tuple(round(value, 4) for value in vertex)
                base = normals[index]
                total = (0.0, 0.0, 0.0)
                for other, _ in buckets[key]:
                    if dot(base, normals[other]) >= limit:
                        total = add(total, normals[other])
                baked = norm(total)
                tone = 1 + 0.045 * math.sin(vertex[0] * 1.7 + vertex[2] * 0.6) * math.cos(vertex[2] * 1.1 + vertex[1] * 0.4)
                color = face[3]
                tint = tuple(min(1.0, max(0.0, channel * tone)) if channel_index < 3 else channel for channel_index, channel in enumerate(color))
                soup.append((*vertex, *baked, *tint))
        return soup


def subtract_rects(bounds, holes):
    rects = [bounds]
    for hole in holes:
        nxt = []
        for rect in rects:
            nxt.extend(split_rect(rect, hole))
        rects = [rect for rect in nxt if rect[2] - rect[0] > 0.02 and rect[3] - rect[1] > 0.02]
    return rects


def split_rect(rect, hole):
    x0, y0, x1, y1 = rect
    hx0, hy0, hx1, hy1 = hole
    ix0, iy0 = max(x0, hx0), max(y0, hy0)
    ix1, iy1 = min(x1, hx1), min(y1, hy1)
    if ix0 >= ix1 or iy0 >= iy1:
        return [rect]
    pieces = []
    if y0 < iy0:
        pieces.append((x0, y0, x1, iy0))
    if iy1 < y1:
        pieces.append((x0, iy1, x1, y1))
    if x0 < ix0:
        pieces.append((x0, iy0, ix0, iy1))
    if ix1 < x1:
        pieces.append((ix1, iy0, x1, iy1))
    return pieces


def facade(mesh, origin, axis_u, axis_v, inward, width, height, thickness, holes, color, breach=False):
    rects = subtract_rects((0.0, 0.0, width, height), holes)
    if breach and len(rects) > 4:
        rects.pop(len(rects) // 3)
    inner = scale_rgb(color, 0.62)
    edges = defaultdict(int)
    for x0, y0, x1, y1 in rects:
        for edge in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
            edges[canonical_edge(edge)] += 1
        corner = add(origin, add(mul(axis_u, x0), mul(axis_v, y0)))
        opposite = add(origin, add(mul(axis_u, x1), mul(axis_v, y1)))
        u = add(origin, add(mul(axis_u, x1), mul(axis_v, y0)))
        v = add(origin, add(mul(axis_u, x0), mul(axis_v, y1)))
        mesh.quad(corner, u, opposite, v, mul(inward, -1), color)
        mesh.quad(add(corner, mul(inward, thickness)), add(v, mul(inward, thickness)), add(opposite, mul(inward, thickness)), add(u, mul(inward, thickness)), inward, inner)
    for (start, end), count in edges.items():
        if count != 1:
            continue
        a = add(origin, add(mul(axis_u, start[0]), mul(axis_v, start[1])))
        b = add(origin, add(mul(axis_u, end[0]), mul(axis_v, end[1])))
        direction = norm(sub(b, a))
        outward = norm(cross(direction, inward))
        mesh.quad(a, b, add(b, mul(inward, thickness)), add(a, mul(inward, thickness)), outward, scale_rgb(color, 0.9))


def canonical_edge(edge):
    a, b = edge
    return (a, b) if a <= b else (b, a)


def scale_rgb(color, factor):
    return tuple(min(1.0, channel * factor) if index < 3 else channel for index, channel in enumerate(color))


def place(origin, axis_u, axis_v, x, y):
    return add(origin, add(mul(axis_u, x), mul(axis_v, y)))


def opening(mesh, glass, origin, axis_u, axis_v, inward, hole, frame, glazed=True):
    x0, y0, x1, y1 = hole
    depth = 0.045
    proud = mul(inward, -depth)
    z = mul(inward, 0.11)
    frame_t = 0.07
    sill = 0.08
    mesh.box_frame(origin, axis_u, axis_v, hole, frame_t, proud, frame)
    mesh.box(
        corner_min(origin, axis_u, axis_v, inward, x0 - 0.02, y0 - sill, -0.02),
        corner_max(origin, axis_u, axis_v, inward, x1 + 0.02, y0 + 0.045, 0.08),
        frame,
    )
    if glazed and glass is not None:
        a = add(place(origin, axis_u, axis_v, x0 + 0.04, y0 + 0.04), z)
        b = add(place(origin, axis_u, axis_v, x1 - 0.04, y0 + 0.04), z)
        c = add(place(origin, axis_u, axis_v, x1 - 0.04, y1 - 0.04), z)
        d = add(place(origin, axis_u, axis_v, x0 + 0.04, y1 - 0.04), z)
        glass.quad(a, b, c, d, mul(inward, -1), WHITE)
        mid_x = (x0 + x1) * 0.5
        mesh.box(
            corner_min(origin, axis_u, axis_v, inward, mid_x - 0.02, y0 + 0.05, 0.09),
            corner_max(origin, axis_u, axis_v, inward, mid_x + 0.02, y1 - 0.05, 0.13),
            frame,
        )


def corner_min(origin, axis_u, axis_v, inward, x, y, depth):
    point = add(place(origin, axis_u, axis_v, x, y), mul(inward, depth))
    return point


def corner_max(origin, axis_u, axis_v, inward, x, y, depth):
    return add(place(origin, axis_u, axis_v, x, y), mul(inward, depth))


def _box_from_axes(mesh, origin, axis_u, axis_v, inward, x0, y0, d0, x1, y1, d1, color):
    points = []
    for x, y, depth in (
        (x0, y0, d0), (x1, y0, d0), (x1, y1, d0), (x0, y1, d0),
        (x0, y0, d1), (x1, y0, d1), (x1, y1, d1), (x0, y1, d1),
    ):
        points.append(add(place(origin, axis_u, axis_v, x, y), mul(inward, depth)))
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    zs = [point[2] for point in points]
    mesh.box((min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs)), color)


Mesh.box_frame = lambda self, origin, axis_u, axis_v, hole, thickness, proud, color: frame_box(self, origin, axis_u, axis_v, hole, thickness, proud, color)


def frame_box(mesh, origin, axis_u, axis_v, hole, thickness, proud, color):
    x0, y0, x1, y1 = hole
    outward = mul(proud, -1) if length(proud) else (0, 0, -1)
    # Proud is a small offset opposite the inward wall direction. Build the frame
    # as four thin slabs in world space by sampling the facade plane.
    slabs = (
        (x0 - thickness, y0, x0, y1),
        (x1, y0, x1 + thickness, y1),
        (x0, y1, x1, y1 + thickness),
        (x0 - thickness, y0 - thickness, x1 + thickness, y0),
    )
    for sx0, sy0, sx1, sy1 in slabs:
        a = add(place(origin, axis_u, axis_v, sx0, sy0), proud)
        b = add(place(origin, axis_u, axis_v, sx1, sy0), proud)
        c = add(place(origin, axis_u, axis_v, sx1, sy1), proud)
        d = add(place(origin, axis_u, axis_v, sx0, sy1), proud)
        depth = mul(norm(inward_from_proud(proud, axis_u, axis_v)), 0.05)
        mesh.quad(a, b, c, d, outward, color)
        mesh.quad(add(a, depth), add(d, depth), add(c, depth), add(b, depth), mul(outward, -1), color)


def inward_from_proud(proud, axis_u, axis_v):
    return norm(cross(axis_u, axis_v))


def slope_sheet(mesh, p00, p10, p01, p11, outward, color, across=18, up=12, tiles=9, amp=0.035, skips=()):
    points = []
    for j in range(up + 1):
        v = j / up
        row = []
        for i in range(across + 1):
            u = i / across
            point = lerp(lerp(p00, p10, u), lerp(p01, p11, u), v)
            wave = amp * math.sin((u * tiles + (0.5 if j % 2 else 0.0)) * math.pi) ** 2
            row.append((point[0], point[1] + wave, point[2]))
        points.append(row)

    def skip(u, v):
        return any(a <= u <= c and b <= v <= d for a, b, c, d in skips)

    mesh.grid(points, outward, color, skip)
    thickness = 0.07
    inner = [[add(point, mul(outward, -thickness)) for point in row] for row in points]
    mesh.grid(inner, mul(outward, -1), scale_rgb(color, 0.72), skip)
    return points


def gable_roof(mesh, x0, x1, z0, z1, y_eave, y_ridge, color, skips=(), amp=0.03, wall=SAND):
    mid = (z0 + z1) * 0.5
    street = slope_sheet(
        mesh, (x0, y_eave, z0), (x1, y_eave, z0), (x0, y_ridge, mid), (x1, y_ridge, mid),
        (0, 0.55, -0.85), color, skips=skips, amp=amp,
    )
    slope_sheet(
        mesh, (x0, y_eave, z1), (x1, y_eave, z1), (x0, y_ridge, mid), (x1, y_ridge, mid),
        (0, 0.55, 0.85), color, skips=(), amp=amp,
    )
    cap = scale_rgb(color, 0.82)
    mesh.box((x0 + 0.02, y_ridge - 0.02, mid - 0.09), (x1 - 0.02, y_ridge + 0.08, mid + 0.09), cap)
    timber = scale_rgb(TIMBER, 1.0)
    for x, sign in ((x0, -1), (x1, 1)):
        outer = (
            (x, y_eave, z0),
            (x, y_ridge, mid),
            (x, y_eave, z1),
        )
        inner = [(point[0] + sign * 0.16, point[1], point[2]) for point in outer]
        mesh.add(*outer, wall)
        mesh.add(inner[0], inner[2], inner[1], scale_rgb(wall, 0.7))
        for i in range(3):
            j = (i + 1) % 3
            mesh.quad(outer[i], outer[j], inner[j], inner[i], (sign, 0, 0), scale_rgb(wall, 0.85))
        mesh.cylinder((x + sign * 0.02, y_eave + 0.08, z0 + 0.08), (x + sign * 0.02, y_ridge - 0.02, mid), 0.035, timber, sides=6, caps=False)
    fascia = scale_rgb(color, 0.75)
    mesh.box((x0, y_eave - 0.08, z0 - 0.04), (x1, y_eave + 0.02, z0 + 0.02), fascia)
    mesh.box((x0, y_eave - 0.08, z1 - 0.02), (x1, y_eave + 0.02, z1 + 0.04), fascia)
    return street


def hip_roof(mesh, x0, x1, z0, z1, y_eave, y_ridge, color):
    inset_x = (x1 - x0) * 0.22
    inset_z = (z1 - z0) * 0.22
    ridge0 = (x0 + inset_x, y_ridge, z0 + inset_z)
    ridge1 = (x1 - inset_x, y_ridge, z0 + inset_z)
    ridge2 = (x1 - inset_x, y_ridge, z1 - inset_z)
    ridge3 = (x0 + inset_x, y_ridge, z1 - inset_z)
    slope_sheet(mesh, (x0, y_eave, z0), (x1, y_eave, z0), ridge0, ridge1, (0, 0.6, -0.8), color, across=16, up=8, tiles=8)
    slope_sheet(mesh, (x1, y_eave, z0), (x1, y_eave, z1), ridge1, ridge2, (0.8, 0.6, 0), color, across=14, up=8, tiles=7)
    slope_sheet(mesh, (x1, y_eave, z1), (x0, y_eave, z1), ridge2, ridge3, (0, 0.6, 0.8), color, across=16, up=8, tiles=8)
    slope_sheet(mesh, (x0, y_eave, z1), (x0, y_eave, z0), ridge3, ridge0, (-0.8, 0.6, 0), color, across=14, up=8, tiles=7)
    mesh.box((ridge0[0], y_ridge - 0.02, ridge0[2]), (ridge2[0], y_ridge + 0.06, ridge2[2]), scale_rgb(color, 0.8))


def chimney(mesh, x, z, y0, y1, color):
    mesh.box((x - 0.22, y0, z - 0.22), (x + 0.22, y1, z + 0.22), color)
    mesh.box((x - 0.28, y1, z - 0.28), (x + 0.28, y1 + 0.1, z + 0.28), scale_rgb(color, 0.75))
    mesh.box((x - 0.1, y1 + 0.1, z - 0.1), (x + 0.1, y1 + 0.16, z + 0.1), DARK)


def column(mesh, x, z, y0, y1, radius, color):
    mesh.cylinder((x, y0, z), (x, y1, z), radius, color, sides=10)
    mesh.cylinder((x, y0, z), (x, y0 + 0.06, z), radius * 1.35, scale_rgb(color, 0.8), sides=10)
    mesh.cylinder((x, y1 - 0.05, z), (x, y1 + 0.02, z), radius * 1.25, scale_rgb(color, 0.85), sides=10)


def rubble(mesh, x, z, scale=1.0):
    mesh.sphere((x, 0.16 * scale, z), 0.34 * scale, STONE, (1.3, 0.55, 1.05))
    mesh.sphere((x + 0.38 * scale, 0.1 * scale, z + 0.2 * scale), 0.22 * scale, scale_rgb(STONE, 0.85), (1.1, 0.6, 1.2))
    mesh.sphere((x - 0.22 * scale, 0.08 * scale, z + 0.28 * scale), 0.16 * scale, TIMBER, (1.0, 0.7, 1.0))


def _sphere(mesh, center, radius, color, scale):
    seg, rings = 10, 6
    for ring in range(rings):
        v0 = (ring / rings) * math.pi
        v1 = ((ring + 1) / rings) * math.pi
        for step in range(seg):
            u0 = math.tau * step / seg
            u1 = math.tau * (step + 1) / seg
            def point(u, v):
                raw = (
                    math.cos(u) * math.sin(v) * scale[0],
                    math.cos(v) * scale[1],
                    math.sin(u) * math.sin(v) * scale[2],
                )
                return add(center, mul(raw, radius))
            a, b, c, d = point(u0, v0), point(u1, v0), point(u1, v1), point(u0, v1)
            mesh.quad(a, d, c, b, norm(sub(add(a, c), mul(center, 2))), color)


Mesh.sphere = lambda self, center, radius, color, scale=(1, 1, 1): _sphere(self, center, radius, color, scale)


def shell(body, glass, spec, wall, roof, holes, ruined, porch=0.0, stories=1):
    w, d, h = spec["w"], spec["d"], spec["h"]
    x0, x1 = -w / 2 + 0.18, w / 2 - 0.18
    z_front = -d / 2 + 0.28 + porch
    z_back = d / 2 - 0.22
    wall_h = 2.35 if stories == 1 else min(h - 0.85, 3.15 if stories == 2 else 2.5)
    if stories == 2:
        wall_h = min(4.15, h - 0.9)
    thickness = 0.2
    body.box((x0 - 0.08, 0.0, z_front - 0.06), (x1 + 0.08, 0.16, z_back + 0.06), STONE)
    body.box((x0 + 0.05, 0.16, z_front + thickness), (x1 - 0.05, 0.22, z_back - thickness), scale_rgb(DARK, 1.4))
    facade(
        body, (x0, 0.16, z_front), (1, 0, 0), (0, 1, 0), (0, 0, 1),
        x1 - x0, wall_h - 0.16, thickness, [(hole[0] - x0, hole[1] - 0.16, hole[2] - x0, hole[3] - 0.16) for hole in holes],
        wall, breach=False,
    )
    back_holes = []
    if stories == 2:
        back_holes = [(0.35, 2.15, 1.15, 2.9), (x1 - x0 - 1.15, 2.15, x1 - x0 - 0.35, 2.9)]
    facade(
        body, (x1, 0.16, z_back), (-1, 0, 0), (0, 1, 0), (0, 0, -1),
        x1 - x0, wall_h - 0.16, thickness, back_holes, wall, breach=ruined,
    )
    side_h = wall_h - 0.16
    side_d = z_back - z_front - 2 * thickness
    side_holes = []
    if side_d > 2.1:
        side_holes.append((0.4, 0.85, 1.15, 1.75))
    if side_d > 3.4:
        side_holes.append((side_d - 1.3, 0.85, side_d - 0.45, 1.75))
    if stories == 2 and side_d > 2.4 and side_h > 3.1:
        side_holes.append((side_d * 0.38, 2.2, side_d * 0.38 + 0.72, 3.05))
    facade(body, (x0, 0.16, z_front + thickness), (0, 0, 1), (0, 1, 0), (1, 0, 0), side_d, side_h, thickness, side_holes, wall)
    facade(body, (x1, 0.16, z_back - thickness), (0, 0, -1), (0, 1, 0), (-1, 0, 0), side_d, side_h, thickness, side_holes, wall)
    for hole in side_holes:
        opening(body, glass, (x0, 0.16, z_front + thickness), (0, 0, 1), (0, 1, 0), (1, 0, 0), hole, TRIM)
        opening(body, glass, (x1, 0.16, z_back - thickness), (0, 0, -1), (0, 1, 0), (-1, 0, 0), hole, TRIM)
    for hole in holes:
        door = hole[1] < 0.4 and hole[3] - hole[1] > 1.4
        opening(body, glass, (0, 0, z_front), (1, 0, 0), (0, 1, 0), (0, 0, 1), hole, TRIM, glazed=not door and not (ruined and hole[1] > 2.2 and hole[0] > 0))
        if door:
            body.box((hole[0] + 0.08, hole[1], z_front + 0.03), (hole[2] - 0.08, hole[3] - 0.06, z_front + 0.1), TIMBER)
            body.box((hole[0] + 0.16, hole[1] + 0.18, z_front + 0.015), (hole[2] - 0.16, hole[1] + 0.85, z_front + 0.04), scale_rgb(TIMBER, 0.72))
            body.cylinder(((hole[0] + hole[2]) * 0.5 + 0.22, hole[1] + 0.95, z_front - 0.01), ((hole[0] + hole[2]) * 0.5 + 0.22, hole[1] + 0.95, z_front + 0.06), 0.035, STEEL, sides=8)
    y_eave = wall_h - 0.05
    y_ridge = h - 0.02
    return x0, x1, z_front, z_back, y_eave, y_ridge


def windows_and_door(cx, width, door=True, upper=False):
    holes = []
    if door:
        holes.append((cx - 0.42, 0.16, cx + 0.42, 2.18))
    holes.append((cx - 1.85, 1.05, cx - 1.05, 2.0))
    holes.append((cx + 1.05, 1.05, cx + 1.85, 2.0))
    if upper:
        holes.append((cx - 1.7, 2.55, cx - 0.95, 3.45))
        holes.append((cx + 0.95, 2.55, cx + 1.7, 3.45))
    if width > 6.4:
        holes.append((cx - 2.7, 1.15, cx - 2.05, 1.95))
        holes.append((cx + 2.05, 1.15, cx + 2.7, 1.95))
    return [hole for hole in holes if hole[2] - hole[0] > 0.2]


def build_cottage(spec, ruined):
    body, glass = Mesh(), Mesh()
    holes = [(spec["w"] * 0 - 0.4, 0.16, 0.4, 2.12), (-1.55, 1.02, -0.75, 1.92), (0.75, 1.02, 1.55, 1.92)]
    x0, x1, z0, z1, y_eave, y_ridge = shell(body, glass, spec, SAND, CLAY, holes, ruined)
    skips = [((0.15, 0.25, 0.55, 0.7))] if ruined else []
    gable_roof(body, x0 - 0.34, x1 + 0.34, z0 - 0.32, z1 + 0.28, y_eave, y_ridge, CLAY, skips=skips, wall=SAND)
    chimney(body, x0 + 0.55, (z0 + z1) * 0.5 + 0.3, y_eave - 0.2, y_ridge + 0.45, STONE)
    body.box((-0.55, 0.16, z0 - 0.42), (0.55, 0.32, z0), STONE)
    if ruined:
        rubble(body, x1 - 0.4, z1 - 0.3)
    return body, glass


def build_porch(spec, ruined):
    body, glass = Mesh(), Mesh()
    holes = windows_and_door(0, spec["w"], upper=True)
    porch = 1.15
    x0, x1, z0, z1, y_eave, y_ridge = shell(body, glass, spec, PLASTER, TERRACOTTA, holes, ruined, porch=porch, stories=2)
    gable_roof(body, x0 - 0.4, x1 + 0.4, z0 - porch - 0.15, z1 + 0.3, y_eave, y_ridge, TERRACOTTA, skips=[(0.4, 0.15, 0.85, 0.62)] if ruined else [], wall=PLASTER)
    deck_z = z0 - porch
    body.box((x0 + 0.1, 0.16, deck_z), (x1 - 0.1, 0.38, z0 + 0.02), scale_rgb(TIMBER, 1.15))
    body.box((x0 - 0.05, y_eave - 0.16, deck_z - 0.08), (x1 + 0.05, y_eave, z0 + 0.08), scale_rgb(TERRACOTTA, 0.9))
    for x in (x0 + 0.35, x0 + 1.15, x1 - 1.15, x1 - 0.35):
        column(body, x, deck_z + 0.18, 0.38, y_eave - 0.16, 0.09, PLASTER)
    for x in (x0 + 0.2, x1 - 0.55):
        body.box((x, 2.35, z0 - 0.28), (x + 0.35, 2.48, z0 + 0.05), TIMBER)
    chimney(body, x1 - 0.7, z1 - 0.7, y_eave - 0.4, y_ridge + 0.35, STONE)
    if ruined:
        rubble(body, 0.2, deck_z + 0.4, 1.2)
    return body, glass


def build_dormer(spec, ruined):
    body, glass = Mesh(), Mesh()
    holes = windows_and_door(0, spec["w"], upper=True)
    x0, x1, z0, z1, y_eave, y_ridge = shell(body, glass, spec, ROSE, CLAY, holes, ruined, stories=2)
    dormer_skip = [(0.32, 0.18, 0.68, 0.55)]
    if ruined:
        dormer_skip.append((0.05, 0.4, 0.28, 0.85))
    gable_roof(body, x0 - 0.36, x1 + 0.36, z0 - 0.3, z1 + 0.28, y_eave, y_ridge, CLAY, skips=dormer_skip, wall=ROSE)
    # Dormer sitting in the skipped roof patch. Street slope runs from z0 to mid.
    mid = (z0 + z1) * 0.45
    dx0, dx1 = -0.55, 0.55
    dz0, dz1 = z0 + 0.55, z0 + 1.35
    base = y_eave + 0.35
    top = base + 0.85
    body.box((dx0, base, dz0), (dx1, top, dz1), ROSE)
    opening(body, glass, (dx0 + 0.15, 0, dz0), (1, 0, 0), (0, 1, 0), (0, 0, 1), (dx0 + 0.18, base + 0.18, dx1 - 0.18, top - 0.22), TRIM, glazed=not ruined)
    gable_roof(body, dx0 - 0.12, dx1 + 0.12, dz0 - 0.12, dz1 + 0.08, top - 0.05, top + 0.42, scale_rgb(CLAY, 0.92), wall=ROSE)
    chimney(body, x0 + 0.6, mid, y_eave, y_ridge + 0.4, STONE)
    for hole in holes[:3]:
        if hole[3] < 2.3:
            body.box((hole[0] - 0.12, hole[1], z0 - 0.08), (hole[0] - 0.02, hole[3], z0 + 0.02), TIMBER)
            body.box((hole[2] + 0.02, hole[1], z0 - 0.08), (hole[2] + 0.12, hole[3], z0 + 0.02), TIMBER)
    if ruined:
        rubble(body, x1 - 0.2, z0 + 0.5)
    return body, glass


def build_gablefront(spec, ruined):
    body, glass = Mesh(), Mesh()
    # Ridge runs toward the street, so the gable end is the facade. Swap by building
    # the long axis on Z and then rotating the finished meshes 90 degrees.
    holes = windows_and_door(0, spec["d"], upper=True)
    spun = {"w": spec["d"], "d": spec["w"], "h": spec["h"]}
    x0, x1, z0, z1, y_eave, y_ridge = shell(body, glass, spun, ADOBE, TERRACOTTA, holes, ruined, stories=2)
    gable_roof(body, x0 - 0.32, x1 + 0.32, z0 - 0.22, z1 + 0.28, y_eave, y_ridge, TERRACOTTA, skips=[(0.2, 0.2, 0.7, 0.75)] if ruined else [], wall=ADOBE)
    # Arch fill above the door.
    door = holes[0]
    arch(body, (door[0] + door[2]) * 0.5, door[3] - 0.55, 0.48, z0, ADOBE)
    chimney(body, 0.0, z1 - 0.45, y_eave - 0.2, y_ridge + 0.55, STONE)
    rotate_y(body, math.pi / 2)
    rotate_y(glass, math.pi / 2)
    if ruined:
        rubble(body, 1.4, -0.4)
    return body, glass


def arch(mesh, cx, y_spring, radius, z, color):
    steps = 8
    points = []
    for i in range(steps + 1):
        angle = math.pi * i / steps
        points.append((cx - math.cos(angle) * radius, y_spring + math.sin(angle) * radius, z))
    left = (cx - radius, y_spring + radius, z)
    right = (cx + radius, y_spring + radius, z)
    for i in range(steps // 2):
        mesh.add(left, points[i], points[i + 1], color)
        mesh.add((left[0], left[1], z + 0.2), (points[i + 1][0], points[i + 1][1], z + 0.2), (points[i][0], points[i][1], z + 0.2), scale_rgb(color, 0.7))
    for i in range(steps // 2, steps):
        mesh.add(right, points[i + 1], points[i], color)
        mesh.add((right[0], right[1], z + 0.2), (points[i][0], points[i][1], z + 0.2), (points[i + 1][0], points[i + 1][1], z + 0.2), scale_rgb(color, 0.7))


def rotate_y(mesh, angle):
    c, s = math.cos(angle), math.sin(angle)
    def spin(point):
        return (point[0] * c + point[2] * s, point[1], -point[0] * s + point[2] * c)
    mesh.faces = [(spin(a), spin(b), spin(c), color) for a, b, c, color in mesh.faces]


def build_compound(spec, ruined):
    body, glass = Mesh(), Mesh()
    holes = windows_and_door(0.3, spec["w"], upper=False)
    holes.append((-2.55, 1.2, -1.9, 1.9))
    x0, x1, z0, z1, y_eave, y_ridge = shell(body, glass, spec, LIMESTONE, CLAY, holes, ruined, stories=2)
    gable_roof(body, -0.2, x1 + 0.3, z0 - 0.25, z1 + 0.25, y_eave, y_ridge, CLAY, skips=[(0.55, 0.1, 0.95, 0.6)] if ruined else [], wall=LIMESTONE)
    # Lower annex on the street-left side.
    ax0, ax1 = x0 - 0.05, -0.15
    body.box((ax0, 0.16, z0), (ax1, 2.55, z0 + 2.4), scale_rgb(OCHRE, 0.95))
    body.box((ax0 - 0.08, 2.5, z0 - 0.12), (ax1 + 0.08, 2.78, z0 + 2.55), STONE)
    opening(body, glass, (ax0 + 0.25, 0, z0), (1, 0, 0), (0, 1, 0), (0, 0, 1), (ax0 + 0.4, 0.2, ax1 - 0.35, 2.05), TRIM, glazed=False)
    arch(body, (ax0 + ax1) * 0.5, 1.45, (ax1 - ax0) * 0.32, z0, scale_rgb(OCHRE, 0.95))
    chimney(body, x1 - 0.55, 0.2, y_eave - 0.3, y_ridge + 0.4, STONE)
    if ruined:
        rubble(body, ax0 + 0.4, z0 + 0.6, 1.3)
    return body, glass


def build_hip(spec, ruined):
    body, glass = Mesh(), Mesh()
    holes = windows_and_door(0, spec["w"], upper=True)
    x0, x1, z0, z1, y_eave, y_ridge = shell(body, glass, spec, OCHRE, TERRACOTTA, holes, ruined, stories=2)
    hip_roof(body, x0 - 0.4, x1 + 0.4, z0 - 0.32, z1 + 0.28, y_eave, min(y_ridge, y_eave + 1.15), TERRACOTTA)
    column(body, x1 - 0.85, z1 - 0.85, y_eave + 0.95, y_eave + 1.55, 0.28, scale_rgb(STEEL, 0.7))
    body.cylinder((x1 - 0.85, y_eave + 1.5, z1 - 0.85), (x1 - 0.85, y_eave + 1.62, z1 - 0.85), 0.34, scale_rgb(STEEL, 0.55), sides=12)
    chimney(body, x0 + 0.7, z0 + 0.8, y_eave - 0.2, y_eave + 1.35, STONE)
    body.box((-0.7, 0.16, z0 - 0.55), (0.7, 0.34, z0), STONE)
    if ruined:
        rubble(body, 0.8, z1 - 0.4)
        # A collapsed roof bite is suggested by rubble plus a missing upper window.
    return body, glass


BUILDERS = {
    "house_type01": build_cottage,
    "house_type02": build_porch,
    "house_type06": build_dormer,
    "house_type08": build_gablefront,
    "house_type10": build_compound,
    "house_type17": build_hip,
}

SPECS = {
    "house_type01": {"w": 5.72, "d": 4.03, "h": 3.25},
    "house_type02": {"w": 5.76, "d": 6.19, "h": 5.01},
    "house_type06": {"w": 5.72, "d": 5.79, "h": 5.01},
    "house_type08": {"w": 7.64, "d": 4.43, "h": 5.28},
    "house_type10": {"w": 7.95, "d": 6.15, "h": 5.01},
    "house_type17": {"w": 6.19, "d": 4.88, "h": 5.01},
}


def recenter(body, glass):
    lows, highs = body.bounds()
    if glass.faces:
        glows, ghighs = glass.bounds()
        lows = [min(a, b) for a, b in zip(lows, glows)]
        highs = [max(a, b) for a, b in zip(highs, ghighs)]
    offset = (-(lows[0] + highs[0]) * 0.5, -lows[1], -(lows[2] + highs[2]) * 0.5)
    body.translate(offset)
    glass.translate(offset)


def build_fence(open_gate=False):
    mesh = Mesh()
    width = 3.48
    depth = 2.32 if open_gate else 3.48
    x0, x1 = -width / 2, width / 2
    z = -0.08
    height = 1.12
    pier = STONE
    wall = ADOBE
    if open_gate:
        mesh.box((x0, 0, z), (x0 + 0.85, height, z + 0.16), wall)
        mesh.box((x1 - 0.85, 0, z), (x1, height, z + 0.16), wall)
        mesh.box((x0 + 0.72, 0.72, z - 0.02), (x1 - 0.72, 0.84, z + 0.18), TIMBER)
        for x in (x0 + 0.78, x1 - 0.78):
            mesh.cylinder((x, 0, 0.08), (x, height + 0.18, 0.08), 0.08, pier, sides=8)
        # Gate leaves swung a little open.
        mesh.box((x0 + 0.9, 0.08, z), (x0 + 1.55, height - 0.08, z + 0.06), TIMBER)
        mesh.box((x1 - 1.55, 0.08, z + 0.15), (x1 - 0.9, height - 0.08, z + 0.21), TIMBER)
    else:
        mesh.box((x0 + 0.18, 0, -depth / 2), (x0 + 0.34, height, depth / 2), wall)
        mesh.box((x1 - 0.34, 0, -depth / 2), (x1 - 0.18, height, depth / 2), wall)
        mesh.box((x0, 0, -depth / 2), (x1, height * 0.72, -depth / 2 + 0.16), wall)
        mesh.box((x0, height * 0.72, -depth / 2 - 0.04), (x1, height * 0.72 + 0.1, -depth / 2 + 0.2), STONE)
        for x in (x0 + 0.12, x1 - 0.12):
            mesh.box((x - 0.12, 0, -depth / 2 - 0.06), (x + 0.12, height + 0.16, -depth / 2 + 0.22), pier)
    return mesh


def build_jeep():
    mesh = Mesh()
    # Chassis tub. Forward is -Z, matching the existing wheel layout.
    mesh.box((-0.74, 0.52, -1.35), (0.74, 0.74, 1.48), OLIVE_DARK)
    mesh.box((-0.86, 0.48, -1.62), (0.86, 0.62, -1.42), STEEL)
    mesh.box((-0.8, 0.5, 1.4), (0.8, 0.64, 1.58), STEEL)
    crowned(mesh, (-0.7, -1.58), (0.7, -0.42), lambda u, v: 0.96 + v * 0.24 + 0.05 * (1 - (u * 2 - 1) ** 2) * math.sin(v * math.pi), (0, 1, 0), OLIVE, 10, 8)
    # Hood sides.
    mesh.box((-0.74, 0.78, -1.5), (-0.68, 1.16, -0.48), OLIVE)
    mesh.box((0.68, 0.78, -1.5), (0.74, 1.16, -0.48), OLIVE)
    # Grille and lamps buckets.
    mesh.box((-0.46, 0.64, -1.66), (0.46, 1.05, -1.56), DARK)
    for index in range(7):
        x = -0.33 + index * 0.11
        mesh.box((x, 0.7, -1.68), (x + 0.035, 1.0, -1.6), STEEL)
    for side in (-1, 1):
        mesh.cylinder((side * 0.66, 0.96, -1.5), (side * 0.66, 0.96, -1.62), 0.13, STEEL, sides=12)
        fender(mesh, side)
        mesh.box((side * 0.78, 0.62, -0.15), (side * 0.9, 1.12, 1.42), OLIVE)
        mesh.box((side * 0.9, 0.58, 0.15), (side * 1.08, 0.68, 1.15), OLIVE_DARK)
        seat(mesh, side * 0.32)
    # Cowl and dash.
    mesh.box((-0.7, 0.9, -0.5), (0.7, 1.28, -0.32), OLIVE)
    mesh.box((-0.62, 1.05, -0.34), (0.62, 1.32, -0.18), OLIVE_DARK)
    # Bed floor and tailgate.
    mesh.box((-0.7, 0.7, 0.35), (0.7, 0.8, 1.38), OLIVE_DARK)
    mesh.box((-0.72, 0.74, 1.32), (0.72, 1.08, 1.42), OLIVE)
    cage(mesh)
    spare(mesh)
    mesh.box((-0.92, 0.78, 1.28), (-0.55, 1.28, 1.48), RUST)
    mesh.box((-0.84, 1.22, 1.3), (-0.63, 1.32, 1.46), DARK)
    # Windshield frame around the separate glass pane.
    for side in (-1, 1):
        mesh.cylinder((side * 0.62, 1.22, -0.36), (side * 0.62, 1.72, -0.22), 0.03, STEEL, sides=8, caps=False)
    mesh.cylinder((-0.62, 1.7, -0.24), (0.62, 1.7, -0.24), 0.028, STEEL, sides=8, caps=False)
    return mesh


def crowned(mesh, xz0, xz1, height, outward, color, across, along):
    x0, z0 = xz0
    x1, z1 = xz1
    points = []
    for j in range(along + 1):
        v = j / along
        row = []
        for i in range(across + 1):
            u = i / across
            row.append((mix(x0, x1, u), height(u, v), mix(z0, z1, v)))
        points.append(row)
    mesh.grid(points, outward, color)


def fender(mesh, side):
    for z_center in (-1.0, 1.0):
        segments, width = 18, 7
        layers = []
        for radius in (0.62, 0.55):
            grid = []
            for i in range(segments + 1):
                theta = math.pi * (0.12 + 0.76 * i / segments)
                lift = math.sin(theta)
                forward = -math.cos(theta)
                row = []
                for j in range(width + 1):
                    t = j / width
                    x = side * (0.78 + t * 0.46)
                    crown = 0.03 * math.sin(t * math.pi)
                    row.append((x, 0.45 + lift * radius + crown, z_center + forward * radius))
                grid.append(row)
            layers.append(grid)
        mesh.grid(layers[0], (side, 1, 0), OLIVE)
        mesh.grid(layers[1], (-side, -1, 0), OLIVE_DARK)
        for edge, direction in ((0, -1), (width, 1)):
            for i in range(segments):
                mesh.quad(
                    layers[0][i][edge], layers[0][i + 1][edge], layers[1][i + 1][edge], layers[1][i][edge],
                    (side * direction, 0, 0), OLIVE,
                )


def seat(mesh, x):
    mesh.box((x - 0.22, 0.78, -0.05), (x + 0.22, 0.92, 0.42), SEAT)
    mesh.box((x - 0.22, 0.9, 0.28), (x + 0.22, 1.38, 0.46), SEAT)
    mesh.box((x - 0.24, 1.28, 0.24), (x + 0.24, 1.4, 0.48), scale_rgb(SEAT, 0.8))


def cage(mesh):
    posts = ((-0.78, -0.28), (0.78, -0.28), (-0.78, 0.72), (0.78, 0.72))
    for x, z in posts:
        mesh.cylinder((x, 1.05, z), (x, 2.18, z), 0.04, STEEL, sides=8, caps=False)
    mesh.cylinder((-0.78, 2.16, -0.28), (0.78, 2.16, -0.28), 0.038, STEEL, sides=8, caps=False)
    mesh.cylinder((-0.78, 2.05, 0.72), (0.78, 2.05, 0.72), 0.038, STEEL, sides=8, caps=False)
    for x in (-0.78, 0.78):
        mesh.cylinder((x, 2.16, -0.28), (x, 2.05, 0.72), 0.034, STEEL, sides=8, caps=False)
    mesh.cylinder((-0.78, 1.35, 0.72), (0.78, 1.35, 0.72), 0.03, STEEL, sides=8, caps=False)


def spare(mesh):
    center = (0.0, 1.02, 1.5)
    segments, sides = 18, 8
    major, minor = 0.34, 0.09
    rings = []
    for i in range(segments):
        theta = math.tau * i / segments
        ring = []
        hub = (center[0] + math.cos(theta) * major, center[1] + math.sin(theta) * major, center[2])
        for j in range(sides):
            phi = math.tau * j / sides
            radial = (math.cos(theta) * math.cos(phi), math.sin(theta) * math.cos(phi), math.sin(phi))
            ring.append(add(hub, mul(radial, minor)))
        rings.append(ring)
    for i in range(segments):
        nxt = rings[(i + 1) % segments]
        for j in range(sides):
            k = (j + 1) % sides
            outward = norm(sub(rings[i][j], center))
            mesh.quad(rings[i][j], rings[i][k], nxt[k], nxt[j], outward, RUBBER)
    mesh.cylinder((0, 1.02, 1.44), (0, 1.02, 1.56), 0.14, STEEL, sides=12)


def pack_models(models, json_path, bin_path):
    blob = bytearray()
    document = []
    for name, body, glass in models:
        parts = []
        lows = [1e9, 1e9, 1e9]
        highs = [-1e9, -1e9, -1e9]
        for part_name, mesh in (("body", body), ("window", glass)):
            if mesh is None or not mesh.faces:
                continue
            soup = mesh.bake()
            parts.append({"name": part_name, "offset": len(blob), "count": len(soup)})
            for vertex in soup:
                blob += struct.pack("<10f", *vertex)
                for axis in range(3):
                    lows[axis] = min(lows[axis], vertex[axis])
                    highs[axis] = max(highs[axis], vertex[axis])
        document.append({"name": name, "parts": parts, "bounds": [lows, highs]})
    bin_path.write_bytes(blob)
    json_path.write_text(json.dumps(document, separators=(",", ":")))
    return len(blob)


def pack_jeep(mesh):
    soup = mesh.bake(crease=50)
    blob = bytearray()
    lows = [1e9, 1e9, 1e9]
    highs = [-1e9, -1e9, -1e9]
    for vertex in soup:
        blob += struct.pack("<10f", *vertex)
        for axis in range(3):
            lows[axis] = min(lows[axis], vertex[axis])
            highs[axis] = max(highs[axis], vertex[axis])
    (ASSETS / "JeepBody.bin").write_bytes(blob)
    (ASSETS / "JeepBody.json").write_text(json.dumps({"count": len(soup), "bounds": [lows, highs]}))
    return len(soup)


def subdivide_character():
    manifest_path = ASSETS / "DriverMesh.json"
    binary_path = ASSETS / "DriverMesh.bin"
    manifest = json.loads(manifest_path.read_text())
    data = bytearray(binary_path.read_bytes())
    mesh = manifest["meshes"][2]
    count = mesh["positions"]["count"]
    if count > 12000:
        return count, sum(tri["count"] for tri in mesh["triangles"]) // 3

    def floats(slice_info, components):
        offset = slice_info["offset"]
        return [struct.unpack_from("<" + "f" * components, data, offset + index * 4 * components) for index in range(slice_info["count"])]

    positions = [list(value) for value in floats(mesh["positions"], 3)]
    uvs = [list(value) for value in floats(mesh["uv"], 2)]
    joints = [list(struct.unpack_from("<4H", data, mesh["joints"]["offset"] + index * 8)) for index in range(count)]
    weights = [list(value) for value in floats(mesh["weights"], 4)]
    faces = []
    for material, tri in enumerate(mesh["triangles"]):
        indices = struct.unpack_from("<" + "I" * tri["count"], data, tri["offset"])
        for cursor in range(0, len(indices), 3):
            faces.append((indices[cursor], indices[cursor + 1], indices[cursor + 2], material))

    edge_faces = defaultdict(list)
    for face_index, (a, b, c, _) in enumerate(faces):
        for start, end, opposite in ((a, b, c), (b, c, a), (c, a, b)):
            edge_faces[tuple(sorted((start, end)))].append((face_index, opposite))

    neighbors = defaultdict(set)
    boundary = set()
    for (a, b), users in edge_faces.items():
        neighbors[a].add(b)
        neighbors[b].add(a)
        if len(users) != 2:
            boundary.add(a)
            boundary.add(b)

    def accumulate(slots):
        total = defaultdict(float)
        for coef, index in slots:
            for joint, weight in zip(joints[index], weights[index]):
                if weight:
                    total[joint] += coef * weight
        top = sorted(total.items(), key=lambda item: -item[1])[:4]
        scale = sum(value for _, value in top) or 1.0
        packed_joints = [0, 0, 0, 0]
        packed_weights = [0.0, 0.0, 0.0, 0.0]
        for slot, (joint, value) in enumerate(top):
            packed_joints[slot] = joint
            packed_weights[slot] = value / scale
        return packed_joints, packed_weights

    edge_index = {}
    edge_positions = []
    edge_uvs = []
    edge_joints = []
    edge_weights = []
    for (a, b), users in edge_faces.items():
        if len(users) == 2:
            opposite = [users[0][1], users[1][1]]
            coefs = ((0.375, a), (0.375, b), (0.125, opposite[0]), (0.125, opposite[1]))
        else:
            coefs = ((0.5, a), (0.5, b))
            opposite = []
        position = [0.0, 0.0, 0.0]
        uv = [0.0, 0.0]
        for coef, index in coefs:
            for axis in range(3):
                position[axis] += coef * positions[index][axis]
            uv[0] += coef * uvs[index][0]
            uv[1] += coef * uvs[index][1]
        packed_joints, packed_weights = accumulate(coefs)
        edge_index[(a, b)] = count + len(edge_positions)
        edge_positions.append(position)
        edge_uvs.append(uv)
        edge_joints.append(packed_joints)
        edge_weights.append(packed_weights)

    new_positions = []
    new_uvs = []
    new_joints = []
    new_weights = []
    for index in range(count):
        ring = neighbors[index]
        if index in boundary:
            border = [other for other in ring if tuple(sorted((index, other))) in edge_faces and len(edge_faces[tuple(sorted((index, other)))]) != 2]
            border = border[:2] if len(border) >= 2 else list(ring)[:2]
            coefs = [(0.75, index)] + [(0.125, other) for other in border]
        else:
            valence = max(3, len(ring))
            beta = 3 / 16 if valence == 3 else 3 / (8 * valence)
            coefs = [(1 - valence * beta, index)] + [(beta, other) for other in ring]
        position = [0.0, 0.0, 0.0]
        uv = [0.0, 0.0]
        for coef, source in coefs:
            for axis in range(3):
                position[axis] += coef * positions[source][axis]
            uv[0] += coef * uvs[source][0]
            uv[1] += coef * uvs[source][1]
        packed_joints, packed_weights = accumulate(coefs)
        new_positions.append(position)
        new_uvs.append(uv)
        new_joints.append(packed_joints)
        new_weights.append(packed_weights)

    positions = new_positions + edge_positions
    uvs = new_uvs + edge_uvs
    joints = new_joints + edge_joints
    weights = new_weights + edge_weights
    divided = []
    for a, b, c, material in faces:
        ab = edge_index[tuple(sorted((a, b)))]
        bc = edge_index[tuple(sorted((b, c)))]
        ca = edge_index[tuple(sorted((c, a)))]
        divided.extend(((a, ab, ca, material), (b, bc, ab, material), (c, ca, bc, material), (ab, bc, ca, material)))

    grouped = defaultdict(list)
    for a, b, c, material in divided:
        grouped[material].extend((a, b, c))
    old_low = [-0.93, -0.01, -0.17]
    old_high = [0.93, 1.82, 0.13]
    lows = [min(vertex[axis] for vertex in positions) for axis in range(3)]
    highs = [max(vertex[axis] for vertex in positions) for axis in range(3)]
    for axis in range(3):
        if lows[axis] < old_low[axis] - 0.25 or highs[axis] > old_high[axis] + 0.25:
            raise SystemExit(f"Character subdivision left the body bounds: {lows} {highs}")
    if any(abs(sum(weight) - 1) > 0.02 for weight in weights[::97]):
        raise SystemExit("Character skin weights no longer sum to one")

    prefix = data[:mesh["positions"]["offset"]]
    inverse = data[manifest["inverseBind"]["offset"]:manifest["inverseBind"]["offset"] + manifest["inverseBind"]["count"] * 64]
    blob = bytearray(prefix)

    def emit(values, fmt):
        start = len(blob)
        for value in values:
            blob.extend(struct.pack(fmt, *value))
        return start

    position_offset = emit(positions, "<3f")
    normal_offset = len(blob)
    # Smooth the subdivided surface. Skinning reorients these with the bones.
    face_normals = defaultdict(lambda: [0.0, 0.0, 0.0])
    for a, b, c, _ in divided:
        normal = cross(sub(positions[b], positions[a]), sub(positions[c], positions[a]))
        for index in (a, b, c):
            for axis in range(3):
                face_normals[index][axis] += normal[axis]
    normals = []
    for index in range(len(positions)):
        normals.append(list(norm(face_normals[index])))
    emit(normals, "<3f")
    uv_offset = emit(uvs, "<2f")
    joint_offset = emit(joints, "<4H")
    weight_offset = emit(weights, "<4f")
    triangle_slices = []
    for material in range(4):
        indices = grouped.get(material, [])
        triangle_slices.append({"offset": len(blob), "count": len(indices)})
        if indices:
            blob.extend(struct.pack("<" + "I" * len(indices), *indices))
    inverse_offset = len(blob)
    blob.extend(inverse)
    mesh["positions"] = {"offset": position_offset, "count": len(positions)}
    mesh["normals"] = {"offset": normal_offset, "count": len(positions)}
    mesh["uv"] = {"offset": uv_offset, "count": len(positions)}
    mesh["joints"] = {"offset": joint_offset, "count": len(positions)}
    mesh["weights"] = {"offset": weight_offset, "count": len(positions)}
    mesh["triangles"] = triangle_slices
    manifest["inverseBind"]["offset"] = inverse_offset
    binary_path.write_bytes(blob)
    manifest_path.write_text(json.dumps(manifest, separators=(",", ":")))
    return len(positions), len(divided)


def shifted(mesh, offset):
    copy = Mesh()
    copy.faces = [(add(a, offset), add(b, offset), add(c, offset), color) for a, b, c, color in mesh.faces]
    return copy


def render_preview(models, jeep, path):
    width, height = 1400, 900
    image = bytearray([28, 24, 20]) * (width * height)
    depth = [1e9] * (width * height)
    light = norm((0.4, 0.85, 0.35))
    placed = []
    for index, (mesh, _) in enumerate(models):
        placed.append(shifted(mesh, ((index % 3) * 16 - 16, 0, (index // 3) * 14)))
    placed.append(shifted(jeep, (18, 0, 28)))

    def project(vertex):
        x, y, z = vertex
        return (x * 0.86 + z * 0.42, y * 0.96 + x * 0.04 - z * 0.12)

    cloud = [project(vertex) for mesh in placed for face in mesh.faces for vertex in face[:3]]
    min_x = min(point[0] for point in cloud)
    max_x = max(point[0] for point in cloud)
    min_y = min(point[1] for point in cloud)
    max_y = max(point[1] for point in cloud)
    scale = min((width - 40) / max(0.01, max_x - min_x), (height - 40) / max(0.01, max_y - min_y))

    def pixel(point):
        return (int((point[0] - min_x) * scale) + 20, int(height - 20 - (point[1] - min_y) * scale))

    for mesh in placed:
        for a, b, c, color in mesh.faces:
            normal = norm(cross(sub(b, a), sub(c, a)))
            shade = max(0.16, dot(normal, light))
            rgb = bytes(int(min(255, max(0, (channel ** (1 / 2.2)) * 255 * shade))) for channel in color[:3])
            pa, pb, pc = pixel(project(a)), pixel(project(b)), pixel(project(c))
            minx = max(0, min(pa[0], pb[0], pc[0]))
            maxx = min(width - 1, max(pa[0], pb[0], pc[0]))
            miny = max(0, min(pa[1], pb[1], pc[1]))
            maxy = min(height - 1, max(pa[1], pb[1], pc[1]))
            denom = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
            if abs(denom) < 1:
                continue
            average_z = a[0] * 0.2 + a[2] + b[2] + c[2]
            for y in range(miny, maxy + 1):
                for x in range(minx, maxx + 1):
                    w0 = ((pb[1] - pc[1]) * (x - pc[0]) + (pc[0] - pb[0]) * (y - pc[1])) / denom
                    w1 = ((pc[1] - pa[1]) * (x - pc[0]) + (pa[0] - pc[0]) * (y - pc[1])) / denom
                    w2 = 1 - w0 - w1
                    if w0 >= 0 and w1 >= 0 and w2 >= 0:
                        slot = y * width + x
                        if average_z < depth[slot]:
                            depth[slot] = average_z
                            image[slot * 3:slot * 3 + 3] = rgb
    ppm = ROOT / "build" / "mesh-preview.ppm"
    ppm.parent.mkdir(exist_ok=True)
    ppm.write_bytes(f"P6\n{width} {height}\n255\n".encode() + bytes(image))


def main():
    models = []
    previews = []
    for name, spec in SPECS.items():
        for ruined in (False, True):
            body, glass = BUILDERS[name](spec, ruined)
            recenter(body, glass)
            models.append((name + ("-ruin" if ruined else ""), body, glass))
        previews.append((models[-2][1], 1))
    fence = build_fence(False)
    gate = build_fence(True)
    recenter(fence, Mesh())
    recenter(gate, Mesh())
    models.append(("fence_large", fence, None))
    models.append(("fence_open", gate, None))
    size = pack_models(models, ASSETS / "EnvironmentMesh.json", ASSETS / "EnvironmentMesh.bin")
    jeep = build_jeep()
    jeep_count = pack_jeep(jeep)
    verts, tris = subdivide_character()
    print(f"environment {size} bytes, {len(models)} models")
    for name, body, glass in models:
        print(f"  {name}: {len(body.faces)} body tris, {len(glass.faces) if glass else 0} glass")
    print(f"jeep {jeep_count} vertices")
    print(f"character {verts} vertices, {tris} tris")
    render_preview(previews, jeep, ROOT / "build" / "mesh-preview.ppm")


if __name__ == "__main__":
    main()
