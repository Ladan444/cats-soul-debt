"""Таверна «Красная черепица» внутри (VILLAGE_SPEC, раздел 5; Глава 1 — Литература/CHAPTER1.md).

Запуск из Blender (MCP), открывает НОВЫЙ файл и сохраняет Арт/Blender/tavern.blend:
    exec(open(r"<проект>/Tools/blender/build_tavern.py", encoding="utf-8").read(), {"__name__": "__main__"})
Результат: Game/CatsSoulDebt/assets/levels/tavern.glb.

Состав (решение автора: отдельная сцена из модулей):
- стены — модули Quaternius (побелка с брусом, окна, двери; Tools/blender/village_houses.py), меш «Walls»;
- мебель — KayKit Dungeon (CC0), уменьшена до нашего масштаба (PROP_SCALE), меш «Props» (одна палитра-текстура);
- пол — доски KayKit; южной стены нет (срез диорамы — камера смотрит с юга).
Планировка, м (x — восток, y — север): зал 14 × 10 (x −7…7, y −5…5); комната Рэя — восточный угол за перегородкой
(x 3…7, y 0…5) с кроватью; стойка графа у северной стены; камин у западной; столы в зале.
Точки для Godot (пустышки): spawn-start (у кровати Рэя), npc-velmor (за стойкой), exit-village (у южного края),
fx-fire (камин), fx-candle-NN (свечи), banner-third-company (место знамени над камином).
Оси: Blender (x, y, z) → Godot (x, z, −y).
"""
import glob
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
BLEND = os.path.join(PROJECT, "Арт", "Blender", "tavern.blend")
GLB = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "levels", "tavern.glb")
KAYKIT = glob.glob(os.path.join(glob.escape(os.path.join(PROJECT, "Арт", "Ассеты", "KayKit Dungeon")), "*", "Assets", "gltf"))[0]
PROP_SCALE = 0.6

_props = []      # (меш, матрица)
_prop_lib = {}


def _ui():
    """Контекст окна для операторов импорта/экспорта; в фоне (blender -b, Tools/rebuild_world.ps1) окон нет."""
    ws = bpy.context.window_manager.windows
    return {"window": ws[0], "screen": ws[0].screen} if ws else {}


def kaykit(name):
    if name in _prop_lib:
        return _prop_lib[name]
    before = set(bpy.data.objects)
    with bpy.context.temp_override(**_ui()):
        bpy.ops.import_scene.gltf(filepath=os.path.join(KAYKIT, name + ".gltf"))
    new = [o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    bm = bmesh.new()
    for o in new:
        if o.type != "MESH":
            continue
        tmp = o.data.copy()
        tmp.transform(o.matrix_world)
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    me = bpy.data.meshes.new("kk_" + name)
    bm.to_mesh(me)
    bm.free()
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    _prop_lib[name] = me
    return me


def prop(name, x, y, z=0.0, rot=0.0, scale=PROP_SCALE, collide=None):
    """Предмет KayKit. collide=(w, d, h) — коробка коллизии (в метрах уже с масштабом)."""
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rot, 4, "Z") @ Matrix.Scale(scale, 4)
    _props.append((kaykit(name), m))
    if collide:
        w, d, h = collide
        COLLIDERS.append((x, y, z, w, d, h, rot))


COLLIDERS = []
POINTS = []      # (имя, x, y, z)


def finish_props(col):
    bm = bmesh.new()
    uv_name = None
    for me, m in _props:
        tmp = me.copy()
        tmp.transform(m)
        if tmp.uv_layers:
            tmp.uv_layers[0].name = "UV0"
        bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
    props = bpy.data.meshes.new("Props")
    bm.to_mesh(props)
    bm.free()
    mat = bpy.data.materials.get("kaykit_palette") or bpy.data.materials.new("kaykit_palette")
    props.materials.append(mat)
    for p in props.polygons:
        p.material_index = 0
    col.objects.link(bpy.data.objects.new("Props", props))
    cb = bmesh.new()
    for x, y, z, w, d, h, rot in COLLIDERS:
        g = bmesh.ops.create_cube(cb, size=1.0)
        bmesh.ops.scale(cb, vec=(w, d, h), verts=g["verts"])
        bmesh.ops.rotate(cb, verts=g["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(rot, 3, "Z"))
        bmesh.ops.translate(cb, vec=(x, y, z + h / 2), verts=g["verts"])
    cm = bpy.data.meshes.new("Props-colonly")
    cb.to_mesh(cm)
    cb.free()
    col.objects.link(bpy.data.objects.new("Props-colonly", cm))


def floor(col):
    """Доски KayKit (плитка 4 м × PROP_SCALE = 2,4 м — доски в масштабе Рэя) по всему залу; под ними — коллизия."""
    step = 4.0 * PROP_SCALE
    nx, ny = int(math.ceil(15.0 / step)), int(math.ceil(11.0 / step))
    for i in range(nx):
        for j in range(ny):
            # Сетка по центру зала: лишнее уходит поровну под стены с обеих сторон.
            prop("floor_wood_large", step * (i + 0.5 - nx / 2), step * (j + 0.5 - ny / 2), 0.0)
    bm = bmesh.new()
    g = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(16, 12, 0.5), verts=g["verts"])
    bmesh.ops.translate(bm, vec=(0, 0, -0.25), verts=g["verts"])
    me = bpy.data.meshes.new("TavernFloor-colonly")
    bm.to_mesh(me)
    bm.free()
    col.objects.link(bpy.data.objects.new("TavernFloor-colonly", me))


def walls(kit):
    """Стены Quaternius по периметру (север, запад, восток) и перегородка комнаты Рэя. Модуль 2 м, наружу −y."""
    place = kit["place"]
    # Север (смотрит внутрь — на юг): модули повёрнуты на 180°, окна через один.
    for i, x in enumerate(range(-6, 8, 2)):
        name = "Wall_Plaster_Window_Wide_Flat" if i in (1, 5) else ("Wall_Plaster_Door_Round" if i == 3 else "Wall_Plaster_Straight")
        place(name, x, 5.0, 0.0, math.pi)
        if i in (1, 5):
            place("Window_Wide_Flat1", x, 5.0, 0.0, math.pi)
    # Запад и восток: стены лицом внутрь.
    for y in range(-4, 6, 2):
        place("Wall_Plaster_Straight" if y != 0 else "Wall_Plaster_Window_Wide_Flat", -7.0, y, 0.0, -math.pi / 2)
        place("Wall_Plaster_Straight" if y != -2 else "Wall_Plaster_Window_Wide_Flat", 7.0, y, 0.0, math.pi / 2)
    place("Window_Wide_Flat1", -7.0, 0, 0.0, -math.pi / 2)
    place("Window_Wide_Flat1", 7.0, -2, 0.0, math.pi / 2)
    # Перегородка комнаты Рэя: по x = 3 (y 1…5) с дверью, по y = 0 (x 3…7) — низкая (срез к камере).
    for y, name in ((1.0, "Wall_Plaster_Door_Round"), (3.0, "Wall_Plaster_Straight")):
        place(name, 3.0, y, 0.0, -math.pi / 2)
    for x in (4.0, 6.0):
        place("Wall_BottomCover", x, 0.0, 0.0, 0.0)
    for x, y in ((-7, 5), (7, 5), (3, 5), (-7, -5), (7, -5), (3, 0)):
        place("Corner_Exterior_Wood", x, y, 0.0)
    kit["_colliders"].extend([
        (0.0, 5.3, 0.3, 14.6, 0.4, 3.2), (-7.3, 0.0, 0.3, 0.4, 10.6, 3.2), (7.3, 0.0, 0.3, 0.4, 10.6, 3.2),
        (3.0, 4.0, 0.3, 0.3, 2.0, 3.2), (5.0, 0.0, 0.3, 4.0, 0.3, 1.0),
    ])


def furniture():
    # Стойка графа: две длинные столешницы вдоль северной стены, за ними — бочки и полки с бутылками.
    for x in (-2.4, 0.0):
        prop("table_long", x, 2.6, 0.0, math.pi / 2, collide=(2.4, 1.3, 1.0))
    prop("keg", -5.6, 4.0, rot=0.3, collide=(1.1, 1.1, 1.2))
    prop("barrel_large", -6.2, 2.6, collide=(1.1, 1.1, 1.2))
    prop("barrel_small_stack", 2.0, 4.3)
    prop("shelf_large", -1.2, 4.95, 1.5, math.pi, 1.0)
    prop("shelf_large", 1.2, 4.95, 1.5, math.pi, 1.0)
    for i, x in enumerate((-1.9, -1.4, -0.9, 0.7, 1.2, 1.7)):
        prop(["bottle_A_brown", "bottle_B_brown", "bottle_C_brown", "bottle_A_labeled_brown"][i % 4], x, 4.72, 1.6, 0.0, 0.45)
    prop("plate_food_A", -1.6, 2.6, 0.62)
    prop("candle_lit", 0.6, 2.6, 0.62)
    POINTS.append(("npc-velmor", -1.0, 3.9, 0.0))
    POINTS.append(("fx-candle-01", 0.6, 2.6, 1.15))
    # Камин у западной стены — каменная труба Quaternius ставится в build(), здесь — дрова и стол рядом.
    prop("table_medium_tablecloth_decorated_B", -3.6, -1.6, collide=(1.3, 1.3, 1.0))
    for dx, dy, r in ((-1.0, 0, -math.pi / 2), (1.0, 0, math.pi / 2), (0, -1.0, 0)):
        prop("chair", -3.6 + dx, -1.6 + dy, rot=r)
    POINTS.append(("fx-candle-02", -3.6, -1.6, 1.2))
    prop("table_long_decorated_A", 0.6, -2.0, 0.0, 0.0, collide=(1.3, 2.5, 1.0))
    for dy in (-0.8, 0.8):
        prop("stool", -0.4, -2.0 + dy)
        prop("stool", 1.6, -2.0 + dy)
    POINTS.append(("fx-candle-03", 0.6, -2.0, 0.75))
    prop("table_small_decorated_A", -5.4, -3.6, collide=(0.9, 0.9, 0.8))
    prop("stool", -4.6, -3.6)
    prop("crates_stacked", 2.4, -4.2, rot=0.4, collide=(1.2, 1.2, 1.2))
    # Комната Рэя: кровать, сундук, свеча.
    prop("bed_decorated", 5.6, 3.6, 0.0, math.pi / 2, collide=(1.9, 1.2, 0.8))
    prop("trunk_medium_A", 6.3, 1.3, rot=math.pi / 2)
    prop("candle_lit", 4.0, 4.5, 0.0)
    POINTS.append(("spawn-start", 4.5, 2.4, 0.0))
    POINTS.append(("fx-candle-04", 4.0, 4.5, 0.65))
    # Знамя третьей роты над камином (появляется, когда Рэй его принёс).
    POINTS.append(("banner-third-company", -6.8, 0.0, 1.5))
    POINTS.append(("exit-village", -1.0, -5.6, 0.0))


def hearth(kit):
    """Камин: кирпичная труба Quaternius внизу западной стены, огонь — точка fx-fire."""
    kit["place"]("Prop_Chimney", -6.6, 0.0, 0.0, math.pi / 2)
    kit["_colliders"].append((-6.5, 0.0, 0.3, 1.2, 1.2, 3.2))
    POINTS.append(("fx-fire", -6.1, 0.0, 0.4))


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    for store in (bpy.data.meshes, bpy.data.materials):
        for item in list(store):
            if item.users == 0:
                store.remove(item)
    col = bpy.data.collections.new("Таверна")
    bpy.context.scene.collection.children.link(col)
    kit = {"__name__": "village_houses", "PROJECT": PROJECT}
    exec(open(os.path.join(PROJECT, "Tools", "blender", "village_houses.py"), encoding="utf-8").read(), kit)
    floor(col)
    walls(kit)
    hearth(kit)
    furniture()
    kit["finish"](col, "Walls", False)
    finish_props(col)
    # Знамя третьей роты над камином — отдельный объект: в игре видно, когда Рэй его принёс.
    banner = kaykit("banner_brown").copy()
    banner.transform(Matrix.Translation((-6.85, 0.0, 0.2)) @ Matrix.Rotation(-math.pi / 2, 4, "Z") @ Matrix.Scale(0.7, 4))
    banner.materials.clear()
    banner.materials.append(bpy.data.materials["kaykit_palette"])
    col.objects.link(bpy.data.objects.new("Banner", banner))
    for name, x, y, z in POINTS:
        e = bpy.data.objects.new(name, None)
        e.location = (x, y, z)
        col.objects.link(e)
    return col


def export(col):
    for ob in bpy.context.view_layer.objects:
        ob.select_set(ob.name in col.all_objects)
    with bpy.context.temp_override(**_ui()):
        bpy.ops.export_scene.gltf(filepath=GLB, use_selection=True, export_extras=True, export_yup=True,
                                  export_apply=True, export_lights=False, export_cameras=False,
                                  export_image_format="NONE")


if __name__ == "__main__":
    collection = build()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    export(collection)
    result_info = {"objects": [o.name for o in collection.objects],
                   "props_tris": sum(len(p.vertices) - 2 for p in bpy.data.objects["Props"].data.polygons)}
