"""Дополнения к паку растительности: подлесок и мелочи, которых нет в Ultimate Stylized Nature Pack.
Лёгкие низкополигональные модели на атласах 40 пикселей на метр (Tools/nature_extras_textures.py).

Запуск в Blender (открывает новый файл, мир надо пересобрать после этого):
    exec(open(r"<проект>/Tools/blender/nature_extras.py", encoding="utf-8").read(), {"__name__": "__main__"})
Результат: assets/models/nature/nature_extras.glb и pack_extras.json (высота, радиус, треугольники, коллизия).
Имена: Dt_* — мелочь (без тени и коллизии, видна недалеко), Pr_* — предмет (тень, видна дальше, у некоторых коллизия).
Расставляет их build_world.py (extras()), показывает scripts/levels/nature_scatter.gd.
"""
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
GAME = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "models", "nature")
ATLAS = json.load(open(os.path.join(GAME, "extras_atlas.json"), encoding="utf-8"))
SIZE = ATLAS["size"]
FOLIAGE, SOLID = "ExtrasFoliage", "ExtrasSolid"


def tile_uv(atlas, tile, u, v):
    """u, v 0..1 внутри плитки (v = 0 — верх картинки) → UV Blender."""
    x, y, w, h = ATLAS[atlas][tile]
    return ((x + 0.5 + u * (w - 1)) / SIZE, 1.0 - (y + 0.5 + v * (h - 1)) / SIZE)


class Model:
    """Один меш: bmesh с UV, грань — quad/tri с координатами плитки."""

    def __init__(self, name, atlas, seed=None):
        self.name, self.atlas = name, atlas
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UV0")
        self.rng = random.Random(seed if seed is not None else name)
        self.extra = {}

    def face(self, pts, tile, uvs):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        for loop, (u, v) in zip(f.loops, uvs):
            loop[self.uv].uv = tile_uv(self.atlas, tile, u, v)
        return f


def strip(m, tile, base, yaw, length, rise, droop, width, segs=4, roll=0.0):
    """Изогнутая лента-лист от base наружу: u вдоль, v поперёк. rise — высота дуги, droop — на сколько кончик ниже верха."""
    ux, uy = math.cos(yaw), math.sin(yaw)
    px, py = -uy * width / 2, ux * width / 2
    rows = []
    for k in range(segs + 1):
        t = k / segs
        r = length * t
        z = rise * math.sin(min(t * 1.2, 1.0) * math.pi / 2) - droop * t * t
        c = Vector((base[0] + ux * r, base[1] + uy * r, base[2] + z))
        s = Vector((px, py, roll * width / 2))
        rows.append((c - s, c + s, t))
    for (a0, b0, t0), (a1, b1, t1) in zip(rows, rows[1:]):
        m.face([a0, b0, b1, a1], tile, [(t0, 0), (t0, 1), (t1, 1), (t1, 0)])


def rosette(name, tile, n, length, rise, droop, width, seed=None):
    """Куст из листьев, расходящихся от центра (папоротник, широкий лист)."""
    m = Model(name, FOLIAGE, seed)
    for i in range(n):
        yaw = (i + m.rng.uniform(-0.3, 0.3)) / n * math.tau
        k = m.rng.uniform(0.75, 1.1)
        o = (m.rng.uniform(-0.05, 0.05), m.rng.uniform(-0.05, 0.05), 0.0)
        strip(m, tile, o, yaw, length * k, rise * k * m.rng.uniform(0.8, 1.15), droop * k, width, 4, m.rng.uniform(-0.25, 0.25))
    return m


def cross(name, tile, w, h, cards=3, seed=None, lean=0.06):
    """Плоскости крест-накрест (трава, цветы): основание внизу плитки."""
    m = Model(name, FOLIAGE, seed)
    for i in range(cards):
        a = i / cards * math.pi + m.rng.uniform(-0.2, 0.2)
        dx, dy = math.cos(a) * w / 2, math.sin(a) * w / 2
        tx, ty = m.rng.uniform(-lean, lean) * h, m.rng.uniform(-lean, lean) * h
        m.face([(-dx, -dy, 0), (dx, dy, 0), (dx + tx, dy + ty, h), (-dx + tx, -dy + ty, h)], tile, [(0, 1), (1, 1), (1, 0), (0, 0)])
    return m


def flat(name, tile, w, d, height=0.03, dome=0.0, atlas=SOLID, n=1):
    """Плоская заплатка на земле; dome — приподнятая середина (мох), края чуть утоплены."""
    m = Model(name, atlas)
    n = 3 if dome else n
    for j in range(n):
        for i in range(n):
            def p(a, b):
                ca, cb = a / n, b / n
                z = height + dome * math.sin(ca * math.pi) * math.sin(cb * math.pi) - (0 if dome else 0)
                return ((ca - 0.5) * w, (cb - 0.5) * d, z)
            m.face([p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)], tile,
                   [(i / n, j / n), ((i + 1) / n, j / n), ((i + 1) / n, (j + 1) / n), (i / n, (j + 1) / n)])
    return m


def lump(m, center, r, squash=0.7, tile="stone", moss_above=None, jitter=0.22, subdiv=1):
    """Камень: икосфера, вершины сдвинуты. moss_above — у граней, смотрящих вверх, плитка мха."""
    g = bmesh.ops.create_icosphere(m.bm, subdivisions=subdiv, radius=1.0)
    vs = g["verts"]
    for v in vs:
        k = 1.0 + m.rng.uniform(-jitter, jitter)
        v.co = Vector((center[0] + v.co.x * r * k, center[1] + v.co.y * r * k,
                       center[2] + max(v.co.z, -0.55) * r * squash * k))
    faces = {f for v in vs for f in v.link_faces}
    for f in faces:
        f.normal_update()
        use = tile
        if moss_above is not None and f.normal.z > moss_above:
            use = "moss"
        ox, oy = m.rng.random() * 0.5, m.rng.random() * 0.5
        for loop in f.loops:
            co = loop.vert.co
            u = (ox + 0.5 * ((co.x - center[0]) / (2.2 * r) + 0.5)) % 1.0
            v_ = (oy + 0.5 * ((co.y - center[1] + co.z - center[2]) / (2.2 * r) + 0.5)) % 1.0
            loop[m.uv].uv = tile_uv(m.atlas, use, u, v_)


def ring_verts(m, c, r, n, phase=0.0, axis="z", jitter=0.0):
    out = []
    for i in range(n):
        a = phase + i / n * math.tau
        rr = r * (1 + m.rng.uniform(-jitter, jitter))
        if axis == "z":
            out.append(m.bm.verts.new((c[0] + math.cos(a) * rr, c[1] + math.sin(a) * rr, c[2])))
        else:      # кольцо поперёк оси x
            out.append(m.bm.verts.new((c[0], c[1] + math.cos(a) * rr, c[2] + math.sin(a) * rr)))
    return out


def tube(m, rings, tile, moss=None, closed_top=None, u_span=1.0, v_scale=1.0):
    """Трубка по кольцам вершин. moss(f) → True: у грани плитка мха. closed_top — плитка торца (последнее кольцо)."""
    n = len(rings[0])
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            f = m.bm.faces.new([rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]])
            f.normal_update()
            use = "moss" if moss and moss(f) else tile
            for loop, (u, v) in zip(f.loops, [(i / n, k), ((i + 1) / n, k), ((i + 1) / n, k + 1), (i / n, k + 1)]):
                loop[m.uv].uv = tile_uv(m.atlas, use, (u * u_span) % 1.0001, (v / (len(rings) - 1) * v_scale) % 1.0001)
    if closed_top:
        cap(m, rings[-1], closed_top)


def cap(m, ring, tile):
    f = m.bm.faces.new(ring)
    n = len(ring)
    for i, loop in enumerate(f.loops):
        a = i / n * math.tau
        loop[m.uv].uv = tile_uv(m.atlas, tile, 0.5 + 0.48 * math.cos(a), 0.5 + 0.48 * math.sin(a))
    return f


def bracket(m, c, yaw, r):
    """Трутовик: полукруглая полка на стволе (ref: грибы на коре)."""
    n = 5
    pts = [Vector((c[0] + math.cos(yaw + (i / n - 0.5) * math.pi) * r, c[1] + math.sin(yaw + (i / n - 0.5) * math.pi) * r, c[2] - 0.02)) for i in range(n + 1)]
    root = m.bm.verts.new(c)
    vs = [m.bm.verts.new(p) for p in pts]
    for i in range(n):
        f = m.bm.faces.new([root, vs[i], vs[i + 1]])
        for loop, (u, v) in zip(f.loops, [(0.5, 0.05), (i / n, 0.9), ((i + 1) / n, 0.9)]):
            loop[m.uv].uv = tile_uv(m.atlas, "fungus", u, v)


def shrooms(name, cap_tile, count, r_lo, r_hi, spread, seed=None):
    m = Model(name, SOLID, seed)
    for i in range(count):
        a, d = m.rng.uniform(0, math.tau), spread * math.sqrt(m.rng.random())
        x, y = math.cos(a) * d, math.sin(a) * d
        r = m.rng.uniform(r_lo, r_hi)
        tall = r * m.rng.uniform(1.1, 1.9)
        lean = (m.rng.uniform(-0.15, 0.15) * tall, m.rng.uniform(-0.15, 0.15) * tall)
        top = (x + lean[0], y + lean[1], tall)
        sb = ring_verts(m, (x, y, -0.02), r * 0.28, 4)
        st = ring_verts(m, top, r * 0.22, 4)
        tube(m, [sb, st], "stem")
        n = 7
        rim = [(top[0] + math.cos(j / n * math.tau) * r, top[1] + math.sin(j / n * math.tau) * r, top[2] - r * 0.1) for j in range(n)]
        apex = (top[0], top[1], top[2] + r * 0.62)
        for j in range(n):
            u0, u1 = j / n, (j + 1) / n
            m.face([rim[j], rim[(j + 1) % n], apex], cap_tile, [(u0, 1), (u1, 1), ((u0 + u1) / 2, 0)])
    return m


def stump(name, r, tall, seed=None):
    m = Model(name, SOLID, seed)
    n = 9
    moss_yaw = m.rng.uniform(0, math.tau)

    def is_moss(f):
        c = f.calc_center_median()
        return math.cos(math.atan2(c.y, c.x) - moss_yaw) > 0.75 and c.z < tall * 0.5
    rings = [ring_verts(m, (0, 0, -0.12), r * 1.5, n, 0.0, "z", 0.12), ring_verts(m, (0, 0, tall * 0.25), r * 1.08, n, 0.0, "z", 0.06),
             ring_verts(m, (0, 0, tall), r, n, 0.0, "z", 0.05)]
    tube(m, rings, "bark", is_moss, "rings")
    for i in range(4):                                  # корневые наплывы
        a = m.rng.uniform(0, math.tau)
        b0 = ring_verts(m, (math.cos(a) * r * 0.9, math.sin(a) * r * 0.9, tall * 0.32), r * 0.16, 4)
        b1 = ring_verts(m, (math.cos(a) * r * 1.9, math.sin(a) * r * 1.9, -0.06), r * 0.1, 4)
        tube(m, [b0, b1], "bark")
    for i in range(2):
        a = moss_yaw + math.pi + m.rng.uniform(-0.9, 0.9)
        z = m.rng.uniform(0.35, 0.8) * tall
        bracket(m, (math.cos(a) * r * 0.95, math.sin(a) * r * 0.95, z), a, r * 0.42)
    return m


def log(name, length, r, seed=None):
    m = Model(name, SOLID, seed)
    n = 8

    def is_moss(f):
        return f.normal.z > 0.55 and m.rng.random() < 0.8
    segs = 4
    rings = []
    for k in range(segs + 1):
        t = k / segs
        c = (t * length - length / 2, 0.0, r * 0.75 - 0.02 + math.sin(t * math.pi) * 0.05)
        rings.append(ring_verts(m, c, r * (1.08 - 0.3 * t), n, 0.3, "x", 0.05))
    tube(m, rings, "bark", is_moss, None, u_span=1.0, v_scale=1.0)
    # Нормали колец заданы порядком вершин; торцы — кольца годовых колец.
    cap(m, rings[-1], "rings")
    cap(m, list(reversed(rings[0])), "rings")
    for s in (0.25, 0.68):                              # сучья
        a = m.rng.uniform(0.6, 2.4)
        cx = s * length - length / 2
        b0 = ring_verts(m, (cx, math.cos(a) * r * 0.7, r * 0.75 + math.sin(a) * r * 0.7), r * 0.2, 4)
        b1 = ring_verts(m, (cx + 0.15, math.cos(a) * r * 2.0, r * 0.75 + math.sin(a) * r * 2.0), r * 0.1, 4)
        tube(m, [b0, b1], "bark")
    for i in range(3):
        a = m.rng.uniform(-0.3, 0.3)
        side = m.rng.choice((-1, 1))
        cx = m.rng.uniform(-0.35, 0.35) * length
        bracket(m, (cx, side * r * 0.95, r * (0.55 + a)), side * math.pi / 2, r * 0.42)
    m.extra["box"] = [length * 0.95, r * 1.7, r * 2.0]
    return m


def roots(name, n, reach, seed=None):
    """Корни у основания дерева: изогнутые трубки от ствола в землю; центр пуст (там ствол дерева)."""
    m = Model(name, SOLID, seed)
    for i in range(n):
        a = (i + m.rng.uniform(-0.3, 0.3)) / n * math.tau
        rr = reach * m.rng.uniform(0.7, 1.15)
        rings = []
        for k, (t, z, thick) in enumerate(((0.06, 0.55, 0.11), (0.35, 0.28, 0.1), (0.68, 0.08, 0.07), (1.0, -0.1, 0.03))):
            wob = m.rng.uniform(-0.12, 0.12) * t
            rings.append(ring_verts(m, (math.cos(a + wob) * rr * t, math.sin(a + wob) * rr * t, z), thick, 4, a))
        tube(m, rings, "bark", lambda f: f.normal.z > 0.75 and m.rng.random() < 0.4)
    return m


def ivy_shell(name, r0, r1, tall, seed=None):
    """Плющ на стволе: открытая оболочка из плитки с рваной альфой, шире снизу, плюс пара свисающих плетей."""
    m = Model(name, FOLIAGE, seed)
    n = 6
    for k, (z0, z1) in enumerate(((0.0, tall * 0.45), (tall * 0.45, tall))):
        rb, rt = r0 + (r1 - r0) * (z0 / tall), r0 + (r1 - r0) * (z1 / tall)
        for i in range(n):
            a0, a1 = i / n * math.tau, (i + 1) / n * math.tau
            p = [(math.cos(a0) * rb, math.sin(a0) * rb, z0), (math.cos(a1) * rb, math.sin(a1) * rb, z0),
                 (math.cos(a1) * rt, math.sin(a1) * rt, z1), (math.cos(a0) * rt, math.sin(a0) * rt, z1)]
            tile = "ivy" if k == 0 else "ivy_thin"
            m.face(p, tile, [(i / n, 1), ((i + 1) / n, 1), ((i + 1) / n, 0), (i / n, 0)])
    return m


def vine_curtain(name, w, tall, cards=3, seed=None):
    """Свисающие плети: основание наверху (начало координат); ставится на край постройки или ветку."""
    m = Model(name, FOLIAGE, seed)
    for i in range(cards):
        x = (i / max(1, cards - 1) - 0.5) * w
        y = m.rng.uniform(-0.12, 0.12)
        ww = 0.62
        hh = tall * m.rng.uniform(0.7, 1.0)
        m.face([(x - ww / 2, y, -hh), (x + ww / 2, y, -hh), (x + ww / 2, y, 0), (x - ww / 2, y, 0)], "vine", [(0, 1), (1, 1), (1, 0), (0, 0)])
    return m


def plank_box(m, c, size, yaw=0.0, tile="planks", tilt=0.0):
    """Короб из досок: плитка поперёк длинной стороны. c — центр низа; tilt — наклон вокруг длинной оси."""
    w, d, h_ = size
    cs, sn = math.cos(yaw), math.sin(yaw)
    ct, st = math.cos(tilt), math.sin(tilt)

    def P_(x, y, z):
        y, z = y * ct - z * st, y * st + z * ct
        return (c[0] + x * cs - y * sn, c[1] + x * sn + y * cs, c[2] + z)
    xs, ys = (-w / 2, w / 2), (-d / 2, d / 2)
    corners = [P_(x, y, z) for z in (0.0, h_) for y in ys for x in xs]
    # Индексы: 0–3 низ, 4–7 верх.
    for idx in ((0, 1, 5, 4), (1, 3, 7, 5), (3, 2, 6, 7), (2, 0, 4, 6), (4, 5, 7, 6), (2, 3, 1, 0)):
        m.face([corners[i] for i in idx], tile, [(0, 1), (1, 1), (1, 0), (0, 0)])


def barrel(m, c, r, tall, tile="planks", lying=False):
    """Бочка: брюхо шире краёв, железные обручи. lying — на боку."""
    n = 9
    rows = [(0.0, r * 0.82), (0.5, r), (1.0, r * 0.82)]
    rings = []
    for t, rr in rows:
        if lying:
            rings.append(ring_verts(m, (c[0] + (t - 0.5) * tall, c[1], c[2] + r), rr, n, 0.2, "x"))
        else:
            rings.append(ring_verts(m, (c[0], c[1], c[2] + t * tall), rr, n, 0.2))
    tube(m, rings, tile, None, "rings")
    cap(m, list(reversed(rings[0])), "rings")


def models_made():
    """Рукотворные мелочи: брошенное и забытое вдоль дорог и у воды."""
    out = []
    m = Model("Pr_Cairn", SOLID)                         # пирамидка из камней
    for x, y, z, r in ((0.0, 0.0, 0.12, 0.42), (0.3, 0.12, 0.08, 0.28), (-0.28, 0.2, 0.08, 0.26), (0.02, 0.03, 0.42, 0.28), (-0.02, 0.0, 0.66, 0.2), (0.0, 0.0, 0.84, 0.13)):
        lump(m, (x, y, z), r, 0.62, "stone", 0.75, 0.14)
    m.extra["solid"] = 0.45
    out.append(m)
    m = Model("Pr_Waystone", SOLID)                      # придорожный камень в мху
    lump(m, (0, 0, 0.1), 0.42, 0.55, "stone_cold", 0.85, 0.12)
    plank_box(m, (0, 0, 0.1), (0.42, 0.26, 1.15), 0.2, "stone")
    plank_box(m, (0, 0, 1.25), (0.5, 0.32, 0.12), 0.2, "stone_cold")
    m.extra["solid"] = 0.35
    out.append(m)
    m = Model("Pr_Barrels", SOLID)
    barrel(m, (0.0, 0.0, -0.02), 0.34, 0.9)
    barrel(m, (0.68, 0.2, -0.02), 0.3, 0.78, "planks_grey")
    barrel(m, (-0.1, -0.85, 0.0), 0.3, 0.8, "planks_grey", True)
    m.extra["solid"] = 0.72
    out.append(m)
    m = Model("Pr_Crates", SOLID)
    plank_box(m, (0, 0, 0), (0.8, 0.8, 0.7), 0.3)
    plank_box(m, (0.9, 0.2, 0), (0.62, 0.62, 0.55), -0.2, "planks_grey")
    plank_box(m, (0.08, 0.05, 0.7), (0.56, 0.56, 0.46), 0.75, "planks_grey")
    m.extra["solid"] = 0.72
    out.append(m)
    m = Model("Pr_FenceOld", SOLID)                      # остатки изгороди: покосившиеся столбы и жерди
    for x, lean in ((-1.7, 0.1), (0.0, -0.16), (1.7, 0.22)):
        plank_box(m, (x, 0, -0.1), (0.14, 0.14, 1.25), 0.0, "bark_grey", lean)
    for z, a, b, tilt in ((0.5, -1.7, 0.0, 0.0), (0.92, -1.7, 0.0, 0.05), (0.42, 0.0, 1.0, 0.25)):
        plank_box(m, ((a + b) / 2, 0.07, z), (abs(b - a) + 0.2, 0.05, 0.11), 0.0, "planks_grey", tilt)
    out.append(m)
    m = Model("Pr_Boat", SOLID)                          # старая лодка, вытащенная на берег и завалившаяся набок
    L, W_ = 3.0, 0.62
    n = 7
    prof = []                                            # сечения от носа к корме: (x, полуширина, высота борта, низ)
    for i in range(n):
        t = i / (n - 1)
        hw = W_ * math.sin(math.pi * (0.1 + t * 0.8)) ** 0.7
        prof.append(((t - 0.5) * L, hw, 0.62 + 0.14 * abs(t - 0.5) * 2, 0.14 * abs(t - 0.5) * 2))
    tilt = 0.24
    cos_, sin_ = math.cos(tilt), math.sin(tilt)

    def bp(x, y, z):
        return (x, y * cos_ - z * sin_, y * sin_ + z * cos_ + 0.02)
    for (x0, w0, top0, low0), (x1, w1, top1, low1) in zip(prof, prof[1:]):
        for s in (-1, 1):
            m.face([bp(x0, s * w0 * 0.25, low0), bp(x1, s * w1 * 0.25, low1), bp(x1, s * w1, top1), bp(x0, s * w0, top0)], "planks_grey", [(0, 1), (1, 1), (1, 0), (0, 0)])
        m.face([bp(x0, -w0 * 0.25, low0), bp(x1, -w1 * 0.25, low1), bp(x1, w1 * 0.25, low1), bp(x0, w0 * 0.25, low0)], "planks", [(0, 1), (1, 1), (1, 0), (0, 0)])
    for x in (-0.55, 0.5):                               # банки
        k = 0.95 if abs(x) < 0.6 else 0.7
        plank_box(m, (x, 0, 0.0), (0.26, W_ * 1.6 * k, 0.05), 0.0, "planks")
    m.extra["box"] = [L * 0.92, 0.7, W_ * 1.7]
    out.append(m)
    m = Model("Pr_FishPoles", SOLID)                     # шесты для сушки сетей у воды
    for x in (-1.1, 1.1):
        for s in (-1, 1):
            plank_box(m, (x, s * 0.34, -0.1), (0.07, 0.07, 1.9), 0.0, "bark_grey", -s * 0.2)
    plank_box(m, (0, 0, 1.66), (2.9, 0.07, 0.07), 0.0, "bark_grey")
    out.append(m)
    return out


def models():
    out = models_made() + [
        rosette("Dt_Fern_A", "fern", 8, 1.25, 0.72, 0.5, 0.46),
        rosette("Dt_Fern_B", "fern_dark", 9, 1.55, 0.95, 0.62, 0.55),
        rosette("Dt_Fern_C", "fern_small", 6, 0.8, 0.45, 0.28, 0.34),
        rosette("Dt_Broad_A", "broad", 9, 1.35, 0.95, 0.62, 0.34),
        rosette("Dt_Broad_B", "broad_small", 7, 0.72, 0.42, 0.25, 0.22),
        cross("Dt_Tuft_A", "tuft", 1.15, 1.0),
        cross("Dt_Tuft_Tall", "tuft_tall", 1.4, 1.65),
        cross("Dt_Tuft_Dry", "tuft_dry", 1.35, 1.35),
        cross("Dt_Cattail", "cattail", 1.2, 1.85, 3),
        cross("Dt_Lily", "lily", 1.3, 1.5, 2),
        cross("Dt_Spike", "spike", 1.15, 1.75, 2),
        cross("Dt_Poppy", "poppy", 1.35, 1.05, 2),
        cross("Dt_Umbel", "umbel", 1.5, 1.3, 2),
        flat("Dt_Moss_A", "moss_patch", 1.8, 1.8, 0.0, 0.08),
        flat("Dt_Moss_B", "moss_patch_dark", 2.2, 2.2, 0.0, 0.1),
        flat("Dt_Litter", "litter", 2.4, 2.4, 0.04),
        flat("Dt_Twigs", "twigs", 2.4, 1.6, 0.05),
        shrooms("Dt_Shroom_Tan", "cap_tan", 6, 0.07, 0.14, 0.35),
        shrooms("Dt_Shroom_Red", "cap_red", 3, 0.09, 0.15, 0.22),
    ]
    for name, tile, count, lo, hi, spread, squash in (("Dt_Pebbles_A", "stone", 7, 0.09, 0.26, 0.5, 0.6),
                                                      ("Dt_Pebbles_B", "stone_cold", 9, 0.06, 0.17, 0.62, 0.55)):
        m = Model(name, SOLID)
        for i in range(count):
            a, d = m.rng.uniform(0, math.tau), spread * math.sqrt(m.rng.random())
            r = m.rng.uniform(lo, hi)
            lump(m, (math.cos(a) * d, math.sin(a) * d, r * 0.2), r, squash, tile, None, 0.2)
        out.append(m)
    m = Model("Pr_RiverStones", SOLID)
    for x, y, r in ((0.0, 0.0, 0.55), (0.75, 0.25, 0.32), (-0.6, 0.4, 0.26), (0.2, -0.7, 0.2)):
        lump(m, (x, y, r * 0.1), r, 0.55, "stone_cold", 0.86, 0.14)
    out.append(m)
    for name, r, squash, mz in (("Pr_Boulder_A", 0.85, 0.72, 0.62), ("Pr_Boulder_B", 1.15, 0.6, 0.52)):
        m = Model(name, SOLID)
        lump(m, (0, 0, r * 0.28), r, squash, "stone", mz, 0.2, 2)
        m.extra["solid"] = r * 0.85
        out.append(m)
    for name, r, tall in (("Pr_Stump_A", 0.34, 0.62), ("Pr_Stump_B", 0.48, 0.95)):
        m = stump(name, r, tall)
        m.extra["solid"] = r
        out.append(m)
    out += [log("Pr_Log_A", 3.6, 0.27), log("Pr_Log_B", 5.2, 0.38), roots("Pr_Roots", 6, 1.35),
            ivy_shell("Pr_Ivy", 0.3, 0.2, 2.8), vine_curtain("Pr_Vine", 1.5, 2.4)]
    return out


def to_object(m):
    me = bpy.data.meshes.new(m.name)
    bmesh.ops.recalc_face_normals(m.bm, faces=m.bm.faces) if m.name.startswith(("Pr_Stump", "Pr_Log", "Pr_Boulder", "Pr_Roots", "Pr_River", "Dt_Pebbles")) else None
    m.bm.to_mesh(me)
    m.bm.free()
    mat = bpy.data.materials.get("nature_" + m.atlas) or _material(m.atlas)
    me.materials.append(mat)
    ob = bpy.data.objects.new(m.name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _material(atlas):
    """Имя материала — по нему игра подключает свою картинку (nature_scatter.gd); картинку в glb не кладём.
    В Blender картинка нужна только для кадра сверки."""
    mat = bpy.data.materials.new("nature_" + atlas)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    img = bpy.data.images.load(os.path.join(GAME, "textures", atlas + ".png"), check_existing=True)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    mat.surface_render_method = "DITHERED"
    return mat


def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    info = {}
    obs = []
    for m in models():
        extra = m.extra
        atlas = m.atlas
        ob = to_object(m)
        obs.append(ob)
        me = ob.data
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        crown = max(math.hypot(x, y) for x, y in zip(xs, ys))
        rec = {"materials": [atlas], "height": round(max(zs), 2), "crown": round(crown, 2), "tris": tris}
        if "solid" in extra:
            rec["solid"] = round(extra["solid"], 2)
        if "box" in extra:
            rec["box"] = [round(v, 2) for v in extra["box"]]
        info[ob.name] = rec
    with open(os.path.join(GAME, "pack_extras.json"), "w", encoding="utf-8") as f:
        json.dump({"models": info}, f, ensure_ascii=False, indent=0)
    return obs, info


def export(obs):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in obs:
        ob.select_set(True)
    windows = bpy.context.window_manager.windows
    with bpy.context.temp_override(**({"window": windows[0], "screen": windows[0].screen} if windows else {})):
        bpy.ops.export_scene.gltf(filepath=os.path.join(GAME, "nature_extras.glb"), export_format="GLB", use_selection=True,
                                  export_apply=True, export_image_format="NONE", export_yup=True)


if __name__ == "__main__":
    objects, models_info = build()
    export(objects)
    result_info = {"models": len(models_info), "tris": {k: v["tris"] for k, v in models_info.items()}}
