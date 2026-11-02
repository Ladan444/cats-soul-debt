"""Рисует в Blender схему Рубежа по Tools/blender/rubezh_layout.py и рендерит по картинке на этаж.

Запуск из Blender (MCP или Text Editor):
    exec(open(r"<проект>/Tools/blender/build_schema.py", encoding="utf-8").read(), {"__name__": "__main__"})
Результат: коллекции «Схема F1»… в «Схема», картинки Арт/Blender/schema_F1.png…, общий лист rubezh_schema.png
(склеивает Tools/blender/compose_schema.py).
"""
import math
import os

import bmesh
import bpy

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
OUT_DIR = os.path.join(PROJECT, "Арт", "Blender")
CORRIDOR_W = 3.0

# Какую планировку рисовать: по умолчанию Рубеж (LAYOUT_FILE, OUT_PREFIX — для других планировок).
LAYOUT_FILE = globals().get("LAYOUT_FILE", "rubezh_layout.py")
OUT_PREFIX = globals().get("OUT_PREFIX", "schema")
ns = {}
exec(open(os.path.join(PROJECT, "Tools", "blender", LAYOUT_FILE), encoding="utf-8").read(), ns)
FLOORS = ns["FLOORS"]

ROOM_COLORS = {
    "hub": (0.30, 0.36, 0.45), "deadend": (0.30, 0.26, 0.22), "locked": (0.42, 0.33, 0.10),
    "secret": (0.12, 0.28, 0.16), "story": (0.30, 0.18, 0.40), "ambush": (0.40, 0.14, 0.12),
    "trap": (0.40, 0.14, 0.12), "corridor": (0.20, 0.21, 0.24), "start": (0.25, 0.35, 0.30),
}
DEFAULT_ROOM = (0.22, 0.25, 0.31)
LINK_COLORS = {
    "key": (0.95, 0.45, 0.02), "bigkey": (0.95, 0.12, 0.02), "oneway": (0.02, 0.75, 0.95),
    "soul": (0.45, 0.10, 0.95), "secret": (0.10, 0.75, 0.25), "story": (0.95, 0.80, 0.10),
    "stairs": (0.85, 0.85, 0.85),
}
MARK_COLORS = {
    "lantern": (0.30, 0.08, 0.95), "enemy": (0.90, 0.06, 0.03), "creature": (0.65, 0.03, 0.55),
    "kvald": (0.30, 0.60, 0.15), "kobold": (0.85, 0.40, 0.10), "golem": (0.55, 0.50, 0.60),
    "boss": (1.00, 0.30, 0.00), "chest": (0.95, 0.70, 0.05), "key": (1.00, 0.95, 0.10),
    "bigkey": (1.00, 0.25, 0.05), "soul": (0.10, 0.85, 0.90), "item": (0.10, 0.70, 0.45),
    "trap": (0.95, 0.05, 0.35), "exit": (1.0, 1.0, 1.0),
}
LEGEND = [
    ("mark", "lantern", "фонарь душ"), ("mark", "enemy", "Утопший солдат"), ("mark", "creature", "Тварь Тихой Воды"),
    ("mark", "kvald", "квалд (пост)"), ("mark", "kobold", "кобольды (стая)"), ("mark", "golem", "голем-шахтёр"),
    ("mark", "boss", "командир-страж"), ("mark", "chest", "награда (сундук)"), ("mark", "soul", "душа товарища"),
    ("mark", "item", "находка / записи / улики"), ("mark", "key", "малый ключ"), ("mark", "bigkey", "особый ключ"),
    ("mark", "trap", "ловушка / засада"), ("mark", "exit", "переход между этажами"),
    ("link", "key", "дверь на ключ"), ("link", "bigkey", "большая дверь"), ("link", "oneway", "дверь в одну сторону"),
    ("link", "soul", "печать души"), ("link", "secret", "ложная стена (тайник)"), ("link", "story", "закрыто по сюжету"),
    ("room", "deadend", "тупик"), ("room", "locked", "закрытый зал"), ("room", "secret", "тайная комната"),
    ("room", "ambush", "засада / ловушка"), ("room", "hub", "узел / безопасная зона"), ("room", "story", "сюжетный зал"),
]

# Планировка может добавить свои цвета, порядок тегов и легенду (у деревни — вода, поля, жители...).
ROOM_COLORS.update(ns.get("ROOM_COLORS", {}))
MARK_COLORS.update(ns.get("MARK_COLORS", {}))
LEGEND = ns.get("LEGEND", LEGEND)
TAG_PRIORITY = ns.get("TAG_PRIORITY", ["story", "secret", "locked", "ambush", "trap", "deadend", "corridor", "hub", "start"])
ROUND_MARKS = set(ns.get("ROUND_MARKS", [])) | {"lantern", "chest", "key", "bigkey", "soul", "item"}

_materials = {}


def emission(name, rgb, strength=1.0):
    key = (name, rgb)
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new("Схема: " + name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1.0)
    em.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    _materials[key] = m
    return m


def link_to(ob, col):
    col.objects.link(ob)
    return ob


def slab(col, name, x, y, w, h, z, mat, rot=0.0):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    ob.location = (x, y, z)
    ob.scale = (w, h, 0.1)
    ob.rotation_euler[2] = rot
    return link_to(ob, col)


def disc(col, name, x, y, z, r, mat):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=16, radius=r)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    ob.location = (x, y, z)
    return link_to(ob, col)


def text(col, body, x, y, z, size, rgb=(1, 1, 1), align="CENTER"):
    curve = bpy.data.curves.new("Текст", "FONT")
    curve.body = body
    curve.size = size
    curve.align_x = align
    curve.align_y = "CENTER"
    ob = bpy.data.objects.new("Текст: " + body.replace("\n", " ")[:24], curve)
    ob.location = (x, y, z)
    curve.materials.append(emission("текст %.2f %.2f %.2f" % rgb, rgb, 1.0))
    return link_to(ob, col)


def bounds(r):
    _, _, x, y, w, h, _, _ = r
    return x - w / 2, x + w / 2, y - h / 2, y + h / 2


def clamp(v, a, b):
    return max(a, min(b, v))


def route(ra, rb):
    """Путь от комнаты a к комнате b: прямой, если комнаты перекрываются по оси, иначе Г-образный."""
    ax0, ax1, ay0, ay1 = bounds(ra)
    bx0, bx1, by0, by1 = bounds(rb)
    sx, sy = clamp(rb[2], ax0, ax1), clamp(rb[3], ay0, ay1)
    ex, ey = clamp(sx, bx0, bx1), clamp(sy, by0, by1)
    if abs(sx - ex) < 0.01 or abs(sy - ey) < 0.01:
        return [(sx, sy), (ex, ey)]
    # Г-образный: из центра a по горизонтали к x центра b, затем по вертикали в b.
    sx, sy = ra[2], ra[3]
    ex, ey = rb[2], rb[3]
    return [(sx, sy), (ex, sy), (ex, ey)]


def door_point(path, rb):
    """Где путь входит в комнату b — там дверь."""
    bx0, bx1, by0, by1 = bounds(rb)
    (px, py), (qx, qy) = path[-2], path[-1]
    if abs(px - qx) < 0.01:  # вертикальный отрезок
        y = py if by0 <= py <= by1 else (by0 if py < qy else by1)
        return qx, y
    x = px if bx0 <= px <= bx1 else (bx0 if px < qx else bx1)
    return x, qy


def build_floor(floor, parent):
    col = bpy.data.collections.new("Схема " + floor["id"])
    parent.children.link(col)
    rooms = {r[0]: r for r in floor["rooms"]}
    s = floor.get("scale", 1.0)  # крупнее подписи и значки на больших картах
    cw = floor.get("road_w", CORRIDOR_W)
    corridor_mat = emission("проход", ROOM_COLORS["corridor"])
    # Проходы — под комнатами.
    for a, b, kind, label in floor["links"]:
        path = route(rooms[a], rooms[b])
        for (x0, y0), (x1, y1) in zip(path, path[1:]):
            w = abs(x1 - x0) + cw
            h = abs(y1 - y0) + cw
            slab(col, "Проход %s-%s" % (a, b), (x0 + x1) / 2, (y0 + y1) / 2, w, h, -0.3, corridor_mat)
        if kind != "open":
            dx, dy = door_point(path, rooms[b])
            mat = emission("дверь " + kind, LINK_COLORS[kind])
            slab(col, "Дверь %s %s-%s" % (kind, a, b), dx, dy, 2.4 * s, 2.4 * s, 0.6, mat, math.radians(45))
            if kind == "oneway":
                # Стрелка «из → в»: от двери внутрь комнаты b.
                (px, py), (qx, qy) = path[-2], path[-1]
                ang = math.atan2(qy - py, qx - px)
                text(col, "➜", dx + math.cos(ang) * 2.2, dy + math.sin(ang) * 2.2, 0.8, 2.2, LINK_COLORS[kind]).rotation_euler[2] = ang
            if label:
                text(col, label, dx + 2.0 * s, dy + 2.0 * s, 0.9, 1.3 * s, LINK_COLORS[kind], "LEFT")
    # Комнаты.
    for rid, name, x, y, w, h, z, tags in floor["rooms"]:
        color = DEFAULT_ROOM
        for t in TAG_PRIORITY:
            if t in tags:
                color = ROOM_COLORS[t]
                break
        slab(col, "Комната " + rid, x, y, w, h, 0.0, emission("комната " + rid, color))
        if name:
            label = name + (("\n(%+.1f м)" % z).replace(".", ",") if z else "")
            size = (1.5 if min(w, h) >= 10 else 1.15) * s
            text(col, label, x, y + h / 2 - 1.2 * size - (0.6 * size if "\n" in name else 0), 0.5, size, (0.95, 0.95, 0.92))
    # Метки.
    for kind, x, y, label in floor["marks"]:
        mat = emission("метка " + kind, MARK_COLORS[kind])
        if kind in ("enemy", "creature", "kvald", "kobold", "golem", "boss", "trap"):
            slab(col, "Метка " + kind, x, y, 1.6 * s, 1.6 * s, 0.7, mat, math.radians(45))
        elif kind == "exit":
            slab(col, "Метка " + kind, x, y, 2.2 * s, 2.2 * s, 0.7, mat)
        else:
            disc(col, "Метка " + kind, x, y, 0.7, 1.0 * s, mat)
        if label:
            text(col, label, x + 1.5 * s, y - 1.6 * s, 0.9, 1.05 * s, MARK_COLORS[kind] if kind != "exit" else (1, 1, 1), "LEFT")
    return col


def floor_extent(floor):
    xs, ys = [], []
    for r in floor["rooms"]:
        x0, x1, y0, y1 = bounds(r)
        xs += [x0, x1]
        ys += [y0, y1]
    return min(xs), max(xs), min(ys), max(ys)


def render_floor(scene, cam, floor, col, path):
    for c in bpy.data.collections["Схема"].children:
        c.hide_render = c != col
        c.hide_viewport = c != col
    x0, x1, y0, y1 = floor_extent(floor)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    span = max(x1 - x0, y1 - y0) + 24
    s = floor.get("scale", 1.0)
    title = text(col, floor["title"], cx, cy + span / 2 - 4 * s, 1.0, 2.6 * s, (1, 0.92, 0.75))
    cam.location = (cx, cy, 80)
    cam.data.ortho_scale = span
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def build_legend(parent):
    col = bpy.data.collections.new("Схема легенда")
    parent.children.link(col)
    y = 0.0
    text(col, "Обозначения", 0, 4, 1, 2.4, (1, 0.92, 0.75), "LEFT")
    for group, key, label in LEGEND:
        if group == "mark":
            mat = emission("метка " + key, MARK_COLORS[key])
            if key in ("enemy", "creature", "kvald", "kobold", "golem", "boss", "trap"):
                slab(col, "Л", 1.5, y, 1.6, 1.6, 0.5, mat, math.radians(45))
            elif key == "exit":
                slab(col, "Л", 1.5, y, 2.2, 2.2, 0.5, mat)
            else:
                disc(col, "Л", 1.5, y, 0.5, 1.0, mat)
        elif group == "link":
            slab(col, "Л", 1.5, y, 2.0, 2.0, 0.5, emission("дверь " + key, LINK_COLORS[key]), math.radians(45))
        else:
            slab(col, "Л", 1.5, y, 3.0, 2.2, 0.5, emission("легенда " + key, ROOM_COLORS[key]))
        text(col, label, 4.0, y, 1, 1.5, (0.95, 0.95, 0.92), "LEFT")
        y -= 3.2
    return col, y


def main():
    scene = bpy.context.scene
    old = bpy.data.collections.get("Схема")
    if old:
        for c in list(old.children_recursive):
            for ob in list(c.objects):
                bpy.data.objects.remove(ob, do_unlink=True)
            bpy.data.collections.remove(c)
        for ob in list(old.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.collections.remove(old)
    for m in list(bpy.data.materials):
        if m.name.startswith("Схема") and m.users == 0:
            bpy.data.materials.remove(m)
    parent = bpy.data.collections.new("Схема")
    scene.collection.children.link(parent)

    cam = bpy.data.objects.new("Схема: камера", bpy.data.cameras.new("Схема: камера"))
    parent.objects.link(cam)
    cam.data.type = "ORTHO"
    cam.data.clip_end = 300
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 1800
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.015, 0.015, 0.02, 1)

    paths = []
    for floor in FLOORS:
        col = build_floor(floor, parent)
        path = os.path.join(OUT_DIR, "%s_%s.png" % (OUT_PREFIX, floor["id"]))
        render_floor(scene, cam, floor, col, path)
        paths.append(path)
    legend, bottom = build_legend(parent)
    for c in parent.children:
        c.hide_render = c != legend
        c.hide_viewport = c != legend
    scene.render.resolution_x = 900
    cam.location = (18, (4 + bottom) / 2, 80)
    cam.data.ortho_scale = (4 - bottom) + 10
    legend_path = os.path.join(OUT_DIR, "%s_legend.png" % OUT_PREFIX)
    scene.render.filepath = legend_path
    bpy.ops.render.render(write_still=True)
    scene.render.resolution_x = 1800
    for c in parent.children:
        c.hide_render = False
        c.hide_viewport = c.name != "Схема F1"
    return paths + [legend_path]


if __name__ == "__main__":
    result_paths = main()
