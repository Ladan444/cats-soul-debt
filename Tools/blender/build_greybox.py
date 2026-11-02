"""Серые блоки этажа Рубежа в Blender по Tools/blender/rubezh_layout.py и экспорт в Godot (.glb).

Запуск из Blender (MCP или Text Editor):
    ns = {"__name__": "__main__", "FLOOR_ID": "F1"}
    exec(open(r"<проект>/Tools/blender/build_greybox.py", encoding="utf-8").read(), ns)

Как строится:
- Пол раскладывается на сетку 0,5 м (комнаты и коридоры из связей). Стены встают на границах «пол — пустота».
- Высота стен: залы 5 м, высокие залы 7 м, коридоры 3,5 м, мост — парапет 1 м. Южные стены (к камере) — 0,8 м:
  срез диорамы, чтобы камера видела Рэя.
- Связь между комнатами разной высоты — пандус (наклонный пол, стены по нему).
- Двери, печати, ложные стены и ворота — отдельные объекты Door-<вид>-<из>-<в>, у ключевых — подпись.
- Точки для Godot — пустышки spawn-<вид>-<номер> (фонари, враги, сундуки, ключи...) с подписью в свойстве label.
- Меши с суффиксом -col: Godot сам добавит им коллизию. Материалы — серые, текстуры лягут позже (трипланар в Godot).
Результат: коллекция «Серые блоки <этаж>» и Game/CatsSoulDebt/assets/levels/rubezh_<этаж>.glb.
"""
import math
import os

import bmesh
import bpy

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
LEVELS_DIR = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "levels")
CELL = 0.5
CORRIDOR_W = 3.0
WALL_T = 0.5
H_ROOM, H_TALL, H_CORRIDOR, H_PARAPET, H_SOUTH = 5.0, 7.0, 3.5, 1.0, 0.8
FLOOR_T = 0.5

lib = {"__name__": "lib"}
exec(open(os.path.join(PROJECT, "Tools", "blender", "build_schema.py"), encoding="utf-8").read(), lib)
layout = {}
exec(open(os.path.join(PROJECT, "Tools", "blender", "rubezh_layout.py"), encoding="utf-8").read(), layout)
route, bounds, door_point = lib["route"], lib["bounds"], lib["door_point"]


def material(name, rgb, rough=0.9):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = rough
    return m


MATS = {
    "floor": ("Серый: пол", (0.30, 0.32, 0.36)),
    "corridor": ("Серый: пол коридора", (0.24, 0.26, 0.30)),
    "wall": ("Серый: стена", (0.18, 0.20, 0.24)),
    "chasm": ("Серый: пропасть", (0.03, 0.04, 0.06)),
    "open": ("Серый: проём", (0.4, 0.4, 0.4)),
    "key": ("Дверь: ключ", (0.75, 0.40, 0.08)),
    "bigkey": ("Дверь: особый ключ", (0.75, 0.15, 0.05)),
    "oneway": ("Дверь: в одну сторону", (0.10, 0.55, 0.70)),
    "soul": ("Дверь: печать души", (0.40, 0.15, 0.75)),
    "secret": ("Дверь: ложная стена", (0.20, 0.22, 0.26)),
    "story": ("Дверь: сюжет", (0.70, 0.60, 0.15)),
}


def mat(key):
    name, rgb = MATS[key]
    return material(name, rgb)


def add_box(bm, x0, x1, y0, y1, z0, z1):
    verts = [bm.verts.new(v) for v in (
        (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
        (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([verts[i] for i in f])


def add_ramp(bm, x0, x1, y0, y1, za, zb, along_y):
    """Наклонная плита: высота меняется от za к zb вдоль Y (along_y) или X."""
    def top(x, y):
        t = (y - y0) / (y1 - y0) if along_y else (x - x0) / (x1 - x0)
        return za + (zb - za) * t
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    low = [bm.verts.new((x, y, min(za, zb) - FLOOR_T)) for x, y in corners]
    high = [bm.verts.new((x, y, top(x, y))) for x, y in corners]
    bm.faces.new(low[::-1])
    bm.faces.new(high)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([low[i], low[j], high[j], high[i]])


def mesh_object(col, name, bm, m):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


class Grid:
    """Клетки пола 0,5 м: высота пола, высота стен, область (для склейки стен)."""

    def __init__(self):
        self.cells = {}

    @staticmethod
    def idx(v):
        return int(math.floor(v / CELL + 1e-6))

    def fill(self, x0, x1, y0, y1, z_of, height, region, overwrite=False):
        for ix in range(self.idx(x0), self.idx(x1 - 1e-6) + 1):
            for iy in range(self.idx(y0), self.idx(y1 - 1e-6) + 1):
                if (ix, iy) in self.cells and not overwrite:
                    continue
                cx, cy = (ix + 0.5) * CELL, (iy + 0.5) * CELL
                self.cells[(ix, iy)] = (z_of(cx, cy), height, region)


def room_height(tags):
    if "bridge" in tags:
        return H_PARAPET
    if "tall" in tags:
        return H_TALL
    if "corridor" in tags:
        return H_CORRIDOR
    return H_ROOM


def build(floor_id):
    floor = next(f for f in layout["FLOORS"] if f["id"] == floor_id)
    base_z = 0.0  # этаж строится у нуля; в Godot этажи — отдельные сцены
    rooms = {r[0]: r for r in floor["rooms"]}

    name = "Серые блоки " + floor_id
    old = bpy.data.collections.get(name)
    if old:
        for ob in list(old.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.collections.remove(old)
    # Меши прошлой сборки остались без владельцев — убрать, иначе новые получат имена «.001».
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)
    col = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(col)

    grid = Grid()
    floors_bm, corridor_bm = bmesh.new(), bmesh.new()
    # Комнаты.
    for rid, _, x, y, w, h, z, tags in floor["rooms"]:
        x0, x1, y0, y1 = bounds(rooms[rid])
        grid.fill(x0, x1, y0, y1, lambda cx, cy, z=z: base_z + z, room_height(tags), rid, overwrite=True)
        add_box(corridor_bm if "corridor" in tags else floors_bm, x0, x1, y0, y1, base_z + z - FLOOR_T, base_z + z)
    # Коридоры связей.
    for a, b, kind, label in floor["links"]:
        ra, rb = rooms[a], rooms[b]
        path = route(ra, rb)
        za, zb = ra[6], rb[6]
        region = "link:%s-%s" % (a, b)
        for (px, py), (qx, qy) in zip(path, path[1:]):
            x0, x1 = min(px, qx) - CORRIDOR_W / 2, max(px, qx) + CORRIDOR_W / 2
            y0, y1 = min(py, qy) - CORRIDOR_W / 2, max(py, qy) + CORRIDOR_W / 2
            if abs(za - zb) > 0.01 and len(path) == 2:
                along_y = abs(qx - px) < 0.01
                length = (qy - py) if along_y else (qx - px)

                def z_of(cx, cy, px=px, py=py, length=length, along_y=along_y):
                    t = ((cy - py) if along_y else (cx - px)) / length if length else 0.0
                    return base_z + za + (zb - za) * max(0.0, min(1.0, t))
                # Пандус — внутри коридора между краями комнат.
                ramp_a = (py if along_y else px)
                ramp_b = (qy if along_y else qx)
                if along_y:
                    add_ramp(corridor_bm, x0, x1, min(ramp_a, ramp_b), max(ramp_a, ramp_b),
                             base_z + (za if ramp_a < ramp_b else zb), base_z + (zb if ramp_a < ramp_b else za), True)
                else:
                    add_ramp(corridor_bm, min(ramp_a, ramp_b), max(ramp_a, ramp_b), y0, y1,
                             base_z + (za if ramp_a < ramp_b else zb), base_z + (zb if ramp_a < ramp_b else za), False)
            else:
                def z_of(cx, cy, z=za):
                    return base_z + z
                add_box(corridor_bm, x0, x1, y0, y1, base_z + za - FLOOR_T, base_z + za)
            grid.fill(x0, x1, y0, y1, z_of, H_CORRIDOR, region)
    mesh_object(col, "Floor-col", floors_bm, mat("floor"))
    mesh_object(col, "CorridorFloor-col", corridor_bm, mat("corridor"))

    # Стены по границам пола: склеиваем в полосы одной высоты.
    walls_bm = bmesh.new()
    cells = grid.cells
    runs = {}
    for (ix, iy), (z, h, region) in cells.items():
        for dx, dy, side in ((0, 1, "N"), (0, -1, "S"), (1, 0, "E"), (-1, 0, "W")):
            if (ix + dx, iy + dy) in cells:
                continue
            height = H_SOUTH if side == "S" and h > H_PARAPET else h
            key = (side, iy if side in "NS" else ix, height)
            runs.setdefault(key, []).append((ix if side in "NS" else iy, z))
    for (side, line, height), items in runs.items():
        items.sort()
        start = prev = items[0][0]
        zs = [items[0][1]]
        for pos, z in items[1:] + [(None, None)]:
            if pos is not None and pos == prev + 1:
                prev = pos
                zs.append(z)
                continue
            lo, hi = start * CELL, (prev + 1) * CELL
            z0, z1 = min(zs) - FLOOR_T, max(zs) + height
            if side == "N":
                y = (line + 1) * CELL
                add_box(walls_bm, lo, hi, y, y + WALL_T, z0, z1)
            elif side == "S":
                y = line * CELL
                add_box(walls_bm, lo, hi, y - WALL_T, y, z0, z1)
            elif side == "E":
                x = (line + 1) * CELL
                add_box(walls_bm, x, x + WALL_T, lo, hi, z0, z1)
            else:
                x = line * CELL
                add_box(walls_bm, x - WALL_T, x, lo, hi, z0, z1)
            if pos is not None:
                start = prev = pos
                zs = [z]
    mesh_object(col, "Walls-col", walls_bm, mat("wall"))

    # Пропасти: дно и скальные стенки до уровня пола.
    for i, (x, y, w, h, bottom) in enumerate(layout["CHASMS"].get(floor_id, [])):
        bm = bmesh.new()
        x0, x1, y0, y1 = x - w / 2, x + w / 2, y - h / 2, y + h / 2
        add_box(bm, x0, x1, y0, y1, base_z + bottom - 1, base_z + bottom)
        for a0, a1, b0, b1 in ((x0 - 1, x0, y0, y1), (x1, x1 + 1, y0, y1), (x0, x1, y0 - 1, y0), (x0, x1, y1, y1 + 1)):
            add_box(bm, a0, a1, b0, b1, base_z + bottom, base_z - FLOOR_T)
        mesh_object(col, "Chasm%d-col" % i, bm, mat("chasm"))

    # Двери и печати — в проёмах связей.
    for a, b, kind, label in floor["links"]:
        if kind in ("open", "stairs"):
            continue
        path = route(rooms[a], rooms[b])
        dx, dy = door_point(path, rooms[b])
        (px, py), (qx, qy) = path[-2], path[-1]
        vertical = abs(px - qx) < 0.01
        z = base_z + rooms[b][6]
        bm = bmesh.new()
        thick = 0.6 if kind == "secret" else 0.3
        hgt = H_CORRIDOR if kind != "story" else H_ROOM
        if vertical:
            add_box(bm, dx - CORRIDOR_W / 2, dx + CORRIDOR_W / 2, dy - thick / 2, dy + thick / 2, z, z + hgt)
        else:
            add_box(bm, dx - thick / 2, dx + thick / 2, dy - CORRIDOR_W / 2, dy + CORRIDOR_W / 2, z, z + hgt)
        ob = mesh_object(col, "Door-%s-%s-%s-col" % (kind, a, b), bm, mat(kind))
        ob["kind"] = kind
        ob["label"] = label.replace("\n", " ")
        ob["from"], ob["to"] = a, b

    # Центры комнат для Godot (свет, названия): room-<id> со свойствами размеров и тегов.
    for rid, title, x, y, w, h, z, tags in floor["rooms"]:
        e = bpy.data.objects.new("room-%s" % rid, None)
        e.empty_display_type = "CUBE"
        e.empty_display_size = 0.5
        e.location = (x, y, base_z + z)
        e["w"], e["h"], e["z"] = float(w), float(h), float(z)
        e["tags"] = ",".join(tags)
        e["title"] = title.replace("\n", " ").replace("- ", "")
        col.objects.link(e)

    # Точки появления для Godot.
    counters = {}
    for kind, x, y, label in floor["marks"]:
        z = base_z
        for rid, _, rx, ry, w, h, rz, tags in floor["rooms"]:
            if abs(x - rx) <= w / 2 and abs(y - ry) <= h / 2:
                z = base_z + rz
                break
        counters[kind] = counters.get(kind, 0) + 1
        e = bpy.data.objects.new("spawn-%s-%02d" % (kind, counters[kind]), None)
        e.empty_display_type = "SINGLE_ARROW" if kind != "lantern" else "SPHERE"
        e.empty_display_size = 0.8
        e.location = (x, y, z)
        e["kind"] = kind
        e["label"] = label.replace("\n", " ")
        col.objects.link(e)
    return col


def preview_setup(col):
    """Свет и камера «как в игре» (FOV 30, смещение 9 вверх и 11 к югу) — для превью-рендеров."""
    scene = bpy.context.scene
    sun = bpy.data.objects.get("Превью: солнце")
    if sun is None:
        sun = bpy.data.objects.new("Превью: солнце", bpy.data.lights.new("Превью: солнце", "SUN"))
        scene.collection.objects.link(sun)
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(20))
    world = scene.world
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.05, 0.06, 0.08, 1)
    bg.inputs[1].default_value = 1.0
    cam = bpy.data.objects.get("Превью: камера")
    if cam is None:
        cam = bpy.data.objects.new("Превью: камера", bpy.data.cameras.new("Превью: камера"))
        scene.collection.objects.link(cam)
    cam.data.lens_unit = "FOV"
    cam.data.angle = math.radians(30)
    cam.data.clip_end = 500
    return cam


def look_from(cam, target, offset=(0, -11, 9)):
    cam.location = (target[0] + offset[0], target[1] + offset[1], target[2] + offset[2])
    direction = (target[0] - cam.location.x, target[1] - cam.location.y, target[2] - cam.location.z)
    from mathutils import Vector
    cam.rotation_euler = Vector(direction).to_track_quat("-Z", "Y").to_euler()


def export(col, floor_id):
    os.makedirs(LEVELS_DIR, exist_ok=True)
    for ob in bpy.context.view_layer.objects:
        ob.select_set(False)
    for ob in col.objects:
        ob.select_set(True)
    path = os.path.join(LEVELS_DIR, "rubezh_%s.glb" % floor_id.lower())
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_extras=True, export_yup=True,
                              export_apply=True, export_lights=False, export_cameras=False)
    return path


if __name__ == "__main__":
    FID = globals().get("FLOOR_ID", "F1")
    collection = build(FID)
    for c in bpy.context.scene.collection.children:
        if c.name.startswith("Схема"):
            c.hide_viewport = True
            c.hide_render = True
    preview_setup(collection)
    exported = export(collection, FID)
    result_info = {"collection": collection.name, "objects": len(collection.objects), "glb": exported}
