#!/usr/bin/env python3
"""Build an original mid-poly autonomous dozer glTF.

The shape is ours. Public photos of Lumina's Moonlander and Built Robotics'
sensor-topped dozers were used only as style notes: a low glass house, a
sensor mast, a clean industrial body, and a steel blade with a worn edge.
No logos, names, or copied silhouettes.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "godot" / "assets" / "models" / "dozer.glb"


def mat(name: str, color: tuple, metallic: float, roughness: float, emissive=None) -> dict:
    pbr = {
        "baseColorFactor": list(color) + [1.0],
        "metallicFactor": metallic,
        "roughnessFactor": roughness,
    }
    body = {"name": name, "pbrMetallicRoughness": pbr}
    if emissive:
        body["emissiveFactor"] = list(emissive)
    return body


# Metallic stays moderate. A Compatibility renderer has no environment map,
# so a fully metal surface renders as a black hole.
MATERIALS = [
    mat("paint", (0.66, 0.68, 0.64), 0.12, 0.48),
    mat("charcoal", (0.16, 0.17, 0.18), 0.18, 0.55),
    mat("steel", (0.62, 0.63, 0.60), 0.38, 0.40),
    mat("edge", (0.74, 0.62, 0.40), 0.22, 0.62),
    mat("rubber", (0.07, 0.07, 0.075), 0.02, 0.9),
    mat("glass", (0.28, 0.42, 0.46), 0.08, 0.08),
    mat("sensor", (0.12, 0.13, 0.14), 0.28, 0.32),
    mat("lamp", (0.95, 0.55, 0.12), 0.05, 0.35, (0.9, 0.35, 0.05)),
]


class Mesh:
    def __init__(self, material: int):
        self.material = material
        self.positions: list[float] = []
        self.normals: list[float] = []
        self.uvs: list[float] = []
        self.indices: list[int] = []

    def _vert(self, p, n, uv) -> int:
        idx = len(self.positions) // 3
        self.positions.extend(p)
        self.normals.extend(n)
        self.uvs.extend(uv)
        return idx

    def add_tri(self, a, b, c, na, nb, nc, uva, uvb, uvc) -> None:
        self.indices.extend([self._vert(a, na, uva), self._vert(b, nb, uvb), self._vert(c, nc, uvc)])

    def add_quad(self, p, n) -> None:
        # p is 4 points, n is the face normal
        self.add_tri(p[0], p[1], p[2], n, n, n, (0, 0), (1, 0), (1, 1))
        self.add_tri(p[0], p[2], p[3], n, n, n, (0, 0), (1, 1), (0, 1))

    def box(self, center, size) -> None:
        cx, cy, cz = center
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        faces = [
            ((0, 1, 0), [(-hx, hy, -hz), (hx, hy, -hz), (hx, hy, hz), (-hx, hy, hz)]),
            ((0, -1, 0), [(-hx, -hy, hz), (hx, -hy, hz), (hx, -hy, -hz), (-hx, -hy, -hz)]),
            ((1, 0, 0), [(hx, -hy, -hz), (hx, -hy, hz), (hx, hy, hz), (hx, hy, -hz)]),
            ((-1, 0, 0), [(-hx, -hy, hz), (-hx, -hy, -hz), (-hx, hy, -hz), (-hx, hy, hz)]),
            ((0, 0, 1), [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]),
            ((0, 0, -1), [(hx, -hy, -hz), (-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz)]),
        ]
        for normal, corners in faces:
            pts = [(cx + x, cy + y, cz + z) for x, y, z in corners]
            self.add_quad(pts, normal)

    def cylinder(self, start, end, radius, segments=18) -> None:
        ax = (end[0] - start[0], end[1] - start[1], end[2] - start[2])
        length = math.sqrt(sum(v * v for v in ax)) or 1.0
        ax = tuple(v / length for v in ax)
        helper = (0.0, 1.0, 0.0) if abs(ax[1]) < 0.9 else (1.0, 0.0, 0.0)
        ux = _cross(helper, ax)
        ux = _norm(ux)
        uy = _cross(ax, ux)
        rings = []
        for end_point in (start, end):
            ring = []
            for i in range(segments):
                a = (i / segments) * math.tau
                n = (
                    ux[0] * math.cos(a) + uy[0] * math.sin(a),
                    ux[1] * math.cos(a) + uy[1] * math.sin(a),
                    ux[2] * math.cos(a) + uy[2] * math.sin(a),
                )
                ring.append(((end_point[0] + n[0] * radius, end_point[1] + n[1] * radius, end_point[2] + n[2] * radius), n))
            rings.append(ring)
        for i in range(segments):
            j = (i + 1) % segments
            a, na = rings[0][i]
            b, nb = rings[0][j]
            c, nc = rings[1][j]
            d, nd = rings[1][i]
            self.add_tri(a, b, c, na, nb, nc, (i / segments, 0), ((i + 1) / segments, 0), ((i + 1) / segments, 1))
            self.add_tri(a, c, d, na, nc, nd, (i / segments, 0), ((i + 1) / segments, 1), (i / segments, 1))


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _norm(v):
    length = math.sqrt(sum(x * x for x in v)) or 1.0
    return tuple(x / length for x in v)


def track(side: float, label: str) -> list[tuple[str, Mesh]]:
    shoes_mesh = Mesh(4)
    x = side * 1.18
    shoes = 52
    for i in range(shoes):
        ang = (i / shoes) * math.tau
        z = math.cos(ang) * 1.95
        # The lower half wraps under the idler and sprocket and meets the ground.
        if ang <= math.pi:
            y = 0.42 - math.sin(ang) * 0.34
        else:
            y = 0.84
        on_ground = y < 0.55
        shoes_mesh.box((x, max(y, 0.06), z), (0.64 if on_ground else 0.5, 0.07 if on_ground else 0.045, 0.14))
    steel = Mesh(2)
    steel.cylinder((x - 0.14, 0.42, 1.72), (x + 0.14, 0.42, 1.72), 0.34, 28)
    steel.cylinder((x - 0.12, 0.46, -1.78), (x + 0.12, 0.46, -1.78), 0.38, 24)
    for z in (-1.15, -0.55, 0.05, 0.65, 1.2):
        steel.cylinder((x - 0.1, 0.30, z), (x + 0.1, 0.30, z), 0.13, 10)
    frame = Mesh(1)
    frame.box((x - side * 0.16, 0.48, 0.0), (0.08, 0.22, 3.35))
    frame.box((x, 0.22, 0.0), (0.16, 0.06, 3.5))
    # A continuous belt under the cleats, so the run is not a row of floating blocks.
    shoes_mesh.box((x, 0.1, 0.0), (0.58, 0.08, 3.55))
    return [
        (f"{label}-shoes", shoes_mesh),
        (f"{label}-wheels", steel),
        (f"{label}-frame", frame),
    ]


def hull_parts() -> list[tuple[str, Mesh]]:
    paint = Mesh(0)
    dark = Mesh(1)
    steel = Mesh(2)
    glass = Mesh(5)
    sensor = Mesh(6)
    lamp = Mesh(7)
    # Belly and battery cases. No exhaust, no brand.
    dark.box((0.0, 0.62, -0.05), (1.55, 0.55, 3.15))
    paint.box((0.0, 1.05, 0.35), (1.72, 0.42, 2.15))
    paint.box((0.0, 1.22, -0.85), (1.62, 0.38, 1.15))
    # Sloped nose, a separate panel so the hood is not one cube.
    paint.box((0.0, 1.18, 1.15), (1.48, 0.28, 0.7))
    # Minimal cab: a low dark-glass band, not a tall operator house.
    glass.box((0.0, 1.72, -0.15), (1.28, 0.62, 1.05))
    dark.box((0.0, 2.08, -0.15), (1.36, 0.08, 1.16))
    paint.box((0.0, 1.42, -0.15), (1.4, 0.08, 1.2))
    # A short mast and a wide lidar puck, plus a forward pod. Not exhaust stacks.
    sensor.box((0.0, 2.16, -0.2), (0.9, 0.06, 0.22))
    sensor.cylinder((0.0, 2.18, -0.42), (0.0, 2.38, -0.42), 0.04, 8)
    sensor.cylinder((0.0, 2.38, -0.42), (0.0, 2.48, -0.42), 0.2, 22)
    sensor.box((0.0, 2.14, 0.48), (0.28, 0.1, 0.18))
    sensor.cylinder((0.42, 2.16, 0.15), (0.42, 2.34, 0.15), 0.03, 8)
    sensor.cylinder((0.42, 2.34, 0.15), (0.42, 2.4, 0.15), 0.08, 14)
    lamp.box((0.48, 1.95, 0.42), (0.08, 0.06, 0.08))
    lamp.box((-0.48, 1.95, 0.42), (0.08, 0.06, 0.08))
    # Push arms and a single rear shank. Not a copied ripper frame.
    steel.cylinder((-0.55, 0.55, 0.4), (-0.85, 0.48, 1.55), 0.06, 10)
    steel.cylinder((0.55, 0.55, 0.4), (0.85, 0.48, 1.55), 0.06, 10)
    dark.box((0.0, 0.55, -1.85), (0.9, 0.12, 0.35))
    steel.box((0.0, 0.28, -2.05), (0.08, 0.42, 0.16))
    return [
        ("hull-paint", paint),
        ("hull-dark", dark),
        ("hull-steel", steel),
        ("cab-glass", glass),
        ("sensors", sensor),
        ("lamps", lamp),
    ]


def blade_mesh() -> tuple[Mesh, Mesh]:
    face = Mesh(2)
    edge = Mesh(3)
    cols, rows = 48, 22
    width = 3.72

    def point(u: float, t: float) -> tuple:
        x = (u - 0.5) * width
        y = t * 1.12
        # Curl back toward the machine as the moldboard rises.
        z = 2.15 - t * 0.12 - t * t * 0.62
        end = 1.0 - _smooth(u / 0.12) * _smooth((1.0 - u) / 0.12)
        z -= end * 0.18
        z += math.sin(u * math.pi) * 0.06
        return (x, y, z)

    def grid(mesh: Mesh, t0: float, t1: float, r0: int, r1: int) -> None:
        for r in range(r0, r1):
            ta = t0 + (t1 - t0) * (r - r0) / (r1 - r0)
            tb = t0 + (t1 - t0) * (r + 1 - r0) / (r1 - r0)
            for c in range(cols):
                u0 = c / cols
                u1 = (c + 1) / cols
                p00, p10, p11, p01 = point(u0, ta), point(u1, ta), point(u1, tb), point(u0, tb)
                # The pushing face looks forward, +Z, so a camera in front of the blade sees it lit.
                n = _norm(_cross(_sub(p10, p00), _sub(p11, p00)))
                if n[2] < 0.0:
                    n = _mul(n, -1.0)
                    mesh.add_quad([p00, p01, p11, p10], n)
                else:
                    mesh.add_quad([p00, p10, p11, p01], n)

    grid(edge, 0.0, 0.18, 0, 3)
    grid(face, 0.18, 1.0, 3, rows)
    # Side plates.
    for sign in (-1.0, 1.0):
        x = sign * width * 0.5
        dark_pts = [(x, 0.05, 2.05), (x, 0.15, 1.55), (x, 0.85, 1.35), (x, 0.95, 1.85)]
        face.add_quad(dark_pts, (sign, 0, 0))
    return face, edge


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mul(v, s):
    return (v[0] * s, v[1] * s, v[2] * s)


def _smooth(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def pack(nodes: list, meshes: list[Mesh]) -> bytes:
    blob = bytearray()
    buffer_views = []
    accessors = []

    def align(n=4):
        while len(blob) % n:
            blob.append(0)

    def push(data: bytes, target: int) -> int:
        align(4)
        offset = len(blob)
        blob.extend(data)
        buffer_views.append({
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": len(data),
            "target": target,
        })
        return len(buffer_views) - 1

    def accessor(view: int, count: int, ctype: int, atype: str, mins=None, maxs=None) -> int:
        body = {
            "bufferView": view,
            "componentType": ctype,
            "count": count,
            "type": atype,
        }
        if mins is not None:
            body["min"] = mins
            body["max"] = maxs
        accessors.append(body)
        return len(accessors) - 1

    gltf_meshes = []
    mesh_index = {}
    for mesh in meshes:
        if id(mesh) in mesh_index:
            continue
        pos = struct.pack(f"<{len(mesh.positions)}f", *mesh.positions)
        nor = struct.pack(f"<{len(mesh.normals)}f", *mesh.normals)
        uv = struct.pack(f"<{len(mesh.uvs)}f", *mesh.uvs)
        idx = struct.pack(f"<{len(mesh.indices)}I", *mesh.indices)
        xs = mesh.positions[0::3]
        ys = mesh.positions[1::3]
        zs = mesh.positions[2::3]
        pos_a = accessor(push(pos, 34962), len(xs), 5126, "VEC3", [min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)])
        nor_a = accessor(push(nor, 34962), len(xs), 5126, "VEC3")
        uv_a = accessor(push(uv, 34962), len(xs), 5126, "VEC2")
        idx_a = accessor(push(idx, 34963), len(mesh.indices), 5125, "SCALAR")
        gltf_meshes.append({
            "primitives": [{
                "attributes": {"POSITION": pos_a, "NORMAL": nor_a, "TEXCOORD_0": uv_a},
                "indices": idx_a,
                "material": mesh.material,
            }]
        })
        mesh_index[id(mesh)] = len(gltf_meshes) - 1

    gltf_nodes = []
    for node in nodes:
        body = {"name": node["name"]}
        if "mesh" in node:
            body["mesh"] = mesh_index[id(node["mesh"])]
        if "translation" in node:
            body["translation"] = node["translation"]
        if "children" in node:
            body["children"] = node["children"]
        gltf_nodes.append(body)

    gltf = {
        "asset": {"version": "2.0", "generator": "roleplay make_dozer"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": gltf_nodes,
        "meshes": gltf_meshes,
        "materials": MATERIALS,
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }
    text = json.dumps(gltf, separators=(",", ":")).encode()
    while len(text) % 4:
        text += b" "
    while len(blob) % 4:
        blob.append(0)
    chunks = b"".join([
        struct.pack("<I", len(text)) + b"JSON" + text,
        struct.pack("<I", len(blob)) + b"BIN\x00" + bytes(blob),
    ])
    return b"glTF" + struct.pack("<II", 2, 12 + len(chunks)) + chunks


def main() -> None:
    parts = hull_parts() + track(-1.0, "track-left") + track(1.0, "track-right")
    face, edge = blade_mesh()
    nodes: list[dict] = [{"name": "dozer"}]
    for name, mesh in parts:
        nodes.append({"name": name, "mesh": mesh})
    blade_index = len(nodes)
    tilt_index = blade_index + 1
    nodes.append({
        "name": "blade",
        "translation": [0.0, 0.82, 1.35],
        "children": [tilt_index],
    })
    nodes.append({"name": "blade-angle", "children": [tilt_index + 1, tilt_index + 2]})
    nodes.append({"name": "moldboard", "mesh": face})
    nodes.append({"name": "cutting-edge", "mesh": edge})
    nodes[0]["children"] = list(range(1, blade_index + 1))
    meshes = [mesh for _, mesh in parts] + [face, edge]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(pack(nodes, meshes))
    tris = sum(len(mesh.indices) // 3 for mesh in meshes)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, {tris} tris)")


if __name__ == "__main__":
    main()
