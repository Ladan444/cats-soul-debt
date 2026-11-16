"""Растительность замка из пака проекта (nature_pack.glb, nature_extras.glb) — в своей сцене castle.blend.

Запуск после build_castle.py (MODE build), места берёт из Арт/Blender/castle/castle_spots.json:
    exec(open(r"<проект>/Tools/blender/castle_veg.py", encoding="utf-8").read(), {"__name__": "__main__"})
Модели — связанные копии в коллекции «CastleVeg», дети Castle_Root; библиотека — скрытая коллекция «CastleVegLib».
Пишет Арт/Blender/castle/castle_nature.json в формате assets/levels/world_nature.json:
{модель: [x, y, z, поворот, масштаб, ...]} в осях Godot, координаты мира (посадка на мыс из build_castle.py).
В мир этот файл сам не попадает: его подключат при встраивании.
"""
import json
import math
import os
import random

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
NATURE = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "models", "nature")
OUT = os.path.join(PROJECT, "Арт", "Blender", "castle")
SEED = 21

# Набор и доли: (модель, вес, масштаб от, масштаб до). Трава и папоротник — на уступах, кусты — на верхушках блоков.
LEDGE = [("Dt_Tuft_A", 44, 0.7, 1.2), ("Dt_Tuft_Tall", 14, 0.6, 1.0), ("Dt_Fern_C", 12, 0.8, 1.3), ("Dt_Fern_A", 8, 0.7, 1.1)]
TOP = [("Dt_Fern_B", 26, 0.8, 1.2), ("Dt_Fern_A", 18, 0.8, 1.3), ("Dt_Tuft_Tall", 40, 0.7, 1.2), ("Dt_Tuft_A", 16, 0.8, 1.3)]
STAIR = [("Dt_Tuft_A", 60, 0.5, 0.9), ("Dt_Tuft_Tall", 16, 0.5, 0.9), ("Dt_Fern_C", 24, 0.5, 0.8)]
# Кусты, цветы, лиственные, сухая трава и широкие листья и мёртвые деревья пака — кислотные, бежевые и рыжие точки: на мрачной скале их нет.
TREES = [("PineTree_5", 34, 0.8, 1.3), ("PineTree_3", 30, 1.0, 1.6)]
# Листва пака тёплая и яркая (хвоя 179, 177, 51; трава 97, 121, 47), а палитра меню холодная и тёмная. Для замка — множитель
# в линейном цвете. При встраивании этим растениям нужен свой материал: сейчас NatureScatter красит модели только по яркости.
DARKEN = {"PineTree_Leaves": (0.06, 0.11, 0.90), "ExtrasFoliage": (0.30, 0.34, 1.0), "PineTree_Bark": (0.35, 0.42, 0.60),
          "NormalTree_Bark": (0.12, 0.20, 0.42)}
COUNTS = {"ledge": 2600, "top": 700, "stair": 60, "wall": 90, "tree": 34}


def choose(rng, table):
    total = sum(t[1] for t in table)
    k = rng.uniform(0, total)
    for t in table:
        k -= t[1]
        if k <= 0:
            return t
    return table[-1]


def veg_material(name):
    """Материал по пиксельной текстуре проекта (nearest, вырез по альфе); имя — как в паке."""
    base = name.split(".")[0].replace("Veg_", "").replace("nature_", "").replace("_dark", "")   # в паке: nature_<текстура>
    tint = DARKEN.get(base)
    full = "Veg_" + base + ("_dark" if tint else "")
    m = bpy.data.materials.get(full)
    if m:
        for n in m.node_tree.nodes:
            if tint and n.type == "MIX":
                n.inputs[7].default_value = (*tint, 1.0)
        return m
    m = bpy.data.materials.new(full)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.95
    bsdf.inputs["Specular IOR Level"].default_value = 0.1
    path = os.path.join(NATURE, "textures", base + ".png")
    if os.path.exists(path):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(path, check_existing=True)
        tex.interpolation = "Closest"
        if tint:
            mul = nt.nodes.new("ShaderNodeMix")
            mul.data_type = "RGBA"
            mul.blend_type = "MULTIPLY"
            mul.inputs[0].default_value = 1.0
            mul.inputs[7].default_value = (*tint, 1.0)
            nt.links.new(tex.outputs["Color"], mul.inputs[6])
            nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
        else:
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if tex.image.channels == 4 and base not in ("ExtrasSolid", "Rocks"):
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            m.surface_render_method = "DITHERED"
    return m


def load_library(names):
    """Импорт глб один раз; остаются только нужные модели, в скрытой коллекции."""
    lib = bpy.data.collections.get("CastleVegLib")
    if lib is None:
        lib = bpy.data.collections.new("CastleVegLib")
        bpy.context.scene.collection.children.link(lib)
    lib.hide_render = True
    lib.hide_viewport = True
    have = {o.name: o for o in lib.objects}
    if all(n in have for n in names):
        for o in have.values():
            for i, mat in enumerate(o.data.materials):
                o.data.materials[i] = veg_material(mat.name if mat else "Rocks")
        return have
    before = set(bpy.data.objects)
    bpy.ops.object.select_all(action="DESELECT")
    for f in ("nature_pack.glb", "nature_extras.glb"):
        bpy.ops.import_scene.gltf(filepath=os.path.join(NATURE, f))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
    keep = {}
    for o in new:
        base = o.name.split(".")[0]
        if o.type == "MESH" and base in names and base not in keep:
            o.parent = None
            o.location = (0.0, 0.0, 0.0)
            o.rotation_euler = (0.0, 0.0, 0.0)
            o.rotation_mode = "XYZ"
            o.scale = (1.0, 1.0, 1.0)
            o.name = base
            lib.objects.link(o)
            keep[base] = o
            me = o.data
            for i, mat in enumerate(me.materials):
                me.materials[i] = veg_material(mat.name if mat else "Rocks")
    for o in new:
        if o.name not in keep or keep.get(o.name) is not o:
            bpy.data.objects.remove(o)
    return {**have, **keep}


def clear_instances():
    coll = bpy.data.collections.get("CastleVeg")
    if coll is None:
        coll = bpy.data.collections.new("CastleVeg")
        bpy.context.scene.collection.children.link(coll)
    for o in list(coll.objects):
        bpy.data.objects.remove(o)
    return coll


def main():
    ns = {"__name__": "castle_lib", "MODE": "none"}
    exec(open(os.path.join(PROJECT, "Tools", "blender", "build_castle.py"), encoding="utf-8").read(), ns)
    S, origin = ns["S"], ns["site_origin"]()
    on_walkway = ns["on_walkway"]
    spots = json.load(open(os.path.join(OUT, "castle_spots.json"), encoding="utf-8"))
    rng = random.Random(SEED)
    names = sorted({t[0] for table in (LEDGE, TOP, STAIR, TREES) for t in table})
    lib = load_library(names)
    missing = [n for n in names if n not in lib]
    coll = clear_instances()
    root = bpy.data.objects["Castle_Root"]
    placed = {}
    counts = {}

    def put(table, x, y, z, sink=0.0):
        name, _, s0, s1 = choose(rng, table)
        if name not in lib:
            return
        scale = rng.uniform(s0, s1)
        rot = rng.uniform(0, math.tau)
        ob = bpy.data.objects.new("v_" + name, lib[name].data)
        ob.location = (x * S, y * S, z * S - sink)
        ob.rotation_euler = (0.0, 0.0, rot)
        ob.scale = (scale, scale, scale)
        ob.parent = root
        coll.objects.link(ob)
        wx, wy, wz = origin[0] + x * S, origin[1] + y * S, origin[2] + z * S - sink
        placed.setdefault(name, []).extend([round(wx, 2), round(wz, 2), round(-wy, 2), round(rot, 3), round(scale, 3)])
        counts[name] = counts.get(name, 0) + 1

    # Опоры берём с настоящей поверхности: грани скалы, смотрящие вверх. Каждое растение проверяется лучом вниз.
    all_verts, all_polys = [], []
    for ob in bpy.data.collections["Castle"].objects:
        if ob.type != "MESH" or ob.name == "Castle_Ivy":
            continue
        base = len(all_verts)
        all_verts.extend(q.co.copy() for q in ob.data.vertices)
        all_polys.extend([base + i for i in q.vertices] for q in ob.data.polygons)
    bvh = BVHTree.FromPolygons(all_verts, all_polys, all_triangles=False, epsilon=0.0)

    def grounded(x, y, z, limit=0.45):
        """Точка в px: есть ли прямо под ней поверхность; возвращает высоту поверхности в px или None."""
        hit = bvh.ray_cast(Vector((x * S, y * S, z * S + 0.35)), Vector((0, 0, -1)), 0.35 + limit)
        return None if hit[0] is None else hit[0].z / S

    rock = bpy.data.objects["Castle_Rock"].data
    faces, weights = [], []
    for poly in rock.polygons:
        if poly.normal.z < 0.34 or len(poly.vertices) != 4:
            continue
        zp = poly.center.z / S
        if zp < 68 or 350 < zp < 464:     # под плато и за куртиной не видно
            continue
        faces.append(poly.index)
        weights.append(poly.area * (poly.normal.z ** 2))
    picks = rng.choices(faces, weights=weights, k=COUNTS["ledge"] + COUNTS["top"])
    for n, fi in enumerate(picks):
        poly = rock.polygons[fi]
        ws = [rng.random() for _ in poly.vertices]
        tot = sum(ws)
        co = sum((rock.vertices[i].co * (w / tot) for i, w in zip(poly.vertices, ws)), Vector((0, 0, 0))) / S
        if on_walkway(co.x, co.y, co.z):
            continue
        gz = grounded(co.x, co.y, co.z)
        if gz is None or abs(gz - co.z) > 2.0:      # над точкой другая деталь или под ней пусто
            continue
        put(LEDGE if n < COUNTS["ledge"] else TOP, co.x, co.y, gz, 0.05)
    for key, table in (("wall", STAIR), ("stair", STAIR)):
        lst = list(spots[key])
        rng.shuffle(lst)
        for q in lst[:COUNTS.get(key, 60)]:
            gz = grounded(q[0], q[1], q[2])
            if gz is not None and not on_walkway(q[0], q[1], gz):
                put(table, q[0], q[1], gz, 0.03)
    # Редкие деревца: на широких уступах, друг от друга подальше.
    wide = [fi for fi, w in zip(faces, weights) if rock.polygons[fi].normal.z > 0.5]
    rng.shuffle(wide)
    trees = []
    for fi in wide:
        if len(trees) >= COUNTS["tree"]:
            break
        co = rock.polygons[fi].center / S
        if on_walkway(co.x, co.y, co.z) or any(math.hypot(co.x - a, co.y - b) < 42 for a, b in trees):
            continue
        gz = grounded(co.x, co.y, co.z)
        if gz is None:
            continue
        put(TREES, co.x, co.y, gz, 0.2)
        trees.append((co.x, co.y))
    with open(os.path.join(OUT, "castle_nature.json"), "w", encoding="utf-8") as f:
        json.dump(placed, f, separators=(",", ":"))
    tris = {n: sum(len(p.vertices) - 2 for p in lib[n].data.polygons) for n in names if n in lib}
    bpy.ops.wm.save_mainfile()
    return {"экземпляров": sum(counts.values()), "по_моделям": counts, "нет_в_паке": missing,
            "треугольников_в_кадре_если_всё": sum(counts[n] * tris[n] for n in counts)}


if __name__ == "__main__":
    RESULT = main()
    globals()["RESULT"] = RESULT
