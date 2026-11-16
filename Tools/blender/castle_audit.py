"""Проверка замка на висящие детали и крупные планы. Только читает сцену castle.blend, геометрию не меняет.

    exec(open(r"<проект>/Tools/blender/castle_audit.py", encoding="utf-8").read(), {"__name__": "__main__", "MODE": "check"})
MODE: check — числа и список в Арт/Blender/castle/audit.json; shots — крупные планы audit_*.png (SHOTS, TAG — приставка имени).

Что считается висящим:
1) «оторвано»: связная группа граней не касается скалы ни прямо, ни через другие детали (зазор больше TOL);
2) «низ в воздухе»: низ объёмной детали не в скале, не на сплошном объёме, и под ним или вокруг него пусто;
3) «лист в воздухе»: у мха и плюща угол грани дальше SHEET_TOL от камня;
4) «растение в воздухе»: под основанием растения нет поверхности в пределах PLANT_TOL.
"""
import json
import math
import os

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
OUT = os.path.join(PROJECT, "Арт", "Blender", "castle")
MODE = globals().get("MODE", "check")
TOL = 0.30         # м: зазор, который ещё считается касанием (плоские окна стоят над стеной до 0,28 м)
SHEET_TOL = 0.45   # м: мох и плющ
PLANT_TOL = 0.80   # м: растение
SOFT = ("Moss", "Ivy", "Scree")   # листья и осыпь: Scree стоит на земле мира, а земли в этой проверке нет


def lib():
    ns = {"__name__": "castle_lib", "MODE": "none"}
    exec(open(os.path.join(PROJECT, "Tools", "blender", "build_castle.py"), encoding="utf-8").read(), ns)
    return ns


def gather(parts_filter):
    """Вершины и грани частей замка в местных координатах (метры, начало — Castle_Root)."""
    verts, polys, owner = [], [], []
    for ob in bpy.data.collections["Castle"].objects:
        if ob.type != "MESH":
            continue
        part = ob.name.replace("Castle_", "")
        if not parts_filter(part):
            continue
        base = len(verts)
        me = ob.data
        verts.extend(v.co.copy() for v in me.vertices)
        for p in me.polygons:
            polys.append([base + i for i in p.vertices])
            owner.append(part)
    return verts, polys, owner


class Union:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, a):
        p = self.p
        while p[a] != a:
            p[a] = p[p[a]]
            a = p[a]
        return a

    def join(self, a, b):
        a, b = self.find(a), self.find(b)
        if a != b:
            self.p[b] = a


def in_rock(ns, x, y, z, margin=2.0):
    """Точка в px: внутри тела скалы (по таблицам сечений, без шума)."""
    if z < ns["ROCK_BASE"]:
        return True
    r = math.hypot(x, y)
    if z <= ns["ROCK"][-1][0] and r <= ns["rock_radius"](math.atan2(y, x), z) + margin:
        return True
    for cx, cy, tbl, _, _ in ns["CRAGS"]:
        if tbl[0][0] <= z <= tbl[-1][0] and math.hypot(x - cx, y - cy) <= ns["interp"](tbl, z)[0] + margin:
            return True
    return False


def check():
    ns = lib()
    S = ns["S"]
    verts, polys, owner = gather(lambda part: part not in SOFT)
    bvh = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
    uf = Union(len(polys))
    first = {}
    for i, poly in enumerate(polys):
        for v in poly:
            if v in first:
                uf.join(first[v], i)
            else:
                first[v] = i
    for a, b in bvh.overlap(bvh):
        if a != b:
            uf.join(a, b)
    rock_face = owner.index("Rock")
    for _ in range(3):      # почти касания: окна и пояса стоят над стеной с зазором
        root = uf.find(rock_face)
        changed = False
        for i, poly in enumerate(polys):
            if uf.find(i) == root:
                continue
            for v in poly:
                for _co, _no, j, _d in bvh.find_nearest_range(verts[v], TOL):
                    if j is not None and uf.find(j) != uf.find(i):
                        uf.join(i, j)
                        changed = True
        if not changed:
            break
    root = uf.find(rock_face)
    comps = {}
    for i, poly in enumerate(polys):
        c = uf.find(i)
        if c == root:
            continue
        rec = comps.setdefault(c, {"tris": 0, "parts": set(), "lo": [1e9] * 3, "hi": [-1e9] * 3})
        rec["tris"] += len(poly) - 2
        rec["parts"].add(owner[i])
        for v in poly:
            co = verts[v]
            for k in range(3):
                rec["lo"][k] = min(rec["lo"][k], co[k])
                rec["hi"][k] = max(rec["hi"][k], co[k])
    detached = sorted(({"tris": r["tris"], "parts": sorted(r["parts"]),
                        "centre_px": [round((r["lo"][k] + r["hi"][k]) / 2 / S) for k in range(3)],
                        "size_m": [round(r["hi"][k] - r["lo"][k], 1) for k in range(3)]} for r in comps.values()),
                      key=lambda q: -q["tris"])
    by_part = {}
    for q in detached:
        for p in q["parts"]:
            by_part[p] = by_part.get(p, 0) + 1

    # Стойки: низ зала, башни, пинакла. Сплошным считаем скалу и таблицы-объёмы генератора.
    solids = ns["upper_solids"]() if "upper_solids" in ns else []

    def supported(x, y, z):
        if in_rock(ns, x, y, z):
            return True
        for kind, a, b, c, d, z0, z1 in solids:
            if not z0 - 3 <= z <= z1 + 3:
                continue
            if kind == "circle" and math.hypot(x - a, y - b) <= c + 3:
                return True
            if kind == "rect" and abs(x - a) <= c / 2 + 3 and abs(y - b) <= d / 2 + 3:
                return True
        return False
    # Низы деталей по настоящей геометрии: точка внутри скалы (луч наружу упирается в скалу), или стоит на сплошном объёме,
    # или прямо под ней есть поверхность. Иначе деталь обрывается в воздухе. Плоские окна и пояса — одна грань — не считаются.
    rock_v, rock_p, _ro = gather(lambda part: part == "Rock")
    rock_bvh = BVHTree.FromPolygons(rock_v, rock_p, all_triangles=False, epsilon=0.0)
    hanging = {}
    hanging_samples = []
    uf0 = Union(len(polys))
    seen0 = {}
    for i, poly in enumerate(polys):
        for v in poly:
            if v in seen0:
                uf0.join(seen0[v], i)
            else:
                seen0[v] = i
    groups = {}
    for i in range(len(polys)):
        groups.setdefault(uf0.find(i), []).append(i)
    for faces in groups.values():
        part = owner[faces[0]]
        if part == "Rock" or len(faces) < 5:
            continue
        pts = [verts[v] for f in faces for v in polys[f]]
        zmin = min(q.z for q in pts)
        low = [q for q in pts if q.z < zmin + 0.03]
        p_ = sum(low, Vector((0, 0, 0))) / len(low)
        r_ = math.hypot(p_.x, p_.y) or 1.0
        if rock_bvh.ray_cast(p_, Vector((p_.x / r_, p_.y / r_, 0.0)), 300.0)[0] is not None:
            continue
        if supported(p_.x / S, p_.y / S, p_.z / S + 1):
            continue
        hit = bvh.ray_cast(p_ - Vector((0, 0, 0.03)), Vector((0, 0, -1)), 0.8)
        if hit[0] is not None:
            continue
        # Стоит на другой детали: каждая нижняя вершина касается чужой геометрии (венец на стволе, зубец на стене).
        # Контрфорс, который только прижат к стене боком, это условие не выполняет: его внешние вершины в воздухе.
        own = uf0.find(faces[0])
        if all(any(j is not None and uf0.find(j) != own for _c, _n, j, _d in bvh.find_nearest_range(q, TOL)) for q in low):
            continue
        down = bvh.ray_cast(p_ - Vector((0, 0, 0.03)), Vector((0, 0, -1)), 60.0)
        gap = round(down[3], 1) if down[0] is not None else 60.0
        hanging[part] = hanging.get(part, 0) + 1
        hanging_samples.append({"часть": part, "px": [round(p_.x / S), round(p_.y / S), round(p_.z / S)], "зазор_м": gap, "граней": len(faces)})
    hanging_samples.sort(key=lambda q: -q["зазор_м"] * q["граней"])
    # Мох и плющ: углы граней от камня.
    soft_v, soft_p, soft_o = gather(lambda part: part in SOFT)
    bad_sheets = {"Ivy": 0}
    all_sheets = {"Ivy": 0}
    far = {"Ivy": 0.0}
    for poly, part in zip(soft_p, soft_o):
        if part != "Ivy":
            continue
        all_sheets[part] += 1
        worst = 0.0
        for v in poly:
            hit = bvh.find_nearest(soft_v[v])
            if hit[0] is not None:
                worst = max(worst, hit[3])
        if worst > SHEET_TOL:
            bad_sheets[part] += 1
            far[part] = max(far[part], worst)

    # Растения: луч вниз от основания.
    plants = {"всего": 0, "в_воздухе": 0, "наибольший_зазор_м": 0.0, "примеры_px": []}
    veg = bpy.data.collections.get("CastleVeg")
    if veg:
        all_v, all_p, _ = gather(lambda part: True)
        full = BVHTree.FromPolygons(all_v, all_p, all_triangles=False, epsilon=0.0)
        for ob in veg.objects:
            plants["всего"] += 1
            p = Vector(ob.location)
            hit = full.ray_cast(p + Vector((0, 0, 0.25)), Vector((0, 0, -1)), 30.0)
            gap = (hit[3] - 0.25) if hit[0] is not None else 30.0
            if gap > PLANT_TOL:
                plants["в_воздухе"] += 1
                plants["наибольший_зазор_м"] = max(plants["наибольший_зазор_м"], round(gap, 1))
                if len(plants["примеры_px"]) < 8:
                    plants["примеры_px"].append([round(p.x / S), round(p.y / S), round(p.z / S)])
    report = {"оторвано_групп": len(detached), "оторвано_по_частям": by_part, "оторвано_примеры": detached[:14],
              "низ_в_воздухе": hanging, "низ_примеры": hanging_samples[:14],
              "лист_в_воздухе": bad_sheets, "лист_всего": all_sheets, "лист_зазор_м": {k: round(v, 1) for k, v in far.items()},
              "растения": plants}
    with open(os.path.join(OUT, "audit.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    return report


SHOTS_DEF = {  # имя: (цель в px модели, откуда — направление от цели, расстояние в м, FOV)
    "stairs": ((230, -560, 110), (0.30, -0.9, 0.34), 62, 32),
    "gate": ((290, -400, 400), (0.25, -0.9, 0.30), 62, 34),
    "upper": ((-20, -190, 640), (-0.15, -0.95, 0.42), 72, 34),
    "spur": ((-470, 30, 510), (-0.65, -0.72, 0.28), 52, 34),
    "broken": ((196, 150, 830), (0.45, -0.85, 0.32), 58, 34),
    "hill": ((430, -120, 560), (0.85, -0.45, 0.25), 60, 34),
    "ring": ((-90, -555, 200), (-0.15, -0.95, 0.28), 42, 34),
    "back": ((-120, 400, 360), (-0.25, 0.92, 0.28), 72, 36),
}


def shots(names=None, tag="audit"):
    ns = lib()
    site = globals().get("SITE_LIB")
    S = ns["S"]
    ns["place"](True)
    origin = ns["site_origin"]()
    scene = bpy.context.scene
    bpy.data.collections["CastleSite"].hide_render = False
    for ob in bpy.data.collections["CastleSite"].objects:
        if "guide" in ob.name or ob.name.split("Site_")[-1] in ("Fortress", "FortressRoofs", "FortressHouses"):
            ob.hide_render = True
    cam = bpy.data.objects["Camera"]
    scene.camera = cam
    cam.data.type = "PERSP"
    cam.data.sensor_fit = "VERTICAL"
    cam.data.sensor_height = 24.0
    cam.data.clip_end = 3000.0
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = False
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    done = []
    for name, (target, away, dist, fov) in SHOTS_DEF.items():
        if names and name not in names:
            continue
        t = Vector((origin[0] + target[0] * S, origin[1] + target[1] * S, origin[2] + target[2] * S))
        cam.location = t + Vector(away).normalized() * dist
        cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 24.0 / (2 * math.tan(math.radians(fov) / 2))
        scene.render.filepath = os.path.join(OUT, "%s_%s.png" % (tag, name))
        bpy.ops.render.render(write_still=True)
        done.append(name)
    return done


if __name__ == "__main__":
    if MODE == "check":
        RESULT = check()
    else:
        RESULT = shots(globals().get("SHOTS"), globals().get("TAG", "audit"))
    globals()["RESULT"] = RESULT
