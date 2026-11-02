"""Детали этажа Рубежа из KayKit Dungeon (CC0) поверх серых блоков — решение автора: «наши стены + детали KayKit».

Запуск из Blender (MCP), открывает НОВЫЙ файл (в rubezh_upper.blend не пишет):
    exec(open(r"<проект>/Tools/blender/rubezh_props.py", encoding="utf-8").read(), {"__name__": "__main__", "FLOOR_ID": "F1"})
Результат: Game/CatsSoulDebt/assets/levels/rubezh_<этаж>_props.glb — меш «Props» (палитра KayKit), «Props-colonly»,
«Arches» (арки в проёмах) и пустышки fx-torch/fx-candle.
Расстановка — по залам из Tools/blender/rubezh_layout.py (по id зала и тегам): факелы на северных стенах,
колонны по углам больших залов, мебель по назначению (казарма — койки, трапезная — столы, оружейная — щиты,
погреб — бочки, сокровищница — сундуки и монеты, склеп — гробы-сундуки, двор — ящики), знамёна.
Мебель уменьшена до масштаба Рэя (PROP_SCALE из build_tavern.py). Центр прохода и двери не загораживаются.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
FLOOR_ID = globals().get("FLOOR_ID", "F1")
GLB = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "levels", "rubezh_%s_props.glb" % FLOOR_ID.lower())

lib = {"__name__": "kaykit_lib"}
exec(open(os.path.join(PROJECT, "Tools", "blender", "build_tavern.py"), encoding="utf-8").read(), lib)
prop, S = lib["prop"], lib["PROP_SCALE"]
layout = {}
exec(open(os.path.join(PROJECT, "Tools", "blender", "rubezh_layout.py"), encoding="utf-8").read(), layout)
schema = {"__name__": "lib"}
exec(open(os.path.join(PROJECT, "Tools", "blender", "build_schema.py"), encoding="utf-8").read(), schema)
rng = random.Random(41)
CORRIDOR_W = 3.0   # как в build_greybox.py


def floor_data():
    return next(f for f in layout["FLOORS"] if f["id"] == FLOOR_ID)


def rooms():
    return floor_data()["rooms"]


def wall_openings(room, side, crossings_only=False):
    """Проёмы в стене зала (north/south/west/east): координаты вдоль стены, где её пересекают коридоры связей
    (route из build_schema, как в build_greybox). crossings_only — только поперечные проходы (места для арок),
    без коридоров, идущих вдоль стены."""
    rid, _, x, y, w, d, z, tags = room
    across_y = side in ("north", "south")          # стена вдоль x
    face = y + d / 2 if side == "north" else y - d / 2 if side == "south" else x + w / 2 if side == "east" else x - w / 2
    centre, half = (x, w / 2) if across_y else (y, d / 2)
    by_id = {r[0]: r for r in rooms()}
    out = []
    for a, b, kind, label in floor_data()["links"]:
        if rid not in (a, b):
            continue
        path = schema["route"](by_id[a], by_id[b])
        for (px, py), (qx, qy) in zip(path, path[1:]):
            # Координата «поперёк стены» (u) и «вдоль» (v) для концов отрезка.
            pu, qu, pv, qv = (py, qy, px, qx) if across_y else (px, qx, py, qy)
            if abs(pv - qv) < 0.01 and min(pu, qu) - 0.01 <= face <= max(pu, qu) + 0.01 and abs(pv - centre) <= half:
                out.append(pv)
            elif not crossings_only and abs(pu - qu) < 0.01 and abs(pu - face) < CORRIDOR_W / 2 + 0.5:
                out.extend([min(pv, qv) + i * 0.5 for i in range(int(abs(qv - pv) / 0.5) + 1)])
    return out


def clear_of(px, openings, margin=CORRIDOR_W / 2 + 0.8):
    return all(abs(px - ox) > margin for ox in openings)


_room = None    # текущий зал (кортеж из rubezh_layout) — для проёмов в along_wall


def along_wall(x, y, w, d, side, step, margin=1.5):
    """Точки вдоль стены зала (north/south/west/east) с шагом step, с отступом от углов; в проёмах — пропуск."""
    gaps = wall_openings(_room, side) if _room else []
    pts = []
    if side in ("north", "south"):
        yy = y + (d / 2 - 0.6) * (1 if side == "north" else -1)
        n = max(1, int((w - 2 * margin) // step) + 1)
        for i in range(n):
            pts.append((x - w / 2 + margin + i * step, yy))
    else:
        xx = x + (w / 2 - 0.6) * (1 if side == "east" else -1)
        n = max(1, int((d - 2 * margin) // step) + 1)
        for i in range(n):
            pts.append((xx, y - d / 2 + margin + i * step))
    along = 0 if side in ("north", "south") else 1
    return [p for p in pts if clear_of(p[along], gaps)]


POINTS = []      # (имя, x, y, z) — пустышки fx-* для Ambience в игре
TORCH_FLAME = (0.0, -0.33, 0.51)   # огонь в модели torch_mounted (без масштаба)


_openings = []   # проёмы северной стены текущего зала (north_openings)


def on_north(name, px, y_face, z, scale=S):
    """Настенная вещь на северной стене зала: задняя сторона модели (max y) — вплотную к стене, лицом в зал.
    В проёме (двери, коридоры) не ставится. Возвращает, поставлена ли."""
    me = lib["kaykit"](name)
    half = max(abs(v.co.x) for v in me.vertices) * scale
    if not clear_of(px, _openings, CORRIDOR_W / 2 + half + 0.2):
        return False
    back = max(v.co.y for v in me.vertices)
    prop(name, px, y_face - back * scale, z, 0.0, scale)
    return True


def torch(px, y_face, z, scale=S):
    if not on_north("torch_mounted", px, y_face, z, scale):
        return
    fx, fy, fz = TORCH_FLAME
    POINTS.append(("fx-torch-%02d" % (len(POINTS) + 1), px + fx * scale, y_face + fy * scale, z + fz * scale))


ARCHES = []      # (x, y, z, поворот) — арки KayKit в проёмах; отдельный меш «Arches» (в игре — окно x-ray)
ARCH_WALL_T = 0.5   # толщина наших стен (WALL_T в build_greybox): арка встаёт на середину стены
# Сквозной проём с каменной перемычкой и деревянными стойками (wall_arched — глухая стена с аркой, не проход).
ARCH_MODEL = "wall_open_scaffold"


def arches(room):
    """Обрамление проёма KayKit (ARCH_MODEL, модуль 4 × 4 м, проём ≈ 3,6 м — шире коридора 3 м) в каждом поперечном проёме
    северной, западной и восточной стены зала. Южные стены — низкий срез к камере, арок там нет."""
    rid, _, x, y, w, d, z, tags = room
    for side, rot in (("north", 0.0), ("west", math.pi / 2), ("east", math.pi / 2)):
        for v in sorted(set(round(o * 2) / 2 for o in wall_openings(room, side, True))):
            if side == "north":
                ARCHES.append((v, y + d / 2 + ARCH_WALL_T / 2, z, rot))
            else:
                sx = 1 if side == "east" else -1
                ARCHES.append((x + sx * (w / 2 + ARCH_WALL_T / 2), v, z, rot))


def finish_arches(col):
    bm = bmesh.new()
    me = lib["kaykit"](ARCH_MODEL)
    for ax, ay, az, rot in ARCHES:
        tmp = me.copy()
        tmp.transform(Matrix.Translation((ax, ay, az)) @ Matrix.Rotation(rot, 4, "Z"))
        if tmp.uv_layers:
            tmp.uv_layers[0].name = "UV0"
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    out = bpy.data.meshes.new("Arches")
    bm.to_mesh(out)
    bm.free()
    out.materials.append(bpy.data.materials.get("kaykit_palette") or bpy.data.materials.new("kaykit_palette"))
    col.objects.link(bpy.data.objects.new("Arches", out))


def great_hall(x, y, w, d, z):
    """Большой зал (финал Главы 1): колоннада, знамёна и факелы на северной стене, оплывшие свечи кольцом
    у круга печати, обломки по углам — зал давно заброшен.
    Центр (круг, R ≈ 3,6 м) и проход от южной двери свободны."""
    face = y + d / 2
    for sx in (-1, 1):
        for dy in (-d / 3.5, 0.0, d / 3.5):
            prop("pillar_decorated", x + sx * (w / 2 - 4.5), y + dy, z, 0.0, 1.0, collide=(2.0, 1.7, 4.0))
    for i, px in enumerate((-9.0, -3.0, 3.0, 9.0)):
        on_north("banner_patternA_red" if i in (0, 3) else "banner_thin_red", x + px, face, z + 0.6, 1.0)
    for px in (-6.0, 0.0, 6.0):
        torch(x + px, face, z + 1.5, 0.8)
    for i in range(12):
        ang = i * math.tau / 12 + 0.2
        px, py = x + math.cos(ang) * 4.4, y + math.sin(ang) * 4.4
        prop("candle_melted" if i % 3 else "candle_triple", px, py, z, rng.random() * 6)
        if i % 3 == 0:
            POINTS.append(("fx-candle-%02d" % i, px, py, z + 0.55))
    prop("rubble_half", x - w / 2 + 0.3, y + d / 2 - 3.2, z, 0.0, S, collide=(2.4, 1.8, 2.0))
    prop("rubble_half", x + w / 2 - 0.3, y - d / 2 + 3.5, z, math.pi, S, collide=(2.4, 1.8, 2.0))
    prop("rubble_large", x + w / 2 - 2.5, y + d / 2 - 2.0, z, 0.8)
    prop("table_long_broken", x - w / 2 + 2.0, y - d / 2 + 3.0, z, 0.3, S, collide=(1.3, 2.5, 0.8))
    prop("barrier_column", x - w / 2 + 2.2, y + 2.0, z, math.pi / 2, S, collide=(0.5, 2.4, 0.9))
    prop("sword_shield_broken", x + w / 2 - 3.0, y - d / 2 + 1.5, z + 0.3, 1.2)


def dress_room(rid, x, y, w, d, z, tags):
    global _room
    _room = (rid, "", x, y, w, d, z, tags)
    _openings[:] = wall_openings(_room, "north")
    if "corridor" not in tags and "bridge" not in tags:
        arches(_room)
    if rid == "great":
        great_hall(x, y, w, d, z)
        return
    if "corridor" in tags or "bridge" in tags or "secret" in tags or w * d < 40:
        return
    face = y + d / 2
    # Факелы на северной стене (вместо кубиков-огоньков), не в проёмах.
    for px, py in along_wall(x, y, w, d, "north", 6.0, 2.5):
        torch(px, face, z + 1.4)
    # Колонны по углам больших залов.
    if w >= 16 and d >= 12:
        for sx in (-1, 1):
            for sy in (-1, 1):
                prop("pillar", x + sx * (w / 2 - 1.2), y + sy * (d / 2 - 1.2), z, 0.0, S, collide=(0.9, 0.9, 3.0))
    if rid == "barracks":
        for i, (px, py) in enumerate(along_wall(x, y, w, d, "west", 2.2, 2.0)):
            prop("bed_floor" if i % 2 else "bed_frame", px + 0.6, py, z, math.pi / 2, collide=(1.2, 0.8, 0.6))
        for px, py in along_wall(x, y, w, d, "north", 3.0, 3.0)[:3]:
            prop("trunk_small_A", px, py - 0.4, z, math.pi)
        prop("table_medium", x + 3, y - 2, z, 0.3, collide=(1.2, 1.2, 0.8))
        prop("stool", x + 2, y - 2.6, z)
        on_north("banner_blue", x + 1.5, face, z)
    elif rid == "mess":
        for dy in (-2.5, 2.0):
            prop("table_long_broken" if dy < 0 else "table_long_decorated_A", x - 1, y + dy, z, math.pi / 2, collide=(2.4, 1.2, 0.8))
            for dx in (-2.0, -0.8, 0.4):
                prop("stool", x - 1 + dx, y + dy - 0.9, z)
        prop("barrel_small_stack", x + w / 2 - 1.2, y + d / 2 - 1.2, z)
    elif rid == "armory":
        # Мечи со щитами — между факелами (факелы на x−3,5 и x+2,5).
        for dx in (-5.0, -1.8, 0.4, 4.6):
            on_north("sword_shield" if rng.random() < 0.7 else "sword_shield_broken", x + dx, face, z + 0.9)
        prop("barrel_large", x + w / 2 - 1.2, y - d / 2 + 1.3, z, 0.0, S, collide=(1.1, 1.1, 1.2))
        prop("box_stacked", x - w / 2 + 1.3, y - d / 2 + 1.3, z, 0.4)
    elif rid == "cellar":
        for px, py in along_wall(x, y, w, d, "north", 1.6, 1.5):
            prop("barrel_large" if rng.random() < 0.5 else "keg", px, py - 0.4, z, rng.random() * 6, S, collide=(1.1, 1.1, 1.2))
    elif rid == "treasury":
        prop("chest_gold", x, y + d / 2 - 1.6, z, math.pi, S, collide=(1.1, 0.9, 0.8))
        for dx in (-3, 3):
            prop("chest", x + dx, y + d / 2 - 1.6, z, math.pi, S, collide=(1.1, 0.9, 0.8))
        for _ in range(6):
            prop(rng.choice(["coin_stack_small", "coin_stack_medium", "coin_stack_large"]),
                 x + rng.uniform(-w / 3, w / 3), y + rng.uniform(0, d / 3), z)
    elif rid == "crypt":
        # Гробы — длинные сундуки рядами вдоль восточной и западной стен (саркофагов в наборе нет).
        for side in ("west", "east"):
            for px, py in along_wall(x, y, w, d, side, 3.0, 2.5):
                prop("trunk_large_A", px + (1.0 if side == "west" else -1.0), py, z, math.pi / 2, S, collide=(1.2, 1.8, 0.8))
        for c in range(3):
            prop("candle_triple", x - 2 + c * 2, y + d / 2 - 1.0, z)
    elif rid == "yard":
        for px, py in ((x - w / 2 + 2, y - d / 2 + 2), (x + w / 2 - 2.5, y + d / 2 - 2)):
            prop("crates_stacked", px, py, z, rng.random() * 3, S, collide=(1.2, 1.2, 1.2))
        prop("barrel_small", x + w / 2 - 1.5, y - d / 2 + 1.5, z)
        on_north("banner_triple_blue", x + 1.5, face, z)
    elif rid == "guard":
        prop("table_small_decorated_B", x, y + 1, z, 0.0, S, collide=(0.9, 0.9, 0.8))
        prop("chair", x - 0.9, y + 1, z, -math.pi / 2)
        prop("keyring_hanging", x + w / 2 - 0.16 * S, y, z + 1.3, -math.pi / 2)
    elif rid == "chapel":
        for c in range(4):
            prop("candle_thin_lit", x - 3 + c * 2, y + d / 2 - 1.0, z)
        on_north("banner_shield_blue", x, face, z)
    elif rid == "ossuary":
        prop("rubble_large", x, y, z, 0.6)
    elif rid == "gate":
        for sx in (-1, 1):
            prop("pillar_decorated", x + sx * 3.0, y + d / 2 - 1.0, z, 0.0, S, collide=(0.9, 0.9, 3.0))


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    col = bpy.data.collections.new("Детали " + FLOOR_ID)
    bpy.context.scene.collection.children.link(col)
    for rid, title, x, y, w, d, z, tags in rooms():
        dress_room(rid, x, y, w, d, z, tags)
    lib["finish_props"](col)
    if ARCHES:
        finish_arches(col)
    for name, px, py, pz in POINTS:
        e = bpy.data.objects.new(name, None)
        e.location = (px, py, pz)
        col.objects.link(e)
    return col


if __name__ == "__main__":
    collection = build()
    window = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(window=window, screen=window.screen):
        bpy.ops.object.select_all(action="DESELECT")
        for ob in collection.all_objects:
            ob.select_set(True)
        bpy.ops.export_scene.gltf(filepath=GLB, use_selection=True, export_yup=True, export_apply=True,
                                  export_lights=False, export_cameras=False, export_image_format="NONE")
    result_info = {"tris": sum(len(p.vertices) - 2 for p in bpy.data.objects["Props"].data.polygons), "glb": GLB}
