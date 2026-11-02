"""Три варианта моста для Ивового Брода — на выбор автора (до переноса в игру).

Запуск из Blender (MCP), открывает НОВЫЙ файл и сохраняет Арт/Blender/bridges.blend:
    exec(open(r"<проект>/Tools/blender/bridge_variants.py", encoding="utf-8").read(), {"__name__": "__main__"})
Материалы — процедурные узлы Blender (Brick Texture, Voronoi, Noise), без внешних картинок.
Каждый мост — на своём куске берега с рекой (река вдоль y, мост вдоль x, ширина воды как в деревне).
Кадры — Арт/Blender/bridge_<вариант>_game.png (угол игровой камеры) и _side.png.
  A — горбатый каменный: одна арка из клиновидных камней, парапеты с карнизом, столбы на въездах.
  B — деревянный на сваях: сваи с подкосами, настил из досок, перила из жердей.
  C — трёхарочный каменный: быки с волнорезами, почти ровный настил, деревянные перила со столбиками.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
OUT = os.path.join(PROJECT, "Арт", "Blender")
WATER = 0.0          # гладь реки
BANK = 1.0           # берег над водой
RIVER_HALF = 4.6     # полуширина воды (как в деревне)
rng = random.Random(5)


def lin(c):
    return tuple(v ** 2.2 for v in c)


# --- Материалы ------------------------------------------------------------------------

def _nodes(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Roughness"].default_value = 0.9
    return m, nt, bsdf


def _triplanar_vectors(nt, scale):
    """Три проекции координат объекта (вид спереди, сбоку, сверху) и веса по нормали."""
    tc = nt.nodes.new("ShaderNodeTexCoord")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    sn = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Normal"], sn.inputs[0])

    def combine(a, b):
        c = nt.nodes.new("ShaderNodeCombineXYZ")
        nt.links.new(sep.outputs[a], c.inputs[0])
        nt.links.new(sep.outputs[b], c.inputs[1])
        mp = nt.nodes.new("ShaderNodeVectorMath")
        mp.operation = "SCALE"
        nt.links.new(c.outputs[0], mp.inputs[0])
        mp.inputs["Scale"].default_value = scale
        return mp.outputs[0]

    def absn(i):
        a = nt.nodes.new("ShaderNodeMath")
        a.operation = "ABSOLUTE"
        nt.links.new(sn.outputs[i], a.inputs[0])
        return a.outputs[0]

    ax, ay, az = absn(0), absn(1), absn(2)
    top = nt.nodes.new("ShaderNodeMath")
    top.operation = "GREATER_THAN"
    nt.links.new(az, top.inputs[0])
    top.inputs[1].default_value = 0.6
    side_x = nt.nodes.new("ShaderNodeMath")
    side_x.operation = "GREATER_THAN"
    nt.links.new(ax, side_x.inputs[0])
    nt.links.new(ay, side_x.inputs[1])
    return (combine("X", "Z"), combine("Y", "Z"), combine("X", "Y")), side_x.outputs[0], top.outputs[0], sn.outputs[2]


def _mix(nt, fac, a, b):
    m = nt.nodes.new("ShaderNodeMix")
    m.data_type = "RGBA"
    nt.links.new(fac, m.inputs["Factor"])
    nt.links.new(a, m.inputs[6])
    nt.links.new(b, m.inputs[7])
    return m.outputs[2]


def _moss(nt, color, nz, amount):
    """Мох пятнами по шуму, гуще сверху."""
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.55
    ramp.color_ramp.elements[1].position = 0.62
    nt.links.new(noise.outputs["Fac"], ramp.inputs[0])
    up = nt.nodes.new("ShaderNodeMath")
    up.operation = "MULTIPLY_ADD"
    nt.links.new(nz, up.inputs[0])
    up.inputs[1].default_value = 0.5
    up.inputs[2].default_value = 0.5
    mask = nt.nodes.new("ShaderNodeMath")
    mask.operation = "MULTIPLY"
    nt.links.new(ramp.outputs["Color"], mask.inputs[0])
    nt.links.new(up.outputs[0], mask.inputs[1])
    k = nt.nodes.new("ShaderNodeMath")
    k.operation = "MULTIPLY"
    nt.links.new(mask.outputs[0], k.inputs[0])
    k.inputs[1].default_value = amount
    moss = nt.nodes.new("ShaderNodeRGB")
    moss.outputs[0].default_value = (*lin((0.33, 0.45, 0.17)), 1)
    return _mix(nt, k.outputs[0], color, moss.outputs[0])


def mat_brick(name, a, b, mortar, brick_w=0.55, brick_h=0.28, moss=0.8):
    """Кладка: Brick Texture в трёх проекциях, неровность цвета, рельеф швов, мох."""
    m, nt, bsdf = _nodes(name)
    (v_front, v_side, v_top), side_x, top, nz = _triplanar_vectors(nt, 1.0)
    outs = []
    for v in (v_front, v_side, v_top):
        br = nt.nodes.new("ShaderNodeTexBrick")
        br.inputs["Color1"].default_value = (*lin(a), 1)
        br.inputs["Color2"].default_value = (*lin(b), 1)
        br.inputs["Mortar"].default_value = (*lin(mortar), 1)
        br.inputs["Scale"].default_value = 1.0
        br.inputs["Mortar Size"].default_value = 0.025
        br.inputs["Brick Width"].default_value = brick_w
        br.inputs["Row Height"].default_value = brick_h
        br.offset = 0.5
        nt.links.new(v, br.inputs["Vector"])
        outs.append(br)
    col = _mix(nt, side_x, outs[0].outputs["Color"], outs[1].outputs["Color"])
    col = _mix(nt, top, col, outs[2].outputs["Color"])
    fac = _mix(nt, side_x, outs[0].outputs["Fac"], outs[1].outputs["Fac"])
    fac = _mix(nt, top, fac, outs[2].outputs["Fac"])
    # Неровность камня.
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9.0
    var = nt.nodes.new("ShaderNodeMix")
    var.data_type = "RGBA"
    var.blend_type = "MULTIPLY"
    var.inputs["Factor"].default_value = 0.35
    nt.links.new(col, var.inputs[6])
    nt.links.new(noise.outputs["Color"], var.inputs[7])
    col = var.outputs[2]
    if moss:
        col = _moss(nt, col, nz, moss)
    nt.links.new(col, bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.45
    bump.invert = True
    nt.links.new(fac, bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def mat_ashlar(name, a, b, moss=0.25):
    """Тёсаный камень без рисунка кладки — форму блока дают сама геометрия и фаски (кольцо арки, карнизы)."""
    m, nt, bsdf = _nodes(name)
    (v_front, v_side, v_top), side_x, top, nz = _triplanar_vectors(nt, 1.0)
    info = nt.nodes.new("ShaderNodeObjectInfo")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6.0
    noise.inputs["Detail"].default_value = 6.0
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*lin(a), 1)
    ramp.color_ramp.elements[1].color = (*lin(b), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs[0])
    shade = nt.nodes.new("ShaderNodeMapRange")
    shade.inputs["To Min"].default_value = 0.85
    shade.inputs["To Max"].default_value = 1.08
    nt.links.new(info.outputs["Random"], shade.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "SCALE"
    nt.links.new(ramp.outputs["Color"], mul.inputs[0])
    nt.links.new(shade.outputs["Result"], mul.inputs["Scale"])
    col = _moss(nt, mul.outputs[0], nz, moss) if moss else mul.outputs[0]
    nt.links.new(col, bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.25
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def mat_cobble(name):
    """Брусчатка настила: Voronoi (расстояние до края) — круглые камни со швами, мох в швах."""
    m, nt, bsdf = _nodes(name)
    (v_front, v_side, v_top), side_x, top, nz = _triplanar_vectors(nt, 1.0)
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 4.5
    nt.links.new(v_top, vor.inputs["Vector"])
    cells = nt.nodes.new("ShaderNodeTexVoronoi")
    cells.inputs["Scale"].default_value = 4.5
    nt.links.new(v_top, cells.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.03
    ramp.color_ramp.elements[0].color = (*lin((0.42, 0.40, 0.32)), 1)
    ramp.color_ramp.elements[1].position = 0.09
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    nt.links.new(vor.outputs["Distance"], ramp.inputs[0])
    tone = nt.nodes.new("ShaderNodeValToRGB")
    tone.color_ramp.elements[0].color = (*lin((0.46, 0.43, 0.38)), 1)
    tone.color_ramp.elements[1].color = (*lin((0.66, 0.62, 0.54)), 1)
    nt.links.new(cells.outputs["Color"], tone.inputs[0])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(tone.outputs["Color"], mul.inputs[6])
    nt.links.new(ramp.outputs["Color"], mul.inputs[7])
    col = _moss(nt, mul.outputs[2], nz, 0.35)
    nt.links.new(col, bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.6
    nt.links.new(vor.outputs["Distance"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def mat_wood(name, a, b):
    """Дерево: волокна (шум, растянутый вдоль доски) и разный тон у каждой доски (Object Info → Random)."""
    m, nt, bsdf = _nodes(name)
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (14.0, 1.2, 14.0)
    nt.links.new(tc.outputs["Object"], mp.inputs[0])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.5
    noise.inputs["Detail"].default_value = 8.0
    nt.links.new(mp.outputs[0], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*lin(a), 1)
    ramp.color_ramp.elements[1].color = (*lin(b), 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs[0])
    info = nt.nodes.new("ShaderNodeObjectInfo")
    shade = nt.nodes.new("ShaderNodeMapRange")
    shade.inputs["To Min"].default_value = 0.72
    shade.inputs["To Max"].default_value = 1.1
    nt.links.new(info.outputs["Random"], shade.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeVectorMath")
    mul.operation = "SCALE"
    nt.links.new(ramp.outputs["Color"], mul.inputs[0])
    nt.links.new(shade.outputs["Result"], mul.inputs["Scale"])
    nt.links.new(mul.outputs[0], bsdf.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.3
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def mat_flat(name, rgb, rough=0.9, alpha=1.0):
    m, nt, bsdf = _nodes(name)
    bsdf.inputs["Base Color"].default_value = (*lin(rgb), 1)
    bsdf.inputs["Roughness"].default_value = rough
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
    return m


# --- Геометрия ------------------------------------------------------------------------
# Развёртка — в метрах (в игре делится на размер плитки текстуры, 40 пикселей на метр):
# по умолчанию плоская по оси нормали (фасад — x/z, торцы — y/z, верх — x/y, ряды кладки горизонтальны);
# свод арки — вдоль дуги, брёвна и жерди — вдоль длины (волокна вдоль бруса). Такие грани помечены «uvdone».

def _uv(bm):
    return bm.loops.layers.uv.verify()


def _uv_done(bm):
    return bm.faces.layers.int.get("uvdone") or bm.faces.layers.int.new("uvdone")


def planar_uv(bm):
    """Плоская развёртка по ближайшей оси нормали — для всех граней, у которых своей ещё нет."""
    uv, done = _uv(bm), _uv_done(bm)
    for f in bm.faces:
        if f[done]:
            continue
        f.normal_update()
        n = f.normal
        for loop in f.loops:
            p = loop.vert.co
            if abs(n.z) >= max(abs(n.x), abs(n.y)):
                loop[uv].uv = (p.x, p.y)
            elif abs(n.x) > abs(n.y):
                loop[uv].uv = (p.y, p.z)
            else:
                loop[uv].uv = (p.x, p.z)


def add_box(bm, c, s, rz=0.0):
    g = bmesh.ops.create_cube(bm, size=1.0)
    vs = g["verts"]
    bmesh.ops.scale(bm, vec=s, verts=vs)
    if rz:
        bmesh.ops.rotate(bm, verts=vs, cent=(0, 0, 0), matrix=Matrix.Rotation(rz, 3, "Z"))
    bmesh.ops.translate(bm, vec=c, verts=vs)


def add_cyl(bm, p0, p1, r, segs=8):
    a, b = Vector(p0), Vector(p1)
    d = b - a
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=d.length)
    # Развёртка до поворота: u — по окружности, v — вдоль бревна (метры).
    uv, done = _uv(bm), _uv_done(bm)
    faces = {f for v in g["verts"] for f in v.link_faces}
    circ = 2 * math.pi * r
    for f in faces:
        f[done] = 1
        us = []
        for loop in f.loops:
            p = loop.vert.co
            us.append(((math.atan2(p.y, p.x) / (2 * math.pi)) % 1.0) * circ)
        # Шов окружности: грань не должна растягиваться через всю развёртку.
        if max(us) - min(us) > circ / 2:
            us = [u + circ if u < circ / 2 else u for u in us]
        for loop, u in zip(f.loops, us):
            loop[uv].uv = (u, loop.vert.co.z)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix()
    bmesh.ops.rotate(bm, verts=g["verts"], cent=(0, 0, 0), matrix=rot)
    bmesh.ops.translate(bm, vec=(a + b) / 2, verts=g["verts"])


def add_wedge(bm, cx, cz, r0, r1, a0, a1, y0, y1):
    """Клиновидный камень арки между радиусами r0..r1 и углами a0..a1."""
    pts = [(r0, a0), (r1, a0), (r1, a1), (r0, a1)]
    front = [bm.verts.new((cx + r * math.cos(t), y0, cz + r * math.sin(t))) for r, t in pts]
    back = [bm.verts.new((cx + r * math.cos(t), y1, cz + r * math.sin(t))) for r, t in pts]
    bm.faces.new(front)
    bm.faces.new(back[::-1])
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([front[j], front[i], back[i], back[j]])


def add_profile(bm, xs, top, bot, y0, y1, top_mat=1):
    """Тело, вытянутое по y: сверху top(x), снизу bot(x). Верхние грани — материал top_mat."""
    cols = []
    arc = [0.0]      # длина нижней кривой — развёртка свода вдоль дуги
    for i, x in enumerate(xs):
        t, b = top(x), bot(x)
        if i:
            arc.append(arc[-1] + math.hypot(x - xs[i - 1], b - bot(xs[i - 1])))
        cols.append([bm.verts.new((x, y0, b)), bm.verts.new((x, y1, b)), bm.verts.new((x, y1, t)),
                     bm.verts.new((x, y0, t))])
    uv, done = _uv(bm), _uv_done(bm)
    for k, (c0, c1) in enumerate(zip(cols, cols[1:])):
        bm.faces.new([c0[0], c1[0], c1[3], c0[3]])            # перед (−y)
        bm.faces.new([c0[1], c0[2], c1[2], c1[1]])            # зад (+y)
        f = bm.faces.new([c0[3], c1[3], c1[2], c0[2]])        # верх
        f.material_index = top_mat
        f = bm.faces.new([c0[0], c0[1], c1[1], c1[0]])        # низ (свод)
        f[done] = 1
        for loop in f.loops:
            s = arc[k] if loop.vert in (c0[0], c0[1]) else arc[k + 1]
            loop[uv].uv = (s, loop.vert.co.y)
    bm.faces.new(cols[0][::-1])
    bm.faces.new(cols[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def make_obj(name, bm, mats, coll, bevel=0.0, smooth=False):
    me = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    planar_uv(bm)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    for p in me.polygons:
        p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    if bevel:
        mod = ob.modifiers.new("Фаска", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        mod.harden_normals = False
    return ob


def site(coll, ox, mats, half_len=11.0):
    """Кусок местности: два берега с травой, откос, дно и вода."""
    for side in (-1, 1):
        bm = bmesh.new()
        x0 = ox + side * (RIVER_HALF + 0.6)
        x1 = ox + side * (RIVER_HALF + 16)
        cx = (x0 + x1) / 2
        add_box(bm, (cx, 0, BANK / 2 - 1.0), (abs(x1 - x0), 26, BANK + 2.0))
        make_obj("Берег", bm, [mats["bank"]], coll, 0.15)
        # Откос к воде — клин от кромки берега до дна.
        bm = bmesh.new()
        top_x, low_x = ox + side * (RIVER_HALF + 0.6), ox + side * (RIVER_HALF - 0.8)
        prof = [(top_x, BANK), (low_x, -1.4), (top_x, -1.4)]
        a = [bm.verts.new((x, -13, z)) for x, z in prof]
        b = [bm.verts.new((x, 13, z)) for x, z in prof]
        bm.faces.new(a)
        bm.faces.new(b[::-1])
        for i in range(3):
            j = (i + 1) % 3
            bm.faces.new([a[i], a[j], b[j], b[i]])
        make_obj("Откос", bm, [mats["dirt"]], coll)
    bm = bmesh.new()
    add_box(bm, (ox, 0, -1.6), (RIVER_HALF * 2 + 2, 26, 0.4))
    make_obj("Дно", bm, [mats["dirt"]], coll)
    bm = bmesh.new()
    add_box(bm, (ox, 0, WATER - 0.02), (RIVER_HALF * 2 + 1.6, 26, 0.04))
    make_obj("Вода", bm, [mats["water"]], coll)


# --- Мост A: горбатый каменный ----------------------------------------------------------

def bridge_a(coll, ox, mats):
    half, w = 9.5, 3.4
    top_z = WATER + 4.0
    g = BANK

    def deck(x):
        t = min(abs(x - ox) / half, 1.0)
        return g + (top_z - g) * 0.5 * (1 + math.cos(math.pi * t))

    c, s = 4.7, 2.9                      # полупролёт и стрела арки
    R = (c * c + s * s) / (2 * s)
    zc = WATER + 0.2 + s - R

    def arch(x):
        dx = x - ox
        return zc + math.sqrt(R * R - dx * dx) if abs(dx) < c else WATER - 1.5

    xs = [ox - half + i * 0.1 for i in range(int(2 * half / 0.1) + 1)]
    bm = bmesh.new()
    add_profile(bm, xs, lambda x: deck(x), arch, -w / 2, w / 2)
    make_obj("A: тело", bm, [mats["stone"], mats["cobble"]], coll)
    # Клиновидные камни арки и замок.
    a_start = math.atan2(WATER + 0.2 - zc, -c)
    a_end = math.atan2(WATER + 0.2 - zc, c)
    if a_start < 0:
        a_start += 2 * math.pi
    n = 19
    for i in range(n):
        a0 = a_start + (a_end - a_start) * i / n + 0.022
        a1 = a_start + (a_end - a_start) * (i + 1) / n - 0.022
        key = i == n // 2
        outer = 0.85 if key else (0.66 if i % 2 else 0.54)
        bm = bmesh.new()
        add_wedge(bm, ox, zc, R - 0.02, R + outer, a0, a1, -w / 2 - 0.06, w / 2 + 0.06)
        make_obj("A: камень арки", bm, [mats["arch"]], coll, 0.04)
    # Парапеты с карнизом.
    for side in (-1, 1):
        # Наружная грань парапета чуть выступает за стену тела — иначе грани совпадают и рябят.
        y = side * (w / 2 - 0.15)
        bm = bmesh.new()
        add_profile(bm, xs, lambda x: deck(x) + 0.75, lambda x: deck(x) - 0.05, y - 0.18, y + 0.18, 0)
        make_obj("A: парапет", bm, [mats["stone_wall"]], coll)
        bm = bmesh.new()
        add_profile(bm, xs, lambda x: deck(x) + 0.88, lambda x: deck(x) + 0.75, y - 0.25, y + 0.25, 0)
        make_obj("A: карниз", bm, [mats["arch"]], coll)
    # Столбы на въездах.
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = ox + sx * (half + 0.15), sy * (w / 2 - 0.1)
            bm = bmesh.new()
            add_box(bm, (x, y, g + 0.45), (0.6, 0.6, 1.5))
            add_box(bm, (x, y, g + 1.25), (0.75, 0.75, 0.15))
            add_box(bm, (x, y, g + 1.42), (0.42, 0.42, 0.2))
            make_obj("A: столб", bm, [mats["arch"]], coll, 0.03)


# --- Мост B: деревянный на сваях --------------------------------------------------------

def bridge_b(coll, ox, mats):
    half, w = 9.0, 3.0
    g = BANK

    def deck(x):
        t = min(abs(x - ox) / half, 1.0)
        return g + 0.35 + 0.55 * math.cos(math.pi * t / 2)

    # Сваи парами с насадкой и подкосами.
    for px in (-6.6, -2.3, 2.3, 6.6):
        x = ox + px
        top = deck(x) - 0.12
        base = WATER - 1.6 if abs(px) < RIVER_HALF else g - 0.6
        bm = bmesh.new()
        for sy in (-1, 1):
            add_cyl(bm, (x, sy * 1.3, base), (x, sy * 1.3, top + 0.02), 0.17, 10)
        make_obj("B: сваи", bm, [mats["log"]], coll, smooth=True)
        bm = bmesh.new()
        add_box(bm, (x, 0, top - 0.1), (0.3, w + 0.5, 0.24))
        make_obj("B: насадка", bm, [mats["wood"]], coll, 0.03)
        bm = bmesh.new()
        add_cyl(bm, (x, -1.3, base + 0.6), (x, 1.3, top - 0.3), 0.07, 6)
        add_cyl(bm, (x, 1.3, base + 0.6), (x, -1.3, top - 0.3), 0.07, 6)
        make_obj("B: подкосы", bm, [mats["log"]], coll, smooth=True)
    # Прогоны — три бревна вдоль моста.
    xs = [ox - half + i * 0.5 for i in range(int(2 * half / 0.5) + 1)]
    for sy in (-1.0, 0.0, 1.0):
        bm = bmesh.new()
        for x0, x1 in zip(xs, xs[1:]):
            add_cyl(bm, (x0, sy, deck(x0) - 0.17), (x1, sy, deck(x1) - 0.17), 0.12, 8)
        make_obj("B: прогон", bm, [mats["log"]], coll, smooth=True)
    # Настил — отдельные доски с зазорами, чуть вразнобой.
    x = ox - half
    while x < ox + half:
        pw = rng.uniform(0.24, 0.32)
        bm = bmesh.new()
        add_box(bm, (x + pw / 2, rng.uniform(-0.04, 0.04), deck(x + pw / 2) + rng.uniform(-0.01, 0.015)),
                (pw - 0.03, w + rng.uniform(-0.1, 0.1), 0.08), rng.uniform(-0.03, 0.03))
        make_obj("B: доска", bm, [mats["wood"]], coll, 0.012)
        x += pw
    # Перила: столбики-бревна, верхняя и средняя жердь.
    posts = [ox + v for v in (-8.7, -6.6, -4.4, -2.3, 0.0, 2.3, 4.4, 6.6, 8.7)]
    for sy in (-1, 1):
        y = sy * (w / 2 - 0.08)
        bm = bmesh.new()
        prev = None
        for px in posts:
            z = deck(px)
            add_cyl(bm, (px, y, z - 0.3), (px, y, z + 1.05), 0.08, 8)
            if prev:
                add_cyl(bm, (prev[0], y, prev[1] + 0.98), (px, y, z + 0.98), 0.06, 6)
                add_cyl(bm, (prev[0], y, prev[1] + 0.5), (px, y, z + 0.5), 0.045, 6)
            prev = (px, z)
        make_obj("B: перила", bm, [mats["log"]], coll, smooth=True)


# --- Мост C: трёхарочный ----------------------------------------------------------------

def bridge_c(coll, ox, mats):
    half, w = 10.5, 3.2
    g = BANK
    top_z = WATER + 3.0
    arches = [(ox - 5.9, 2.0, 1.9), (ox, 2.9, 2.5), (ox + 5.9, 2.0, 1.9)]   # центр, полупролёт, стрела

    def deck(x):
        dx = abs(x - ox)
        if dx < 8.0:
            return top_z + 0.25 * math.cos(math.pi * dx / 16)
        t = min((dx - 8.0) / (half - 8.0), 1.0)
        return top_z + (g - top_z) * t

    def circ(cx, c, s):
        R = (c * c + s * s) / (2 * s)
        return R, WATER + 0.25 + s - R

    def bot(x):
        for cx, c, s in arches:
            if abs(x - cx) < c:
                R, zc = circ(cx, c, s)
                return zc + math.sqrt(R * R - (x - cx) ** 2)
        return WATER - 1.5

    xs = [ox - half + i * 0.1 for i in range(int(2 * half / 0.1) + 1)]
    bm = bmesh.new()
    add_profile(bm, xs, deck, bot, -w / 2, w / 2)
    make_obj("C: тело", bm, [mats["stone"], mats["cobble"]], coll)
    # Кольца арок.
    for cx, c, s in arches:
        R, zc = circ(cx, c, s)
        a_start = math.pi - math.asin((WATER + 0.25 - zc) / R)
        a_end = math.asin((WATER + 0.25 - zc) / R)
        n = 13 if c > 2.5 else 9
        for i in range(n):
            a0 = a_start + (a_end - a_start) * i / n + 0.03
            a1 = a_start + (a_end - a_start) * (i + 1) / n - 0.03
            bm = bmesh.new()
            # Камни одной высоты: ступенчатый край в пикселях читается как пила.
            add_wedge(bm, cx, zc, R - 0.02, R + 0.48, a0, a1, -w / 2 - 0.05, w / 2 + 0.05)
            make_obj("C: камень арки", bm, [mats["arch"]], coll, 0.03)
    # Быки с волнорезами (треугольные носы вверх и вниз по течению) — посередине между арками.
    for px in (-3.4, 3.4):
        x = ox + px
        for sy in (-1, 1):
            bm = bmesh.new()
            base, topb = WATER - 1.5, WATER + 1.3
            pts = [(x - 0.5, sy * w / 2), (x + 0.5, sy * w / 2), (x, sy * (w / 2 + 1.0))]
            lo = [bm.verts.new((px_, py_, base)) for px_, py_ in pts]
            hi = [bm.verts.new((px_, py_, topb)) for px_, py_ in pts]
            bm.faces.new(lo)
            bm.faces.new(hi[::-1])
            for i in range(3):
                j = (i + 1) % 3
                bm.faces.new([lo[i], lo[j], hi[j], hi[i]])
            # Шапка волнореза — пирамидка.
            apex = bm.verts.new((x, sy * (w / 2 + 0.35), topb + 0.6))
            for i in range(3):
                j = (i + 1) % 3
                bm.faces.new([hi[i], hi[j], apex])
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            make_obj("C: волнорез", bm, [mats["stone"]], coll, 0.03)
    # Бордюр по краю настила и деревянные перила со столбиками в каменных шапках.
    for sy in (-1, 1):
        y = sy * (w / 2 - 0.12)
        bm = bmesh.new()
        add_profile(bm, xs, lambda x: deck(x) + 0.18, lambda x: deck(x) - 0.3, y - 0.14, y + 0.14, 0)
        make_obj("C: бордюр", bm, [mats.get("trim", mats["arch"])], coll)
        posts = [ox - half + 0.3 + i * (2 * half - 0.6) / 12 for i in range(13)]
        rails = bmesh.new()
        caps = bmesh.new()
        prev = None
        for px in posts:
            z = deck(px) + 0.18
            add_box(rails, (px, y, z + 0.45), (0.2, 0.2, 0.9))
            add_box(caps, (px, y, z + 0.97), (0.3, 0.3, 0.16))
            add_box(caps, (px, y, z + 1.09), (0.18, 0.18, 0.08))
            if prev:
                for hh in (0.38, 0.82):
                    add_cyl(rails, (prev[0], y, prev[1] + hh), (px, y, z + hh), 0.05, 6)
                # Крест между столбиками — как резной узор на образце, только проще.
                add_cyl(rails, (prev[0], y, prev[1] + 0.38), (px, y, z + 0.82), 0.03, 6)
                add_cyl(rails, (prev[0], y, prev[1] + 0.82), (px, y, z + 0.38), 0.03, 6)
            prev = (px, z)
        make_obj("C: перила", rails, [mats["wood"]], coll, 0.015)
        make_obj("C: шапки столбов", caps, [mats.get("trim", mats["arch"])], coll, 0.02)
    return deck


# --- Сцена и кадры ----------------------------------------------------------------------

def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    scene = bpy.context.scene
    mats = {
        "stone": mat_brick("Камень: кладка", (0.56, 0.53, 0.47), (0.47, 0.45, 0.41), (0.27, 0.25, 0.22)),
        "stone_wall": mat_brick("Камень: парапет", (0.60, 0.57, 0.50), (0.50, 0.48, 0.43), (0.28, 0.26, 0.23),
                                0.42, 0.24, 0.6),
        "arch": mat_ashlar("Камень: тёсаный (арка, карниз, столбы)", (0.60, 0.57, 0.51), (0.74, 0.71, 0.64)),
        "cobble": mat_cobble("Брусчатка настила"),
        "wood": mat_wood("Дерево: доски", (0.36, 0.22, 0.12), (0.55, 0.37, 0.21)),
        "log": mat_wood("Дерево: брёвна", (0.27, 0.18, 0.11), (0.42, 0.29, 0.18)),
        "bank": mat_flat("Трава", (0.33, 0.52, 0.20)),
        "dirt": mat_flat("Земля откоса", (0.40, 0.31, 0.21)),
        "water": mat_flat("Вода", (0.16, 0.36, 0.48), 0.05, 0.75),
    }
    mats["water"].surface_render_method = "BLENDED"
    variants = {"A": bridge_a, "B": bridge_b, "C": bridge_c}
    origins = {"A": 0.0, "B": 45.0, "C": 90.0}
    for key, fn in variants.items():
        coll = bpy.data.collections.new("Мост %s" % key)
        scene.collection.children.link(coll)
        site(coll, origins[key], mats)
        fn(coll, origins[key], mats)
    return origins


def render(origins):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "AgX"
    scene.render.resolution_x, scene.render.resolution_y = 1600, 900
    world = bpy.data.worlds.new("Небо")
    scene.world = world
    world.use_nodes = True
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.55, 0.65, 0.75, 1)
    bg.inputs[1].default_value = 0.9
    sun = bpy.data.objects.new("Солнце", bpy.data.lights.new("Солнце", "SUN"))
    sun.data.energy = 3.5
    sun.data.color = (1.0, 0.92, 0.8)
    sun.data.angle = math.radians(3)
    sun.rotation_euler = (math.radians(50), 0, math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Камера", bpy.data.cameras.new("Камера"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    shots = []
    for key, ox in origins.items():
        target = Vector((ox, 0, 1.6))
        # Как игровая камера: сверху-сбоку с юга, узкий угол.
        for tag, off, fov in (("game", (0, -21, 17), 32), ("side", (-13, -15, 6), 40)):
            cam.location = target + Vector(off)
            cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
            cam.data.angle = math.radians(fov)
            path = os.path.join(OUT, "bridge_%s_%s.png" % (key, tag))
            scene.render.filepath = path
            bpy.ops.render.render(write_still=True)
            shots.append(path)
    return shots


if __name__ == "__main__":
    origins = build()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "bridges.blend"))
    result_info = {"shots": render(origins)}
    bpy.ops.wm.save_mainfile()
