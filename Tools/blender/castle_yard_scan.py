"""Снимает двор с готовой модели (запуск в Blender при открытом castle.blend, после build): растр сверху (что и на какой высоте видно)
и таблицы генератора. Единицы — px исходника (1 px = 0,12 м), начало модели, X восток, Y север.
Пишет Арт/Blender/castle/yard_scan.npz и yard_scan.json; план из них собирает Tools/castle_yard_plan.py."""
import json
import math

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
OUT = PROJECT + r"\Арт\Blender\castle"
GEN = PROJECT + r"\Tools\blender\build_castle.py"
ns = {"__name__": "castle_lib", "MODE": "none"}
exec(open(GEN, encoding="utf-8").read(), ns)
S = ns["S"]

PARTS = ["Rock", "Ring", "Curtain", "Gate", "Stairs", "Spur", "Inner", "Upper", "Crown"]   # Плющ и осыпь не считаем: это не форма двора
verts, polys, owner = [], [], []
rock_v, rock_p = [], []
for k, name in enumerate(PARTS):
    ob = bpy.data.objects["Castle_" + name]
    me = ob.data
    base = len(verts)
    verts.extend((v.co.x / S, v.co.y / S, v.co.z / S) for v in me.vertices)
    for p in me.polygons:
        polys.append([base + i for i in p.vertices])
        owner.append(k)
    if name == "Rock":
        rock_v = verts[:]
        rock_p = polys[:]
full = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
rock = BVHTree.FromPolygons(rock_v, rock_p, all_triangles=False, epsilon=0.0)

STEP = 3.0     # px: 0,36 м
X0, X1, Y0, Y1 = -720.0, 680.0, -640.0, 640.0
xs = np.arange(X0, X1 + STEP, STEP)
ys = np.arange(Y0, Y1 + STEP, STEP)
Z = np.full((len(ys), len(xs)), np.nan, dtype=np.float32)      # верх всего, что видно сверху
PART = np.full((len(ys), len(xs)), -1, dtype=np.int8)          # чья это поверхность
ROCKZ = np.full((len(ys), len(xs)), np.nan, dtype=np.float32)  # верх скалы, и под зданиями тоже
NZ = np.full((len(ys), len(xs)), np.nan, dtype=np.float32)
down = Vector((0.0, 0.0, -1.0))
for j, y in enumerate(ys):
    for i, x in enumerate(xs):
        o = Vector((float(x), float(y), 1300.0))
        loc, nor, idx, _ = full.ray_cast(o, down)
        if loc is not None:
            Z[j, i] = loc.z
            PART[j, i] = owner[idx]
            NZ[j, i] = abs(nor.z)
        loc, _, _, _ = rock.ray_cast(o, down)
        if loc is not None:
            ROCKZ[j, i] = loc.z
np.savez_compressed(OUT + r"\yard_scan.npz", Z=Z, PART=PART, ROCKZ=ROCKZ, NZ=NZ, xs=xs, ys=ys)

# Таблицы генератора: то, что точнее растра (стены, башни, ворота, лестница)
g = ns["GATE"]
(ax, ay), (bx, by) = g["t1"], g["t2"]
nx, ny = ns["normal2"]((ax, ay), (bx, by))
mx, my, _, _ = ns["gate_landing"]()
back = g["recess"]
plan = [(ax - nx * back, ay - ny * back), (bx - nx * back, by - ny * back), (bx - nx * g["depth"], by - ny * g["depth"]), (ax - nx * g["depth"], ay - ny * g["depth"])]
c = ns["CURTAIN"]
r = ns["RING"]
data = {
    "S": S, "parts": PARTS, "step": STEP,
    "curtain": {"path": ns["se_path"](c["ext"], c["p"], 240), "t": c["t"], "z1": c["z1"], "ext": c["ext"], "p": c["p"],
                "towers": [(x, ns["se_y"](x, c["ext"], c["p"], side), top, rad) for x, side, top, rad in ns["CURTAIN_TOWERS"]]},
    "ring": {"path": ns["se_path"](r["ext"], r["p"], 240), "t": r["t"], "z1": r["z1"], "gap": ns["RING_GAP"],
             "towers": [(x, ns["se_y"](x, r["ext"], r["p"], side), top, rad) for x, side, top, rad in ns["RING_TOWERS"]]},
    "gate": {"t1": g["t1"], "t2": g["t2"], "r": g["r"], "plan": plan, "arch_w": g["arch_w"], "arch_z": g["arch_z"], "normal": (nx, ny), "mid": (mx, my), "depth": g["depth"]},
    "stairs": ns["stair_points"](), "stairs_w": ns["STAIRS"]["w"], "landing": ns["STAIRS"]["landing"],
    "donjon": {k: ns["DONJON"][k] for k in ("x", "y")}, "donjon_r": ns["DONJON"]["tiers"][0][2],
    "broken": {k: ns["BROKEN"][k] for k in ("x", "y", "r", "z0")},
    "round": {k: ns["ROUND"][k] for k in ("x", "y", "r", "z0")},
    "spur": {k: ns["SPUR"][k] for k in ("x", "y", "r", "foot")},
    "arcade": {"p0": ns["ARCADE"]["p0"], "p1": ns["ARCADE"]["p1"], "t": ns["ARCADE"]["t"], "arch_z": ns["ARCADE"]["arch_z"]},
    "inner_walls": ns["INNER_WALLS"], "inner_towers": ns["INNER_TOWERS"],
    "tower_houses": ns["TOWER_HOUSES"], "turrets": ns["TURRETS"],
    "halls": [list(h) for h in ns["all_halls"]()],
    "origin": list(ns["site_origin"]()),
}
with open(OUT + r"\yard_scan.json", "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False)
RESULT = {"cells": Z.size, "hit": int(np.isfinite(Z).sum()), "halls": len(data["halls"])}
