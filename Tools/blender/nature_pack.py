"""Пак растительности (Арт/Ассеты/Nature Pack, FBX) → модели для Godot.

Запуск из Blender (MCP или Text Editor), открывает НОВЫЙ пустой файл (несохранённое в текущем потеряется):
    exec(open(r"<проект>/Tools/blender/nature_pack.py", encoding="utf-8").read(), {"__name__": "__main__"})

Что делает:
- импортирует все FBX пака, кроме пальм (решение автора: «всё, кроме пальм»);
- ставит каждую модель в начало координат: основание ствола — в (0, 0, 0);
- меряет плотность текселей каждой текстуры (метров на единицу UV) — чтобы свести её к 40 пикселям на метр;
- сохраняет исходные текстуры в Арт/Ассеты/Nature Pack/textures/ (без карт нормалей);
- экспортирует glb без картинок (материалы задаёт Godot) и описание pack.json:
  модели (материалы → текстуры, высота, радиус ствола) и нужный размер каждой текстуры.
Дальше: python Tools/nature_textures.py → пиксельные текстуры в assets/models/nature/textures/.
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Vector

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
SRC = os.path.join(PROJECT, "Арт", "Ассеты", "Nature Pack")
TEX_OUT = os.path.join(SRC, "textures")
OUT_DIR = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "models", "nature")
SKIP = ("Palm",)
PX_PER_M = 40


def base_name(image):
    """«BirchTree_Leaves.png.001» → «BirchTree_Leaves»."""
    n = image.name
    return n[:n.index(".png")] if ".png" in n else os.path.splitext(n)[0]


def material_image(m):
    """Цветовая текстура материала (не карта нормалей)."""
    if not (m and m.use_nodes):
        return None
    for n in m.node_tree.nodes:
        # «_Normal» — карта нормалей; у обычных деревьев «Normal» и в начале имени («NormalTree_Bark»).
        if n.type == "TEX_IMAGE" and n.image and not base_name(n.image).endswith("_Normal"):
            return n.image
    return None


def texture_of(m):
    """Имя текстуры материала; у ив и тростника своя, хотя картинка в Blender — от исходной модели."""
    if m.name in ("nature_WillowTree_Leaves", "nature_Reed"):
        return m.name.removeprefix("nature_")
    return base_name(material_image(m))


def import_pack():
    bpy.ops.wm.read_homefile(use_empty=True)
    for root, _, files in os.walk(SRC):
        if "textures" in root:
            continue
        for f in files:
            if f.lower().endswith(".fbx") and not any(s in f for s in SKIP):
                bpy.ops.import_scene.fbx(filepath=os.path.join(root, f))
    for ob in list(bpy.data.objects):
        if ob.type != "MESH" or any(s in ob.name for s in SKIP):
            bpy.data.objects.remove(ob, do_unlink=True)
    meshes = [ob for ob in bpy.data.objects if ob.type == "MESH"]
    for ob in meshes:
        mw = ob.matrix_world.copy()
        ob.parent = None
        ob.matrix_world = mw
        ob.data = ob.data.copy()
        ob.data.transform(ob.matrix_world)
        ob.matrix_world.identity()
    return meshes


def to_origin(ob):
    """Основание — середина нижних вершин (у дерева — ствол, а не центр кроны)."""
    vs = [v.co for v in ob.data.vertices]
    zmin = min(v.z for v in vs)
    low = [v for v in vs if v.z < zmin + 0.15]
    cx = sum(v.x for v in low) / len(low)
    cy = sum(v.y for v in low) / len(low)
    shift = Vector((-cx, -cy, -zmin))
    for v in ob.data.vertices:
        v.co += shift
    ob.data.update()
    vs = [v.co for v in ob.data.vertices]
    height = max(v.z for v in vs)
    # Радиус ствола (камня) — по вершинам у земли, для коллизии.
    ground = [v for v in vs if v.z < min(0.6, height * 0.25)]
    trunk = max((math.hypot(v.x, v.y) for v in ground), default=0.2)
    crown = max(math.hypot(v.x, v.y) for v in vs)
    return height, trunk, crown


def make_willows():
    """Ив в паке нет (а деревня — Ивовый Брод): плакучая ива из обычного дерева — крона шире
    и опускается к краям (ветви вместе с листвой), листва — своя текстура WillowTree_Leaves."""
    leaves = None
    out = []
    for n in (1, 2, 3):
        src = bpy.data.objects.get("NormalTree_%d" % n)
        if not src:
            continue
        ob = src.copy()
        ob.data = src.data.copy()
        ob.name = ob.data.name = "WillowTree_%d" % n
        bpy.context.scene.collection.objects.link(ob)
        vs = ob.data.vertices
        height = max(v.co.z for v in vs)
        crown = max(math.hypot(v.co.x, v.co.y) for v in vs)
        for v in vs:
            if v.co.z < height * 0.35:
                continue
            d = math.hypot(v.co.x, v.co.y) / crown
            v.co.x *= 1.2
            v.co.y *= 1.2
            v.co.z -= height * 0.38 * d * d
        ob.data.update()
        for i, m in enumerate(ob.data.materials):
            img = material_image(m)
            if img and base_name(img) == "NormalTree_Leaves":
                if leaves is None:
                    leaves = m.copy()
                    leaves.name = "nature_WillowTree_Leaves"
                ob.data.materials[i] = leaves
        out.append(ob)
    return out


def make_reeds():
    """Тростник у воды: высокий узкий пучок травы пака, своя оливковая окраска (Reed)."""
    src = bpy.data.objects.get("Grass_Large_Extruded")
    out = []
    for n, (sxy, sz) in enumerate(((0.7, 3.2), (0.55, 4.0)), 1):
        ob = src.copy()
        ob.data = src.data.copy()
        ob.name = ob.data.name = "Reed_%d" % n
        bpy.context.scene.collection.objects.link(ob)
        for v in ob.data.vertices:
            v.co.x *= sxy
            v.co.y *= sxy
            v.co.z *= sz
        ob.data.update()
        m = ob.data.materials[0].copy()
        m.name = "nature_Reed"
        ob.data.materials[0] = bpy.data.materials.get("nature_Reed") or m
        out.append(ob)
    return out


def make_lilypads():
    """Кувшинки: плоский диск с вырезом, развёртка на половину текстуры LilyPad (левая — лист, правая — с цветком).
    Текстуру рисует Tools/leaf_sprites.py."""
    out = []
    m = bpy.data.materials.get("nature_LilyPad") or bpy.data.materials.new("nature_LilyPad")
    for n, u0 in ((1, 0.0), (2, 0.5)):
        bm = bmesh.new()
        uv = bm.loops.layers.uv.verify()
        r, segs = 0.45, 12
        c = bm.verts.new((0, 0, 0.02))
        ring = [bm.verts.new((r * math.cos(a), r * math.sin(a), 0.02))
                for a in (2 * math.pi * (i + 0.5) / segs for i in range(segs))]
        for i in range(segs - 1):   # последний сектор пропущен — вырез листа
            f = bm.faces.new([c, ring[i], ring[i + 1]])
            for loop in f.loops:
                p = loop.vert.co
                loop[uv].uv = (u0 + 0.25 + p.x / (4 * r), 0.5 + p.y / (2 * r))
        me = bpy.data.meshes.new("LilyPad_%d" % n)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(m)
        ob = bpy.data.objects.new("LilyPad_%d" % n, me)
        bpy.context.scene.collection.objects.link(ob)
        out.append(ob)
    return out


def tri_area(a, b, c):
    return (b - a).cross(c - a).length / 2.0


def texel_density(ob, stats):
    """Сумма площадей в мире и в UV для каждой текстуры → метры на единицу UV."""
    me = ob.data
    uv = me.uv_layers.active
    if not uv:
        return
    for p in me.polygons:
        m = me.materials[p.material_index] if p.material_index < len(me.materials) else None
        img = material_image(m)
        if not img:
            continue
        idx = list(p.loop_indices)
        world = 0.0
        tex = 0.0
        for k in range(1, len(idx) - 1):
            a, b, c = (me.vertices[me.loops[i].vertex_index].co for i in (idx[0], idx[k], idx[k + 1]))
            world += tri_area(a, b, c)
            ua, ub, uc = (Vector((*uv.data[i].uv, 0.0)) for i in (idx[0], idx[k], idx[k + 1]))
            tex += tri_area(ua, ub, uc)
        s = stats.setdefault(base_name(img), [0.0, 0.0, img])
        s[0] += world
        s[1] += tex


def main():
    meshes = import_pack()
    os.makedirs(TEX_OUT, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)
    models = {}
    stats = {}
    for ob in meshes:
        to_origin(ob)
    meshes += make_willows() + make_reeds()
    for ob in meshes:
        height, trunk, crown = to_origin(ob)
        if not ob.name.startswith(("Willow", "Reed")):
            texel_density(ob, stats)
        mats = []
        for m in ob.data.materials:
            img = material_image(m)
            mats.append(texture_of(m) if img else "")
        models[ob.name] = {"materials": mats, "height": round(height, 2), "trunk": round(trunk, 2),
                           "crown": round(crown, 2), "tris": sum(len(p.vertices) - 2 for p in ob.data.polygons)}
    images = {}
    for name, (world, tex, img) in stats.items():
        m_per_uv = math.sqrt(world / tex) if tex > 0 else 1.0
        images[name] = {"meters_per_uv": round(m_per_uv, 3), "px": max(8, round(PX_PER_M * m_per_uv))}
        path = os.path.join(TEX_OUT, name + ".png")
        if not os.path.exists(path):
            img.filepath_raw = path
            img.file_format = "PNG"
            img.save()
    # Листва ив и тростник — перекраска текстур пака (их делает Tools/nature_textures.py).
    images["WillowTree_Leaves"] = dict(images["NormalTree_Leaves"], source="NormalTree_Leaves")
    images["Reed"] = dict(images["Grass"], source="Grass")
    # Кувшинки — текстуру рисует Tools/leaf_sprites.py.
    for ob in make_lilypads():
        meshes.append(ob)
        models[ob.name] = {"materials": ["LilyPad"], "height": 0.02, "trunk": 0.0, "crown": 0.45, "tris": 11}
    images["LilyPad"] = {"generated": True}
    # Материалы в glb — по имени текстуры (у дублей «.001» иначе разные имена).
    for ob in meshes:
        for i, m in enumerate(ob.data.materials):
            img = material_image(m)
            if img:
                key = "nature_" + texture_of(m)
                mat = bpy.data.materials.get(key) or m.copy()
                mat.name = key
                ob.data.materials[i] = mat
    for i, ob in enumerate(meshes):
        ob.location = (0, 0, 0)
    with open(os.path.join(OUT_DIR, "pack.json"), "w", encoding="utf-8") as f:
        json.dump({"models": models, "images": images}, f, ensure_ascii=False, indent=1)
    for ob in bpy.context.view_layer.objects:
        ob.select_set(ob in meshes)
    window = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=window, screen=window.screen):
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "nature_pack.glb"), use_selection=True,
                                  export_yup=True, export_apply=True, export_image_format="NONE",
                                  export_lights=False, export_cameras=False)
    return {"models": len(models), "images": images}


if __name__ == "__main__":
    result_info = main()
