"""Примерка замка на мыс Каменного Рубежа — в своём файле Арт/Blender/castle/castle.blend, мир не меняет.

Коллекция «CastleSite»: рельеф вокруг мыса из Арт/Blender/world_heights.npy, гладь озера, мост и старая крепость —
копии объектов из Арт/Blender/world.blend (файл только читается). Запуск после build_castle.py (MODE build):
    exec(open(r"<проект>/Tools/blender/castle_site.py", encoding="utf-8").read(), {"__name__": "__main__", "MODE": "build"})
MODE: build — собрать площадку; render — рендеры Арт/Blender/castle/site_*.png.
Камера «game_*» — точно игровая (Tools/godot/build_world.gd, diorama_camera.gd): FOV 30 по вертикали, смещение от Рэя
(0, 9, 11) в осях Godot, 1280×720. «south_*» — вид из-за рукава, такой камеры в игре сейчас нет.
"""
import json
import math
import os

import bpy
import numpy as np
from mathutils import Vector

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
OUT = os.path.join(PROJECT, "Арт", "Blender", "castle")
WORLD_BLEND = os.path.join(PROJECT, "Арт", "Blender", "world.blend")
HEIGHTS = os.path.join(PROJECT, "Арт", "Blender", "world_heights.npy")
TERRAIN_META = os.path.join(PROJECT, "Арт", "Blender", "world_terrain.json")
MODE = globals().get("MODE", "build")

# Участок мира вокруг мыса, метры (x — восток, y — север).
AREA = (-640.0, 360.0, -220.0, 760.0)
OLD_FORT = ["Fortress", "FortressRoofs", "FortressHouses"]
BRIDGE_PARTS = ["Bridge_stone", "Bridge_cobble", "Bridge_arch", "Bridge_trim"]
GATE = (-427.0, 480.0)
FORT_WALLS_PX = [(245, 110), (300, 55), (420, 60), (432, 200), (400, 238), (270, 245), (245, 200)]
SHORE_PX = [(238, 98), (234, 150), (234, 205), (262, 258), (330, 258), (410, 252), (432, 205), (432, 100)]


def P(px, py):
    return px - 757.0, 722.0 - py


def own_collection():
    coll = bpy.data.collections.get("CastleSite")
    if coll:
        for ob in list(coll.objects):
            me = ob.data
            bpy.data.objects.remove(ob)
            if isinstance(me, bpy.types.Mesh) and me.users == 0:
                bpy.data.meshes.remove(me)
    else:
        coll = bpy.data.collections.new("CastleSite")
        bpy.context.scene.collection.children.link(coll)
    return coll


def flat_material(name, color, roughness=0.9):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def vertex_material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    for n in [n for n in nt.nodes if n.type == "VERTEX_COLOR"]:
        nt.nodes.remove(n)
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    return m


def build_terrain(coll):
    meta = json.load(open(TERRAIN_META, encoding="utf-8"))
    ox, oy = meta["origin"]
    step = meta["step"]
    h = np.load(HEIGHTS)
    i0, i1 = int((AREA[0] - ox) / step), int((AREA[2] - ox) / step)
    j0, j1 = int((AREA[1] - oy) / step), int((AREA[3] - oy) / step)
    sub = h[j0:j1, i0:i1]
    rows, cols = sub.shape
    verts = [(ox + (i0 + i) * step, oy + (j0 + j) * step, float(sub[j, i])) for j in range(rows) for i in range(cols)]
    faces = [(j * cols + i, j * cols + i + 1, (j + 1) * cols + i + 1, (j + 1) * cols + i)
             for j in range(rows - 1) for i in range(cols - 1)]
    me = bpy.data.meshes.new("Site_Terrain")
    me.from_pydata(verts, [], faces)
    me.update()
    gy, gx = np.gradient(sub, step)
    slope = np.hypot(gx, gy)
    # Только для примерки: приглушённые холодные тона. В игре земля — свои текстуры мира.
    grass, dirt, rock = np.array((0.055, 0.085, 0.060)), np.array((0.085, 0.085, 0.080)), np.array((0.10, 0.115, 0.13))
    near_water = np.clip((3.6 - sub) / 1.6, 0.0, 1.0)[..., None]
    steep = np.clip((slope - 0.55) / 0.5, 0.0, 1.0)[..., None]
    col = grass * (1 - near_water) + dirt * near_water
    col = col * (1 - steep) + rock * steep
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    flat = np.concatenate([col.reshape(-1, 3), np.ones((rows * cols, 1))], axis=1).ravel()
    attr.data.foreach_set("color", flat.astype(np.float32))
    me.materials.append(vertex_material("Site_Terrain"))
    ob = bpy.data.objects.new("Site_Terrain", me)
    coll.objects.link(ob)
    return {"rows": rows, "cols": cols}


def build_water(coll):
    x0, y0, x1, y1 = AREA
    z = 2.0
    me = bpy.data.meshes.new("Site_Water")
    me.from_pydata([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], [], [(0, 1, 2, 3)])
    me.update()
    me.materials.append(flat_material("Site_Water", (0.018, 0.04, 0.065), 0.25))
    ob = bpy.data.objects.new("Site_Water", me)
    coll.objects.link(ob)


def append_world(coll, names):
    """Копии объектов мира. world.blend только читается: он не открывается и не сохраняется."""
    with bpy.data.libraries.load(WORLD_BLEND, link=False) as (src, dst):
        have = set(src.objects)
        dst.objects = [n for n in names if n in have]
    out = []
    for ob in dst.objects:
        if ob is None:
            continue
        ob.name = "Site_" + ob.name
        coll.objects.link(ob)
        out.append(ob.name)
    return out


def ribbon(coll, name, pts, color, z, width=1.4, closed=True):
    """Линия-лента над землёй: контуры на виде сверху."""
    verts, faces = [], []
    seq = pts + pts[:1] if closed else pts
    for a, b in zip(seq, seq[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / L * width / 2, dx / L * width / 2
        k = len(verts)
        verts += [(a[0] - nx, a[1] - ny, z), (b[0] - nx, b[1] - ny, z), (b[0] + nx, b[1] + ny, z), (a[0] + nx, a[1] + ny, z)]
        faces.append((k, k + 1, k + 2, k + 3))
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type == "BSDF_PRINCIPLED":
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1.0)
    em.inputs["Strength"].default_value = 2.0
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    nt.links.new(em.outputs[0], out.inputs[0])
    me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob["guide"] = True
    coll.objects.link(ob)


def build():
    coll = own_collection()
    stats = build_terrain(coll)
    build_water(coll)
    stats["из мира"] = append_world(coll, OLD_FORT + BRIDGE_PARTS)
    ribbon(coll, "Site_guide_old_walls", [P(*q) for q in FORT_WALLS_PX], (0.95, 0.15, 0.1), 160.0)
    ribbon(coll, "Site_guide_shore", [P(*q) for q in SHORE_PX], (0.1, 0.5, 1.0), 160.0, closed=False)
    ribbon(coll, "Site_guide_gate", [(GATE[0] - 7, GATE[1]), (GATE[0] + 7, GATE[1]), (GATE[0], GATE[1] - 12)], (1.0, 0.9, 0.1), 160.0)
    bpy.ops.wm.save_mainfile()
    return stats


def set_visible(prefixes, visible):
    coll = bpy.data.collections["CastleSite"]
    for ob in coll.objects:
        if any(ob.name.startswith("Site_" + p) for p in prefixes):
            ob.hide_render = not visible
            ob.hide_viewport = not visible


def camera(pos, target, fov_v=30.0, ortho=None):
    scene = bpy.context.scene
    cam = bpy.data.objects.get("Camera")
    scene.camera = cam
    cam.data.clip_end = 3000.0
    cam.data.sensor_fit = "VERTICAL"
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.sensor_height = 24.0
        cam.data.lens = 24.0 / (2 * math.tan(math.radians(fov_v) / 2))
    cam.location = pos
    direction = Vector(target) - Vector(pos)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def light():
    scene = bpy.context.scene
    sun = bpy.data.objects.get("CastleSun")
    if sun is None:
        sun = bpy.data.objects.new("CastleSun", bpy.data.lights.new("CastleSun", "SUN"))
        scene.collection.objects.link(sun)
    sun.data.energy = 3.6
    sun.rotation_euler = (math.radians(55), 0, math.radians(-30))
    eevee = scene.eevee
    eevee.use_raytracing = True
    eevee.use_fast_gi = True
    eevee.fast_gi_method = "AMBIENT_OCCLUSION_ONLY"
    eevee.fast_gi_distance = 6.0
    old = bpy.data.objects.get("Light")
    if old:
        old.hide_render = True
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.62, 0.70, 0.82, 1.0)
    bg.inputs[1].default_value = 0.62


def shoot(name, res=(1280, 720)):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = False
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.filepath = os.path.join(OUT, "site_%s.png" % name)
    bpy.ops.render.render(write_still=True)


def game_camera(ray):
    """Камера игры для Рэя в точке ray (Blender): Godot (0, 9, 11) → Blender (0, −11, 9)."""
    camera((ray[0], ray[1] - 11.0, ray[2] + 9.0), ray)


def render(names=None):
    ns = {"__name__": "castle_lib", "MODE": "none"}
    exec(open(os.path.join(PROJECT, "Tools", "blender", "build_castle.py"), encoding="utf-8").read(), ns)
    ns["place"](True)
    coll = bpy.data.collections["CastleSite"]
    coll.hide_render = False
    bpy.data.collections["Castle"].hide_render = False
    light()
    centre = (-425.0, 555.0, 40.0)
    shots = names or ("top", "south_new", "south_old", "south_low", "menu", "game_bridge", "game_foot", "game_flight", "game_crossing", "game_upper")
    guides = ["guide"]
    set_visible(guides, False)
    set_visible(OLD_FORT, False)
    if "top" in shots:
        set_visible(guides, True)
        camera((-425.0, 560.0, 900.0), (-425.0, 560.0, 0.0), ortho=330.0)
        shoot("top", (1100, 1100))
        set_visible(guides, False)
    if "south_new" in shots:
        camera((-300.0, 150.0, 120.0), centre)
        shoot("south_new")
    if "south_low" in shots:
        camera((-400.0, 330.0, 16.0), (-425.0, 540.0, 48.0), fov_v=38.0)
        shoot("south_low")
    if "south_old" in shots:
        bpy.data.collections["Castle"].hide_render = True
        veg = bpy.data.collections.get("CastleVeg")
        if veg:
            veg.hide_render = True
        set_visible(OLD_FORT, True)
        camera((-300.0, 150.0, 120.0), centre)
        shoot("south_old")
        set_visible(OLD_FORT, False)
        bpy.data.collections["Castle"].hide_render = False
        if veg:
            veg.hide_render = False
    if "menu" in shots:      # ночь, как в главном меню: бледная луна сзади-справа, холодное небо
        sun = bpy.data.objects["CastleSun"]
        world = bpy.context.scene.world
        bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
        saved = (sun.data.energy, tuple(sun.data.color), tuple(sun.rotation_euler), tuple(bg.inputs[0].default_value), bg.inputs[1].default_value)
        sun.data.energy = 1.5
        sun.data.color = (0.66, 0.80, 0.88)
        sun.rotation_euler = (math.radians(66), 0, math.radians(-62))
        bg.inputs[0].default_value = (0.19, 0.28, 0.33, 1.0)
        bg.inputs[1].default_value = 0.42
        # Камера на дальнем берегу рукава: высота — от рельефа, чтобы не оказаться внутри холма.
        meta = json.load(open(TERRAIN_META, encoding="utf-8"))
        h = np.load(HEIGHTS)
        cx, cy = -560.0, 392.0
        gz = float(h[int((cy - meta["origin"][1]) / meta["step"]), int((cx - meta["origin"][0]) / meta["step"])])
        camera((cx, cy, gz + 10.0), (-432.0, 548.0, 58.0), fov_v=40.0)
        shoot("menu")
        sun.data.energy, sun.data.color, sun.rotation_euler = saved[0], saved[1], saved[2]
        bg.inputs[0].default_value, bg.inputs[1].default_value = saved[3], saved[4]
    # Кадры игровой камеры: Рэй на мосту, у подножия лестницы, на нижнем марше, между башнями, перед верхними воротами.
    S, origin = ns["S"], ns["site_origin"]()
    nodes = [(origin[0] + x * S, origin[1] + y * S, origin[2] + z * S) for x, y, z in ns["stair_points"]()]
    mx, my, nx, ny = ns["gate_landing"]()
    arch = (origin[0] + (mx + nx * 58) * S, origin[1] + (my + ny * 58) * S, origin[2] + ns["GATE"]["arch_z"] * S)
    cx, cy, cz, _, _ = ns["stair_crossing"]()
    frames = {"game_bridge": (GATE[0], GATE[1] - 30.0, 7.0), "game_foot": (nodes[-1][0], nodes[-1][1] - 2.0, nodes[-1][2]),
              "game_flight": ((nodes[-1][0] + nodes[-2][0]) / 2, (nodes[-1][1] + nodes[-2][1]) / 2, (nodes[-1][2] + nodes[-2][2]) / 2),
              "game_crossing": (origin[0] + cx * S, origin[1] + cy * S, origin[2] + cz * S), "game_upper": arch}
    for name, ray in frames.items():
        if name in shots:
            game_camera(ray)
            shoot(name)
    bpy.ops.wm.save_mainfile()
    return {"shots": list(shots)}


if __name__ == "__main__":
    if MODE == "build":
        RESULT = build()
    elif MODE == "render":
        RESULT = render(globals().get("SHOTS"))
    globals()["RESULT"] = RESULT
