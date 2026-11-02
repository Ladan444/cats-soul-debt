"""Дома Ивового Брода из модулей Quaternius Medieval Village MegaKit (CC0) — решение автора.

Подключается из build_world.py (village): exec этого файла, затем build_house(...) на каждый дом,
в конце finish(col) — все модули сливаются в один меш «Houses» (материалы по текстурам пака)
и пишется Game/CatsSoulDebt/assets/textures/village_kit/kit.json — сколько метров на единицу UV у каждой
текстуры (по ней Tools/kit_textures.py делает пиксельные текстуры 40 px/м).

Сетка пака — 2 м: стены 2 × 3 м (этаж), фасад на y = −0.09 (наружу −y), крыши Roof_RoundTiles_<пролёт>x<длина>
(конёк вдоль y), фронтоны Roof_Front_Brick<пролёт>. Размеры домов округляются до 2 м (решение автора).
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

KIT = os.path.join(PROJECT, "Арт", "Ассеты", "Medieval Village MegaKit", "Medieval Village MegaKit[Standard]", "glTF")
KIT_JSON = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "textures", "village_kit", "kit.json")
FLOOR_H = 3.0
ROOF_SIZES = {4: (4, 6, 8), 6: (4, 6, 8, 10, 12, 14), 8: (8, 10, 12, 14)}
_lib = {}          # имя модуля → меш (импортирован один раз)
_parts = []        # (меш, матрица, {старый материал → новый}, центр дома или None, имя модуля)
_house_center = None   # центр строящегося дома: грани модулей, смотрящие к нему, — изнанка (материал «…_inside»)
_colliders = []    # (cx, cy, z0, w, d, h, rot)
_rng = random.Random(23)


def _ui():
    """Контекст окна для операторов импорта/экспорта; в фоне (blender -b, Tools/rebuild_world.ps1) окон нет."""
    ws = bpy.context.window_manager.windows
    return {"window": ws[0], "screen": ws[0].screen} if ws else {}


def _module(name):
    """Меш модуля пака (с базовыми материалами без «.001»)."""
    if name in _lib:
        return _lib[name]
    before = set(bpy.data.objects)
    with bpy.context.temp_override(**_ui()):
        bpy.ops.import_scene.gltf(filepath=os.path.join(KIT, name + ".gltf"))
    new = [o for o in bpy.data.objects if o not in before]
    mesh_obs = [o for o in new if o.type == "MESH"]
    bpy.context.view_layer.update()
    # Модуль может состоять из нескольких объектов — склеить в один меш в координатах модуля.
    bm = bmesh.new()
    for o in mesh_obs:
        tmp = o.data.copy()
        tmp.transform(o.matrix_world)
        # Индексы материалов → общие для модуля.
        bm_part = bmesh.new()
        bm_part.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        me_tmp = bpy.data.meshes.new("tmp")
        bm_part.to_mesh(me_tmp)
        bm_part.free()
        bm.from_mesh(me_tmp)
        bpy.data.meshes.remove(me_tmp)
    me = bpy.data.meshes.new("kit_" + name)
    bm.to_mesh(me)
    bm.free()
    # Материалы: берём из первого объекта (у модулей пака это один объект).
    for o in mesh_obs[:1]:
        for s in o.material_slots:
            me.materials.append(_canonical(s.material))
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    _lib[name] = me
    return me


def _canonical(m):
    """«MI_Plaster.003» → общий материал «MI_Plaster» (glTF импорт плодит копии)."""
    base = m.name.split(".")[0]
    keep = bpy.data.materials.get(base)
    if keep is None:
        m.name = base
        return m
    return keep


def place(name, x, y, z, rot=0.0, remap=None):
    _parts.append((_module(name), Matrix.Translation((x, y, z)) @ Matrix.Rotation(rot, 4, "Z"), remap or {},
                   _house_center, name))


def _roof_size(span, length):
    span = min((4, 6, 8), key=lambda s: abs(s - span))
    lengths = ROOF_SIZES[span]
    length = min(lengths, key=lambda l: abs(l - length))
    return span, length


def build_house(rid, x, y, base, w, d, floors=1, roof="red", style="plaster", door_side=(0, -1),
                chimney=False, boarded=False):
    """Дом по центру (x, y) с основанием base. w, d — по x и y (округляются до 2 м); конёк — вдоль длинной стороны.
    Возвращает (верх стен, высота конька, точка трубы или None)."""
    along_y = d >= w
    span, length = _roof_size(w if along_y else d, d if along_y else w)
    W, D = (span, length) if along_y else (length, span)
    rot_house = 0.0 if along_y else math.pi / 2
    walls_top = base + FLOOR_H * floors
    # Нутро дома (решение автора: в «окне» вокруг Рэя не должно быть видно пустой коробки с травой):
    # пол из тёмных досок, изнанка стен и крыши — тёмная (материал «…_inside», в игре — затемнение).
    global _house_center
    _house_center = Vector((x, y, base + FLOOR_H * floors / 2))
    for i in range(int(round(W / 2))):
        for j in range(int(round(D / 2))):
            place("Floor_WoodDark", x - W / 2 + 1 + 2 * i, y - D / 2 + 1 + 2 * j, base + 0.04)
    # Стены по периметру: сегменты 2 м; сторона двери — к площади/дороге.
    sides = [((0, -1), W, 0.0), ((0, 1), W, math.pi), ((1, 0), D, math.pi / 2), ((-1, 0), D, -math.pi / 2)]
    for (sx, sy), length_side, rot in sides:
        n = int(round(length_side / 2))
        cx, cy = x + sx * W / 2, y + sy * D / 2
        for f in range(floors):
            z = base + f * FLOOR_H
            door_i = n // 2 if (sx, sy) == tuple(door_side) and f == 0 else -1
            for i in range(n):
                t = -length_side / 2 + 1 + 2 * i
                px, py = (cx, cy + t) if sx else (cx + t, cy)
                if i == door_i:
                    wall = "Wall_UnevenBrick_Door_Round" if style == "stone" else "Wall_Plaster_Door_Round"
                    place(wall, px, py, z, rot)
                    if boarded:
                        place("Door_1_Flat", px - 0.53 * math.cos(rot), py - 0.53 * math.sin(rot), z, rot)
                    else:
                        place("Door_1_Round", px - 0.53 * math.cos(rot), py - 0.53 * math.sin(rot), z, rot)
                    continue
                window = (i % 2 == 1) and n > 1 and not (f == 0 and style == "stone" and i % 4 != 1)
                if style == "stone" and f == 0:
                    wall = "Wall_UnevenBrick_Window_Wide_Flat" if window else "Wall_UnevenBrick_Straight"
                elif window:
                    wall = "Wall_Plaster_Window_Wide_Flat"
                elif f == 0:
                    wall = "Wall_Plaster_Straight_Base"     # первый этаж — на каменном основании, без подкосов (автор)
                else:
                    wall = "Wall_Plaster_Straight"
                place(wall, px, py, z, rot)
                if window:
                    place("Window_Wide_Flat1", px, py, z, rot)
                    if boarded:
                        place("WindowShutters_Wide_Flat_Closed", px, py, z, rot)
                    elif _rng.random() < 0.5:
                        place("WindowShutters_Wide_Flat_Open", px, py, z, rot)
            # Брус по низу стены между этажами.
            if f > 0:
                for i in range(n):
                    t = -length_side / 2 + 1 + 2 * i
                    px, py = (cx, cy + t) if sx else (cx + t, cy)
                    place("Wall_BottomCover", px, py, z, rot)
    # Угловые брусья.
    for f in range(floors):
        for sx in (-1, 1):
            for sy in (-1, 1):
                place("Corner_Exterior_Brick" if style == "stone" and f == 0 else "Corner_Exterior_Wood",
                      x + sx * W / 2, y + sy * D / 2, base + f * FLOOR_H)
    # Крыша и фронтоны (модули — с коньком вдоль y; дом с коньком вдоль x — поворот на 90°).
    roof_name = "Roof_RoundTiles_%dx%d" % (span, length)
    remap = {"MI_RoundTiles": "MI_RoundTiles_" + roof} if roof != "red" else None
    place(roof_name, x, y, walls_top, rot_house, remap)
    for s in (-1, 1):
        gx, gy = (x, y + s * D / 2) if along_y else (x + s * W / 2, y)
        place("Roof_Front_Brick%d" % span, gx, gy, walls_top,
              rot_house + (0.0 if s < 0 else math.pi))
    ridge = walls_top + {4: 2.9, 6: 4.4, 8: 5.6}[span]
    chimney_top = None
    if chimney:
        off = length / 2 - 1.5
        cxp, cyp = (x + span / 4, y + off) if along_y else (x + off, y + span / 4)
        place("Prop_Chimney", cxp, cyp, walls_top + 1.6)
        chimney_top = (cxp, cyp, walls_top + 1.6 + 3.18)
    # Вьюны — на стенах, где-нибудь у угла.
    if not boarded and _rng.random() < 0.6:
        vine = _rng.choice(("Prop_Vine1", "Prop_Vine2", "Prop_Vine4", "Prop_Vine5"))
        place(vine, x + _rng.uniform(-W / 3, W / 3), y - D / 2 - 0.12, base + 2.9)
    _colliders.append((x, y, base, W + 0.3, D + 0.3, walls_top - base + 0.5))
    _house_center = None
    return walls_top, ridge, chimney_top, (W, D)


def finish(col, mesh_name="Houses", write_info=True, keep_lib=False):
    """Слить все модули в меш mesh_name (материалы — по текстурам пака), простую коллизию — <mesh_name>-colonly.
    write_info — писать kit.json (метров на UV): только для деревни, где собраны все виды модулей.
    keep_lib — не выгружать импортированные модули (мир собирает дома по одному — группы правки); потом release()."""
    bm = bmesh.new()
    mats = []
    inside = {}
    for me, mat_w, remap, center, module in _parts:
        tmp = me.copy()
        tmp.transform(mat_w)
        # Слои развёртки у модулей названы по-разному — при слиянии bmesh сопоставляет их по имени
        # и терял бы UV (белые стены). Приводим к «UV0» (+ «UV1» для потёртостей).
        while len(tmp.uv_layers) < 2:
            tmp.uv_layers.new(name="UVtmp")
        for i, layer in enumerate(tmp.uv_layers):
            layer.name = "UV%d" % i
        # Перенумеровать материалы в общий список.
        index = []
        for m in tmp.materials:
            name = remap.get(m.name, m.name)
            target = bpy.data.materials.get(name)
            if target is None:
                target = m.copy()
                target.name = name
            if target not in mats:
                mats.append(target)
            index.append(mats.index(target))
        part = bmesh.new()
        part.from_mesh(tmp)
        for f in part.faces:
            f.material_index = index[f.material_index] if f.material_index < len(index) else 0
            # Изнанка: грань смотрит внутрь дома (кроме пола, вьюнов и печной трубы).
            if center is not None and not module.startswith(("Floor", "Prop_")):
                f.normal_update()
                c = f.calc_center_median()
                if f.normal.dot(center - c) > 0.05:
                    base_mat = mats[f.material_index]
                    if base_mat.name not in inside:
                        im = base_mat.copy()
                        im.name = base_mat.name + "_inside"
                        inside[base_mat.name] = im
                        mats.append(im)
                    f.material_index = mats.index(inside[base_mat.name])
        part.to_mesh(tmp)
        part.free()
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    houses = bpy.data.meshes.new(mesh_name)
    bm.to_mesh(houses)
    bm.free()
    for m in mats:
        houses.materials.append(m)
    col.objects.link(bpy.data.objects.new(mesh_name, houses))
    # Коллизия — коробки по стенам (без крыш: Рэй всё равно внутрь не ходит).
    cb = bmesh.new()
    for cx, cy, z0, w, d, h in _colliders:
        g = bmesh.ops.create_cube(cb, size=1.0)
        bmesh.ops.scale(cb, vec=(w, d, h), verts=g["verts"])
        bmesh.ops.translate(cb, vec=(cx, cy, z0 + h / 2 - 0.3), verts=g["verts"])
    cm = bpy.data.meshes.new(mesh_name + "-colonly")
    cb.to_mesh(cm)
    cb.free()
    col.objects.link(bpy.data.objects.new(mesh_name + "-colonly", cm))
    if write_info:
        _write_texel_info(houses)
    _parts.clear()
    _colliders.clear()
    if not keep_lib:
        release()


def release():
    """Выгрузить импортированные модули пака."""
    for me in _lib.values():
        bpy.data.meshes.remove(me)
    _lib.clear()


def _write_texel_info(me):
    """Метров на единицу UV (первый слой) для каждой текстуры — по площадям граней в мире и в UV."""
    import json
    uv = me.uv_layers.get("UV0")
    stats = {}
    for p in me.polygons:
        m = me.materials[p.material_index]
        img = _base_image(m)
        if not img or not uv:
            continue
        idx = list(p.loop_indices)
        world = tex = 0.0
        for k in range(1, len(idx) - 1):
            a, b, c = (me.vertices[me.loops[i].vertex_index].co for i in (idx[0], idx[k], idx[k + 1]))
            world += (b - a).cross(c - a).length / 2
            ua, ub, uc = (Vector((*uv.data[i].uv, 0)) for i in (idx[0], idx[k], idx[k + 1]))
            tex += (ub - ua).cross(uc - ua).length / 2
        s = stats.setdefault(img, [0.0, 0.0])
        s[0] += world
        s[1] += tex
    info = {}
    for img, (world, tex) in stats.items():
        info[img] = {"meters_per_uv": round(math.sqrt(world / tex), 3) if tex > 0 else 1.0}
    materials = {m.name: _base_image(m) or "" for m in me.materials}
    os.makedirs(os.path.dirname(KIT_JSON), exist_ok=True)
    with open(KIT_JSON, "w", encoding="utf-8") as f:
        json.dump({"images": info, "materials": materials}, f, ensure_ascii=False, indent=1)


def _base_image(m):
    """Цветовая текстура материала («T_Plaster_BaseColor» или «T_VineLeaf»)."""
    if not (m and m.node_tree):
        return None
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            name = n.image.name.split(".png")[0]
            if "Normal" in name or "Roughness" in name or "ORM" in name or "Wear" in name or "Noise" in name:
                continue
            return name
    return None
