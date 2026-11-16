"""Мир вокруг Ивового Брода в Blender — этап 1: рельеф, вода, дороги, черновые формы мест (по Tools/world_layout.py).

Запуск из Blender (MCP), открывает НОВЫЙ файл:
    exec(open(r"<проект>/Tools/blender/build_world.py", encoding="utf-8").read(), {"__name__": "__main__"})
Результат: Арт/Blender/world.blend (коллекция «Мир»), рендеры сверки Арт/Blender/world_top.png и world_view_*.png.

Как строится:
- Сетка рельефа 2 м на весь мир (~1,5 × 1 км), высоты — numpy + шум mathutils: луга, западные горы (край — MOUNTAIN_EDGE),
  южный гребень, холмы с кладбищем, каменистые выходы, террасы ступенями, площадки деревни и крепости.
- Дороги выравнивают землю по своей линии; русло реки и озеро прорезаются ПОСЛЕ дорог (иначе дорога засыпает брод).
- Цвет земли — в вершинах (экранные цвета → линейные, lin()); плотность леса — карта FOREST (для расстановки деревьев).
- Черновые формы: стены и башни крепости, мосты, дома (короб + двускатная крыша), мельница, частокол, шатры, пни,
  руины святилища, надгробия, входы в шахту и пещеры, пристань. Пустышки poi-<id>, lantern-NN — для Godot.
Оси: Blender (x — восток, y — север, z — вверх) = метры планировки; в Godot (x, z, −y).
"""
import json
import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
BLEND = os.path.join(PROJECT, "Арт", "Blender", "world.blend")
RENDER = os.path.join(PROJECT, "Арт", "Blender", "world_%s.png")

W = {}
exec(open(os.path.join(PROJECT, "Tools", "world_layout.py"), encoding="utf-8").read(), W)
P, PL = W["P"], W["PL"]

STEP = 2.0
BX0, BY0, BX1, BY1 = W["BOUNDS"]
XS = np.arange(math.floor(BX0), math.ceil(BX1) + STEP / 2, STEP)
YS = np.arange(math.floor(BY0), math.ceil(BY1) + STEP / 2, STEP)
GX, GY = np.meshgrid(XS, YS)
LAKE_Z = 2.0             # гладь озера
RIVER_END_Z = -5.0       # гладь реки у южного края
random.seed(11)

# Ручные правки автора (редактор Godot → меню «Мир: сохранить правки» → этот файл): id группы →
# {"dx", "dy" — сдвиг в метрах Blender, "rot" — поворот вокруг вертикали в градусах, "hide" — убрать}.
OVERRIDES_JSON = os.path.join(PROJECT, "Tools", "world_overrides.json")
OVR = json.load(open(OVERRIDES_JSON, encoding="utf-8")) if os.path.exists(OVERRIDES_JSON) else {}


def ovr(gid):
    """Правка группы: (dx, dy, поворот в радианах, скрыть)."""
    o = OVR.get(gid, {})
    return float(o.get("dx", 0.0)), float(o.get("dy", 0.0)), math.radians(float(o.get("rot", 0.0))), bool(o.get("hide", False))


def rotate_about(x, y, cx, cy, a):
    c, s_ = math.cos(a), math.sin(a)
    return cx + (x - cx) * c - (y - cy) * s_, cy + (x - cx) * s_ + (y - cy) * c


# --- Геометрия на сетке -------------------------------------------------------------------------

def _ui():
    """Контекст окна для операторов импорта/экспорта; в фоне (blender -b, Tools/rebuild_world.ps1) окон нет."""
    ws = bpy.context.window_manager.windows
    return {"window": ws[0], "screen": ws[0].screen} if ws else {}


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def noise_field(scale, z, fn):
    out = np.empty(GX.shape)
    for j, y in enumerate(YS):
        row = out[j]
        for i, x in enumerate(XS):
            row[i] = fn(Vector((x / scale, y / scale, z)))
    return out


def poly_mask(poly):
    """Точки сетки внутри многоугольника (метры) — чётно-нечётное правило, векторно."""
    inside = np.zeros(GX.shape, dtype=bool)
    n = len(poly)
    for k in range(n):
        x1, y1 = poly[k]
        x2, y2 = poly[(k + 1) % n]
        cond = (y1 > GY) != (y2 > GY)
        xint = (x2 - x1) * (GY - y1) / ((y2 - y1) if y2 != y1 else 1e-9) + x1
        inside ^= cond & (GX < xint)
    return inside


def seg_dist(ax, ay, bx, by):
    """Расстояние от точек сетки до отрезка и параметр t (0..1) вдоль него."""
    vx, vy = bx - ax, by - ay
    l2 = vx * vx + vy * vy or 1e-9
    t = np.clip(((GX - ax) * vx + (GY - ay) * vy) / l2, 0.0, 1.0)
    dx, dy = GX - (ax + t * vx), GY - (ay + t * vy)
    return np.sqrt(dx * dx + dy * dy), t


def edge_dist(poly):
    """Расстояние до границы многоугольника."""
    d = np.full(GX.shape, 1e9)
    for k in range(len(poly)):
        (ax, ay), (bx, by) = poly[k], poly[(k + 1) % len(poly)]
        dk, _ = seg_dist(ax, ay, bx, by)
        d = np.minimum(d, dk)
    return d


def signed_inside(poly):
    """>0 — внутри (метры до края), <0 — снаружи."""
    d = edge_dist(poly)
    return np.where(poly_mask(poly), d, -d)


def line_field(points, values):
    """Ближайшая точка ломаной: расстояние и значение (линейно по values в вершинах)."""
    best = np.full(GX.shape, 1e9)
    val = np.zeros(GX.shape)
    for k in range(len(points) - 1):
        (ax, ay), (bx, by) = points[k], points[k + 1]
        d, t = seg_dist(ax, ay, bx, by)
        v = values[k] + (values[k + 1] - values[k]) * t
        closer = d < best
        best = np.where(closer, d, best)
        val = np.where(closer, v, val)
    return best, val


def chaikin(points, iterations=3):
    """Сглаживание ломаной (срез углов Чайкина), концы остаются на месте — дороги изгибаются плавно."""
    for _ in range(iterations):
        out = [points[0]]
        for (ax, ay), (bx, by) in zip(points, points[1:]):
            out.append((0.75 * ax + 0.25 * bx, 0.75 * ay + 0.25 * by))
            out.append((0.25 * ax + 0.75 * bx, 0.25 * ay + 0.75 * by))
        out.append(points[-1])
        points = out
    return points


def resample(points, step=6.0):
    out = [points[0]]
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        n = max(1, int(math.hypot(bx - ax, by - ay) / step))
        out += [(ax + (bx - ax) * i / n, ay + (by - ay) * i / n) for i in range(1, n + 1)]
    return out


def sample(h, x, y):
    i = int(round((x - XS[0]) / STEP))
    j = int(round((y - YS[0]) / STEP))
    i = max(1, min(len(XS) - 2, i))
    j = max(1, min(len(YS) - 2, j))
    return float(h[j - 1:j + 2, i - 1:i + 2].mean())


def pad(h, mask_dist, target, fall, strength=1.0):
    """Выравнивание к target: mask_dist — расстояние до области (0 внутри), fall — ширина плавного края."""
    w = (1.0 - smoothstep(0.0, fall, mask_dist)) * strength
    return h * (1.0 - w) + target * w


# --- Высоты ------------------------------------------------------------------------------------

def mountain_poly():
    edge = [(x, y) for y, x in W["MOUNTAIN_EDGE"]]
    return PL([(-60, -60)] + edge + [(-60, 1100)])


MOUNTAIN_PEAK = 125.0     # потолок гор (мягкий, tanh): пики выходят ~90–100 м, вершины в снегу


def voronoi_field(scale, z):
    """Ячеистый шум Вороного: F1 (до ближайшей точки), F2−F1 (близость к границе ячеек) и «номер» ячейки 0..1."""
    f1 = np.empty(GX.shape)
    edge = np.empty(GX.shape)
    cell = np.empty(GX.shape)
    for j, y in enumerate(YS):
        for i, x in enumerate(XS):
            dist, pts = noise.voronoi(Vector((x / scale, y / scale, z)), distance_metric="DISTANCE")
            f1[j, i] = dist[0]
            edge[j, i] = dist[1] - dist[0]
            p = pts[0]
            cell[j, i] = (math.sin(p.x * 12.9898 + p.y * 78.233 + p.z * 37.719) * 43758.5453) % 1.0
    return f1, edge, cell


def mountains(dm, ds):
    """Горы из четырёх шумов (решение автора): Перлин — подножие и пологие склоны, «симплекс» — улучшенный
    Перлин (PERLIN_NEW: в mathutils нет симплекса, это его аналог без сеточных артефактов) — крупные массивы,
    гребневый шум — острые хребты и пики, Вороной — плато-уступы, каменные глыбы и трещины-каньоны.
    dm, ds — расстояние внутрь западных гор и южного гребня (м, <0 — снаружи)."""
    perlin = noise_field(55.0, 4.2, lambda v: noise.fractal(v, 1.0, 2.0, 3, noise_basis="PERLIN_ORIGINAL"))
    simplex = noise_field(160.0, 6.1, lambda v: noise.fractal(v, 0.9, 2.0, 4, noise_basis="PERLIN_NEW"))
    ridged = noise_field(85.0, 1.7, lambda v: noise.ridged_multi_fractal(v, 1.0, 2.1, 6, 1.0, 2.0,
                                                                          noise_basis="PERLIN_NEW"))
    ridged = np.clip(ridged / 1.6, 0.0, 1.0)
    f1, edge, cell = voronoi_field(70.0, 9.3)
    inside = np.maximum(dm, ds * 1.4)
    foot = smoothstep(-35.0, 15.0, inside) * (5.0 + 5.0 * perlin)                  # предгорья
    massif = smoothstep(0.0, 160.0, inside) * (38.0 + 22.0 * simplex)              # тело хребта
    crest = smoothstep(15.0, 110.0, inside) * 55.0 * ridged ** 1.4                 # гребни и пики
    m = foot + massif + crest
    # Плато: в части ячеек Вороного высота ступенями по 9 м (уступы, как на референсе шахты).
    plateau = (cell > 0.62) * smoothstep(0.06, 0.25, edge) * smoothstep(20.0, 60.0, inside)
    m = m * (1 - plateau * 0.8) + np.round(m / 9.0) * 9.0 * plateau * 0.8
    # Глыбы — купола в центрах ячеек; трещины-каньоны — по границам ячеек.
    m += smoothstep(0.35, 0.0, f1) * 6.0 * smoothstep(5.0, 40.0, inside)
    m -= (1.0 - smoothstep(0.0, 0.07, edge)) * 10.0 * smoothstep(30.0, 90.0, inside)
    m = MOUNTAIN_PEAK * np.tanh(np.maximum(m, 0.0) / MOUNTAIN_PEAK)
    return m, perlin


def heights():
    fbm = noise_field(140.0, 0.3, lambda v: noise.fractal(v, 1.0, 2.0, 4))
    ridge = noise_field(70.0, 1.7, lambda v: noise.ridged_multi_fractal(v, 1.0, 2.0, 5, 1.0, 2.0))
    detail = noise_field(20.0, 3.1, lambda v: noise.fractal(v, 0.8, 2.0, 3))
    h = 4.0 + 3.0 * fbm + 0.6 * detail
    # Западные горы и южный гребень — четыре шума (mountains()).
    dm = signed_inside(mountain_poly())
    ds = signed_inside(PL(W["SOUTH_RIDGE"]))
    m, _ = mountains(dm, ds)
    h += m
    # Холмы со старым кладбищем — пологий массив.
    dh = signed_inside(PL(W["HILLS"]))
    h += smoothstep(-40.0, 90.0, dh) * W["HILLS_HEIGHT"] * (0.75 + 0.35 * fbm)
    # Каменистые выходы.
    for x, y, r in W["ROCKS"]:
        cx, cy = P(x, y)
        d = np.hypot(GX - cx, GY - cy)
        h += (1.0 - smoothstep(0.35 * r, r, d)) * r * 0.16 * (0.6 + 0.8 * (ridge + 0.5))
    return h, fbm, ridge, detail


# --- Деревня: план домов ------------------------------------------------------------------------

# Дома — модули Quaternius (Tools/blender/village_houses.py): этажи, черепица (red/slate/brown), первый этаж.
HOUSE_STYLE = {
    "tavern": (2, "red", "plaster"), "smithy": (1, "slate", "stone"), "shop": (1, "brown", "plaster"),
    "workshop": (1, "red", "plaster"), "liara": (1, "slate", "stone"), "h1": (1, "brown", "plaster"),
    "h2": (2, "slate", "plaster"), "h3": (1, "red", "plaster"), "h4": (1, "brown", "stone"),
    "hut": (1, "brown", "plaster"), "shed1": (1, "brown", "plaster"), "shed2": (1, "slate", "plaster"),
    "mill": (2, "brown", "stone"),
}
CHIMNEYS = {"tavern", "smithy", "h1", "h2", "h4", "workshop"}
ROOF_SIZES = {4: (4, 6, 8), 6: (4, 6, 8, 10, 12, 14), 8: (8, 10, 12, 14)}   # как в village_houses.py
PLAZA_R = 8.0          # площадь у колодца (меньше — решение автора 2026-10-29)


def village_plan():
    """Дома деревни в метрах: центр, размеры по модулям крыш (кратно 2 м), сторона двери — к колодцу."""
    plan = []
    for rid, name, x, y, w, d, kind in W["VILLAGE"]:
        bx, by = P(x, y)
        ox, oy, orot, _ = ovr("house:" + rid)             # ручная правка автора (сдвиг, поворот)
        cx, cy = bx + ox, by + oy
        item = {"rid": rid, "kind": kind, "x": cx, "y": cy, "w": w, "d": d, "base": (bx, by), "rot": orot}
        if kind in ("building", "shed", "watermill"):
            along_y = d >= w
            span = min((4, 6, 8), key=lambda s: abs(s - (w if along_y else d)))
            length = min(ROOF_SIZES[span], key=lambda l: abs(l - (d if along_y else w)))
            ww, dd = (span, length) if along_y else (length, span)
            dx, dy = -bx, -by                                # сторона двери — по месту без правки
            side = (0, 1 if dy > 0 else -1) if abs(dy) >= abs(dx) else (1 if dx > 0 else -1, 0)
            item.update(w=ww, d=dd, side=side, door=(cx + side[0] * (ww / 2 + 0.4), cy + side[1] * (dd / 2 + 0.4)))
        plan.append(item)
    return plan


RING_R = 20.0     # кольцевая улица вокруг площади (деревня кучнее — решение автора 2026-10-29)


def village_lanes(plan):
    """Улицы деревни: кольцо RING_R вокруг площади, четыре выхода с кольца на площадь (С, Ю, З, В) и дорожки
    от дверей к ближайшей точке кольца (у домов внутри кольца — к площади)."""
    ring = [(math.cos(a) * RING_R, math.sin(a) * RING_R) for a in np.linspace(0, math.tau, 33)]
    lanes = [ring]
    for a in (0.0, math.pi / 2, math.pi, 1.5 * math.pi):
        lanes.append([(math.cos(a) * PLAZA_R, math.sin(a) * PLAZA_R), (math.cos(a) * RING_R, math.sin(a) * RING_R)])
    for it in plan:
        if "door" not in it or it["kind"] in ("watermill", "shed"):   # к мельнице — тропы из ROADS; сараи — без дорожек
            continue
        dx, dy = it["door"]
        ox, oy = dx + it["side"][0] * 2.5, dy + it["side"][1] * 2.5
        dx, dy = rotate_about(dx, dy, it["x"], it["y"], it["rot"])
        ox, oy = rotate_about(ox, oy, it["x"], it["y"], it["rot"])
        r = math.hypot(ox, oy) or 1.0
        target = RING_R if r > RING_R + 2 else PLAZA_R
        lanes.append([(dx, dy), (ox, oy), (ox / r * target, oy / r * target)])
    return lanes


def yard(it):
    """Двор жилого дома (прямоугольник забора вокруг дома с запасом; проход — у двери) или None."""
    if not it["rid"].startswith("h") and it["rid"] not in ("liara",):
        return None
    m = 4.0
    x0, x1 = it["x"] - it["w"] / 2 - m, it["x"] + it["w"] / 2 + m
    y0, y1 = it["y"] - it["d"] / 2 - m, it["y"] + it["d"] / 2 + m
    sx, sy = it["side"]
    gap = (it["x"] + sx * (it["w"] / 2 + m), it["y"] + sy * (it["d"] / 2 + m))
    pts = [rotate_about(px_, py_, it["x"], it["y"], it["rot"]) for px_, py_ in [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]]
    return pts, rotate_about(gap[0], gap[1], it["x"], it["y"], it["rot"])


def rect_dist(cx, cy, w, d, rot=0.0):
    lx, ly = GX - cx, GY - cy
    if rot:
        lx, ly = lx * math.cos(rot) + ly * math.sin(rot), -lx * math.sin(rot) + ly * math.cos(rot)
    dx = np.maximum(np.abs(lx) - w / 2, 0.0)
    dy = np.maximum(np.abs(ly) - d / 2, 0.0)
    return np.sqrt(dx * dx + dy * dy)


class EditGroup:
    """Группа ручной правки (дом, пролёт забора, мелочь): всё, что построено между созданием группы и finish(),
    становится детьми пустышки «Edit_<id>» — автор двигает её в редакторе Godot. built — где группа построена,
    base — где она стоит без правки (от неё считается сдвиг), moved — правка уже учтена при постройке (дома:
    смещение — в village_plan, чтобы площадка, двор и дорожки шли за домом); поворот — всегда здесь."""

    def __init__(self, col, gid, built, h, base=None, moved=False, kit=None, tav=None):
        self.col, self.gid, self.h, self.kit, self.tav = col, gid, h, kit, tav
        self.dx, self.dy, self.rot, self.hide = ovr(gid)
        self.built = built
        self.base = base or (built if not moved else (built[0] - self.dx, built[1] - self.dy))
        self.new = built if moved else (built[0] + self.dx, built[1] + self.dy)
        self.objs0 = set(col.objects)
        self.pt0 = len(POINTS)
        self.kit0 = (len(kit["_parts"]), len(kit["_colliders"])) if kit else None
        self.tav0 = (len(tav["_props"]), len(tav["COLLIDERS"])) if tav else None
        self.bms = {}

    def bm(self, key):
        if key not in self.bms:
            self.bms[key] = bmesh.new()
        return self.bms[key]

    def finish(self, colors, prefix=""):
        """colors — цвет каждого меша группы (ключ bm → rgb), prefix — начало имени меша (Poi_, Detail_ …)."""
        safe = self.gid.replace(":", "_")
        if self.kit and len(self.kit["_parts"]) > self.kit0[0]:
            parts, cols_ = self.kit["_parts"], self.kit["_colliders"]
            mine_p, mine_c = parts[self.kit0[0]:], cols_[self.kit0[1]:]
            del parts[self.kit0[0]:]
            del cols_[self.kit0[1]:]
            if not self.hide:
                keep_p, keep_c = list(parts), list(cols_)
                parts[:], cols_[:] = mine_p, mine_c
                self.kit["finish"](self.col, "Houses__" + safe, False, True)
                parts[:], cols_[:] = keep_p, keep_c
        if self.tav and len(self.tav["_props"]) > self.tav0[0]:
            props, pcol = self.tav["_props"], self.tav["COLLIDERS"]
            mine_p, mine_c = props[self.tav0[0]:], pcol[self.tav0[1]:]
            del props[self.tav0[0]:]
            del pcol[self.tav0[1]:]
            if not self.hide:
                keep_p, keep_c = list(props), list(pcol)
                props[:], pcol[:] = mine_p, mine_c
                self.tav["finish_props"](self.col)
                bpy.data.objects["Props"].name = "Props__" + safe
                bpy.data.objects["Props-colonly"].name = "Props__" + safe + "-colonly"
                props[:], pcol[:] = keep_p, keep_c
        for key, bm in self.bms.items():
            if self.hide or not bm.faces:
                bm.free()
                continue
            finish_mesh(self.col, prefix + key + "__" + safe, bm, colors.get(key, (0.5, 0.5, 0.5)))
        new = [o for o in self.col.objects if o not in self.objs0]
        if self.hide:
            for o in new:
                bpy.data.objects.remove(o, do_unlink=True)
            del POINTS[self.pt0:]
            return
        for o in new:
            if "__" not in o.name:
                o.name = (o.name[:-8] + "__" + safe + "-colonly") if o.name.endswith("-colonly") else o.name + "__" + safe
        bx, by = self.built
        nx, ny = self.new
        bz, nz = height_at(self.h, bx, by), height_at(self.h, nx, ny)
        T = Matrix.Translation((nx, ny, nz)) @ Matrix.Rotation(self.rot, 4, "Z") @ Matrix.Translation((-bx, -by, -bz))
        e = bpy.data.objects.new("Edit_" + safe, None)
        e.empty_display_size = 2.0
        e.location = (nx, ny, nz)
        e.rotation_euler = (0.0, 0.0, self.rot)
        e["edit_id"] = self.gid
        e["base_x"], e["base_y"] = float(self.base[0]), float(self.base[1])
        self.col.objects.link(e)
        bpy.context.view_layer.update()
        for o in new:
            o.matrix_world = T @ o.matrix_world
            o.parent = e
            o.matrix_parent_inverse = e.matrix_world.inverted()
        for k in range(self.pt0, len(POINTS)):
            name, x, y, z = POINTS[k]
            v = T @ Vector((x, y, z))
            POINTS[k] = (name, v.x, v.y, v.z)


BRIDGE_TOE = 1.0      # край настила заходит в землю на столько метров: ступеньки на въезде нет
BRIDGE_PLAN = []


def bridge_plan():
    """Мосты: где стоят и где их концы. Речные — поперёк реки в середине отрезка из W["BRIDGES"], концы на суше
    (4 м от кромки воды). У каждого конца: E — точка, где настил выходит на землю, out — наружу вдоль оси моста,
    road — конец дороги из W["ROADS"], appr — длина прямого подхода, z — высота (bridge_banks)."""
    if BRIDGE_PLAN:
        return BRIDGE_PLAN
    for name, a, b in W["BRIDGES"]:
        pa, pb = P(*a), P(*b)
        if name == "Мост к воротам Рубежа":
            gate = P(*W["FORTRESS"]["gate"])
            bank = pb if math.hypot(pb[0] - gate[0], pb[1] - gate[1]) > 20 else pa
            L = math.hypot(bank[0] - gate[0], bank[1] - gate[1])
            out = ((bank[0] - gate[0]) / L, (bank[1] - gate[1]) / L)
            BRIDGE_PLAN.append({"name": name, "kind": "gate", "gate": gate, "surf": LAKE_Z,
                                "ends": [{"E": bank, "out": out, "road": bank, "appr": 10.0}]})   # 10 м: башня у берега
            continue
        (qx, qy), flow, width, surf = river_at((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2)
        axis = flow + math.pi / 2
        ux, uy = math.cos(axis), math.sin(axis)
        half = width / 2 + 4.0
        ends = []
        for s in (-1, 1):
            E = (qx + ux * s * half, qy + uy * s * half)
            road = min((pa, pb), key=lambda p: math.hypot(p[0] - E[0], p[1] - E[1]))
            ends.append({"E": E, "out": (ux * s, uy * s), "road": road, "appr": 6.0})
        kind = {"Главный мост": "stone", "Ветхий мостик": "rickety"}.get(name, "wood")
        BRIDGE_PLAN.append({"name": name, "kind": kind, "q": (qx, qy), "axis": axis, "half": half, "width": width,
                            "surf": surf, "ends": ends})
    return BRIDGE_PLAN


def bridge_into(e):
    """Куда упирается лента дороги: на 1 м под настил (стыка не видно)."""
    return (e["E"][0] - e["out"][0], e["E"][1] - e["out"][1])


def bridge_approach(pts):
    """Дорога, кончающаяся у моста, идёт к его концу и на настил прямо вдоль оси (иначе упирается в перила).
    Старая конечная точка убирается, если лежит почти у моста или дала бы крутой поворот."""
    pts = list(pts)
    for br in bridge_plan():
        for e in br["ends"]:
            appr = (e["E"][0] + e["out"][0] * e["appr"], e["E"][1] + e["out"][1] * e["appr"])
            for rev in (False, True):
                seq = pts[::-1] if rev else pts
                end, prev = seq[-1], seq[-2]
                if math.hypot(end[0] - e["road"][0], end[1] - e["road"][1]) > 6.0:
                    continue
                turn = abs((math.atan2(appr[1] - end[1], appr[0] - end[0]) -
                            math.atan2(end[1] - prev[1], end[0] - prev[0]) + math.pi) % math.tau - math.pi)
                if math.hypot(end[0] - e["E"][0], end[1] - e["E"][1]) < 8.0 or turn > math.radians(60):
                    seq = seq[:-1]
                seq = seq + [appr, bridge_into(e)]
                pts = seq[::-1] if rev else seq
    return pts


def bridge_banks(h, river):
    """После прорезки воды: у концов мостов — площадка на высоте настила, от неё вдоль дороги пологий подъём (30 м)
    к прежнему рельефу. Русло не засыпается: у воды рельеф остаётся прежним."""
    d_r, _, half_r = river
    h0 = h.copy()
    road_half = {"road": 2.6, "paved": 2.8, "path": 1.5, "lane": 1.1}
    for br in bridge_plan():
        for e in br["ends"]:
            z = sample(h0, *e["E"])
            if br["kind"] == "gate":
                e["z"] = max(z, LAKE_Z + 2.7)         # край настила дамбы не ниже LAKE_Z + 2.6 (causeway)
            elif br["kind"] == "stone":
                e["z"] = min(max(z, br["surf"] + 1.4), br["surf"] + 2.2)
            else:
                e["z"] = min(max(z, br["surf"] + 1.2), br["surf"] + 3.2)
        if br["kind"] == "stone":                     # трёхарочный симметричен: концы на одной высоте
            mean = sum(e["z"] for e in br["ends"]) / 2
            for e in br["ends"]:
                e["z"] = mean
        for e in br["ends"]:
            into = bridge_into(e)
            for kind, pts in ROAD_LINES:
                if math.hypot(pts[0][0] - into[0], pts[0][1] - into[1]) < 0.01:
                    seq = pts
                elif math.hypot(pts[-1][0] - into[0], pts[-1][1] - into[1]) < 0.01:
                    seq = pts[::-1]
                else:
                    continue
                full = resample(seq, 2.0)
                line, s = [full[0]], [0.0]
                for p in full[1:]:
                    s.append(s[-1] + math.hypot(p[0] - line[-1][0], p[1] - line[-1][1]))
                    line.append(p)
                    if s[-1] > 30.0:
                        break
                z1 = sample(h0, *line[-1])
                zs = []
                for sv in s:
                    t = max(0.0, (sv - 4.0) / (s[-1] - 4.0))
                    zs.append(e["z"] + (z1 - e["z"]) * t * t * (3.0 - 2.0 * t))
                d, zf = line_field(line, zs)
                h = pad(h, np.maximum(d - road_half[kind] - 0.5, 0.0), zf, 6.0)
                e.setdefault("line", line)
    w = smoothstep(half_r - 0.5, half_r + 3.5, d_r)
    return h0 * (1.0 - w) + h * w


def shape(h, fbm):
    """Площадки, террасы, поля, дороги (до прорезки воды)."""
    # Деревня — ровная терраса вокруг колодца.
    dv = np.hypot(GX, GY)
    h = pad(h, np.maximum(dv - 110.0, 0.0), 4.5 + 0.4 * fbm, 50.0, 0.85)
    # Площадки под домами и площадь.
    for it in village_plan():
        if it["kind"] in ("building", "shed", "watermill"):
            h = pad(h, rect_dist(it["x"], it["y"], it["w"] + 3.0, it["d"] + 3.0, it["rot"]), sample(h, it["x"], it["y"]), 5.0)
    h = pad(h, np.maximum(dv - PLAZA_R - 1.0, 0.0), sample(h, 0.0, 0.0), 6.0)
    # Крепость — мыс над озером.
    fw = PL(W["FORTRESS"]["walls"])
    df = np.maximum(-signed_inside(fw), 0.0)
    h = pad(h, df, 9.0, 18.0)
    # Террасы — ступени по 1,6 м.
    for poly in W["TERRACES"]:
        d = np.maximum(-signed_inside(PL(poly)), 0.0)
        stepped = np.round(h / 1.6) * 1.6
        w = 1.0 - smoothstep(0.0, 6.0, d)
        h = h * (1 - w) + stepped * w
    # Поля и огороды — почти ровно.
    for poly in W["FIELDS"] + W["GARDENS"]:
        pts = PL(poly)
        d = np.maximum(-signed_inside(pts), 0.0)
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        h = pad(h, d, sample(h, cx, cy), 8.0, 0.8)
    # Входы в шахту и пещеры — площадки у подножия гор (иначе вход висит на склоне). Высота — с дороги рядом.
    for pid in ("mine", "cave", "adit", "gorge"):
        poi = next(p for p in W["POIS"] if p[0] == pid)
        cx, cy = P(poi[3], poi[4])
        foot = sample(h, cx + 30.0, cy)
        h = pad(h, np.maximum(np.hypot(GX - cx - 10.0, GY - cy) - 16.0, 0.0), foot, 14.0)
    # Кладбище на холме — площадка.
    cx, cy = P(415, 525)
    h = pad(h, np.maximum(np.hypot(GX - cx, GY - cy) - 55.0, 0.0), sample(h, cx, cy), 20.0, 0.7)
    # Дороги и тропы: по сглаженной высоте вдоль линии.
    road_d = np.full(GX.shape, 1e9)
    path_d = np.full(GX.shape, 1e9)
    # Дороги и тропы — плавными изгибами (сглаживание Чайкина) вместо ломаных с углами.
    lines = [(kind, chaikin(bridge_approach(PL(pts_px)), 3)) for kind, pts_px in W["ROADS"]]
    lines += [("lane", pts) for pts in village_lanes(village_plan())]
    ROAD_LINES[:] = lines
    for kind, pts_m in lines:
        pts = resample(pts_m, 6.0 if kind != "lane" else 2.0)
        zs = [sample(h, x, y) for x, y in pts]
        zs = np.convolve(np.pad(zs, 3, mode="edge"), np.ones(7) / 7.0, mode="valid")
        d, z = line_field(pts, list(zs))
        half = ROAD_HALF[kind]
        # Дорога чуть утоплена в землю (наезжена), тропа — едва.
        sink = {"road": 0.18, "paved": 0.12, "path": 0.08, "lane": 0.05}[kind]
        h = pad(h, np.maximum(d - half, 0.0), z - sink, 5.0, 0.9)
        if kind in ("road", "paved"):
            road_d = np.minimum(road_d, d)
        else:
            path_d = np.minimum(path_d, d)
    return h, road_d, path_d


def water(h):
    """Озеро, пруды, река и ручей — после дорог. Возвращает гладь реки вдоль русла и маски воды."""
    lake = PL(W["LAKE"])
    dl = signed_inside(lake)
    # Сначала берег (выравнивание к глади + 0,7), потом дно — иначе берег засыпал бы дно выше воды.
    # Дно мелеет к берегу плавно (без ступени в 1 м у кромки — на сетке 2 м она давала «пилу»).
    bed = LAKE_Z + 0.7 - np.clip(dl * 0.3, 0.0, 1.5) - np.clip((dl - 5.0) * 0.12, 0.0, 8.0)
    shore = np.clip(-dl, 0.0, None)
    h = np.where(dl > 0, h, pad(h, shore, LAKE_Z + 0.7, 14.0, 0.8))
    h = np.where(dl > 0, np.minimum(h, bed), h)
    # Остров — поднимается над водой.
    di = signed_inside(PL(W["ISLAND"]))
    h = np.where(di > -10, np.maximum(h, LAKE_Z + 0.6 + smoothstep(-10, 15, di) * 4.0), h)
    for x, y, r in W["PONDS"]:
        cx, cy = P(x, y)
        d = np.hypot(GX - cx, GY - cy)
        surf = sample(h, cx, cy) - 0.5
        POND_Z[(x, y)] = surf
        # Берег — до выкапывания (иначе засыплет дно выше глади).
        h = pad(h, np.maximum(d - r, 0.0), surf + 0.4, 6.0, 0.7)
        h = np.where(d < r, np.minimum(h, surf - 0.3 - 1.5 * (1 - (d / r) ** 2)), h)
    # Река: гладь падает от озера к югу; русло — парабола, берега к глади + 0,8.
    rp = [P(x, y) for x, y, w in W["RIVER"]]
    widths = [w for x, y, w in W["RIVER"]]
    n = len(rp)
    levels = [LAKE_Z + (RIVER_END_Z - LAKE_Z) * (k / (n - 1)) ** 0.8 for k in range(n)]
    d, surf = line_field(rp, levels)
    _, wid = line_field(rp, widths)
    half = wid / 2.0
    # Берега (решение автора): в основном пологие — откос 6 м от воды к лугу; утёсы местами — в верховье
    # (у озера) и пятнами по шуму: откос 1,5 м, бровка на 2,8 м над водой (камни на них ставит nature()).
    cliffs = noise_field(60.0, 8.8, lambda v: noise.noise(v, noise_basis="PERLIN_NEW"))
    cliff = (cliffs > 0.35) | (GY > 330.0)
    mill = next(i for i in village_plan() if i["kind"] == "watermill")
    cliff &= np.hypot(GX - mill["x"], GY - mill["y"]) > 34.0          # у мельницы берег пологий
    inner = half - 2.0
    ramp = np.where(cliff, 4.5, 6.0)   # утёс мягче (автор): откос 4,5 м, бровка 2 м над водой
    top = np.where(cliff, surf + 2.0, surf + 0.7)
    chan = surf - 0.8 - 2.2 * np.clip(1.0 - (d / np.maximum(inner, 1.0)) ** 2, 0.0, 1.0)
    bank = surf - 0.8 + (top - (surf - 0.8)) * smoothstep(inner, inner + ramp, d)
    h = pad(h, np.maximum(d - inner - ramp, 0.0), top, 14.0, 0.75)
    h = np.where(d < inner + ramp, np.where(d < inner, chan, bank), h)
    # Берега реки не насыпаются поверх дна озера: иначе у истока кольцо суши отрезает реку от озера.
    h = np.where((dl > 0) & (d < inner + ramp + 16.0), np.minimum(h, bed), h)
    RIVER_CLIFF[:] =[cliff & (d < inner + ramp + 2.0) & (d > inner)]
    # Мельница Ганса: ровная площадка дома (восточная часть стоит на каменном цоколе над откосом),
    # под колесом — жёлоб, ниже по течению — омут (CANON: омут у мельницы).
    it = mill
    m = mill_site(it)
    wgt = (1.0 - smoothstep(0.0, 4.0, rect_dist(it["x"], it["y"], it["w"] + 2.0, it["d"] + 2.0))) * (GX < m["xe"] + 0.5)
    h = h * (1.0 - wgt) + (m["base"] - 0.05) * wgt
    # Пологий спуск к мельнице (замечание автора): вокруг дома уклон не круче ~15° (луг опускается к ней чашей).
    dm = rect_dist(it["x"], it["y"], it["w"] + 2.0, it["d"] + 2.0)
    h = np.where(GX < m["xe"] + 0.5, np.minimum(h, m["base"] + 0.27 * dm + 0.004 * dm * dm), h)
    # Хижина Клауса: ровная площадка над берегом (к реке — откос, мостки).
    hs = hermit_site()
    h = pad(h, rect_dist(hs["x"], hs["y"], hs["w"] + 10.0, hs["d"] + 9.0), hs["base"] - 0.05, 10.0)
    # Площадки не засыпают русло: профиль реки — верхний предел.
    h = np.where(d < inner + ramp, np.minimum(h, np.where(d < inner, chan, bank)), h)
    trench = (np.abs(GX - m["hub"][0]) < 2.6) & (np.abs(GY - m["hub"][1]) < 3.6)
    h = np.where(trench, np.minimum(h, m["surf"] - 1.8), h)
    dp = np.hypot(GX - m["pool"][0], GY - m["pool"][1])
    h = np.where(dp < 6.5, np.minimum(h, m["surf"] - 0.8 - 2.2 * (1.0 - (dp / 6.5) ** 2)), h)
    # Ручей из ущелья.
    sp = [P(x, y) for x, y, w in W["STREAM"]]
    ds, _ = line_field(sp, [0] * len(sp))
    h -= (1.0 - smoothstep(1.0, 4.0, ds)) * 1.2
    return h, (d, surf, half), dl


def forest_density(h, fbm, road_d, path_d, river, dl):
    """0..1 — где лес. Густой — за рекой и к северу; на западе и в холмах — рощами; в деревне — редкие деревья."""
    d_river, _, half = river
    clump = noise_field(45.0, 7.7, lambda v: noise.fractal(v, 1.0, 2.0, 3))
    # Граница густого леса: за рекой, к северу — до озера, к югу — вплотную к деревне (как на концепте).
    east = smoothstep(-30.0, 10.0, GX - np.interp(GY, [-310, -120, 0, 300, 450, 730], [-60, 90, 190, 70, -60, -60]))
    north = smoothstep(380.0, 430.0, GY) * smoothstep(-200.0, -80.0, GX)
    base = np.maximum(east * 0.95, north * 0.9)
    west = smoothstep(0.1, 0.45, clump) * 0.7
    f = np.maximum(base, west)
    f *= smoothstep(120.0, 170.0, np.hypot(GX, GY)) * 0.9 + 0.1 * smoothstep(0.35, 0.6, clump)
    f *= smoothstep(4.0, 10.0, road_d) * smoothstep(2.0, 6.0, path_d)
    f *= smoothstep(half + 2.0, half + 10.0, d_river)
    f *= smoothstep(4.0, 14.0, -dl)
    for pid in ("hunters", "logging", "shrine", "cemetery", "mine", "rubezh", "hermit"):
        poi = next(p for p in W["POIS"] if p[0] == pid)
        cx, cy = P(poi[3], poi[4])
        r = {"hunters": 38, "logging": 70, "shrine": 40, "cemetery": 70, "mine": 40, "rubezh": 120, "hermit": 24}[pid]
        f *= smoothstep(r * 0.8, r * 1.3, np.hypot(GX - cx, GY - cy))
    for poly in W["TERRACES"] + W["FIELDS"] + W["GARDENS"]:
        f *= smoothstep(-2.0, 8.0, -signed_inside(PL(poly)))
    f *= 1.0 - smoothstep(25.0, 55.0, h)        # выше 55 м — голые скалы
    return np.clip(f, 0.0, 1.0)


# --- Цвет земли --------------------------------------------------------------------------------

def colors(h, fbm, road_d, path_d, river, dl, forest):
    gy, gx = np.gradient(h, STEP)
    slope = np.sqrt(gx * gx + gy * gy)
    c = np.zeros(GX.shape + (3,))
    t = smoothstep(-0.6, 0.6, fbm)[..., None]
    c[:] = np.array([0.30, 0.44, 0.17]) * (1 - t) + np.array([0.40, 0.50, 0.21]) * t

    def paint(mask, rgb, amount=1.0):
        m = (np.clip(mask, 0, 1) * amount)[..., None]
        c[:] = c * (1 - m) + np.array(rgb) * m
    paint(forest, (0.16, 0.27, 0.11), 0.85)
    for poly in W["TERRACES"]:
        inside = poly_mask(PL(poly))
        stripe = np.floor(h / 1.6) % 2 == 0
        paint(inside & stripe, (0.52, 0.50, 0.24))
        paint(inside & ~stripe, (0.40, 0.48, 0.20))
    for poly in W["FIELDS"]:
        inside = poly_mask(PL(poly))
        stripe = np.floor((GX + GY) / 2.0) % 2 == 0
        paint(inside, (0.72, 0.62, 0.30))
        paint(inside & stripe, (0.62, 0.52, 0.24))
    for poly in W["GARDENS"]:
        inside = poly_mask(PL(poly))
        stripe = np.floor(GY / 1.5) % 2 == 0
        paint(inside & stripe, (0.43, 0.33, 0.20))
        paint(inside & ~stripe, (0.33, 0.43, 0.17))
    cx, cy = P(415, 525)
    paint(np.hypot(GX - cx, GY - cy) < 55, (0.30, 0.36, 0.22), 0.8)
    # Мощёный двор Рубежа.
    paint(poly_mask(PL(W["FORTRESS"]["walls"])), (0.52, 0.50, 0.46), 0.9)
    lx, ly = P(1120, 330)
    paint(np.hypot(GX - lx, GY - ly) < 60, (0.42, 0.36, 0.22), 0.6)
    # Дороги и тропы рисуют гладкие ленты (road_ribbons): на земле — только лёгкая подложка уже ленты,
    # иначе клетки сетки 2 м проступают «квадратами» (замечание автора).
    paint((1.0 - smoothstep(0.5, 1.5, path_d)) * 0.5, (0.50, 0.44, 0.30))
    paint((1.0 - smoothstep(1.0, 2.0, road_d)) * 0.5, (0.52, 0.45, 0.31))
    paint(np.hypot(GX, GY) < PLAZA_R + 1.0, (0.55, 0.52, 0.46))
    d_river, surf, half = river
    paint(1.0 - smoothstep(half + 1, half + 4, d_river), (0.34, 0.31, 0.24))
    paint(smoothstep(-6.0, 0.0, dl) * (dl < 4), (0.48, 0.44, 0.33))
    paint(smoothstep(0.9, 1.4, slope), (0.40, 0.40, 0.42))
    paint(smoothstep(0.45, 0.9, slope) * smoothstep(25.0, 40.0, h), (0.44, 0.43, 0.42), 0.85)   # скалы гор
    paint(smoothstep(62.0, 75.0, h), (0.90, 0.91, 0.94))
    return c


# --- Данные для Godot ----------------------------------------------------------------------------

GODOT_LEVELS = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "levels")
GODOT_GLB = os.path.join(GODOT_LEVELS, "world.glb")
DATA_DIR = os.path.join(PROJECT, "Арт", "Blender")


def splat(h, fbm, road_d, path_d, river, dl, forest):
    """Карта смешивания текстур земли для шейдера terrain_splat (1 пиксель = клетка сетки, STEP м).
    A: R — дорога/тропа (подложка под лентой), G — сухая трава, B — скала, A — пашня/огород/террасы.
    B: R — брусчатка (двор Рубежа, площадь у колодца), G — галька у воды, B — запас, A — тень леса.
    C: R — запас (колеи дают ленты дорог), G — дно под водой, B — снег, A — 1.
    Строка r — y = YS[0] + r·STEP, столбец i — x = XS[0] + i·STEP (Godot: x, −z)."""
    gy, gx = np.gradient(h, STEP)
    slope = np.sqrt(gx * gx + gy * gy)
    # Подложка дороги шире ленты и с неровным краем (замечание автора 2026-10-29: переход в траву мягче).
    wob = noise_field(9.0, 3.1, lambda v: noise.noise(v)) * 1.6
    road = np.maximum(1.0 - smoothstep(0.8, 4.2, road_d + wob), 1.0 - smoothstep(0.3, 2.6, path_d + wob * 0.7))
    dry = smoothstep(0.15, 0.55, fbm) * 0.6
    # Наполнение (EXTRAS_ZONE): в лесу подстилка пятнами (сухая трава в тени леса), на лугах — плеши голой земли.
    if EXTRAS_ZONE:
        zx0, zy0, zx1, zy1 = EXTRAS_ZONE
        zone = smoothstep(zx0 - 8, zx0 + 8, GX) * (1 - smoothstep(zx1 - 8, zx1 + 8, GX)) * smoothstep(zy0 - 8, zy0 + 8, GY) * (1 - smoothstep(zy1 - 8, zy1 + 8, GY))
    else:
        zone = np.ones_like(h)
    litter = noise_field(9.0, 17.3, lambda v: noise.noise(v))
    bare = noise_field(11.0, 19.1, lambda v: noise.fractal(v, 1.0, 2.0, 3))
    dry = np.maximum(dry, zone * smoothstep(0.3, 0.7, forest) * smoothstep(-0.25, 0.15, litter) * 0.9)
    road = np.maximum(road, zone * (1.0 - smoothstep(0.1, 0.4, forest)) * smoothstep(0.3, 0.46, bare) * 0.9)
    dry = np.maximum(dry, smoothstep(0.6, 1.0, slope) * 0.8)
    cx, cy = P(415, 525)
    dry = np.maximum(dry, (np.hypot(GX - cx, GY - cy) < 55) * 0.8)
    lx, ly = P(1120, 330)
    dry = np.maximum(dry, (np.hypot(GX - lx, GY - ly) < 60) * 0.9)
    rock = np.maximum(smoothstep(0.9, 1.4, slope), smoothstep(0.45, 0.9, slope) * smoothstep(25.0, 40.0, h))
    soil = np.zeros_like(h)
    for poly in W["FIELDS"] + W["GARDENS"] + W["TERRACES"]:
        soil = np.maximum(soil, poly_mask(PL(poly)).astype(float))
    cobble = np.maximum(poly_mask(PL(W["FORTRESS"]["walls"])).astype(float),
                        (np.hypot(GX, GY) < PLAZA_R + 1.0).astype(float))
    for it in village_plan():                        # под домами — плиты: трава не прорастает сквозь пол (кузня)
        if it["kind"] in ("building", "shed", "watermill"):
            cobble = np.maximum(cobble, (rect_dist(it["x"], it["y"], it["w"], it["d"], it["rot"]) <= 0.0).astype(float))
    d_river, surf, half = river
    pebbles = np.maximum(1.0 - smoothstep(half + 1, half + 4, d_river), smoothstep(-6.0, 0.0, dl) * (dl < 4))
    under = ((dl > 0.5) | (d_river < half - 0.5)).astype(float)
    snow = smoothstep(62.0, 75.0, h)
    zero = np.zeros_like(h)
    a = np.stack([road, dry, rock, soil], axis=-1)
    b = np.stack([cobble, pebbles, zero, np.clip(forest, 0, 1) * 0.85], axis=-1)
    c = np.stack([zero, under, snow, np.ones_like(h)], axis=-1)
    return a, b, c


def write_png(path, rgba):
    """RGBA 0..1 → PNG 8 бит (в Blender нет Pillow): zlib + заголовки вручную."""
    import struct
    import zlib
    data = (np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8)
    hgt, wid = data.shape[:2]
    raw = b"".join(b"\x00" + data[r].tobytes() for r in range(hgt))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", wid, hgt, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def write_godot_data(h, fbm, road_d, path_d, river, dl, forest):
    """Для Godot (Tools/godot/build_world.gd): высоты — float32 построчно (строка — y), карты смешивания A/B/C."""
    import json
    h.astype("<f4").tofile(os.path.join(DATA_DIR, "world_heights.bin"))
    for key, data in zip("abc", splat(h, fbm, road_d, path_d, river, dl, forest)):
        write_png(os.path.join(DATA_DIR, "world_splat_%s.png" % key), data)
    with open(os.path.join(DATA_DIR, "world_terrain.json"), "w", encoding="utf-8") as f:
        json.dump({"origin": [float(XS[0]), float(YS[0])], "size": [len(XS), len(YS)], "step": STEP,
                   "lake_z": LAKE_Z}, f)


def export_godot(col):
    """glb для Godot: всё, кроме рельефа (его строит Godot из высот) и предпросмотра растительности."""
    keep = {o.name for o in col.all_objects if o.name != "Terrain" and not o.name.startswith("Nature_")}
    for ob in bpy.context.view_layer.objects:
        ob.select_set(ob.name in keep)
    with bpy.context.temp_override(**_ui()):
        bpy.ops.export_scene.gltf(filepath=GODOT_GLB, use_selection=True, export_extras=True, export_yup=True,
                                  export_apply=True, export_lights=False, export_cameras=False,
                                  export_vertex_color="ACTIVE", export_image_format="NONE")
    return len(keep)


# --- Меши ----------------------------------------------------------------------------------------

def lin(rgb):
    return tuple(float(v) ** 2.2 for v in rgb)


_mats = {}


def vc_material():
    if "vc" not in _mats:
        m = bpy.data.materials.new("Цвет вершин")
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        ca = nt.nodes.new("ShaderNodeVertexColor")
        ca.layer_name = "Col"
        nt.links.new(ca.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.95
        _mats["vc"] = m
    return _mats["vc"]


def finish_mesh(col, name, bm, rgb):
    """bmesh → объект с цветом в вершинах (Col) и общим материалом «Цвет вершин»."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    rgba = np.tile(np.array(lin(rgb) + (1.0,), dtype=np.float32), len(me.vertices))
    attr.data.foreach_set("color", rgba)
    me.color_attributes.active_color = attr
    me.materials.append(vc_material())
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


def terrain_mesh(col, h, c):
    ny, nx = h.shape
    verts = np.stack([GX.ravel(), GY.ravel(), h.ravel()], axis=1)
    idx = np.arange(nx * ny).reshape(ny, nx)
    faces = np.stack([idx[:-1, :-1].ravel(), idx[:-1, 1:].ravel(), idx[1:, 1:].ravel(), idx[1:, :-1].ravel()], axis=1)
    me = bpy.data.meshes.new("Terrain")
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.astype(np.float32).ravel())
    me.loops.add(faces.size)
    me.loops.foreach_set("vertex_index", faces.astype(np.int32).ravel())
    me.polygons.add(len(faces))
    me.polygons.foreach_set("loop_start", np.arange(0, faces.size, 4, dtype=np.int32))
    me.update()
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    rgba = np.concatenate([np.power(c.reshape(-1, 3), 2.2), np.ones((nx * ny, 1))], axis=1).astype(np.float32)
    attr.data.foreach_set("color", rgba.ravel())
    me.color_attributes.active_color = attr
    me.materials.append(vc_material())
    ob = bpy.data.objects.new("Terrain", me)
    col.objects.link(ob)
    return ob


def box(bm, cx, cy, z0, w, d, hgt, rot=0.0):
    g = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(w, d, hgt), verts=g["verts"])
    bmesh.ops.rotate(bm, verts=g["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(rot, 3, "Z"))
    bmesh.ops.translate(bm, vec=(cx, cy, z0 + hgt / 2), verts=g["verts"])


def cyl(bm, cx, cy, z0, r, hgt, seg=10, r2=None):
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=hgt)
    bmesh.ops.translate(bm, vec=(cx, cy, z0 + hgt / 2), verts=g["verts"])


def roof(bm, cx, cy, z0, w, d, hgt, rot=0.0):
    """Двускатная крыша: призма вдоль d."""
    hw, hd = w / 2 + 0.4, d / 2 + 0.4
    v = [bm.verts.new(p) for p in [(-hw, -hd, 0), (hw, -hd, 0), (hw, hd, 0), (-hw, hd, 0), (0, -hd, hgt), (0, hd, hgt)]]
    for f in [(0, 1, 4), (3, 5, 2), (0, 4, 5, 3), (1, 2, 5, 4), (0, 3, 2, 1)]:
        bm.faces.new([v[i] for i in f])
    m = Matrix.Translation((cx, cy, z0)) @ Matrix.Rotation(rot, 4, "Z")
    bmesh.ops.transform(bm, matrix=m, verts=v)


def polygon_face(bm, pts, z):
    vs = [bm.verts.new((x, y, z)) for x, y in pts]
    f = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[f])


def water_meshes(col, river):
    bm = bmesh.new()
    polygon_face(bm, PL(W["LAKE"]), LAKE_Z)
    finish_mesh(col, "Lake", bm, (0.20, 0.38, 0.52))
    bm = bmesh.new()
    pts = [P(x, y) for x, y, w in W["RIVER"]]
    widths = [w for x, y, w in W["RIVER"]]
    n = len(pts)
    levels = [LAKE_Z + (RIVER_END_Z - LAKE_Z) * (k / (n - 1)) ** 0.8 for k in range(n)]
    dense, dz, dw = [], [], []
    for k in range(n - 1):
        (ax, ay), (bx, by) = pts[k], pts[k + 1]
        m = max(1, int(math.hypot(bx - ax, by - ay) / 6))
        for i in range(m):
            t = i / m
            dense.append((ax + (bx - ax) * t, ay + (by - ay) * t))
            dz.append(levels[k] + (levels[k + 1] - levels[k]) * t)
            dw.append(widths[k] + (widths[k + 1] - widths[k]) * t)
    dense.append(pts[-1]); dz.append(levels[-1]); dw.append(widths[-1])
    left, right = [], []
    for i, (x, y) in enumerate(dense):
        a = dense[max(0, i - 1)]
        b = dense[min(len(dense) - 1, i + 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        L = math.hypot(tx, ty) or 1
        nx_, ny_ = -ty / L, tx / L
        hw = dw[i] / 2 + 1.5
        left.append(bm.verts.new((x + nx_ * hw, y + ny_ * hw, dz[i] - 0.5)))
        right.append(bm.verts.new((x - nx_ * hw, y - ny_ * hw, dz[i] - 0.5)))
    for i in range(len(dense) - 1):
        bm.faces.new([left[i], right[i], right[i + 1], left[i + 1]])
    finish_mesh(col, "River", bm, (0.22, 0.42, 0.55))
    bm = bmesh.new()
    for x, y, r in W["PONDS"]:
        cx, cy = P(x, y)
        g = bmesh.ops.create_circle(bm, cap_ends=True, segments=16, radius=r)
        bmesh.ops.translate(bm, vec=(cx, cy, 0), verts=g["verts"])
    ponds = finish_mesh(col, "Ponds", bm, (0.20, 0.38, 0.52))
    return ponds


# --- Постройки и места ---------------------------------------------------------------------------

POINTS = []   # (имя, x, y, z)
NATURE_COUNT = {}
POND_Z = {}   # (px, py) пруда → высота глади
ROAD_LINES = []   # (вид, точки) — сглаженные линии дорог, троп и улиц (shape() → road_ribbons())
ROAD_HALF = {"road": 2.6, "paved": 2.8, "path": 1.5, "lane": 1.1}   # полуширина ленты по виду линии, м
RIVER_CLIFF = [None]   # маска утёсов по берегам реки (water() → nature())


WALL_Z0, WALL_H, WALL_T = 8.0, 11.0, 3.4     # стены Рубежа: от, высота, толщина
# Постройки двора (пиксели концепта, размеры м, этажи, крыша): из модулей Quaternius, первый этаж — камень.
FORT_HOUSES = [("hall", 395, 115, 14, 8, 2), ("barracks", 290, 175, 6, 12, 2), ("chapel", 398, 182, 8, 10, 1),
               ("commander", 360, 85, 12, 8, 2), ("armory", 270, 130, 8, 8, 2), ("stables", 330, 215, 12, 6, 1),
               ("store1", 415, 150, 6, 8, 1), ("store2", 300, 225, 8, 6, 1), ("smithy", 265, 205, 8, 6, 1)]


def merlons(bm, ax, ay, bx, by, z, thick):
    """Зубцы по верху стены от (ax, ay) до (bx, by)."""
    L = math.hypot(bx - ax, by - ay)
    rot = math.atan2(by - ay, bx - ax)
    n = int(L / 2.4)
    for i in range(n):
        t = (i + 0.5) / n
        box(bm, ax + (bx - ax) * t, ay + (by - ay) * t, z, 1.2, thick, 1.5, rot)


def round_tower(bm, roofs, x, y, z0, r, hgt, roof_h):
    cyl(bm, x, y, z0, r, hgt, 14)
    cyl(bm, x, y, z0 + hgt - 0.5, r + 0.6, 1.0, 14)                  # пояс под зубцами
    for k in range(10):
        a = k * math.tau / 10
        box(bm, x + math.cos(a) * (r + 0.1), y + math.sin(a) * (r + 0.1), z0 + hgt + 0.5, 1.2, 1.0, 1.4, a)
    cyl(roofs, x, y, z0 + hgt + 0.4, r + 0.9, roof_h, 14, 0.15)


def fortress(col, h):
    """Каменный Рубеж снаружи (по концепту): зубчатые стены с поясом, круглые башни с островерхими крышами,
    надвратные башни с аркой к мосту, квадратный донжон с шатром, постройки двора (зал, казарма, часовня)."""
    F = W["FORTRESS"]
    walls = PL(F["walls"])
    gate = P(*F["gate"])
    bm, roofs = bmesh.new(), bmesh.new()
    top = WALL_Z0 + WALL_H
    for k in range(len(walls)):
        (ax, ay), (bx, by) = walls[k], walls[(k + 1) % len(walls)]
        L = math.hypot(bx - ax, by - ay)
        rot = math.atan2(by - ay, bx - ax)
        ux, uy = (bx - ax) / L, (by - ay) / L
        # Ворота — проём 8 м там, где точка ворот проецируется на ближайшую к ней стену.
        t = (gate[0] - ax) * ux + (gate[1] - ay) * uy
        off = abs((gate[0] - ax) * -uy + (gate[1] - ay) * ux)
        spans = [(0.0, L)]
        if 6.0 < t < L - 6.0 and off < 6.0:
            spans = [(0.0, t - 4.0), (t + 4.0, L)]
            gx, gy = ax + ux * t, ay + uy * t
            box(bm, gx, gy, top - 4.5, 8.0, WALL_T + 1.0, 4.5, rot)          # арка над воротами
            merlons(bm, gx - ux * 4, gy - uy * 4, gx + ux * 4, gy + uy * 4, top, WALL_T + 1.0)
            for s in (-1, 1):
                round_tower(bm, roofs, gx + ux * s * 7.0, gy + uy * s * 7.0, WALL_Z0, 4.2, WALL_H + 4.0, 6.0)
        for s0, s1 in spans:
            c = (s0 + s1) / 2
            cx, cy = ax + ux * c, ay + uy * c
            box(bm, cx, cy, WALL_Z0, s1 - s0, WALL_T, WALL_H, rot)
            box(bm, cx, cy, WALL_Z0, s1 - s0, WALL_T + 1.2, 1.6, rot)        # цоколь
            nx_, ny_ = -uy * WALL_T / 2, ux * WALL_T / 2
            for side in (-1, 1):
                merlons(bm, ax + ux * s0 + nx_ * side, ay + uy * s0 + ny_ * side,
                        ax + ux * s1 + nx_ * side, ay + uy * s1 + ny_ * side, top, 0.6)
    for x, y in PL(F["towers"]):
        round_tower(bm, roofs, x, y, WALL_Z0 - 0.5, 5.2, WALL_H + 7.0, 8.0)
    # Донжон: квадратная башня с шатровой крышей.
    kx, ky = P(*F["keep"])
    box(bm, kx, ky, WALL_Z0, 18.0, 18.0, 24.0)
    box(bm, kx, ky, WALL_Z0 + 23.5, 19.4, 19.4, 1.0)
    for s in (-1, 1):
        merlons(bm, kx - 9.4, ky + s * 9.4, kx + 9.4, ky + s * 9.4, WALL_Z0 + 24.5, 0.8)
        merlons(bm, kx + s * 9.4, ky - 9.4, kx + s * 9.4, ky + 9.4, WALL_Z0 + 24.5, 0.8)
    g = bmesh.ops.create_cone(roofs, cap_ends=True, segments=4, radius1=12.5, radius2=0.2, depth=12.0)
    bmesh.ops.rotate(roofs, verts=g["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 4, 3, "Z"))
    bmesh.ops.translate(roofs, vec=(kx, ky, WALL_Z0 + 24.4 + 6.0), verts=g["verts"])
    finish_mesh(col, "Fortress", bm, (0.60, 0.60, 0.62))
    finish_mesh(col, "FortressRoofs", roofs, (0.22, 0.26, 0.34))
    # Постройки двора — модули Quaternius (камень, сланец).
    kit = {"__name__": "village_houses", "PROJECT": PROJECT}
    exec(open(os.path.join(PROJECT, "Tools", "blender", "village_houses.py"), encoding="utf-8").read(), kit)
    for rid, x, y, w, d, floors in FORT_HOUSES:
        cx, cy = P(x, y)
        side = (0, -1) if abs(cy - gate[1]) > abs(cx - gate[0]) else ((1 if gate[0] > cx else -1), 0)
        kit["build_house"]("fort_" + rid, cx, cy, sample(h, cx, cy), w, d, floors, "slate", "stone", side,
                           True, False)
    kit["finish"](col, "FortressHouses", False)
    POINTS.append(("poi-rubezh-gate", gate[0], gate[1], WALL_Z0 + 1.0))


def river_at(x, y):
    """Ближайшая точка реки: (точка, направление течения в радианах, ширина, высота глади)."""
    pts = [P(px_, py_) for px_, py_, w in W["RIVER"]]
    widths = [w for px_, py_, w in W["RIVER"]]
    n = len(pts)
    levels = [LAKE_Z + (RIVER_END_Z - LAKE_Z) * (k / (n - 1)) ** 0.8 for k in range(n)]
    best = None
    for k in range(n - 1):
        (ax, ay), (bx, by) = pts[k], pts[k + 1]
        vx, vy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy)))
        qx, qy = ax + vx * t, ay + vy * t
        d = math.hypot(x - qx, y - qy)
        if best is None or d < best[0]:
            best = (d, (qx, qy), math.atan2(vy, vx), widths[k] + (widths[k + 1] - widths[k]) * t,
                    levels[k] + (levels[k + 1] - levels[k]) * t)
    return best[1:]


def mill_site(it):
    """Водяная мельница: гладь реки у дома, пол, восточная стена (к реке), ось колеса, омут ниже по течению."""
    _, flow, _, surf = river_at(it["x"], it["y"])
    xe = it["x"] + it["w"] / 2
    hub = (xe + 2.0, it["y"] - 1.0, surf + 1.4)
    pool = (hub[0] + math.cos(flow) * 6.5, hub[1] + math.sin(flow) * 6.5)
    return {"surf": surf, "base": surf + 1.3, "xe": xe, "hub": hub, "R": 3.0, "pool": pool, "flow": flow}


def hermit_site():
    """Хижина Клауса (CANON: на берегу реки вдали от деревни): центр — из POIS, «вперёд» (face) — к реке."""
    poi = next(p for p in W["POIS"] if p[0] == "hermit")
    cx, cy = P(poi[3], poi[4])
    (qx, qy), flow, width, surf = river_at(cx, cy)
    return {"x": cx, "y": cy, "w": 12, "d": 9, "surf": surf, "base": surf + 2.4, "half": width / 2,
            "face": math.atan2(qy - cy, qx - cx), "dist": math.hypot(qx - cx, qy - cy)}


BRIDGE_COLORS = {"stone": (0.56, 0.53, 0.47), "cobble": (0.58, 0.55, 0.48), "arch": (0.70, 0.67, 0.60),
                 "trim": (0.72, 0.69, 0.62), "wood": (0.50, 0.33, 0.19)}


def bridge_lib():
    lib_b = {"__name__": "bridge_lib"}
    exec(open(os.path.join(PROJECT, "Tools", "blender", "bridge_variants.py"), encoding="utf-8").read(), lib_b)
    return lib_b


def merge_parts(tmp, keys, matrix, merged):
    """Детали из временной коллекции (с фасками) → bmesh по ключу материала, с переносом matrix."""
    key_of = {m.name: key for key, m in keys.items()}
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    for ob in list(tmp.objects):
        ev = ob.evaluated_get(deps)
        me = ev.to_mesh()
        for i, m in enumerate(me.materials):
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index != i], context="FACES")
            bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
            part = bpy.data.meshes.new("tmp")
            bm.to_mesh(part)
            bm.free()
            merged.setdefault(key_of[m.name], bmesh.new()).from_mesh(part)
            bpy.data.meshes.remove(part)
        ev.to_mesh_clear()
        bpy.data.objects.remove(ob, do_unlink=True)


def stone_bridge_c(lib_b, tmp, keys, br, merged):
    """Главный мост — вариант C (выбор автора), поперёк реки: концы на суше, край настила на 1 м заходит в землю."""
    qx, qy = br["q"]
    lib_b["WATER"] = br["surf"] - 0.5
    lib_b["BANK"] = br["ends"][0]["z"] - 0.1
    lib_b["bridge_c"](tmp, 0.0, keys, br["half"] + BRIDGE_TOE, 4.0)
    merge_parts(tmp, keys, Matrix.Translation((qx, qy, 0)) @ Matrix.Rotation(br["axis"], 4, "Z"), merged)


def causeway(lib_b, tmp, keys, a, b, z_a, z_b, water, merged, width=5.0, span=8.0):
    """Каменный мост с арками от a до b (к воротам Рубежа): настил полого от z_a к z_b, арки через span м,
    парапеты с зубцами-тумбами."""
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    n = max(1, int(L // span))
    step = L / n
    piers = [i * step for i in range(n + 1)]

    def top(x):
        # Над водой настил не ниже water + 5 (под ним видны арки), к концам — плавный спуск к берегам.
        lin_z = z_a + (z_b - z_a) * (x / L)
        edge = min(x, L - x)
        return max(lin_z, (water + 5.0) - max(0.0, 6.0 - edge) * 0.4)

    def bot(x):
        for k in range(n):
            c = (piers[k] + piers[k + 1]) / 2
            half = step / 2 - 0.9
            if abs(x - c) < half and 0 < k < n - 1 or (abs(x - c) < half and n <= 2):
                rise = min(top(c) - water - 1.2, half)
                return water + 0.2 + rise * math.sqrt(max(0.0, 1 - ((x - c) / half) ** 2))
        return water - 1.5

    xs = [i * 0.25 for i in range(int(L / 0.25) + 1)]
    bm = bmesh.new()
    lib_b["add_profile"](bm, xs, top, bot, -width / 2, width / 2)
    lib_b["make_obj"]("Мост к воротам: тело", bm, [keys["stone"], keys["cobble"]], tmp)
    for sy in (-1, 1):
        y = sy * (width / 2 - 0.25)
        bm = bmesh.new()
        lib_b["add_profile"](bm, xs, lambda x: top(x) + 1.0, lambda x: top(x) - 0.2, y - 0.25, y + 0.25, 0)
        lib_b["make_obj"]("Мост к воротам: парапет", bm, [keys["trim"]], tmp)
        caps = bmesh.new()
        for x in xs[::12]:
            lib_b["add_box"](caps, (x, y, top(x) + 1.25), (0.6, 0.6, 0.5))
        lib_b["make_obj"]("Мост к воротам: тумбы", caps, [keys["arch"]], tmp)
    rot = math.atan2(b[1] - a[1], b[0] - a[0])
    merge_parts(tmp, keys, Matrix.Translation((a[0], a[1], 0)) @ Matrix.Rotation(rot, 4, "Z"), merged)


def wooden_bridge(wood, planks, collider, br, rng, rickety=False):
    """Деревянный мост поперёк реки: доски (planks, без коллизии), сваи и перила (wood), ровная невидимая дорожка
    вдоль настила (collider, «-colonly»): между досками зазоры, а у ветхого и дыры, — Рэй не должен в них застревать.
    rickety — провисший, без части досок и с проломленными перилами (пролом закрыт невидимой стенкой)."""
    qx, qy = br["q"]
    axis, half, width, surf = br["axis"], br["half"], br["width"], br["surf"]
    ux, uy = math.cos(axis), math.sin(axis)
    za, zb = br["ends"][0]["z"], br["ends"][1]["z"]
    W_ = 2.6
    sag = 0.4 if rickety else 0.9

    def deck(t):           # верх настила; t в метрах от −half до half (и на BRIDGE_TOE дальше — в землю)
        c = max(-half, min(half, t))
        return za + (zb - za) * (c + half) / (2 * half) + sag * (1 - (c / half) ** 2) - 0.12 * max(0.0, abs(t) - half)

    t, missed = -half - BRIDGE_TOE, False
    while t < half + BRIDGE_TOE:
        x, y = qx + ux * t, qy + uy * t
        missed = rickety and not missed and rng.random() < 0.14 and abs(t) < width / 2      # две дыры подряд — нет
        if not missed:
            tilt = rng.uniform(-0.12, 0.12) if rickety else 0.0
            box(planks, x, y, deck(t) - 0.12, 0.5, W_, 0.12, axis + tilt)
        t += 0.6
    rows = []
    for t in np.arange(-half - BRIDGE_TOE, half + BRIDGE_TOE + 0.25, 0.5):
        x, y = qx + ux * t, qy + uy * t
        z = deck(t) + 0.02
        rows.append([collider.verts.new((x + uy * W_ / 2 * s, y - ux * W_ / 2 * s, z)) for s in (-1, 1)])
    for r0, r1 in zip(rows, rows[1:]):
        f = collider.faces.new([r0[0], r0[1], r1[1], r1[0]])
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    for k, t in enumerate(np.linspace(-half + 0.5, half - 0.5, int(2 * half / 3.5) + 1)):
        x, y = qx + ux * t, qy + uy * t
        z0 = surf - 1.5 if abs(t) < width / 2 + 0.5 else deck(half) - 0.6 - abs(za - zb)
        for s in (-1, 1):
            px_, py_ = x - uy * s * (W_ / 2 + 0.1), y + ux * s * (W_ / 2 + 0.1)
            box(wood, px_, py_, z0, 0.25, 0.25, deck(t) + 1.1 - z0)
    hole = 0.0
    for s in (-1, 1):
        ts = np.linspace(-half + 0.5, half - 0.5, 9)
        for t0, t1 in zip(ts, ts[1:]):
            if rickety and s > 0 and abs((t0 + t1) / 2) < 2.5:
                hole = max(hole, abs(t0), abs(t1))
                continue                                                  # пролом в перилах
            tm = (t0 + t1) / 2
            x, y = qx + ux * tm, qy + uy * tm
            px_, py_ = x - uy * (W_ / 2 + 0.1) * s, y + ux * (W_ / 2 + 0.1) * s
            box(wood, px_, py_, deck(tm) + 0.85, t1 - t0, 0.12, 0.12, axis)
    if hole:
        box(collider, qx - uy * (W_ / 2 + 0.1), qy + ux * (W_ / 2 + 0.1), deck(0.0) - 0.3, 2 * hole, 0.2, 2.0, axis)


def bridges(col, h):
    """Мосты (по концепту): главный — каменный вариант C, старый и ветхий — деревянные, к воротам Рубежа —
    каменный арочный через рукав озера. Геометрия — bridge_plan(), берега и подводка дорог — bridge_banks()."""
    lib_b = bridge_lib()
    tmp = bpy.data.collections.new("Мосты: детали")
    bpy.context.scene.collection.children.link(tmp)
    keys = {key: bpy.data.materials.new("bridge_" + key) for key in BRIDGE_COLORS}
    merged = {}
    wood, planks, collider = bmesh.new(), bmesh.new(), bmesh.new()
    rng = random.Random(5)
    for br in bridge_plan():
        if br["kind"] == "stone":
            stone_bridge_c(lib_b, tmp, keys, br, merged)
        elif br["kind"] == "wood":
            wooden_bridge(wood, planks, collider, br, rng)
        elif br["kind"] == "rickety":
            wooden_bridge(wood, planks, collider, br, rng, rickety=True)
        else:
            e = br["ends"][0]
            toe = (e["E"][0] + e["out"][0] * BRIDGE_TOE, e["E"][1] + e["out"][1] * BRIDGE_TOE)
            causeway(lib_b, tmp, keys, br["gate"], toe, WALL_Z0 + 0.2, e["z"] - 0.1, LAKE_Z, merged, 6.0)
    bpy.data.collections.remove(tmp)
    for m in keys.values():
        bpy.data.materials.remove(m)
    for key, bm in merged.items():
        finish_mesh(col, "Bridge_" + key, bm, BRIDGE_COLORS[key])
    finish_mesh(col, "BridgesWood", wood, (0.46, 0.33, 0.20))
    finish_mesh(col, "BridgesPlanks", planks, (0.46, 0.33, 0.20))
    finish_mesh(col, "BridgesDeck-colonly", collider, (0.46, 0.33, 0.20))
    write_bridges_json()


def write_water_json():
    """Гладь воды для scripts/levels/deep_water.gd (где Рэй тонет), в метрах Godot (x, z). Границы — как у water_meshes."""
    import json
    rp = [P(x, y) for x, y, w in W["RIVER"]]
    n = len(rp)
    river = []
    for k, ((x, y), (_, _, w)) in enumerate(zip(rp, W["RIVER"])):
        level = LAKE_Z + (RIVER_END_Z - LAKE_Z) * (k / (n - 1)) ** 0.8
        river.append([round(x, 2), round(-y, 2), round(level - 0.5, 3), w / 2 + 1.5])
    ponds = []
    for x, y, r in W["PONDS"]:
        cx, cy = P(x, y)
        ponds.append([round(cx, 2), round(-cy, 2), r, round(POND_Z[(x, y)], 3)])
    data = {"lake_z": LAKE_Z, "lake": [[round(x, 2), round(-y, 2)] for x, y in PL(W["LAKE"])], "river": river, "ponds": ponds}
    with open(os.path.join(os.path.dirname(NATURE_JSON), "world_water.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))


def write_bridges_json():
    """Маршруты для теста Tools/godot/tests/world_bridges_test.gd: дорога — настил — дорога, в метрах Godot (x, z)."""
    import json
    out = []

    def gd(p):
        return [round(p[0], 2), round(-p[1], 2)]
    for br in bridge_plan():
        ends = br["ends"]
        road = [[gd(p) for p in reversed(e["line"][1::3])] for e in ends]
        if br["kind"] == "gate":
            e = ends[0]
            far = (br["gate"][0] + e["out"][0] * 8.0, br["gate"][1] + e["out"][1] * 8.0)
            out.append({"name": br["name"], "water": br["surf"], "a": road[0], "deck": [gd(e["E"]), gd(far)], "b": []})
        else:
            out.append({"name": br["name"], "water": br["surf"], "a": road[0], "deck": [gd(ends[0]["E"]), gd(ends[1]["E"])],
                        "b": road[1][::-1]})
    with open(os.path.join(os.path.dirname(NATURE_JSON), "world_bridges.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=0)


def rotated_box(bm, cx, cy, cz, w, d, hgt, rot_y=0.0, rot_z=0.0):
    """Короб с центром (cx, cy, cz), повёрнутый вокруг Y (крылья мельницы), затем вокруг Z."""
    g = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(w, d, hgt), verts=g["verts"])
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Rotation(rot_z, 4, "Z") @ Matrix.Rotation(rot_y, 4, "Y")
    bmesh.ops.transform(bm, matrix=m, verts=g["verts"])


def fence(bm, pts, h, gap_at=None, closed=True):
    """Изгородь по рельефу: столбы через 2 м и две жерди; gap_at — точка, где оставить проход 3 м."""
    n = len(pts)
    for k in range(n if closed else n - 1):
        (ax, ay), (bx, by) = pts[k], pts[(k + 1) % n]
        L = math.hypot(bx - ax, by - ay)
        rot = math.atan2(by - ay, bx - ax)
        steps = max(1, int(L / 2.0))
        for i in range(steps):
            t0, t1 = i / steps, (i + 1) / steps
            x0, y0 = ax + (bx - ax) * t0, ay + (by - ay) * t0
            x1, y1 = ax + (bx - ax) * t1, ay + (by - ay) * t1
            mx, my = (x0 + x1) / 2, (y0 + y1) / 2
            if gap_at and math.hypot(mx - gap_at[0], my - gap_at[1]) < 1.6:
                continue
            if ROAD_LINES and road_clear(mx, my) < 0.6:  # дорога/тропа/улица через изгородь — проход
                continue
            z0, z1 = sample(h, x0, y0), sample(h, x1, y1)
            box(bm, x0, y0, z0 - 0.3, 0.16, 0.16, 1.5)
            for zz in (0.55, 1.0):
                box(bm, mx, my, (z0 + z1) / 2 + zz, L / steps, 0.08, 0.1, rot)


def _x_box(bm, cx, cy, cz, w, d, hgt, rot_x):
    """Короб с центром (cx, cy, cz), повёрнутый вокруг оси X (лопасти колеса)."""
    g = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(w, d, hgt), verts=g["verts"])
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Rotation(rot_x, 4, "X")
    bmesh.ops.transform(bm, matrix=m, verts=g["verts"])


def plank_wall(bm, a, b, z0, z1, rng, gable=0.0, w=0.3, t=0.12):
    """Стена из вертикальных досок от a до b (x, y): разная высота низа, лёгкий рельеф; gable — высота
    треугольного фронтона над z1 (конёк — посередине)."""
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    rot = math.atan2(b[1] - a[1], b[0] - a[0])
    n = max(1, int(round(L / w)))
    nx, ny = -math.sin(rot), math.cos(rot)
    for i in range(n):
        tt = (i + 0.5) / n
        x, y = a[0] + (b[0] - a[0]) * tt, a[1] + (b[1] - a[1]) * tt
        top = z1 + gable * (1.0 - abs(tt - 0.5) * 2.0)
        lo = z0 - rng.uniform(0.0, 0.12)
        j = rng.uniform(-0.025, 0.025)
        box(bm, x + nx * j, y + ny * j, lo, L / n - 0.025, t, top - lo, rot)


def mill_window(bd, dk, x, y, z, rot, shutters=True):
    """Окно в дощатой стене: тёмный проём, рама, ставни; rot — направление стены (обход против часовой)."""
    nx, ny = math.sin(rot), -math.cos(rot)          # наружу
    cx, cy = x + nx * 0.08, y + ny * 0.08
    box(dk, cx, cy, z, 0.8, 0.04, 0.95, rot)
    ux, uy = math.cos(rot), math.sin(rot)
    for s_ in (-1, 1):
        box(bd, cx + ux * s_ * 0.47, cy + uy * s_ * 0.47, z - 0.05, 0.1, 0.08, 1.05, rot)
        if shutters:
            box(bd, cx + ux * s_ * 0.78 + nx * 0.03, cy + uy * s_ * 0.78 + ny * 0.03, z, 0.48, 0.05, 0.95, rot)
    box(bd, cx, cy, z - 0.12, 1.1, 0.12, 0.1, rot)      # подоконник
    box(bd, cx, cy, z + 0.95, 1.05, 0.1, 0.12, rot)


def watermill(col, kit, tav, wood, stone, thatch, it, h):
    """Водяная мельница Ганса (решение автора 2026-10-27: колесо на реке, недалеко от прежней ветряной;
    референсы автора — дощатая мельница на каменном цоколе, галерея, большое колесо, лоток на козлах).
    Каменный цоколь над откосом берега, два этажа из потемневших досок (MillBoards), угловые столбы и пояса,
    на юге — галерея второго этажа на кронштейнах, черепичная крыша Quaternius, дощатые фронтоны, труба.
    Наливное колесо у восточной стены — отдельный объект MillWheel (начало на оси, Godot его крутит);
    вода — по лотку от каменного шлюза с решёткой (квест «Ларь в решётке шлюза»); с юга — мостки над омутом;
    внутри — тёмный пол и изнанка (MillDark: в «окне» вокруг Рэя не видно пустоты)."""
    rng = random.Random(51)
    m = mill_site(it)
    cx, cy, W_, D_ = it["x"], it["y"], it["w"], it["d"]
    surf, base, xe, R = m["surf"], m["base"], m["xe"], m["R"]
    hx, hy, hz = m["hub"]
    bd, dk = bmesh.new(), bmesh.new()
    x0, x1, y0, y1 = cx - W_ / 2, cx + W_ / 2, cy - D_ / 2, cy + D_ / 2
    zs, zf, zt = base + 0.8, base + 3.0, base + 5.6          # верх цоколя, пол второго этажа, верх стен
    corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]       # обход против часовой: юг, восток, север, запад
    door_y = cy + 1.0
    # Цоколь: от дна до пола (к реке — над откосом), над полом — каменный пояс до zs (у двери — проём).
    box(stone, cx + 0.2, cy, surf - 2.2, W_ + 0.8, D_ + 0.5, base - (surf - 2.2))
    for k in range(4):
        (ax, ay), (bx, by) = corners[k], corners[(k + 1) % 4]
        L = math.hypot(bx - ax, by - ay)
        rot = math.atan2(by - ay, bx - ax)
        cnt = int(L / 0.6)
        for i in range(cnt):
            t = (i + 0.5) / cnt
            px_, py_ = ax + (bx - ax) * t, ay + (by - ay) * t
            if k == 3 and abs(py_ - door_y) < 0.8:
                continue
            box(stone, px_ + math.sin(rot) * 0.08, py_ - math.cos(rot) * 0.08, base - 0.05,
                L / cnt - 0.04, 0.45, zs - base + rng.uniform(-0.08, 0.08), rot)
    for s_ in (-1, 1):
        box(stone, hx, hy + s_ * 3.8, surf - 2.2, 4.6, 0.7, base - 0.4 - (surf - 2.2))   # стенки жёлоба
    # Дощатые стены, фронтоны — на юге и севере (конёк вдоль y).
    for k in range(4):
        plank_wall(bd, corners[k], corners[(k + 1) % 4], zs - 0.1, zt, rng, gable=4.4 if k in (0, 2) else 0.0)
    for x_, y_ in corners:
        box(wood, x_, y_, base, 0.32, 0.32, zt - base + 0.1)                 # угловые столбы
    for k in range(4):
        a, b = corners[k], corners[(k + 1) % 4]
        rot = math.atan2(b[1] - a[1], b[0] - a[0])
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        for z_ in (zs - 0.1, zf - 0.1):
            box(wood, mx + math.sin(rot) * 0.1, my - math.cos(rot) * 0.1, z_, L + 0.3, 0.16, 0.2, rot)   # пояса
        # Изнанка: тёмная обшивка изнутри.
        box(dk, mx - math.sin(rot) * 0.12, my + math.cos(rot) * 0.12, base, L - 0.3, 0.04, zt - base, rot)
    for i in range(int(W_ / 2)):
        for j in range(int(D_ / 2)):
            kit["place"]("Floor_WoodDark", x0 + 1 + 2 * i, y0 + 1 + 2 * j, base + 0.04)
    # Окна и дверь (дверь — на запад, к тропе из деревни).
    for x_, z_ in ((cx - 1.5, base + 1.2), (cx - 1.5, zf + 0.5), (cx + 1.5, zf + 0.5)):
        mill_window(bd, dk, x_, y0, z_, 0.0)
    for y_ in (cy + 2.8, cy - 2.2):
        mill_window(bd, dk, x1, y_, zf + 0.5, math.pi / 2)
    mill_window(bd, dk, cx, y1, zf + 0.5, math.pi, False)
    for y_, z_ in ((cy - 2.6, base + 1.2), (cy - 2.6, zf + 0.5), (cy + 3.0, zf + 0.5)):
        mill_window(bd, dk, x0, y_, z_, -math.pi / 2)
    box(dk, x0 - 0.1, door_y, base, 0.04, 1.2, 2.2)
    for k in range(4):
        box(wood, x0 - 0.13, door_y - 0.45 + k * 0.3, base + 0.02, 0.05, 0.27, 2.1)   # створка из досок
    box(wood, x0 - 0.12, door_y, base + 2.2, 0.16, 1.6, 0.18)
    for s_ in (-1, 1):
        box(wood, x0 - 0.12, door_y + s_ * 0.7, base, 0.16, 0.16, 2.3)
    for k in range(1):                                          # порог
        box(stone, x0 - 0.6 - k * 0.4, door_y, base - 0.2 - k * 0.25, 0.45, 1.6, 0.2)
    # Галерея второго этажа на юге: настил на кронштейнах, перила с балясинами.
    gy = y0 - 0.55
    box(bd, cx, gy, zf - 0.12, W_ + 0.6, 1.1, 0.1)
    for x_ in np.linspace(x0 + 0.3, x1 - 0.3, 4):
        beam(wood, (x_, y0 - 0.05, zf - 1.0), (x_, gy - 0.45, zf - 0.12), 0.07)
        beam(wood, (x_, gy - 0.5, zf - 0.05), (x_, gy - 0.5, zf + 1.0), 0.06)
    box(wood, cx, gy - 0.5, zf + 0.95, W_ + 0.6, 0.1, 0.1)
    for x_ in np.arange(x0 - 0.15, x1 + 0.2, 0.32):
        box(bd, x_, gy - 0.5, zf - 0.02, 0.06, 0.06, 0.95)
    # Крыша Quaternius (черепица, конёк вдоль y; изнанка — тёмная), труба.
    kit["_house_center"] = Vector((cx, cy, (base + zt) / 2))
    kit["place"]("Roof_RoundTiles_%dx%d" % (W_, D_), cx, cy, zt)
    kit["_house_center"] = None
    kit["place"]("Prop_Chimney", cx + 1.5, cy + 3.5, zt + 1.6)
    POINTS.append(("fx-chimney-mill", cx + 1.5, cy + 3.5, zt + 1.6 + 3.18))
    POINTS.append(("poi-mill", x0 - 3.2, cy, base))        # место Ганса — на дворе у двери (к югу — мостки)
    dx, dy = x0 - 1.2, door_y
    POINTS.append(("door-mill", dx - 0.4, dy, base))
    POINTS.append(("fx-mill-wheel", hx, hy, hz))
    # Колесо: два обода, спицы, ступица, 20 лопастей-ковшей. Вершины — вокруг оси (0, 0, 0).
    wb = bmesh.new()
    n = 20
    for sx in (-0.72, 0.72):
        for rr, th in ((R, 0.11), (R - 0.85, 0.08)):
            polyline(wb, [(sx, math.cos(k * math.tau / n) * rr, math.sin(k * math.tau / n) * rr) for k in range(n + 1)], th)
        for k in range(0, n, 2):
            a = k * math.tau / n + 0.1
            beam(wb, (sx, 0, 0), (sx, math.cos(a) * R, math.sin(a) * R), 0.09)
    for k in range(n):
        a = (k + 0.5) * math.tau / n
        r_ = R - 0.42
        _x_box(wb, 0, math.cos(a) * r_, math.sin(a) * r_, 1.44, 0.84, 0.07, a)
    g = bmesh.ops.create_cone(wb, cap_ends=True, segments=10, radius1=0.5, radius2=0.5, depth=1.2)
    bmesh.ops.rotate(wb, verts=g["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"))
    wheel = finish_mesh(col, "MillWheel", wb, (0.36, 0.27, 0.19))
    wheel.location = (hx, hy, hz)
    # Ось — от стены к опорному столбу в реке.
    beam(wood, (xe - 0.1, hy, hz), (hx + 1.6, hy, hz), 0.18, 8)
    beam(wood, (hx + 1.6, hy, surf - 1.8), (hx + 1.6, hy, hz + 0.3), 0.24, 8)
    box(wood, hx + 1.6, hy, hz - 0.2, 0.5, 0.8, 0.35)
    # Лоток: от шлюза на берегу (к северу, выше по течению) — к верху колеса, на козлах с раскосами.
    top = hz + R + 0.35
    ya, yb = y1 + 3.6, hy + 1.0
    box(wood, hx, (ya + yb) / 2, top - 0.1, 1.4, ya - yb, 0.1)
    for s_ in (-1, 1):
        box(wood, hx + s_ * 0.7, (ya + yb) / 2, top - 0.1, 0.08, ya - yb, 0.5)
    for yy in np.arange(yb + 1.5, ya - 0.5, 2.2):
        for s_ in (-1, 1):
            beam(wood, (hx + s_ * 0.75, yy, surf - 1.6), (hx + s_ * 0.75, yy, top - 0.1), 0.1)
        box(wood, hx, yy, top - 0.35, 1.8, 0.18, 0.18)
        beam(wood, (hx - 0.75, yy, surf - 0.6), (hx + 0.75, yy, top - 0.5), 0.05)
    # Шлюз: каменная тумба на берегу, деревянный щит в пазах, кованая решётка.
    box(stone, hx, ya + 0.9, surf - 1.6, 2.2, 1.8, top + 0.3 - (surf - 1.6))
    for s_ in (-1, 1):
        box(wood, hx + s_ * 0.85, ya + 0.05, top - 0.4, 0.22, 0.22, 2.0)
    box(wood, hx, ya + 0.05, top + 1.5, 2.1, 0.26, 0.26)
    box(wood, hx, ya - 0.02, top + 0.05, 1.5, 0.1, 0.7)       # поднятый щит
    for k in range(6):
        box(stone, hx - 0.6 + k * 0.24, ya - 0.25, surf - 1.0, 0.06, 0.06, top - surf + 0.9)   # решётка
    # Вода в лотке и струя на колесо — MillWater (шейдер воды в Godot).
    wa = bmesh.new()
    box(wa, hx, (ya + yb) / 2 + 0.1, top - 0.02, 1.25, ya - yb - 0.2, 0.04)
    box(wa, hx, yb - 0.25, hz + R - 0.6, 1.2, 0.06, top - (hz + R - 0.6), 0.0)
    finish_mesh(col, "MillWater", wa, (0.30, 0.50, 0.60))
    # Мостки над омутом с юга: настил на сваях, перила.
    ys = y0 - 0.2
    for t in np.arange(cx - 1.0, hx + 2.4, 0.55):
        box(wood, t, ys - 1.8, base - 0.12, 0.5, 3.2, 0.1)
    for t in np.arange(cx - 0.6, hx + 2.4, 1.8):
        beam(wood, (t, ys - 3.3, surf - 2.0), (t, ys - 3.3, base + 1.0), 0.09)
    box(wood, (cx - 0.6 + hx + 2.2) / 2, ys - 3.3, base + 0.95, hx + 2.8 - cx, 0.1, 0.1)
    # У двери: жернова (один прислонён к стене), мешки муки, бочка, телега — кроме тех, что встали бы на тропу.
    free = lambda px_, py_, r_: road_clear(px_, py_) > r_
    if free(x0 - 1.8, cy + 3.4, 0.9):
        cyl(stone, x0 - 1.8, cy + 3.4, base - 0.05, 0.85, 0.3, 14)
        cyl(stone, x0 - 1.8, cy + 3.4, base + 0.25, 0.8, 0.3, 14)
    g = bmesh.ops.create_cone(stone, cap_ends=True, segments=14, radius1=0.85, radius2=0.85, depth=0.3)
    bmesh.ops.transform(stone, matrix=Matrix.Translation((x0 - 0.45, cy - 3.0, base + 0.3))
                        @ Matrix.Rotation(math.pi / 2 - 0.2, 4, "Y"), verts=g["verts"])
    for k, (ox, oy) in enumerate(((-0.6, -1.6), (-1.1, -2.2), (-0.5, -2.5), (-0.9, -1.9))):
        if free(dx + ox, dy + oy, 0.4):
            cyl(thatch, dx + ox, dy + oy, base - 0.05 + (0.5 if k == 3 else 0.0), 0.36, 0.62, 8, 0.24)
    if free(dx - 0.6, dy + 1.8, 0.5):
        tav["prop"]("barrel_large", dx - 0.6, dy + 1.8, base - 0.05, 0.4)
    tav["prop"]("crates_stacked", cx - 1.0, y1 + 1.2, base - 0.05, 0.1)
    for wx_, wy_ in ((dx - 4.2, dy - 4.0), (x0 - 2.5, y1 - 1.5), (x0 - 2.5, y0 - 2.5)):
        if free(wx_, wy_, 2.0):
            kit["place"]("Prop_Wagon", wx_, wy_, sample(h, wx_, wy_), 0.5)
            break
    # Зелень (замечание автора): вьюны по стенам, мох на крыше, цоколе и галерее, пряди с настила.
    mm = bmesh.new()
    for vx, vy, vz, rot in ((x0 + 0.9, y0 - 0.09, zt - 0.1, 0.0), (x1 - 0.8, y0 - 0.09, zf - 0.1, 0.0),
                            (x0 - 0.09, y1 - 1.2, zt - 0.1, -math.pi / 2), (x0 - 0.09, cy - 3.6, zf - 0.1, -math.pi / 2),
                            (x1 + 0.09, y1 - 0.9, zt - 0.1, math.pi / 2), (cx + 1.6, y1 + 0.09, zt - 0.1, math.pi)):
        kit["place"](rng.choice(("Prop_Vine1", "Prop_Vine2", "Prop_Vine4", "Prop_Vine5", "Prop_Vine6")), vx, vy, vz, rot)
    for k in range(4):                                          # мох по верху каменного пояса
        (ax, ay), (bx, by) = corners[k], corners[(k + 1) % 4]
        rot = math.atan2(by - ay, bx - ax)
        L = math.hypot(bx - ax, by - ay)
        for t in np.arange(0.1, 0.9, 0.22):
            if rng.random() < 0.6:
                px_, py_ = ax + (bx - ax) * t, ay + (by - ay) * t
                box(mm, px_ + math.sin(rot) * 0.2, py_ - math.cos(rot) * 0.2, zs - 0.06, L * rng.uniform(0.1, 0.2),
                    0.42, 0.1, rot)
    theta = math.atan2(4.4, W_ / 2)
    for side in (-1, 1):                                        # мох на скатах крыши
        for _ in range(16):
            f, yy = rng.uniform(0.05, 0.6), rng.uniform(y0 + 0.4, y1 - 0.4)
            px_ = cx + side * (W_ / 2 + 0.3) * (1.0 - f)
            pz = zt + 4.4 * f + 0.28
            rotated_box(mm, px_, yy, pz, rng.uniform(0.3, 0.8), rng.uniform(0.3, 0.9), 0.06, side * theta,
                        rng.uniform(-0.3, 0.3))
    for x_ in np.arange(x0 - 0.2, x1 + 0.2, 0.45):              # пряди с края галереи
        if rng.random() < 0.55:
            ln = rng.uniform(0.3, 1.1)
            box(mm, x_, gy - 0.56, zf - 0.12 - ln, 0.14, 0.05, ln)
    finish_mesh(col, "MillMoss", mm, (0.30, 0.40, 0.17))
    finish_mesh(col, "MillBoards", bd, (0.40, 0.33, 0.26))
    finish_mesh(col, "MillDark", dk, (0.05, 0.045, 0.04))


def horst_forge(col, kit, tav, wood, stone, it, h):
    """Дом-кузница Хорста — одно здание (черновик утверждён автором 2026-10-27; референс — холст «дома для npc»,
    детали по канону: кузня гарнизона, «Сталь третьей роты»). Фасад — на юг, к площади. Слева — жильё 6×6
    (модули Quaternius 6×8, два этажа: камень внизу, штукатурка наверху, фронтон на улицу, сланец); справа — кузня
    8×6: фахверк сзади и на торце, фасад открыт (столбы на каменных базах с подкосами), её сланцевая крыша
    (конёк вдоль улицы) заходит под скат жилья — без стыков и щелей; на скате — окно-«домик». На стыке сзади —
    каменная труба выше обоих коньков. Внутри — горн с вытяжкой, наковальня на колоде, корыто, верстак,
    стойка с инструментом; снаружи — ящики, короб угля, вывеска. Рэй может войти в открытую кузню."""
    rng = random.Random(77)
    cx, cy = it["x"], it["y"]
    base = sample(h, cx, cy)
    dk = bmesh.new()
    # Жильё (слева): дом из модулей 6×8, два этажа, дверь на улицу.
    kit["build_house"]("smithy", cx - 4.0, cy, base, 6, 8, 2, "slate", "stone", (0, -1), False, False)   # глубже кузни: торец её крыши — внутри
    # Пояс-брус по фасаду и задней стене жилья: закрывает край свеса крыши кузни (он на 0,12 м шире стены).
    for s_ in (-1, 1):
        box(wood, cx - 4.0, cy + s_ * 4.2, base + 2.2, 6.4, 0.34, 0.7)
    # Кузня (справа).
    hx0, hx1, hy0, hy1 = cx - 1.0, cx + 7.0, cy - 3.0, cy + 3.0
    zt = base + 3.0
    box(stone, (hx0 + hx1) / 2, cy, base - 0.15, hx1 - hx0, hy1 - hy0, 0.2)            # пол — плиты
    kit["_house_center"] = Vector(((hx0 + hx1) / 2, cy, base + 1.5))
    for u in (hx0 + 1, hx0 + 3, hx0 + 5, hx0 + 7):                      # стены — на каменном основании (автор)
        kit["place"]("Wall_Plaster_Straight_Base", u, hy1, base, math.pi)
    for v in (hy0 + 1, hy0 + 3, hy0 + 5):
        kit["place"]("Wall_Plaster_Straight_Base", hx1, v, base, math.pi / 2)
    kit["place"]("Corner_Exterior_Wood", hx1, hy1, base)
    # Крыша кузни: 6×10, от x − 3 (внутри крыши жилья, конёк ниже её ската) до торца кузни.
    kit["place"]("Roof_RoundTiles_6x10", cx + 2.0, cy, zt, math.pi / 2, {"MI_RoundTiles": "MI_RoundTiles_slate"})
    kit["place"]("Roof_Front_Brick6", hx1, cy, zt, math.pi / 2 + math.pi)
    kit["_house_center"] = None
    kit["_colliders"].append(((hx0 + hx1) / 2, hy1, base, hx1 - hx0, 0.4, 3.5))
    kit["_colliders"].append((hx1, cy + 0.5, base, 0.4, hy1 - hy0 - 1.0, 3.5))
    # Фасад: столбы на каменных базах, балка, подкосы.
    posts = (hx0 + 0.3, cx + 3.0, hx1 - 0.15)
    for px_ in posts:
        box(stone, px_, hy0, base - 0.1, 0.6, 0.6, 0.7)
        box(wood, px_, hy0, base + 0.55, 0.36, 0.36, zt - base - 0.45)
    box(wood, (hx0 + hx1) / 2, hy0, zt - 0.1, hx1 - hx0 + 0.3, 0.4, 0.35)
    for px_, s_ in ((posts[0], 1), (posts[1], -1), (posts[1], 1), (posts[2], -1)):
        beam(wood, (px_, hy0, zt - 1.1), (px_ + s_ * 0.9, hy0, zt - 0.15), 0.08)
    # Окно-«домик» на переднем скате.
    dx_, dy_, dz_ = cx + 3.4, hy0 + 1.6, zt + 1.3
    box(wood, dx_, dy_, dz_, 1.4, 1.6, 1.4)
    box(dk, dx_, dy_ - 0.81, dz_ + 0.65, 0.75, 0.04, 0.6)
    for s_ in (-1, 1):
        beam(wood, (dx_ + s_ * 0.6, dy_ - 0.85, dz_ + 0.2), (dx_ + s_ * 0.6, dy_ - 1.3, dz_ + 0.05), 0.05)
    box(wood, dx_, dy_ - 1.1, dz_ + 0.15, 1.5, 0.5, 0.06)
    roof(wood, dx_, dy_, dz_ + 1.4, 1.5, 1.8, 0.5, math.pi / 2)
    # Горн у стыка, у задней стены: кладка, угли, вытяжка; огонь.
    fx_, fy_ = hx0 + 1.3, hy1 - 0.95
    box(stone, fx_, fy_, base - 0.05, 1.9, 1.3, 0.95)
    box(dk, fx_, fy_, base + 0.9, 1.4, 0.9, 0.08)
    g = bmesh.ops.create_cone(stone, cap_ends=True, segments=4, radius1=1.3, radius2=0.55, depth=1.3)
    bmesh.ops.transform(stone, matrix=Matrix.Translation((fx_, fy_ + 0.1, base + 2.35)) @ Matrix.Rotation(math.pi / 4, 4, "Z"),
                        verts=g["verts"])
    POINTS.append(("fx-fire-%02d" % len([p for p in POINTS if p[0].startswith("fx-fire")]), fx_, fy_, base + 1.05))
    # Труба на стыке, сзади: выше конька жилья, деревянный навес на стойках.
    # Внизу — широкая кладка очага (прижата к стене), скосы-«плечи», узкий ствол, выступающий венец.
    tx, ty = hx0 + 0.6, hy1 + 0.6
    box(stone, tx, ty, base - 0.1, 2.0, 1.2, 3.3)
    for k in range(4):                                   # плечи — уступами
        box(stone, tx, ty - 0.05 * k, base + 3.2 + k * 0.25, 2.0 - k * 0.3, 1.2 - k * 0.1, 0.27)
    box(stone, tx, ty - 0.15, base + 4.1, 1.0, 0.9, 6.9)
    box(stone, tx, ty - 0.15, base + 10.8, 1.3, 1.2, 0.3)          # венец
    for ox in (-0.4, 0.4):
        for oy in (-0.35, 0.35):
            box(wood, tx + ox, ty - 0.15 + oy, base + 11.1, 0.12, 0.12, 0.65)
    roof(wood, tx, ty - 0.15, base + 11.75, 1.1, 1.0, 0.45)
    POINTS.append(("fx-chimney-smithy", tx, ty - 0.15, base + 11.4))
    # Наковальня на колоде, корыто, верстак, стойка с инструментом.
    ax, ay = cx + 3.0, cy - 0.3
    cyl(wood, ax, ay, base - 0.05, 0.38, 0.62, 10)
    box(dk, ax, ay, base + 0.57, 0.5, 0.28, 0.2)
    box(dk, ax, ay, base + 0.77, 0.85, 0.32, 0.14)
    g = bmesh.ops.create_cone(dk, cap_ends=True, segments=6, radius1=0.12, radius2=0.01, depth=0.42)
    bmesh.ops.transform(dk, matrix=Matrix.Translation((ax + 0.6, ay, base + 0.84)) @ Matrix.Rotation(math.pi / 2, 4, "Y"),
                        verts=g["verts"])
    box(wood, cx + 5.0, cy + 0.6, base - 0.05, 1.5, 0.65, 0.6)            # корыто для закалки
    box(dk, cx + 5.0, cy + 0.6, base + 0.5, 1.3, 0.5, 0.05)
    box(wood, cx + 5.0, hy1 - 0.45, base + 0.85, 2.2, 0.7, 0.08)          # верстак
    for ox in (-1.0, 1.0):
        box(wood, cx + 5.0 + ox, hy1 - 0.45, base - 0.05, 0.1, 0.6, 0.9)
    beam(wood, (cx + 2.2, hy1 - 0.25, base + 2.1), (cx + 3.6, hy1 - 0.25, base + 2.1), 0.05)   # стойка с инструментом
    for k in range(5):
        vx = cx + 2.35 + k * 0.3
        box(dk, vx, hy1 - 0.3, base + 1.25, 0.08 + 0.04 * (k % 2), 0.05, 0.85)
        box(dk, vx, hy1 - 0.3, base + 1.15, 0.22 if k % 3 == 0 else 0.1, 0.06, 0.12)
    tav["prop"]("barrel_large", hx1 - 0.7, cy + 1.6, base - 0.05, 0.3)
    tav["prop"]("sword_shield", cx + 5.6, hy1 - 0.3, base + 0.93, 0.0)
    # Снаружи: ящики, короб угля, вывеска на кронштейне.
    tav["prop"]("crates_stacked", hx1 + 1.3, hy0 - 0.6, base - 0.05, 0.3)
    tav["prop"]("box_stacked", hx1 + 1.1, hy0 + 1.0, base - 0.05, 1.2)
    box(wood, hx1 - 0.6, hy0 - 1.3, base - 0.05, 1.4, 0.9, 0.55)              # короб угля
    for k in range(10):
        rock(dk, hx1 - 1.1 + (k % 5) * 0.25, hy0 - 1.5 + (k // 5) * 0.35, base + 0.45, 0.13, rng, 0.8)
    beam(dk, (hx1 + 0.2, hy0, zt - 0.5), (hx1 + 1.3, hy0, zt - 0.5), 0.04)       # кронштейн
    beam(dk, (hx1 + 0.2, hy0, zt - 1.0), (hx1 + 0.9, hy0, zt - 0.5), 0.03)
    box(wood, hx1 + 1.0, hy0, zt - 1.45, 0.75, 0.06, 0.8)                     # вывеска
    box(dk, hx1 + 1.0, hy0 - 0.04, zt - 1.2, 0.3, 0.02, 0.3)                  # подкова на ней
    woodpile({"wood": wood}, cx - 7.6, cy + 1.0, base - 0.05, math.pi / 2, rng)  # дрова у торца жилья
    POINTS.append(("poi-smithy", cx + 3.0, cy, base))
    POINTS.append(("door-smithy", cx + 3.0, hy0 - 1.2, base))
    POINTS.append(("door-smithy_home", cx - 4.0, cy - 5.2, base))
    finish_mesh(col, "VillageDark", dk, (0.09, 0.085, 0.08))


def hermit_house(kit, tav):
    """KayKit у хижины Клауса (хижина — klaus_hut(), обе — в группе правки «house:hermit»): бочки, меч и щит."""
    x, y, base = klaus_site()
    y0 = y - 2.4
    tav["prop"]("barrel_large", x - 1.8, y0 - 0.95, base - 0.05, 0.3)
    tav["prop"]("barrel_small", x - 2.6, y0 - 1.1, base - 0.05, 1.1)
    tav["prop"]("barrel_small", x + 4.6, y0 + 0.4, base - 0.05, 0.6)
    tav["prop"]("sword_shield_broken", x + 1.75, y0 - 0.4, base - 0.05, 0.0)


VILLAGE_COLORS = {"Wood": (0.45, 0.33, 0.21), "Stone": (0.62, 0.60, 0.56), "Thatch": (0.70, 0.58, 0.32)}


def village(col, h):
    """Деревня: дома из модулей Quaternius (стены, окна, ставни, двери, черепица, трубы, вьюны), мельница,
    кузница, хижина Клауса, колодец с навесом, сушилки, частокол с воротами, изгороди огородов и поля, бочки
    и ящики KayKit у дверей. Каждый дом и каждый пролёт забора — своя группа правки (EditGroup, «Edit_<id>»)."""
    kit = {"__name__": "village_houses", "PROJECT": PROJECT}
    exec(open(os.path.join(PROJECT, "Tools", "blender", "village_houses.py"), encoding="utf-8").read(), kit)
    tav = {"__name__": "kaykit_lib"}
    exec(open(os.path.join(PROJECT, "Tools", "blender", "build_tavern.py"), encoding="utf-8").read(), tav)
    plan = village_plan()
    for it in plan:
        rid, kind, cx, cy = it["rid"], it["kind"], it["x"], it["y"]
        z = sample(h, cx, cy)
        g = EditGroup(col, "house:" + rid, (cx, cy), h, base=it["base"], moved=True, kit=kit, tav=tav)
        wood, stone, thatch = g.bm("Wood"), g.bm("Stone"), g.bm("Thatch")
        if rid == "smithy":
            horst_forge(col, kit, tav, wood, stone, it, h)
        elif kind in ("building", "shed"):
            floors, roof_color, style = HOUSE_STYLE[rid]
            top, ridge, chimney_top, size = kit["build_house"](
                rid, cx, cy, z, it["w"], it["d"], floors, roof_color, style, it["side"],
                rid in CHIMNEYS, rid == "liara")
            POINTS.append(("poi-" + rid, cx, cy, z))
            # Дверь снаружи (на 1,2 м от стены): переходы в дома и место жителя у дома.
            if "door" in it:
                dx, dy = it["door"]
                ddx, ddy = dx + it["side"][0] * 0.8, dy + it["side"][1] * 0.8
                POINTS.append(("door-" + rid, ddx, ddy, sample(h, ddx, ddy)))
            if chimney_top:
                POINTS.append(("fx-chimney-" + rid,) + tuple(chimney_top))
            # Бочки и ящики у дверей мастерских и таверны.
            if rid in ("tavern", "shop", "workshop"):
                dx, dy = it["door"]
                sx, sy = it["side"]
                px_, py_ = dx + sy * 2.2 + sx * 0.8, dy + sx * 2.2 + sy * 0.8
                tav["prop"]("barrel_large", px_, py_, sample(h, px_, py_) - 0.05, 0.3)
                tav["prop"]("crates_stacked", px_ + sy * 1.4, py_ + sx * 1.4, sample(h, px_, py_) - 0.05, 0.8)
                if rid == "tavern":
                    tav["prop"]("keg", dx - sy * 2.4, dy - sx * 2.4, z - 0.05, 0.0)
        elif kind == "watermill":
            watermill(col, kit, tav, wood, stone, thatch, it, h)
        elif kind == "racks":
            for k in range(3):
                px_ = cx + (k - 1) * 2.8
                for s in (-1, 1):
                    box(wood, px_, cy + s * it["d"] / 2.2, sample(h, px_, cy) - 0.3, 0.18, 0.18, 2.6)
                box(wood, px_, cy, sample(h, px_, cy) + 2.2, 0.14, it["d"] / 1.1, 0.14)
                box(thatch, px_, cy, sample(h, px_, cy) + 1.1, 0.5, it["d"] / 1.25, 1.1)   # сено на просушке
        elif kind == "plaza":
            # Колодец: каменный сруб, два столба, навес, ворот.
            cyl(stone, cx, cy, z - 0.3, 1.3, 1.2, 14)
            for s in (-1, 1):
                box(wood, cx + s * 1.05, cy, z, 0.2, 0.2, 2.6)
            box(wood, cx, cy, z + 1.9, 2.2, 0.16, 0.16)
            roof(thatch, cx, cy, z + 2.5, 2.4, 1.6, 0.9, math.pi / 2)
        g.finish(VILLAGE_COLORS, "Village")
    # Хижина Клауса (её берег — мостки, лодка, сети — в pois): сруб, двор и KayKit у стены.
    kx, ky, _ = klaus_site()
    bx_, by_, _ = klaus_site(False)
    g = EditGroup(col, "house:hermit", (kx, ky), h, base=(bx_, by_), moved=True, tav=tav)
    Bh = {k: g.bm(k) for k in list(POI_COLORS) + ["slate"]}
    klaus_hut(Bh, h, random.Random(19))
    hermit_house(kit, tav)
    g.finish(POI_COLORS, "Poi_")
    kit["release"]()
    # Частокол с воротами (рама над проёмом) — одна группа.
    a, b = (P(*p) for p in W["PALISADE"])
    gx, gy = P(*W["PALISADE_GATE"])
    # Сжатие деревни в P() гнёт линию: ворота ставим на прямую частокола (иначе тракт шёл сквозь колья).
    vx_, vy_ = b[0] - a[0], b[1] - a[1]
    t_ = ((gx - a[0]) * vx_ + (gy - a[1]) * vy_) / (vx_ * vx_ + vy_ * vy_)
    gx, gy = a[0] + vx_ * t_, a[1] + vy_ * t_
    g = EditGroup(col, "fence:palisade", (gx, gy), h)
    wood = g.bm("Wood")
    n = int(math.hypot(b[0] - a[0], b[1] - a[1]) / 0.45)
    for i in range(n + 1):
        x = a[0] + (b[0] - a[0]) * i / n
        y = a[1] + (b[1] - a[1]) * i / n
        if math.hypot(x - gx, y - gy) < 3.4:              # проход шире мощёного тракта
            continue
        cyl(wood, x, y, sample(h, x, y) - 0.5, 0.2, 3.4 + 0.3 * math.sin(i * 1.7), 6, 0.04)
    rot = math.atan2(b[1] - a[1], b[0] - a[0])
    for s in (-1, 1):
        px_, py_ = gx + math.cos(rot) * s * 3.4, gy + math.sin(rot) * s * 3.4
        box(wood, px_, py_, sample(h, px_, py_) - 0.5, 0.45, 0.45, 4.6)
    box(wood, gx, gy, sample(h, gx, gy) + 3.7, 7.4, 0.4, 0.4, rot)
    g.finish(VILLAGE_COLORS, "Village")

    def fence_sides(prefix, pts, gap):
        """Изгородь по сторонам многоугольника — каждая сторона своя группа правки."""
        for k in range(len(pts)):
            p0, p1 = pts[k], pts[(k + 1) % len(pts)]
            g = EditGroup(col, "fence:%s_%d" % (prefix, k), ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2), h)
            fence(g.bm("Wood"), [p0, p1], h, gap, closed=False)
            g.finish(VILLAGE_COLORS, "Village")
    # Дворы жилых домов — штакетник с проходом у двери.
    for it in plan:
        y_ = yard(it) if "door" in it else None
        if y_:
            fence_sides("yard_" + it["rid"], y_[0], y_[1])
    # Изгороди: огороды и поле, проход — со стороны деревни.
    for i, poly in enumerate(W["GARDENS"] + W["FIELDS"]):
        pts = PL(poly)
        nearest = min(range(len(pts)), key=lambda k: math.hypot(*pts[k]))
        nxt = pts[(nearest + 1) % len(pts)]
        gap = ((pts[nearest][0] + nxt[0]) / 2, (pts[nearest][1] + nxt[1]) / 2)
        fence_sides("field%d" % i, pts, gap)
    palette_material()


def palette_material():
    """Материал kaykit_palette (детали KayKit) — с картинкой-палитрой, чтобы на рендере сверки был цвет."""
    m = bpy.data.materials.get("kaykit_palette")
    if m is None or m.get("textured"):
        return
    m.use_nodes = True
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "textures", "kaykit",
                                                  "dungeon_texture.png"), check_existing=True)
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    m["textured"] = True


POI_COLORS = {
    "stone": (0.62, 0.61, 0.58), "rock": (0.46, 0.45, 0.42), "wood": (0.46, 0.34, 0.22),
    "oldwood": (0.36, 0.30, 0.24), "dark": (0.05, 0.05, 0.06), "cloth": (0.78, 0.70, 0.52),
    "blue": (0.13, 0.21, 0.46), "gold": (0.88, 0.68, 0.24), "iron": (0.17, 0.17, 0.19),
    "rust": (0.45, 0.25, 0.14), "water": (0.22, 0.46, 0.56), "rune": (0.30, 0.85, 0.80),
    "moss": (0.33, 0.38, 0.20), "thatch": (0.66, 0.55, 0.32), "fur": (0.48, 0.34, 0.22),
}


class Frame:
    """Локальные координаты места: начало (ox, oy), «вперёд» — угол face (радианы, от оси x)."""

    def __init__(self, ox, oy, face):
        self.ox, self.oy, self.f = ox, oy, face

    def at(self, fwd, side):
        c, s = math.cos(self.f), math.sin(self.f)
        return self.ox + c * fwd - s * side, self.oy + s * fwd + c * side


def rock(bm, x, y, z, size, rng, squash=0.8):
    """Скала — сплющенная икосфера со смещёнными вершинами (угловатый камень)."""
    g = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in g["verts"]:
        v.co *= 1.0 + rng.uniform(-0.25, 0.25)
    bmesh.ops.scale(bm, vec=(size * rng.uniform(0.8, 1.3), size * rng.uniform(0.8, 1.3), size * squash),
                    verts=g["verts"])
    bmesh.ops.rotate(bm, verts=g["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(rng.uniform(0, 6.3), 3, "Z"))
    bmesh.ops.translate(bm, vec=(x, y, z), verts=g["verts"])


def beam(bm, a, b, r, seg=6):
    """Брус/бревно от точки a до точки b (3D)."""
    va, vb = Vector(a), Vector(b)
    d = vb - va
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=d.length)
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((va + vb) / 2) @ rot, verts=g["verts"])


def banner(B, x, y, z_top, face, w=2.2, hgt=5.0):
    """Знамя роты (канон): синее полотнище, золотая звезда, древко сверху. face — куда смотрит лицом."""
    nx, ny = math.cos(face), math.sin(face)
    rot = face + math.pi / 2
    box(B["blue"], x, y, z_top - hgt, w, 0.12, hgt, rot)
    box(B["gold"], x + nx * 0.08, y + ny * 0.08, z_top - hgt * 0.45, w * 0.35, 0.06, w * 0.35, rot)   # звезда
    box(B["gold"], x + nx * 0.07, y + ny * 0.07, z_top - hgt * 0.45 - w * 0.12, w * 0.12, 0.06, w * 0.6, rot)
    box(B["wood"], x, y, z_top, w + 0.5, 0.18, 0.18, rot)


def brazier(B, x, y, z):
    cyl(B["stone"], x, y, z - 0.2, 0.55, 1.2, 8)
    cyl(B["iron"], x, y, z + 1.0, 0.75, 0.35, 10, 0.95)
    POINTS.append(("fx-fire-%02d" % len([p for p in POINTS if p[0].startswith("fx-fire")]), x, y, z + 1.4))


def poi_rubezh(B, h, rng):
    """Рубеж по референсу (детали — по канону): утёсы вокруг полуострова, решётка в воротах, предмостная
    башня у берега, знамёна роты на стенах и башнях, жаровни у ворот и на мосту, мостки у воды."""
    F = W["FORTRESS"]
    walls = PL(F["walls"])
    cxw = sum(p[0] for p in walls) / len(walls)
    cyw = sum(p[1] for p in walls) / len(walls)
    gate = P(*F["gate"])
    # Утёсы: скалы вдоль стен снаружи, от воды до подножия стен.
    for k in range(len(walls)):
        (ax, ay), (bx, by) = walls[k], walls[(k + 1) % len(walls)]
        L = math.hypot(bx - ax, by - ay)
        for t in np.arange(0, L, 5.0):
            x, y = ax + (bx - ax) * t / L, ay + (by - ay) * t / L
            ox, oy = x - cxw, y - cyw
            r = math.hypot(ox, oy) or 1
            d = rng.uniform(4.0, 10.0)
            px_, py_ = x + ox / r * d, y + oy / r * d
            if math.hypot(px_ - gate[0], py_ - gate[1]) < 9:
                continue
            rock(B["rock"], px_, py_, LAKE_Z + rng.uniform(0.5, 4.0), rng.uniform(3.0, 6.0), rng, 1.1)
    # Решётка в воротах (ячейка 0,5 м), жаровни по сторонам.
    seg = min(range(len(walls)), key=lambda k: seg_point_dist(walls[k], walls[(k + 1) % len(walls)], gate))
    (ax, ay), (bx, by) = walls[seg], walls[(seg + 1) % len(walls)]
    rot = math.atan2(by - ay, bx - ax)
    ux, uy = math.cos(rot), math.sin(rot)
    out = (gate[0] - cxw, gate[1] - cyw)
    on = math.hypot(*out) or 1
    nx, ny = out[0] / on, out[1] / on
    gx, gy = gate[0] + nx * 1.8, gate[1] + ny * 1.8
    for s in np.arange(-3.5, 3.6, 0.7):
        box(B["iron"], gx + ux * s, gy + uy * s, WALL_Z0, 0.12, 0.12, 6.2, rot)
    for zz in np.arange(WALL_Z0 + 0.6, WALL_Z0 + 6.2, 0.9):
        box(B["iron"], gx, gy, zz, 7.4, 0.12, 0.12, rot)
    for s in (-1, 1):
        brazier(B, gate[0] + nx * 4 + ux * s * 5.5, gate[1] + ny * 4 + uy * s * 5.5, WALL_Z0)
        banner(B, gate[0] + nx * 1.9 + ux * s * 3.0, gate[1] + ny * 1.9 + uy * s * 3.0, WALL_Z0 + WALL_H - 0.6,
               math.atan2(ny, nx), 2.0, 6.0)
    # Знамёна по внешним стенам (через ~28 м) и на круглых башнях.
    for k in range(len(walls)):
        (ax, ay), (bx, by) = walls[k], walls[(k + 1) % len(walls)]
        L = math.hypot(bx - ax, by - ay)
        mx, my = (ax + bx) / 2, (ay + by) / 2
        ox, oy = mx - cxw, my - cyw
        face = math.atan2(oy, ox)
        n_ = (math.cos(face), math.sin(face))
        for t in np.arange(14.0, L - 10.0, 28.0):
            x, y = ax + (bx - ax) * t / L, ay + (by - ay) * t / L
            if math.hypot(x - gate[0], y - gate[1]) < 14:
                continue
            banner(B, x + n_[0] * (WALL_T / 2 + 0.15), y + n_[1] * (WALL_T / 2 + 0.15), WALL_Z0 + WALL_H - 0.8, face)
    # Предмостная башня у берега: квадратная, с аркой проезда, зубцы, жаровни.
    bank = P(*next(b[1] for b in W["BRIDGES"] if b[0] == "Мост к воротам Рубежа"))
    brot = math.atan2(gate[1] - bank[1], gate[0] - bank[0])
    bz = sample(h, *bank)
    bux, buy = math.cos(brot), math.sin(brot)
    for s in (-1, 1):
        px_, py_ = bank[0] - buy * s * 4.0, bank[1] + bux * s * 4.0
        box(B["stone"], px_, py_, bz - 1.0, 6.0, 2.6, 11.0, brot)
        # Жаровни — по бокам башни: прямо перед ней проходит тропа к шахте.
        fx_, fy_ = bank[0] - bux * 1.5 - buy * s * 6.8, bank[1] - buy * 1.5 + bux * s * 6.8
        brazier(B, fx_, fy_, sample(h, fx_, fy_))
    box(B["stone"], bank[0], bank[1], bz + 6.5, 6.0, 10.6, 4.5, brot)
    for s in (-1, 1):
        merlons(B["stone"], bank[0] - bux * 3 + (-buy) * s * 5.3, bank[1] - buy * 3 + bux * s * 5.3,
                bank[0] + bux * 3 + (-buy) * s * 5.3, bank[1] + buy * 3 + bux * s * 5.3, bz + 11.0, 0.8)
    roof(B["slate"], bank[0], bank[1], bz + 11.0, 6.0, 10.6, 4.0, brot)
    banner(B, bank[0] - bux * 3.2, bank[1] - buy * 3.2, bz + 10.5, brot + math.pi, 2.0, 5.0)
    # Мостки у воды под стеной (лодки гарнизона).
    sx, sy = gate[0] + nx * 10 + ux * 18, gate[1] + ny * 10 + uy * 18
    box(B["wood"], sx, sy, LAKE_Z + 0.3, 10.0, 2.4, 0.3, rot)
    for t in (-4.5, 0, 4.5):
        for s in (-1, 1):
            beam(B["wood"], (sx + ux * t - nx * s * 1.1, sy + uy * t - ny * s * 1.1, LAKE_Z - 1.5),
                 (sx + ux * t - nx * s * 1.1, sy + uy * t - ny * s * 1.1, LAKE_Z + 0.9), 0.12)


def seg_point_dist(a, b, p):
    vx, vy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * vx + (p[1] - a[1]) * vy) / (vx * vx + vy * vy)))
    return math.hypot(p[0] - a[0] - vx * t, p[1] - a[1] - vy * t)


def poi_mine(B, h, cx, cy, rng):
    """Заброшенная шахта: крепь из брёвен в скале, тьма штольни, рельсы, ржавая вагонетка, фонарь на цепи,
    рваное знамя, эстакады по склону, ящики и бочки."""
    fr = Frame(cx + 6.0, cy, 0.0)        # лицом на восток, спиной в гору
    z = sample(h, *fr.at(4, 0))
    # Скала над входом.
    for k in range(9):
        x, y = fr.at(rng.uniform(-6, -1), rng.uniform(-9, 9))
        rock(B["rock"], x, y, z + rng.uniform(2, 7), rng.uniform(3, 5), rng, 1.2)
    # Крепь: стойки, верхняк, подкосы.
    for side in (-2.2, 2.2):
        beam(B["oldwood"], fr.at(0, side) + (z - 0.3,), fr.at(0, side * 1.05) + (z + 4.2,), 0.28)
        beam(B["oldwood"], fr.at(1.5, side * 1.6) + (z - 0.2,), fr.at(0.2, side) + (z + 3.0,), 0.16)
    beam(B["oldwood"], fr.at(0, -3.0) + (z + 4.2,), fr.at(0, 3.0) + (z + 4.2,), 0.3)
    beam(B["oldwood"], fr.at(0.4, -2.8) + (z + 4.8,), fr.at(0.4, 2.8) + (z + 4.8,), 0.22)
    box(B["dark"], *fr.at(-0.6, 0), z - 0.2, 0.5, 4.2, 4.2, fr.f)
    # Рельсы из штольни и вагонетка.
    for side in (-0.6, 0.6):
        beam(B["rust"], fr.at(-0.5, side) + (z + 0.12,), fr.at(16, side + 1.2) + (z + 0.12,), 0.06, 4)
    for t in np.arange(0, 16, 0.9):
        x, y = fr.at(t, t * 0.075)
        box(B["oldwood"], x, y, z, 0.3, 1.8, 0.12, fr.f + 0.075)
    cx_, cy_ = fr.at(11.0, -3.6)                  # в стороне от конца тропы: она приходит к рельсам у fr.at(6, -3)
    box(B["rust"], cx_, cy_, z + 0.2, 2.2, 1.4, 1.1, fr.f + 0.4)
    for s in (-1, 1):
        for t in (-0.7, 0.7):
            x, y = cx_ + math.cos(fr.f + 0.4) * t, cy_ + math.sin(fr.f + 0.4) * t
            cyl(B["iron"], x - math.sin(fr.f) * s * 0.75, y + math.cos(fr.f) * s * 0.75, z, 0.35, 0.15, 8)
    # Фонарь на цепи и знамя с кирками (рваное — ниже край).
    lx, ly = fr.at(0.6, -2.6)
    box(B["iron"], lx, ly, z + 3.0, 0.4, 0.4, 0.6, fr.f)
    POINTS.append(("fx-lantern-mine", lx, ly, z + 3.3))
    bx, by = fr.at(0.4, 3.4)
    box(B["cloth"], bx, by, z + 1.4, 1.4, 0.08, 2.6, fr.f + math.pi / 2)
    box(B["dark"], bx + 0.05, by, z + 2.3, 0.9, 0.06, 0.12, fr.f + math.pi / 2 + 0.7)
    box(B["dark"], bx + 0.05, by, z + 2.3, 0.9, 0.06, 0.12, fr.f + math.pi / 2 - 0.7)
    # Эстакады вверх по склону к северу.
    prev = None
    for k in range(7):
        x, y = fr.at(-2 - k * 3.5, 12 + k * 6)
        zt = sample(h, x, y) + 3.0
        for s in (-1, 1):
            beam(B["oldwood"], (x + s * 1.2, y, sample(h, x + s * 1.2, y) - 0.5), (x + s * 0.6, y, zt), 0.18)
        if prev:
            for s in (-0.7, 0.7):
                beam(B["oldwood"], (prev[0] + s, prev[1], prev[2]), (x + s, y, zt), 0.14)
        prev = (x, y, zt)
    # Ящики и бочки у входа.
    for k in range(4):
        x, y = fr.at(rng.uniform(2, 8), rng.uniform(3, 6))
        box(B["wood"], x, y, z, 1.0, 1.0, 1.0, rng.uniform(0, 1))
    cyl(B["wood"], *fr.at(3, 4.2), z, 0.5, 1.1, 10)


def poi_cave(B, h, cx, cy, rng, glow=True):
    """Пещера: проход в скале, по бокам плиты с рунами (свечение — точкой fx-cave для Godot), обвал камней."""
    fr = Frame(cx + 8.0, cy, 0.0)
    z = sample(h, *fr.at(4, 0))
    for k in range(14):
        side = rng.choice((-1, 1))
        x, y = fr.at(rng.uniform(-6, 2), side * rng.uniform(4, 10))
        rock(B["rock"], x, y, z + rng.uniform(1, 6), rng.uniform(3, 5.5), rng, 1.3)
    for k in range(4):
        x, y = fr.at(rng.uniform(-5, -2), rng.uniform(-4, 4))
        rock(B["rock"], x, y, z + 7.5 + rng.uniform(0, 2), 4.5, rng, 0.9)
    box(B["dark"], *fr.at(-1.5, 0), z - 0.3, 0.6, 5.0, 5.5, fr.f)
    for side in (-1, 1):
        sx, sy = fr.at(0.3, side * 3.4)
        box(B["stone"], sx, sy, z - 0.3, 0.9, 1.7, 5.5, fr.f + side * 0.12)
        if glow:
            for k in range(3):
                rx, ry = fr.at(0.8, side * 3.4)
                box(B["rune"], rx, ry, z + 1.2 + k * 1.3, 0.05, 0.7, 0.7, fr.f)
    for k in range(10):
        x, y = fr.at(rng.uniform(1, 7), rng.uniform(-3, 3))
        rock(B["rock"], x, y, z, rng.uniform(0.5, 1.3), rng, 0.8)
    if glow:
        POINTS.append(("fx-cave-%02d" % len([p for p in POINTS if p[0].startswith("fx-cave")]),
                       *fr.at(-1.0, 0), z + 1.5))


def poi_gorge(B, h, cx, cy, rng):
    """Ущелье: водопад с гор (полоса воды по склону) и чаша внизу, мокрые камни."""
    fr = Frame(cx + 2.0, cy, 0.0)
    z = sample(h, *fr.at(6, 0))
    x0, y0 = fr.at(-4, 0)
    top = sample(h, *fr.at(-14, 0)) + 4
    box(B["water"], x0, y0, z, 0.4, 4.5, top - z, fr.f)
    g = bmesh.ops.create_circle(B["water"], cap_ends=True, segments=14, radius=5.0)
    bmesh.ops.translate(B["water"], vec=(*fr.at(1.5, 0), z + 0.05), verts=g["verts"])
    for k in range(16):
        a = k / 16 * math.tau
        x, y = fr.at(1.5 + math.cos(a) * 5.8, math.sin(a) * 5.8)
        rock(B["rock"], x, y, z, rng.uniform(0.8, 1.8), rng, 0.7)
    for side in (-1, 1):
        for k in range(5):
            x, y = fr.at(-6 + k * 1.5, side * rng.uniform(4, 7))
            rock(B["rock"], x, y, z + 4 + k, rng.uniform(3, 5), rng, 1.4)
    POINTS.append(("fx-waterfall", x0, y0, z))


def poi_cemetery(B, h, cx, cy, rng):
    """Старое кладбище: надгробия, кресты, обелиски, кованая ограда с воротами, полуразрушенная часовня-склеп
    на северном краю, дорожка от ворот к часовне."""
    R = 48.0
    gate_a = math.radians(-60)        # ворота на юго-востоке — к дороге из деревни
    # Ограда.
    n = 120
    for k in range(n):
        a0, a1 = k / n * math.tau, (k + 1) / n * math.tau
        if abs((a0 - gate_a + math.pi) % math.tau - math.pi) < 0.06:
            continue
        x0_, y0_ = cx + math.cos(a0) * R, cy + math.sin(a0) * R
        x1_, y1_ = cx + math.cos(a1) * R, cy + math.sin(a1) * R
        z0_ = sample(h, x0_, y0_)
        if rng.random() < 0.08:
            continue                     # провалы в ограде
        box(B["iron"], x0_, y0_, z0_ - 0.3, 0.1, 0.1, 2.0)
        box(B["iron"], (x0_ + x1_) / 2, (y0_ + y1_) / 2, z0_ + 1.4, math.hypot(x1_ - x0_, y1_ - y0_), 0.06, 0.06,
            math.atan2(y1_ - y0_, x1_ - x0_))
    gx, gy = cx + math.cos(gate_a) * R, cy + math.sin(gate_a) * R
    for s in (-1, 1):
        px_, py_ = gx - math.sin(gate_a) * s * 2.2, gy + math.cos(gate_a) * s * 2.2
        box(B["stone"], px_, py_, sample(h, px_, py_) - 0.3, 0.8, 0.8, 3.0)
    # Часовня-склеп: стены с проломами, стрельчатый портал, без кровли сзади.
    chx, chy = cx, cy + 32
    cz = sample(h, chx, chy)
    for (dx, dy, w_, d_, hh) in [(-4.5, 0, 0.8, 12, 7), (4.5, 0, 0.8, 12, 5), (0, 6, 9.8, 0.8, 9),
                                 (-3.2, -6, 3.4, 0.8, 8), (3.2, -6, 3.4, 0.8, 8), (0, -6, 3.0, 0.8, 2.0)]:
        box(B["stone"], chx + dx, chy + dy, cz - 0.3, w_, d_, hh)
    box(B["stone"], chx, chy - 6, cz + 5.0, 3.0, 0.8, 3.5)              # над порталом
    roof(B["stone"], chx, chy - 6, cz + 8.0, 9.8, 0.8, 3.0, math.pi / 2)  # фронтон
    box(B["stone"], chx, chy - 6, cz + 11.0, 0.3, 0.3, 1.6)               # крест на фронтоне
    box(B["stone"], chx, chy - 6, cz + 11.9, 1.0, 0.3, 0.3)
    roof(B["slate"], chx, chy - 2, cz + 7.0, 9.6, 4.0, 2.6)
    box(B["dark"], chx, chy - 6.45, cz - 0.3, 2.0, 0.1, 3.8)
    for k in range(6):
        rock(B["stone"], chx + rng.uniform(-6, 6), chy + rng.uniform(-8, 8), cz, rng.uniform(0.4, 0.9), rng, 0.6)
    # Надгробия рядами с кривизной.
    for gy_ in np.arange(cy - R + 8, cy + R - 18, 5.5):
        for gx_ in np.arange(cx - R + 8, cx + R - 8, 4.2):
            x, y = gx_ + rng.uniform(-0.6, 0.6), gy_ + rng.uniform(-0.6, 0.6)
            if math.hypot(x - cx, y - cy) > R - 4 or abs(x - cx) < 2.2 or rng.random() < 0.45:
                continue
            z = sample(h, x, y) - 0.2
            tilt = rng.uniform(-0.25, 0.25)
            kind = rng.random()
            if kind < 0.5:
                box(B["rock"], x, y, z, 0.9, 0.25, 1.1 + rng.uniform(0, 0.4), tilt)
            elif kind < 0.8:
                box(B["rock"], x, y, z, 0.22, 0.22, 1.7, tilt)
                box(B["rock"], x, y, z + 1.15, 0.9, 0.22, 0.22, tilt)
            else:
                cyl(B["rock"], x, y, z, 0.35, 2.4, 4, 0.08)
            if rng.random() < 0.3:
                box(B["rock"], x, y - 1.0, z, 0.9, 1.6, 0.25, tilt)   # плита могилы
    POINTS.append(("fx-fog-cemetery", cx, cy, sample(h, cx, cy)))


def taper(bm, a, b, r1, r2, seg=8):
    """Сужающийся сегмент (ствол, ветви, корни) от точки a (радиус r1) до b (r2)."""
    va, vb = Vector(a), Vector(b)
    d = vb - va
    g = bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r1, radius2=r2, depth=d.length)
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((va + vb) / 2) @ rot, verts=g["verts"])


def stone_willow(B, x, y, z, rng):
    """Каменная ива святилища (CANON; референс автора 2026-10-27): груда каменных блоков, по ним — корни,
    толстый витой ствол из камня, четыре корявые ветви, с них до земли свисают пряди мха; у подножия —
    две стрельчатые ниши. Ствол и корни — Poi_rock (с коллизией), мох — Poi_moss (без)."""
    # Груда блоков под корнями.
    for _ in range(26):
        a, r = rng.uniform(0, math.tau), 1.2 + 2.2 * math.sqrt(rng.random())
        s_ = rng.uniform(0.45, 1.0)
        bx, by = x + math.cos(a) * r, y + math.sin(a) * r * 0.85
        box(B["stone"], bx, by, z - 0.25 - (0.45 if r > 2.7 else 0.0), s_, s_ * rng.uniform(0.8, 1.2),
            s_ * rng.uniform(0.6, 1.0), rng.uniform(0, 1.5))
    # Ствол: широкое основание, витой подъём, сужение к развилке.
    taper(B["rock"], (x, y, z - 0.2), (x, y, z + 1.3), 2.3, 1.45, 12)
    pts = [(x, y, z + 1.2)]
    for k in range(1, 5):
        pts.append((x + math.sin(k * 1.3) * 0.3, y + math.cos(k * 1.1) * 0.22, z + 1.2 + k * 0.85))
    for k in range(4):
        taper(B["rock"], pts[k], pts[k + 1], 1.45 - k * 0.15, 1.45 - (k + 1) * 0.15, 12)
    for k in range(6):                                          # витые жилы по стволу
        a = k / 6 * math.tau
        taper(B["rock"], (x + math.cos(a) * 1.5, y + math.sin(a) * 1.5, z + 0.4),
              (x + math.cos(a + 0.7) * 0.85, y + math.sin(a + 0.7) * 0.85, z + 4.2), 0.32, 0.18, 6)
    fork = pts[-1]
    # Ветви: витые, расходятся вверх и в стороны, концы — вниз; с них свисают пряди мха.
    limbs = []
    for a in (0.5, 2.0, 3.5, 5.0):
        a += rng.uniform(-0.25, 0.25)
        ca, sa = math.cos(a), math.sin(a)
        p1 = (fork[0] + ca * 1.6, fork[1] + sa * 1.6, fork[2] + 1.2)
        p2 = (fork[0] + ca * 3.3 + rng.uniform(-0.3, 0.3), fork[1] + sa * 3.3, fork[2] + 1.9)
        p3 = (fork[0] + ca * 4.8, fork[1] + sa * 4.8, fork[2] + 1.4)
        p4 = (fork[0] + ca * 5.5, fork[1] + sa * 5.5, fork[2] + 0.4)
        taper(B["rock"], fork, p1, 0.7, 0.5, 8)
        taper(B["rock"], p1, p2, 0.5, 0.3, 7)
        taper(B["rock"], p2, p3, 0.3, 0.17, 6)
        taper(B["rock"], p3, p4, 0.17, 0.08, 6)
        # Боковая ветвь от середины.
        b_ = a + rng.choice((-0.8, 0.8))
        q = (p1[0] + math.cos(b_) * 1.9, p1[1] + math.sin(b_) * 1.9, p1[2] + 1.3)
        taper(B["rock"], p1, q, 0.2, 0.08, 6)
        limbs += [(p1, p2), (p2, p3), (p3, p4), (p1, q)]
    taper(B["rock"], fork, (fork[0] + 0.2, fork[1] - 0.1, fork[2] + 2.8), 0.4, 0.1, 7)     # верхушка
    for a_, b_ in limbs:
        L = math.dist(a_, b_)
        for t in np.arange(0.15, 1.0, 0.28 / max(L, 0.5)):
            px_, py_, pz_ = (a_[i] + (b_[i] - a_[i]) * t for i in range(3))
            for _ in range(2):
                ln = rng.uniform(1.2, 3.6)
                box(B["moss"], px_ + rng.uniform(-0.2, 0.2), py_ + rng.uniform(-0.2, 0.2), pz_ - ln,
                    rng.uniform(0.18, 0.3), 0.08, ln + 0.1, rng.uniform(0, 3.1))
    # Корни: от основания по блокам вниз, со ступеней.
    for k in range(12):
        a = k / 12 * math.tau + rng.uniform(-0.15, 0.15)
        ca, sa = math.cos(a), math.sin(a)
        rp = [(x + ca * 0.9, y + sa * 0.9, z + 1.1), (x + ca * 1.7, y + sa * 1.6, z + 0.55),
              (x + ca * 2.6 + sa * 0.3, y + sa * 2.4 - ca * 0.3, z + 0.35), (x + ca * 3.5, y + sa * 3.1, z - 0.15),
              (x + ca * 4.3, y + sa * 3.7, z - 0.7)]
        for i in range(4):
            taper(B["rock"], rp[i], rp[i + 1], 0.32 - i * 0.06, 0.26 - i * 0.06, 6)
    # Стрельчатые ниши у подножия (по сторонам, к камере — к югу).
    for a in (-0.75, -2.4):
        nx_, ny_ = x + math.cos(a) * 1.45, y + math.sin(a) * 1.45
        rot = a + math.pi / 2
        box(B["stone"], nx_, ny_, z + 0.2, 0.75, 0.35, 1.6, rot)
        box(B["dark"], nx_ + math.cos(a) * 0.18, ny_ + math.sin(a) * 0.18, z + 0.45, 0.4, 0.04, 1.05, rot)
        for s_ in (-1, 1):
            g = bmesh.ops.create_cube(B["stone"], size=1.0)
            bmesh.ops.scale(B["stone"], vec=(0.5, 0.33, 0.12), verts=g["verts"])
            m_ = (Matrix.Translation((nx_ + math.cos(rot) * s_ * 0.17, ny_ + math.sin(rot) * s_ * 0.17, z + 1.95))
                  @ Matrix.Rotation(rot, 4, "Z") @ Matrix.Rotation(-s_ * 0.9, 4, "Y"))
            bmesh.ops.transform(B["stone"], matrix=m_, verts=g["verts"])


def poi_shrine(B, h, cx, cy, rng):
    """Лесное святилище: ступенчатый постамент, на нём каменная ива (вместо монолита — решение автора
    2026-10-27), круг стоячих камней с рунами, чаши с огнём, чистый пруд с каскадом, каменная арка."""
    z = sample(h, cx, cy)
    for k, (w_, hh) in enumerate([(14, 0.5), (10, 0.5), (7, 0.5)]):
        box(B["stone"], cx, cy + 3, z - 0.3 + k * 0.5, w_, w_ * 0.8, hh + 0.3)
    mz = z + 1.2
    stone_willow(B, cx, cy + 3, z + 1.5, rng)
    for side in (-1, 1):
        brazier(B, cx + side * 4.2, cy - 1.5, z + 0.7)
    for k in range(9):
        a = k / 9 * math.tau + 0.3
        x, y = cx + math.cos(a) * 14, cy + 3 + math.sin(a) * 14
        if -0.9 < a - 3 * math.pi / 2 < 0.9:
            continue
        hh = rng.uniform(3, 5.5)
        if road_clear(x, y) < 1.2:                   # тропа входит в круг: камень не на ней
            continue
        zz = sample(h, x, y) - 0.4
        box(B["stone"], x, y, zz, 1.3, 0.9, hh, a + math.pi / 2)
        box(B["gold"], x - math.cos(a) * 0.47, y - math.sin(a) * 0.47, zz + hh * 0.5, 0.45, 0.05, 1.0,
            a + math.pi / 2)
    # Пруд перед постаментом, каскад камней, арка.
    px_, py_ = cx, cy - 12
    g = bmesh.ops.create_circle(B["water"], cap_ends=True, segments=18, radius=6.5)
    bmesh.ops.translate(B["water"], vec=(px_, py_, sample(h, px_, py_) + 0.15), verts=g["verts"])
    for k in range(20):
        a = k / 20 * math.tau
        rock(B["rock"], px_ + math.cos(a) * 7.0, py_ + math.sin(a) * 7.0, z - 0.4, rng.uniform(0.7, 1.4), rng, 0.6)
    for k in range(3):
        rock(B["rock"], px_ + 9 + k * 1.6, py_ + 2 + k, z + k * 0.6, 1.4, rng, 0.8)
    arch = 7.5                                       # полупролёт: опоры не на начале тропы к вырубке
    for s in (-1, 1):
        box(B["stone"], px_ + s * arch, py_ - 7, z - 0.3, 1.2, 1.2, 6.0)
    arc = [(px_ - math.cos(math.pi * k / 10) * arch, py_ - 7, z + 5.6 + math.sin(math.pi * k / 10) * 3.0)
           for k in range(11)]
    for a_, b_ in zip(arc, arc[1:]):
        beam(B["stone"], a_, b_, 0.65, 6)
    POINTS.append(("fx-runes-shrine", cx, cy + 3, mz + 4))
    # Росток Главы 1 — у корней, перед стволом (пустышка item-<id> → находка StoryPickup в Godot).
    sx, sy, sz = cx + 1.5, cy + 1.4, z + 1.5
    POINTS.append(("item-stone_willow_sprout", sx - 0.9, sy - 0.5, sz))


def poi_camp(B, h, cx, cy, rng):
    """Охотничий лагерь: шатры, кострище с камнями, вертел, сушилки со шкурами, бревна-скамьи, ящики."""
    z = sample(h, cx, cy)
    for k in range(3):
        a = k * 2.1 + 0.4
        tx, ty = cx + math.cos(a) * 8, cy + math.sin(a) * 8
        roof(B["cloth"], tx, ty, sample(h, tx, ty) - 0.1, 3.6, 4.6, 2.8, a)
    for k in range(9):
        a = k / 9 * math.tau
        rock(B["rock"], cx + math.cos(a) * 1.1, cy + math.sin(a) * 1.1, z, 0.3, rng, 0.6)
    for s in (-1, 1):
        beam(B["wood"], (cx + s * 1.3, cy, z), (cx + s * 1.1, cy, z + 1.4), 0.07)
    beam(B["wood"], (cx - 1.3, cy, z + 1.35), (cx + 1.3, cy, z + 1.35), 0.05)
    POINTS.append(("fx-fire-camp", cx, cy, z + 0.2))
    for s in (-1, 1):
        beam(B["oldwood"], (cx - 2.2, cy + s * 2.6, z + 0.25), (cx + 2.2, cy + s * 2.8, z + 0.25), 0.25)
    rx, ry = cx + 5, cy - 6
    for s in (-1, 1):
        beam(B["wood"], (rx + s * 1.6, ry, z - 0.2), (rx + s * 1.6, ry, z + 2.4), 0.08)
    beam(B["wood"], (rx - 1.8, ry, z + 2.3), (rx + 1.8, ry, z + 2.3), 0.06)
    box(B["rust"], rx - 0.6, ry, z + 1.0, 1.0, 0.05, 1.3, 0)    # шкуры
    box(B["rust"], rx + 0.7, ry, z + 1.2, 0.9, 0.05, 1.1, 0)
    for k in range(3):
        box(B["wood"], cx - 6 + k * 1.1, cy - 4, z, 1.0, 0.9, 0.8, rng.uniform(0, 1))


def poi_logging(B, h, cx, cy, rng):
    """Заброшенная вырубка: пни, поваленные брёвна и штабель, брошенная телега, козлы с пилой, щепа."""
    for k in range(34):
        a, r = rng.random() * math.tau, 6 + rng.random() * 50
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        zz = sample(h, x, y)
        r1, h1, h2 = 0.45 + rng.random() * 0.35, 0.6 + rng.random() * 0.4, rng.random() * 0.1
        if road_clear(x, y) < 1.0:                       # пни — не на тропе через вырубку
            continue
        cyl(B["wood"], x, y, zz - 0.2, r1, h1, 8)
        cyl(B["cloth"], x, y, zz + 0.35 + h2, 0.4, 0.06, 8)                      # спил
    for k in range(6):
        a, r = rng.random() * math.tau, 10 + rng.random() * 35
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        b = rng.uniform(0, math.pi)
        L = rng.uniform(6, 11)
        zz = sample(h, x, y) + 0.35
        if road_clear(x, y) < L / 2 + 1.0:               # поваленное бревно поперёк тропы — убрать
            continue
        beam(B["oldwood"], (x - math.cos(b) * L / 2, y - math.sin(b) * L / 2, zz),
             (x + math.cos(b) * L / 2, y + math.sin(b) * L / 2, zz), 0.38, 8)
    z = sample(h, cx, cy)
    for row in range(3):
        for k in range(4 - row):
            beam(B["oldwood"], (cx - 4, cy + 6 + k * 0.75 + row * 0.37, z + 0.35 + row * 0.62),
                 (cx + 4, cy + 6 + k * 0.75 + row * 0.37, z + 0.35 + row * 0.62), 0.36, 8)
    tx, ty = cx + 8, cy - 6
    box(B["oldwood"], tx, ty, z + 0.7, 3.4, 1.8, 0.7, 0.5)
    for s in (-1, 1):
        for t in (-1, 1):
            wx, wy = tx + math.cos(0.5) * t * 1.2 - math.sin(0.5) * s * 1.0, ty + math.sin(0.5) * t * 1.2 + math.cos(0.5) * s * 1.0
            beam(B["oldwood"], (wx, wy - 0.12, z + 0.55), (wx, wy + 0.12, z + 0.55), 0.55, 10)
    box(B["oldwood"], cx - 7, cy - 3, z, 2.2, 0.8, 0.9, 0.2)                                       # козлы
    box(B["iron"], cx - 7, cy - 3, z + 1.0, 1.6, 0.04, 0.25, 0.2)                                  # пила


def poi_pier(B, h, cx, cy, rng):
    """Пристань Оды: мостки в реку на сваях, привязанные лодки, сети на шестах."""
    (qx, qy), flow, width, surf = river_at(cx, cy)
    axis = math.atan2(qy - cy, qx - cx)
    fr = Frame(cx, cy, axis)
    L = math.hypot(qx - cx, qy - cy) + 2
    z = surf + 0.6
    for t in np.arange(-3, L, 0.6):
        box(B["wood"], *fr.at(t, 0), z, 0.5, 2.4, 0.12, axis + math.pi / 2)
    for t in np.arange(-2, L, 3.0):
        for s in (-1.2, 1.2):
            beam(B["oldwood"], fr.at(t, s) + (surf - 1.5,), fr.at(t, s) + (z + 0.9,), 0.12)
    for k, s in enumerate((-3.0, 3.0)):
        bx, by = fr.at(L - 3 - k * 3, s)
        box(B["oldwood"], bx, by, surf - 0.25, 4.2, 1.4, 0.6, axis)
    for k in range(3):
        x, y = fr.at(-2 - k * 2.2, 3.5)
        beam(B["wood"], (x, y, sample(h, x, y)), (x, y, sample(h, x, y) + 2.2), 0.06)
    box(B["cloth"], *fr.at(-4.2, 3.5), sample(h, *fr.at(-4.2, 3.5)) + 0.8, 4.4, 0.05, 1.3, axis)


def clip_line(tri, n, c):
    """Отрезок прямой n·p = c внутри треугольника tri (2D) или None."""
    pts = []
    for k in range(3):
        a, b = tri[k], tri[(k + 1) % 3]
        da, db = n[0] * a[0] + n[1] * a[1] - c, n[0] * b[0] + n[1] * b[1] - c
        if (da < 0) != (db < 0) and da != db:
            t = da / (da - db)
            pts.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return pts[:2] if len(pts) >= 2 else None


def klaus_site(with_override=True):
    """Хижина Клауса: центр сруба (от площадки hermit_site — на 3 м от реки, + ручная правка «house:hermit»), пол."""
    hs = hermit_site()
    f = hs["face"]
    dx, dy, _, _ = ovr("house:hermit") if with_override else (0.0, 0.0, 0.0, False)
    return hs["x"] - math.cos(f) * 3.0 + dx, hs["y"] - math.sin(f) * 3.0 + dy, hs["base"]


def klaus_hut(B, h, rng):
    """Хижина Клауса по референсу автора (2026-10-27): бревенчатый сруб под длинной соломенной крышей —
    западный скат до земли (под ним поленница), восточный короче; на фронтонах решётка «в ромб», над коньком
    скрещённые жерди, на торцах — «кони»; каменная труба (квест «Тайник в дымоходе»). Перед входом (юг):
    огород в плетне, тачка, кострище с котлом на треноге, стол со скамьями, шкуры на стене, сундук третьей роты.
    Всё — в мешах Poi_* (коллизия по мешу; солома и шкуры — без)."""
    x, y, base = klaus_site()
    x0, x1, y0, y1 = x - 0.9, x + 4.1, y - 2.4, y + 2.4      # сруб
    xr, ridge = x + 1.6, base + 4.2                            # конёк (вдоль y)
    zw = lambda px_: ridge - (xr - px_) * 4.0 / 6.0            # западный скат: до земли у x − 4,4
    ze = lambda px_: ridge - (px_ - xr) * 2.45 / 3.2           # восточный: до x + 4,8
    door_x, win_x = x + 2.6, x + 0.5
    # Сруб: бревна вперевязку, концы торчат на углах; проёмы двери и окна.
    for i in range(8):
        z_ = base + 0.15 + i * 0.28
        for yy in (y0, y1):
            holes = sorted([(door_x - 0.55, door_x + 0.55, base + 2.0), (win_x - 0.45, win_x + 0.45, base + 1.75)]) if yy == y0 else []
            xs = [x0 - 0.3]
            for a_, b_, top in holes:
                if z_ < top and (a_ != win_x - 0.45 or z_ > base + 0.85):
                    xs += [a_, b_]
            xs.append(x1 + 0.3)
            for k in range(0, len(xs), 2):
                beam(B["oldwood"], (xs[k], yy, z_), (xs[k + 1], yy, z_), 0.15, 7)
        for xx in (x0, x1):
            beam(B["oldwood"], (xx, y0 - 0.3, z_ + 0.14), (xx, y1 + 0.3, z_ + 0.14), 0.15, 7)
    zt = base + 0.15 + 8 * 0.28
    # Фронтоны: доски и решётка в ромб под скатами.
    for yy in (y0, y1):
        tri = [(x0, zt), (x1, zt), (xr, ridge)]
        for px_ in np.arange(x0 + 0.15, x1, 0.3):
            top = min(zw(px_), ze(px_)) - 0.1
            if top > zt:
                box(B["dark"], px_, yy + 0.02, zt, 0.28, 0.06, top - zt)
        for n in ((1.0, -1.0), (1.0, 1.0)):
            for c in np.arange(-12.0, 12.0, 0.45):
                seg = clip_line(tri, n, n[0] * x + n[1] * base + c)
                if seg:
                    (ax, az), (bx, bz) = seg
                    beam(B["wood"], (ax, yy - 0.06, az), (bx, yy - 0.06, bz), 0.035, 4)
    # Внутри: тёмный пол и обшивка (в «окне» вокруг Рэя — не пустота).
    box(B["dark"], (x0 + x1) / 2, y, base - 0.05, x1 - x0 - 0.3, y1 - y0 - 0.3, 0.1)
    for xx in (x0 + 0.2, x1 - 0.2):
        box(B["dark"], xx, y, base, 0.04, y1 - y0 - 0.4, zt - base)
    # Дверь (арка из досок), окно со ставнями.
    for k in range(4):
        box(B["wood"], door_x - 0.36 + k * 0.24, y0 - 0.12, base + 0.02, 0.22, 0.06, 1.85)
    box(B["oldwood"], door_x, y0 - 0.15, base + 1.9, 1.2, 0.18, 0.18)
    for s_ in (-1, 1):
        box(B["oldwood"], door_x + s_ * 0.55, y0 - 0.15, base, 0.16, 0.18, 2.0)
    box(B["dark"], win_x, y0 + 0.02, base + 0.9, 0.85, 0.05, 0.8)
    for s_ in (-1, 1):
        box(B["wood"], win_x + s_ * 0.68, y0 - 0.14, base + 0.9, 0.42, 0.05, 0.8)
    box(B["wood"], win_x, y0 - 0.14, base + 1.3, 0.85, 0.05, 0.05)
    # Крыша: соломенные скаты, западный — слоями с зубчатым краем; конёк, жерди, «кони», стропила на торцах.
    def slab(xa, za, xb, zb, thick, y_from, y_to, lift=0.0):
        L = math.hypot(xb - xa, zb - za)
        a = math.atan2(zb - za, xb - xa)
        rotated_box(B["thatch"], (xa + xb) / 2 - math.sin(a) * (thick / 2 + lift), (y_from + y_to) / 2,
                    (za + zb) / 2 + math.cos(a) * (thick / 2 + lift), L, y_to - y_from, thick, -a)
    slab(x - 4.6, base - 0.05, xr, ridge, 0.35, y0 - 0.6, y1 + 0.6)
    slab(xr, ridge, x + 4.9, base + 1.68, 0.35, y0 - 0.6, y1 + 0.6)
    for k, f in enumerate((0.22, 0.45, 0.68)):                    # слои соломы с зубчатым краем
        for j, yy in enumerate(np.arange(y0 - 0.5, y1 + 0.5, 0.75)):
            fa = f - (0.05 if j % 2 else 0.0)
            xa = x - 4.6 + (xr - x + 4.6) * fa
            xb = xa + 1.6
            slab(xa, zw(xa) - 0.1, xb, zw(xb) - 0.1, 0.12, yy, yy + 0.8, 0.33 + 0.02 * k)
    beam(B["oldwood"], (xr, y0 - 0.8, ridge + 0.45), (xr, y1 + 0.8, ridge + 0.45), 0.13, 7)
    for yy in np.linspace(y0 - 0.3, y1 + 0.3, 8):
        beam(B["oldwood"], (xr - 0.55, yy, ridge + 0.1), (xr + 0.45, yy, ridge + 1.0), 0.05, 5)
        beam(B["oldwood"], (xr + 0.55, yy, ridge + 0.1), (xr - 0.45, yy, ridge + 1.0), 0.05, 5)
    for yy in (y0 - 0.62, y1 + 0.62):
        beam(B["oldwood"], (x - 4.7, yy, base), (xr + 0.6, yy, ridge + 0.9), 0.1, 6)
        beam(B["oldwood"], (x + 5.0, yy, base + 1.6), (xr - 0.6, yy, ridge + 0.95), 0.1, 6)
    for px_ in np.arange(x - 4.0, x0, 1.2):                       # стропила под длинным скатом
        beam(B["oldwood"], (px_, y0 - 0.55, zw(px_) - 0.15), (px_, y0 - 0.55, base - 0.1), 0.08, 5)
    # Под длинным скатом — поленница и шкуры на жерди.
    for k in range(2):
        woodpile(B, x - 1.6 - k * 1.3, y + 0.6, base - 0.05, math.pi / 2, rng)
    beam(B["oldwood"], (x - 2.6, y0 + 0.2, base + 1.7), (x0 - 0.2, y0 + 0.2, base + 2.3), 0.05, 5)
    for k, fx_ in enumerate((x - 2.2, x - 1.5)):
        box(B["fur"], fx_, y0 + 0.2, base + 0.85 + k * 0.15, 0.55, 0.05, 0.95, 0.1)
    box(B["fur"], x + 1.4, y0 - 0.2, base + 0.7, 0.6, 0.05, 1.1)
    # Труба: камень через западный скат.
    cxh, cyh = x - 0.2, y + 0.9
    box(B["stone"], cxh, cyh, base - 0.05, 0.8, 0.8, 5.0)
    box(B["dark"], cxh, cyh, base + 4.95, 0.95, 0.95, 0.15)
    POINTS.append(("fx-chimney-hermit", cxh, cyh, base + 5.2))
    POINTS.append(("door-hermit", door_x, y0 - 1.2, base))
    # Огород в плетне.
    gx, gy = x + 0.3, y0 - 1.8
    box(B["rust"], gx, gy, base - 0.1, 2.6, 1.3, 0.35)
    for k in range(9):
        g = bmesh.ops.create_icosphere(B["moss"], subdivisions=1, radius=0.28)
        bmesh.ops.translate(B["moss"], vec=(gx - 1.0 + (k % 5) * 0.5, gy - 0.3 + (k // 5) * 0.6, base + 0.35),
                            verts=g["verts"])
    for k in range(3):
        g = bmesh.ops.create_icosphere(B["gold"], subdivisions=1, radius=0.2)
        bmesh.ops.translate(B["gold"], vec=(gx - 0.7 + k * 0.7, gy - 0.05, base + 0.35), verts=g["verts"])
    for s_ in (-1, 1):
        for zz in (0.25, 0.5):
            beam(B["wood"], (gx - 1.4, gy + s_ * 0.75, base + zz), (gx + 1.4, gy + s_ * 0.75, base + zz), 0.04, 4)
        for px_ in np.arange(gx - 1.4, gx + 1.5, 0.35):
            beam(B["wood"], (px_, gy + s_ * 0.75, base - 0.1), (px_, gy + s_ * 0.75, base + 0.65), 0.03, 4)
    # Тачка с сеном.
    tx, ty = x - 2.4, y0 - 2.6
    box(B["wood"], tx, ty, base + 0.35, 1.3, 0.8, 0.45, 0.4)
    box(B["thatch"], tx, ty, base + 0.7, 1.1, 0.65, 0.2, 0.4)
    for s_ in (-1, 1):
        g = bmesh.ops.create_cone(B["oldwood"], cap_ends=True, segments=10, radius1=0.38, radius2=0.38, depth=0.08)
        bmesh.ops.transform(B["oldwood"], matrix=Matrix.Translation((tx + math.sin(0.4) * s_ * 0.48,
                            ty - math.cos(0.4) * s_ * 0.48, base + 0.38)) @ Matrix.Rotation(0.4, 4, "Z")
                            @ Matrix.Rotation(math.pi / 2, 4, "X"), verts=g["verts"])
    beam(B["wood"], (tx + 0.6, ty + 0.25, base + 0.6), (tx + 1.6, ty + 0.65, base + 0.25), 0.04, 4)
    # Кострище с котлом на треноге.
    fx_, fy_ = x + 5.3, y0 - 2.4
    for k in range(10):
        a = k / 10 * math.tau
        rock(B["rock"], fx_ + math.cos(a) * 0.75, fy_ + math.sin(a) * 0.75, base - 0.05, 0.2, rng, 0.7)
    for k in range(3):
        a = k / 3 * math.tau
        beam(B["oldwood"], (fx_ + math.cos(a) * 0.9, fy_ + math.sin(a) * 0.9, base - 0.1), (fx_, fy_, base + 1.7), 0.04, 4)
    cyl(B["iron"], fx_, fy_, base + 0.45, 0.38, 0.45, 10, 0.3)
    POINTS.append(("fx-fire-%02d" % len([p for p in POINTS if p[0].startswith("fx-fire")]), fx_, fy_, base + 0.2))
    # Стол и скамьи.
    sx, sy = x + 6.0, y0 + 0.2
    box(B["wood"], sx, sy, base + 0.72, 1.6, 0.8, 0.08)
    for ox in (-0.65, 0.65):
        for oy in (-0.3, 0.3):
            box(B["oldwood"], sx + ox, sy + oy, base - 0.05, 0.1, 0.1, 0.8)
    for s_ in (-1, 1):
        box(B["wood"], sx, sy + s_ * 0.75, base + 0.4, 1.6, 0.3, 0.07)
        for ox in (-0.6, 0.6):
            box(B["oldwood"], sx + ox, sy + s_ * 0.75, base - 0.05, 0.08, 0.25, 0.45)
    cyl(B["rust"], sx - 0.3, sy, base + 0.8, 0.14, 0.22, 8, 0.1)              # кувшин
    # Сундук третьей роты у двери (знамя роты — синее с золотой звездой).
    cx_, cy_ = door_x + 1.0, y0 - 0.55
    box(B["oldwood"], cx_, cy_, base - 0.05, 1.0, 0.55, 0.55)
    box(B["blue"], cx_, cy_ - 0.29, base + 0.12, 1.02, 0.02, 0.18)
    box(B["gold"], cx_, cy_ - 0.31, base + 0.1, 0.15, 0.02, 0.22)
    # Кусты у углов.
    for ox, oy, r in ((x - 4.6, y1 + 0.4, 0.9), (x + 4.7, y1 - 0.2, 0.8), (x - 3.6, y0 - 0.6, 0.6)):
        g = bmesh.ops.create_icosphere(B["moss"], subdivisions=1, radius=r)
        bmesh.ops.scale(B["moss"], vec=(1.0, 1.0, 0.75), verts=g["verts"])
        bmesh.ops.translate(B["moss"], vec=(ox, oy, base + r * 0.4), verts=g["verts"])


def poi_hermit(B, h, cx, cy, rng):
    """Берег Клауса (CANON: отставной сержант, отшельник, рыбачит): мостки в реку с табуретом, ведром
    и удочкой, лодка кверху дном, сети на шестах; хижина и двор — klaus_hut()."""
    hs = hermit_site()
    x, y, base, surf, d = hs["x"], hs["y"], hs["base"], hs["surf"], hs["d"]
    face = hs["face"]
    fr = Frame(x, y, face)
    gz = lambda px_, py_: height_at(h, px_, py_)
    # Мостки: с берега (где земля на уровне настила) — на 4,5 м в реку.
    start, end, z = hs["dist"] - hs["half"] - 3.5, hs["dist"] - hs["half"] + 4.5, surf + 0.6
    for t in np.arange(start, end, 0.5):
        box(B["wood"], *fr.at(t, 0), z, 0.42, 1.8, 0.1, face)
    for t in np.arange(start + 1.0, end, 2.0):
        for s_ in (-0.85, 0.85):
            beam(B["oldwood"], fr.at(t, s_) + (surf - 1.6,), fr.at(t, s_) + (z + (0.9 if t > end - 2.1 else 0.05),), 0.1)
    cyl(B["wood"], *fr.at(end - 0.8, 0.45), z + 0.1, 0.24, 0.45, 8)                     # табурет
    cyl(B["oldwood"], *fr.at(end - 0.7, -0.5), z + 0.1, 0.2, 0.38, 8, 0.25)              # ведро
    beam(B["wood"], fr.at(end - 0.9, 0.4) + (z + 0.6,), fr.at(end + 2.6, 0.9) + (z + 2.1,), 0.03, 5)   # удочка
    beam(B["cloth"], fr.at(end + 2.6, 0.9) + (z + 2.1,), fr.at(end + 2.7, 0.9) + (surf + 0.02,), 0.008, 3)
    # Лодка кверху дном на берегу и вёсла.
    bx, by = fr.at(start - 1.5, 3.4)
    bz = gz(bx, by)
    box(B["oldwood"], bx, by, bz - 0.05, 3.2, 1.2, 0.5, face)
    for s_ in (-1, 1):
        box(B["oldwood"], *fr.at(start - 1.5 + s_ * 1.95, 3.4), bz - 0.05, 0.8, 0.75, 0.42, face)
    box(B["wood"], bx, by, bz + 0.42, 3.9, 0.12, 0.1, face)
    for s_ in (-0.3, 0.3):
        beam(B["wood"], fr.at(start - 2.6, 2.2 + s_) + (gz(*fr.at(start - 2.6, 2.2)),),
             fr.at(start - 1.0, 2.4 + s_) + (gz(*fr.at(start - 1.0, 2.4)) + 0.2,), 0.04, 5)
    # Сети на шестах — на берегу ниже по течению.
    for k in range(3):
        px_, py_ = fr.at(start + 0.5 - k * 2.0, -7.0)
        beam(B["wood"], (px_, py_, gz(px_, py_) - 0.2), (px_, py_, gz(px_, py_) + 2.2), 0.06)
    nx_, ny_ = fr.at(start - 1.5, -7.0)
    box(B["cloth"], nx_, ny_, gz(nx_, ny_) + 0.7, 4.2, 0.05, 1.4, face)



def pois(col, h):
    """Места интереса (подзадача 5, референсы автора — Арт/Концепты/Места/, детали по канону)."""
    rng = random.Random(9)
    B = {k: bmesh.new() for k in POI_COLORS}
    B["slate"] = bmesh.new()
    poi_rubezh(B, h, rng)
    for pid, num, name, x, y, kind, note in W["POIS"]:
        cx, cy = P(x, y)
        z = sample(h, cx, cy)
        POINTS.append(("poi-" + pid, cx, cy, z))
        if pid == "mine":
            poi_mine(B, h, cx, cy, rng)
        elif pid == "cave":
            poi_cave(B, h, cx, cy, rng)
        elif pid == "adit":
            poi_cave(B, h, cx, cy, rng, glow=False)
        elif pid == "gorge":
            poi_gorge(B, h, cx, cy, rng)
        elif pid == "cemetery":
            poi_cemetery(B, h, cx, cy, rng)
        elif pid == "shrine":
            poi_shrine(B, h, cx, cy, rng)
        elif pid == "hunters":
            poi_camp(B, h, cx, cy, rng)
        elif pid == "logging":
            poi_logging(B, h, cx, cy, rng)
        elif pid == "pier":
            poi_pier(B, h, cx, cy, rng)
        elif pid == "hermit":
            poi_hermit(B, h, cx, cy, rng)
    for key, bm in B.items():
        rgb = POI_COLORS.get(key, (0.30, 0.34, 0.42))
        finish_mesh(col, "Poi_" + key, bm, rgb)
    for i, (x, y) in enumerate(W["LANTERNS"]):
        lx, ly = P(x, y)
        POINTS.append(("lantern-%02d" % (i + 1), lx, ly, sample(h, lx, ly)))


def points(col):
    for name, x, y, z in POINTS:
        e = bpy.data.objects.new(name, None)
        e.location = (x, y, z)
        e.empty_display_size = 3.0
        col.objects.link(e)


# --- Мелочи по миру (подзадача 8) -----------------------------------------------------------------

def polyline(bm, pts, r, seg=6):
    """Кованый пруток по точкам (каждый отрезок — beam)."""
    for a, b in zip(pts, pts[1:]):
        beam(bm, a, b, r, seg)


def soul_lantern(B, x, y, z, rng):
    """Фонарь душ (решение автора, референсы 2026-10-22): каменная плита, кованый посох-крюк на трёх
    завитых лапах, на конце крюка — цепь и подвесной гранёный латунный фонарь (шестигранник, шатровая
    крыша с кольцом, низ сужается к капле); внутри фиолетовое стекло и светлый вихрь-огонёк.
    Точки для Godot: fx-soul-lantern (свет), npc-guide (проводник-сова стоит у фонаря),
    spawn-spirit (место призрака, которого видят только мёртвые; появляется с шансом)."""
    a = rng.uniform(0, math.tau)                # куда смотрит крюк
    ux, uy = math.cos(a), math.sin(a)
    n = len([p for p in POINTS if p[0].startswith("fx-soul")])
    # Строится в полный размер, затем сжимается к основанию в SCALE раз (решение автора: фонари вдвое меньше).
    SCALE = 0.5
    before = {k: len(bm.verts) for k, bm in B.items()}
    points_before = len(POINTS)
    # Плита-основание.
    cyl(B["darkstone"], x, y, z - 0.3, 0.85, 0.5, 8)
    cyl(B["stone"], x, y, z + 0.2, 0.62, 0.1, 8)
    # Три завитые лапы (как у подставки на референсе) и посох.
    for k in range(3):
        b = a + math.pi / 3 + k * math.tau / 3
        cx, cy = math.cos(b), math.sin(b)
        prof = [(0.0, 0.85), (0.18, 0.62), (0.34, 0.42), (0.46, 0.34), (0.56, 0.36), (0.6, 0.46), (0.54, 0.54)]
        polyline(B["iron"], [(x + cx * d, y + cy * d, z + hh) for d, hh in prof], 0.04)
    zt = z + 3.4
    beam(B["iron"], (x, y, z + 0.3), (x, y, zt), 0.075, 8)
    cyl(B["iron"], x, y, z + 0.3, 0.12, 0.25, 8)
    # Крюк: полукруг над головой, конец смотрит вниз.
    R = 0.45
    arc = [(x + ux * R * (1 + math.cos(t)), y + uy * R * (1 + math.cos(t)), zt + R * math.sin(t))
           for t in np.linspace(math.pi, 0.0, 10)]
    polyline(B["iron"], arc, 0.06)
    # Завиток внутри крюка.
    curl = [(x + ux * R * (1 + 0.45 * math.cos(t)), y + uy * R * (1 + 0.45 * math.cos(t)),
             zt + R * 0.45 * math.sin(t) + 0.12) for t in np.linspace(0.0, 2.6, 7)]
    polyline(B["iron"], curl, 0.03)
    hx, hy = x + ux * 2 * R, y + uy * 2 * R
    # Цепь (звенья — короткие отрезки вразворот).
    zc = zt
    for k in range(3):
        beam(B["iron"], (hx, hy, zc), (hx, hy, zc - 0.11), 0.025, 4)
        box(B["iron"], hx, hy, zc - 0.11, 0.07, 0.02, 0.05, a + (k % 2) * math.pi / 2)
        zc -= 0.13
    # Фонарь (s — масштаб; размеры по референсу 2).
    s_ = 1.25
    zr = zc - 0.1 * s_                          # центр кольца
    ring = [(hx + ux * math.cos(t) * 0.09 * s_, hy + uy * math.cos(t) * 0.09 * s_, zr + math.sin(t) * 0.09 * s_)
            for t in np.linspace(0, math.tau, 11)]
    polyline(B["brass"], ring, 0.022 * s_, 5)
    z_roof = zr - 0.09 * s_ - 0.05 * s_
    cyl(B["brass"], hx, hy, z_roof - 0.06 * s_, 0.045 * s_, 0.08 * s_, 8)      # шишечка
    roof_h = 0.32 * s_
    g = bmesh.ops.create_cone(B["brass"], cap_ends=True, segments=6, radius1=0.30 * s_, radius2=0.035 * s_,
                              depth=roof_h)
    bmesh.ops.translate(B["brass"], vec=(hx, hy, z_roof - 0.06 * s_ - roof_h / 2), verts=g["verts"])
    z_band = z_roof - 0.06 * s_ - roof_h
    cyl(B["brass"], hx, hy, z_band - 0.06 * s_, 0.31 * s_, 0.06 * s_, 6)
    gh = 0.55 * s_
    z_g = z_band - 0.06 * s_ - gh               # низ стекла
    cyl(B["glass"], hx, hy, z_g, 0.25 * s_, gh, 6)
    cyl(B["brass"], hx, hy, z_g - 0.05 * s_, 0.29 * s_, 0.05 * s_, 6)
    z_drop = z_g - 0.05 * s_ - 0.3 * s_
    for k in range(6):                          # рёбра каркаса и арки к капле
        t = k / 6 * math.tau
        cx, cy = hx + math.cos(t) * 0.265 * s_, hy + math.sin(t) * 0.265 * s_
        beam(B["brass"], (cx, cy, z_g - 0.05 * s_), (cx, cy, z_band), 0.02 * s_, 4)
        mx, my = hx + math.cos(t) * 0.17 * s_, hy + math.sin(t) * 0.17 * s_
        polyline(B["brass"], [(cx, cy, z_g - 0.05 * s_), (mx, my, z_g - 0.2 * s_), (hx, hy, z_drop + 0.04 * s_)],
                 0.018 * s_, 4)
    g = bmesh.ops.create_cone(B["brass"], cap_ends=True, segments=6, radius1=0.02 * s_, radius2=0.08 * s_,
                              depth=0.1 * s_)
    bmesh.ops.translate(B["brass"], vec=(hx, hy, z_drop + 0.05 * s_), verts=g["verts"])
    # Вихрь-огонёк внутри (референс 1): спираль и ядро.
    spiral = [(hx + math.cos(t * 4.5) * (0.07 + 0.08 * t) * s_, hy + math.sin(t * 4.5) * (0.07 + 0.08 * t) * s_,
               z_g + (0.08 + 0.4 * t) * s_) for t in np.linspace(0, 1, 16)]
    polyline(B["flame"], spiral, 0.025 * s_, 4)
    g = bmesh.ops.create_icosphere(B["flame"], subdivisions=1, radius=0.09 * s_)
    bmesh.ops.scale(B["flame"], vec=(1, 1, 1.5), verts=g["verts"])
    bmesh.ops.translate(B["flame"], vec=(hx, hy, z_g + 0.22 * s_), verts=g["verts"])
    for k, bm in B.items():
        bm.verts.ensure_lookup_table()
        for v in bm.verts[before[k]:]:
            v.co = Vector((x, y, z)) + (v.co - Vector((x, y, z))) * SCALE
    del POINTS[points_before:]
    POINTS.append(("fx-soul-lantern-%02d" % n, x + (hx - x) * SCALE, y + (hy - y) * SCALE, z + (z_g + gh / 2 - z) * SCALE))
    POINTS.append(("npc-guide-%02d" % n, x - ux * 1.6 + uy * 0.9, y - uy * 1.6 - ux * 0.9, z))
    POINTS.append(("spawn-spirit-%02d" % n, x - ux * 1.4 - uy * 1.8, y - uy * 1.4 + ux * 1.8, z))


def glow_material(name, rgb, strength, alpha=1.0):
    """Светящийся материал (стекло фонаря душ, огонёк); для превью — EEVEE, в Godot — свой шейдер."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = lin(rgb) + (1.0,)
    bsdf.inputs["Emission Color"].default_value = lin(rgb) + (1.0,)
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        m.surface_render_method = "BLENDED"
    return m


def signpost(B, x, y, z, directions, rng):
    """Указатель: столб и доски-стрелки по направлениям (углы, радианы)."""
    beam(B["oldwood"], (x, y, z - 0.4), (x, y, z + 2.8), 0.12)
    for k, a in enumerate(directions[:3]):
        zz = z + 2.3 - k * 0.45
        ox, oy = math.cos(a) * 0.75, math.sin(a) * 0.75
        box(B["wood"], x + ox, y + oy, zz, 1.4, 0.06, 0.3, a)
        g = bmesh.ops.create_cone(B["wood"], cap_ends=True, segments=3, radius1=0.22, radius2=0.0, depth=0.06)
        bmesh.ops.rotate(B["wood"], verts=g["verts"], cent=(0, 0, 0),
                         matrix=Matrix.Rotation(a, 3, "Z") @ Matrix.Rotation(math.pi / 2, 3, "X"))
        bmesh.ops.translate(B["wood"], vec=(x + ox * 2.0, y + oy * 2.0, zz + 0.15), verts=g["verts"])


def cart(B, x, y, z, rot, rng, broken=False):
    """Телега: кузов, борта, два колеса, оглобли; брошенная — накренена, без колеса."""
    ux, uy = math.cos(rot), math.sin(rot)
    tilt = 0.25 if broken else 0.0
    box(B["oldwood"], x, y, z + 0.6 - tilt, 2.6, 1.4, 0.15, rot)
    for s in (-1, 1):
        box(B["oldwood"], x - uy * s * 0.68, y + ux * s * 0.68, z + 0.7 - tilt, 2.6, 0.08, 0.45, rot)
    for k, s in enumerate((-1, 1)):
        if broken and k == 0:
            continue
        wx, wy = x - uy * s * 0.85, y + ux * s * 0.85
        beam(B["oldwood"], (wx - uy * s * 0.08, wy + ux * s * 0.08, z + 0.55),
             (wx + uy * s * 0.08, wy - ux * s * 0.08, z + 0.55), 0.55, 10)
    for s in (-0.4, 0.4):
        beam(B["oldwood"], (x + ux * 1.3 - uy * s, y + uy * 1.3 + ux * s, z + 0.6),
             (x + ux * 3.2 - uy * s, y + uy * 3.2 + ux * s, z + 0.25), 0.06)
    if not broken and rng.random() < 0.6:
        g = bmesh.ops.create_icosphere(B["hay"], subdivisions=1, radius=1.0)
        bmesh.ops.scale(B["hay"], vec=(1.2, 0.65, 0.4), verts=g["verts"])
        bmesh.ops.rotate(B["hay"], verts=g["verts"], cent=(0, 0, 0), matrix=Matrix.Rotation(rot, 3, "Z"))
        bmesh.ops.translate(B["hay"], vec=(x, y, z + 0.85), verts=g["verts"])


def haystack(B, x, y, z, rng):
    r = rng.uniform(1.7, 2.3)
    cyl(B["hay"], x, y, z - 0.2, r, r * 0.9, 10, r * 0.85)
    g = bmesh.ops.create_cone(B["hay"], cap_ends=True, segments=10, radius1=r * 0.88, radius2=0.1, depth=r * 1.1)
    bmesh.ops.translate(B["hay"], vec=(x, y, z - 0.2 + r * 0.9 + r * 0.55), verts=g["verts"])
    beam(B["oldwood"], (x, y, z + r * 1.9), (x, y, z + r * 2.4), 0.05)


def woodpile(B, x, y, z, rot, rng):
    ux, uy = math.cos(rot), math.sin(rot)
    for row in range(3):
        for k in range(5 - row):
            o = (k - (4 - row) / 2) * 0.32
            px_, py_ = x + ux * o, y + uy * o
            beam(B["wood"], (px_ - uy * 0.5, py_ + ux * 0.5, z + 0.16 + row * 0.28),
                 (px_ + uy * 0.5, py_ - ux * 0.5, z + 0.16 + row * 0.28), 0.15, 7)


def masonry(B, x, y, z, rot, length, top, rng, thick=0.9, hole=None):
    """Кладка рядами (блоки 0,6 м, ряды вразбежку) до высоты top(t), t — 0…1 вдоль стены; верх — мох.
    hole(o, zr) — True, если камня с центром o (вдоль стены от середины) на высоте zr нет (проём)."""
    ux, uy = math.cos(rot), math.sin(rot)
    n = max(1, int(length / 0.75))
    bw = length / n
    for i in range(n):
        o = (i + 0.5) * bw - length / 2
        hh = top((i + 0.5) / n)
        rows = max(1, int(hh / 0.6))
        for r in range(rows):
            if r and rng.random() < 0.05:
                continue                        # выпавший камень
            if hole and hole(o, r * 0.6 + 0.3):
                continue
            sh = (0.5 if r % 2 else 0.0) * bw * 0.3
            key = "darkstone" if (r == 0 or rng.random() < 0.18) else "stone"
            box(B[key], x + ux * (o + sh), y + uy * (o + sh), z - 0.3 + r * 0.6,
                bw * 0.96, thick * rng.uniform(0.92, 1.0), 0.58, rot + rng.uniform(-0.03, 0.03))
        if rng.random() < 0.6:                  # мох на верхнем камне
            box(B["moss"], x + ux * o, y + uy * o, z - 0.3 + rows * 0.6 - 0.02, bw * 0.9, thick * 0.8, 0.08, rot)


def rubble(B, x, y, z, rng, n=8, spread=3.0, size=(0.25, 0.7)):
    for _ in range(n):
        a, r = rng.uniform(0, math.tau), rng.uniform(0, spread)
        key = "moss" if rng.random() < 0.15 else ("darkstone" if rng.random() < 0.4 else "stone")
        rock(B[key], x + math.cos(a) * r, y + math.sin(a) * r, z, rng.uniform(*size), rng, 0.55)


def stone_arch(B, cx, cy, z, rot, span, rise, thick):
    """Арка из клиньев: полукруг над проёмом span, пяты на высоте z."""
    ux, uy = math.cos(rot), math.sin(rot)
    seg = 7
    for k in range(seg):
        a0, a1 = math.pi * k / seg, math.pi * (k + 1) / seg
        p0 = (cx + ux * math.cos(a0) * span / 2, cy + uy * math.cos(a0) * span / 2, z + math.sin(a0) * rise)
        p1 = (cx + ux * math.cos(a1) * span / 2, cy + uy * math.cos(a1) * span / 2, z + math.sin(a1) * rise)
        beam(B["stone"], p0, p1, thick, 4)


def ruin_tower(B, x, y, z, rng):
    """Развалины сторожевой башни: кольцо кладки рядами, обвал с одной стороны (осыпь наружу),
    арочный вход, бойницы-пропуски, упавший кусок стены, мох на верхах, обломки вокруг."""
    R, n = 3.4, 16
    fall = rng.uniform(0, math.tau)             # сторона обвала
    door = fall + math.pi                       # вход — напротив
    for k in range(n):
        a = (k + 0.5) / n * math.tau
        da = abs((a - fall + math.pi) % math.tau - math.pi)
        dd = abs((a - door + math.pi) % math.tau - math.pi)
        if dd < 0.22:
            continue                            # проём входа
        hmax = 7.5 * min(1.0, 0.15 + da / 1.6) * rng.uniform(0.8, 1.0)
        seg_len = 2 * R * math.sin(math.pi / n) + 0.05
        h0, h1 = hmax, hmax * rng.uniform(0.7, 1.05)
        masonry(B, x + math.cos(a) * R, y + math.sin(a) * R, z, a + math.pi / 2, seg_len,
                lambda t, h0=h0, h1=h1: h0 + (h1 - h0) * t, rng, 1.0)
    # Арка входа.
    for s in (-1, 1):
        ja = door + s * 0.3
        box(B["darkstone"], x + math.cos(ja) * R, y + math.sin(ja) * R, z - 0.3, 0.6, 1.1, 2.6, ja + math.pi / 2)
    stone_arch(B, x + math.cos(door) * R, y + math.sin(door) * R, z + 2.2, door + math.pi / 2, 2.0, 0.9, 0.28)
    # Осыпь наружу со стороны обвала и упавший кусок кладки.
    for k in range(18):
        r = rng.uniform(R, R + 6.0)
        a = fall + rng.uniform(-0.6, 0.6)
        rock(B["darkstone" if k % 3 else "stone"], x + math.cos(a) * r, y + math.sin(a) * r, z,
             rng.uniform(0.3, 0.9) * (1.3 - (r - R) / 8), rng, 0.5)
    fx, fy = x + math.cos(fall) * (R + 4.5), y + math.sin(fall) * (R + 4.5)
    box(B["stone"], fx, fy, z - 0.4, 3.2, 1.0, 1.1, fall + 0.4)
    box(B["moss"], fx, fy, z + 0.68, 2.6, 0.8, 0.08, fall + 0.4)
    # Мох у подножия и мелкие обломки внутри.
    rubble(B, x, y, z, rng, 10, R - 0.8, (0.2, 0.5))
    rubble(B, x, y, z, rng, 8, R + 3.0)


def ruin_wall(B, x, y, z, rot, rng):
    """Обломок крепостной стены: кладка ступенчатым изломом, оконная арка, контрфорс, осыпь."""
    ux, uy = math.cos(rot), math.sin(rot)
    L = 9.0
    peak = rng.uniform(0.25, 0.75)
    ox = (peak - 0.5) * L
    # Сквозное арочное окно у вершины излома: камни в проёме не кладутся, сверху — арка из клиньев.
    win_w, sill, spring = 1.5, 1.2, 2.4

    def window(o, zr):
        dx = abs(o - ox) / (win_w / 2)
        return dx < 1.0 and sill < zr < spring + 0.6 * math.sqrt(1 - dx * dx) + 0.3

    masonry(B, x, y, z, rot, L, lambda t: max(0.6, 4.6 * (1 - abs(t - peak) * 1.6)), rng, 1.0, window)
    stone_arch(B, x + ux * ox, y + uy * ox, z - 0.3 + spring, rot, win_w, 0.6, 0.22)
    # Контрфорс и осыпь у подножия с обеих сторон.
    nx, ny = -uy, ux
    box(B["darkstone"], x + ux * (L / 2 - 0.5) + nx * 0.9, y + uy * (L / 2 - 0.5) + ny * 0.9, z - 0.3,
        0.9, 1.0, 2.2, rot)
    for s in (-1, 1):
        rubble(B, x + nx * s * 1.6, y + ny * s * 1.6, z, rng, 7, 2.5)


def details(col, h, forest):
    """Подзадача 8 (выбор автора): фонари душ, указатели на развилках, телеги, стога, поленницы,
    руины и придорожные камни (вёрстовые столбы)."""
    rng = random.Random(31)
    B = {k: bmesh.new() for k in ("stone", "iron", "brass", "glass", "flame", "wood", "oldwood", "hay", "darkstone", "moss")}
    colors_ = {"stone": (0.60, 0.59, 0.56), "iron": (0.17, 0.17, 0.19), "brass": (0.62, 0.47, 0.22),
               "glass": (0.50, 0.32, 0.88), "flame": (0.82, 0.62, 1.0),
               "darkstone": (0.44, 0.44, 0.42), "moss": (0.30, 0.40, 0.18),
               "wood": (0.50, 0.36, 0.22), "oldwood": (0.38, 0.31, 0.24), "hay": (0.78, 0.66, 0.34)}
    count = {}

    def item(kind, anchor, fn):
        """Мелочь — своя группа правки «detail:<вид>_<номер>» (номер — по порядку постройки)."""
        count[kind] = count.get(kind, -1) + 1
        g = EditGroup(col, "detail:%s_%d" % (kind, count[kind]), anchor, h)
        fn({k: g.bm(k) for k in colors_})
        g.finish(colors_, "Detail_")
    # Фонари душ (не двигаются — по ним возрождение и проводники).
    for x, y in W["LANTERNS"]:
        lx, ly = P(x, y)
        soul_lantern(B, lx, ly, height_at(h, lx, ly), rng)
    # Указатели: концы дорог/троп, примыкающие к другой линии (развилки).
    main = [(k, p) for k, p in ROAD_LINES if k != "lane"]
    for idx, (kind, pts) in enumerate(main):
        for end, nxt in ((pts[0], pts[min(3, len(pts) - 1)]), (pts[-1], pts[max(-4, -len(pts))])):
            for jdx, (k2, p2) in enumerate(main):
                if jdx == idx:
                    continue
                q = min(p2, key=lambda p: math.hypot(p[0] - end[0], p[1] - end[1]))
                if math.hypot(q[0] - end[0], q[1] - end[1]) < 6.0:
                    i2 = p2.index(q)
                    a_own = math.atan2(nxt[1] - end[1], nxt[0] - end[0])
                    pa, pb = p2[max(0, i2 - 2)], p2[min(len(p2) - 1, i2 + 2)]
                    a_main = math.atan2(pb[1] - pa[1], pb[0] - pa[0])
                    sx, sy = end[0] + math.cos(a_own + 1.2) * 4.5, end[1] + math.sin(a_own + 1.2) * 4.5
                    if road_clear(sx, sy) < 1.0:                 # на чужой ленте — на другую сторону
                        sx, sy = end[0] + math.cos(a_own - 1.2) * 4.5, end[1] + math.sin(a_own - 1.2) * 4.5
                    item("signpost", (sx, sy), lambda Bg: signpost(Bg, sx, sy, height_at(h, sx, sy),
                                                                  [a_own, a_main, a_main + math.pi], rng))
                    break
    # Вёрстовые столбы — вдоль дорог через ~120 м.
    for kind, pts in main:
        if kind == "path":
            continue
        line = resample(pts, 1.0)
        for k in range(60, len(line) - 30, 120):
            (x0, y0), (x1, y1) = line[k], line[k + 1]
            a = math.atan2(y1 - y0, x1 - x0)
            sx, sy = x0 - math.sin(a) * 3.6, y0 + math.cos(a) * 3.6
            z = height_at(h, sx, sy)

            def milestone(Bg):
                box(Bg["stone"], sx, sy, z - 0.3, 0.45, 0.35, 1.3, a)
                box(Bg["stone"], sx, sy, z + 0.95, 0.5, 0.4, 0.15, a)
            item("milestone", (sx, sy), milestone)
    # Стога — на пашне и террасах; телеги — у полей, огородов и вдоль дорог; поленницы — у домов.
    for poly in W["FIELDS"] + W["TERRACES"]:
        pts = PL(poly)
        xs_ = [p[0] for p in pts]
        ys_ = [p[1] for p in pts]
        mask_poly = pts
        placed = 0
        for _ in range(60):
            if placed >= 5:
                break
            x, y = rng.uniform(min(xs_), max(xs_)), rng.uniform(min(ys_), max(ys_))
            if poly_mask_point(mask_poly, x, y):
                item("haystack", (x, y), lambda Bg: haystack(Bg, x, y, height_at(h, x, y), rng))
                placed += 1
    for poly in W["FIELDS"] + W["GARDENS"]:
        pts = PL(poly)
        cx_ = sum(p[0] for p in pts) / len(pts) + rng.uniform(-3, 3)
        # Телега — с той стороны поля, где дальше от дорог (иначе вставала на ленту).
        cy_ = max((min(p[1] for p in pts) - 4.0, max(p[1] for p in pts) + 4.0), key=lambda yy: road_clear(cx_, yy))
        a_ = rng.uniform(0, math.tau)
        item("cart", (cx_, cy_), lambda Bg: cart(Bg, cx_, cy_, height_at(h, cx_, cy_), a_, rng))
    for kind, pts in main:
        if kind != "road" or rng.random() < 0.4:
            continue
        line = resample(pts, 1.0)
        k = rng.randrange(len(line) // 4, max(len(line) // 4 + 1, 3 * len(line) // 4))
        (x0, y0), (x1, y1) = line[k], line[min(k + 1, len(line) - 1)]
        a = math.atan2(y1 - y0, x1 - x0)
        sx, sy = x0 - math.sin(a) * 5.5, y0 + math.cos(a) * 5.5
        broken = rng.random() < 0.5
        item("cart", (sx, sy), lambda Bg: cart(Bg, sx, sy, height_at(h, sx, sy), a + 0.3, rng, broken=broken))
    for it in village_plan():
        if it["kind"] == "building" and rng.random() < 0.7:
            sx, sy = it["side"]
            wx, wy = it["x"] - sx * (it["w"] / 2 + 1.0) + sy * 2.0, it["y"] - sy * (it["d"] / 2 + 1.0) + sx * 2.0
            wx, wy = rotate_about(wx, wy, it["x"], it["y"], it["rot"])      # за домом, если его повернули
            wa = math.atan2(sy, sx) + math.pi / 2 + it["rot"]
            item("woodpile", (wx, wy), lambda Bg: woodpile(Bg, wx, wy, height_at(h, wx, wy), wa, rng))
    # Руины: сторожевые башни у старых дорог и обломки стены.
    for x, y in W["RUIN_TOWERS"]:
        rx, ry = P(x, y)
        item("ruin_tower", (rx, ry), lambda Bg: ruin_tower(Bg, rx, ry, height_at(h, rx, ry), rng))
    for x, y, a in W["RUIN_WALLS"]:
        rx, ry = P(x, y)
        item("ruin_wall", (rx, ry), lambda Bg: ruin_wall(Bg, rx, ry, height_at(h, rx, ry), a, rng))
    for key, bm in B.items():
        ob = finish_mesh(col, "Detail_" + key, bm, colors_[key])
        if key == "glass":
            ob.data.materials[0] = glow_material("Стекло фонаря душ", colors_[key], 1.5, 0.6)
        elif key == "flame":
            ob.data.materials[0] = glow_material("Огонёк души", colors_[key], 3.0)


def road_clear(x, y):
    """Расстояние от точки до края ближайшей дороги/тропы/улицы (м; < 0 — на ленте). ROAD_LINES — из shape()."""
    best = 1e9
    for kind, pts in ROAD_LINES:
        for a, b in zip(pts, pts[1:]):
            vx, vy = b[0] - a[0], b[1] - a[1]
            t = max(0.0, min(1.0, ((x - a[0]) * vx + (y - a[1]) * vy) / (vx * vx + vy * vy + 1e-9)))
            best = min(best, math.hypot(x - a[0] - vx * t, y - a[1] - vy * t) - ROAD_HALF[kind])
    return best


def poly_mask_point(poly, x, y):
    inside = False
    n = len(poly)
    for k in range(n):
        x1, y1 = poly[k]
        x2, y2 = poly[(k + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / ((y2 - y1) or 1e-9) + x1:
            inside = not inside
    return inside


# --- Дороги лентами ------------------------------------------------------------------------------

# Поперечный профиль ленты: (доля полуширины, цвет). Обочина — колея — полотно — травяная полоса посередине.
ROAD_PROFILE = {
    "road": (2.7, [(-1.0, (0.40, 0.42, 0.24)), (-0.82, (0.55, 0.46, 0.31)), (-0.40, (0.43, 0.34, 0.22)),
                   (-0.12, (0.52, 0.44, 0.30)), (0.0, (0.44, 0.49, 0.25)), (0.12, (0.52, 0.44, 0.30)),
                   (0.40, (0.43, 0.34, 0.22)), (0.82, (0.55, 0.46, 0.31)), (1.0, (0.40, 0.42, 0.24))]),
    "path": (1.4, [(-1.0, (0.42, 0.44, 0.25)), (-0.6, (0.52, 0.44, 0.30)), (0.0, (0.55, 0.47, 0.32)),
                   (0.6, (0.52, 0.44, 0.30)), (1.0, (0.42, 0.44, 0.25))]),
    "lane": (1.1, [(-1.0, (0.45, 0.43, 0.27)), (-0.5, (0.55, 0.48, 0.34)), (0.5, (0.55, 0.48, 0.34)),
                   (1.0, (0.45, 0.43, 0.27))]),
    # Мощёный тракт к Рубежу: бордюр, брусчатка (камни ~0,35 × 0,5 м, пёстрые), провалы с травой (paved_gap).
    "paved": (2.8, [(-1.0, (0.46, 0.45, 0.42)), (-0.85, (0.58, 0.57, 0.53))] +
                   [(round(-0.72 + 0.12 * i, 2), (0.58, 0.57, 0.53)) for i in range(13)] +
                   [(0.85, (0.58, 0.57, 0.53)), (1.0, (0.46, 0.45, 0.42))]),
}


def paved_gap(x, y):
    """Провалы мощения: пятна по шуму (~20 % площади) — камни выбиты, растёт трава."""
    return noise.noise(Vector((x / 7.0, y / 7.0, 2.7))) > 0.30


def road_ribbons(col, h, river, dl):
    """Дороги, тропы и улицы — гладкие ленты поверх земли (шаг 1 м вдоль сглаженной линии), с обочинами,
    колеями и травяной полосой в цвете вершин; UV: u — поперёк (0..1), v — вдоль, в метрах (в Godot текстура
    колей ляжет вдоль дороги). Над водой лента прерывается (там мосты). Меш «Roads»."""
    d_river, surf, half_r = river
    bm = bmesh.new()
    col_layer = bm.loops.layers.float_color.new("Col")
    uv_layer = bm.loops.layers.uv.new("UV0")

    def wet(x, y):
        i = int(round((x - XS[0]) / STEP))
        j = int(round((y - YS[0]) / STEP))
        if not (0 <= i < len(XS) and 0 <= j < len(YS)):
            return True
        return dl[j, i] > -1.5 or d_river[j, i] < half_r[j, i] + 1.0

    for kind, pts in ROAD_LINES:
        half, prof = ROAD_PROFILE[kind]
        line = resample(pts, 0.5 if kind == "paved" else 1.0)
        rows, v = [], 0.0
        for k, (x, y) in enumerate(line):
            a = line[max(0, k - 1)]
            b = line[min(len(line) - 1, k + 1)]
            tx, ty = b[0] - a[0], b[1] - a[1]
            L = math.hypot(tx, ty) or 1.0
            nx, ny = -ty / L, tx / L
            if k:
                v += math.hypot(x - line[k - 1][0], y - line[k - 1][1])
            if wet(x, y):
                rows.append(None)
                continue
            row = []
            for t, rgb in prof:
                px, py = x + nx * t * half, y + ny * t * half
                lift = 0.10 if kind == "paved" else 0.07     # мощёная поверх грунтовой на развилках
                row.append((bm.verts.new((px, py, height_at(h, px, py) + lift)), (t + 1) / 2, v, rgb))
            rows.append(row)
        for r0, r1 in zip(rows, rows[1:]):
            if r0 is None or r1 is None:
                continue
            for c in range(len(prof) - 1):
                quad = [r0[c], r0[c + 1], r1[c + 1], r1[c]]
                face_rgb = None
                if kind == "paved" and 0 < c < len(prof) - 2:
                    # Брусчатка: цвет на грань (камень целиком), провал — трава с землёй.
                    cx_ = sum(q[0].co.x for q in quad) / 4
                    cy_ = sum(q[0].co.y for q in quad) / 4
                    if paved_gap(cx_, cy_):
                        face_rgb = (0.36, 0.40, 0.21) if (int(cx_ * 3) + int(cy_ * 3)) % 3 else (0.40, 0.33, 0.22)
                    else:
                        k_ = 0.72 + 0.42 * ((math.sin(cx_ * 12.9898 + cy_ * 78.233) * 43758.5453) % 1.0)
                        face_rgb = tuple(min(1.0, c_ * k_) for c_ in quad[0][3])
                f = bm.faces.new([q[0] for q in quad])
                for loop, q in zip(f.loops, quad):
                    loop[uv_layer].uv = (q[1], q[2])
                    loop[col_layer] = lin(face_rgb or q[3]) + (1.0,)
    # Грани — лицом вверх (порядок вершин в профиле дал их лицом вниз; в Godot их отсекает куллинг).
    for f in bm.faces:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    me = bpy.data.meshes.new("Roads")
    bm.to_mesh(me)
    bm.free()
    for p_ in me.polygons:
        p_.use_smooth = True
    me.color_attributes.active_color = me.color_attributes["Col"]
    me.color_attributes.render_color_index = 0          # иначе экспорт glTF пишет белый цвет вершин
    me.materials.append(vc_material())
    col.objects.link(bpy.data.objects.new("Roads", me))


# --- Растительность ------------------------------------------------------------------------------

NATURE_JSON = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "levels", "world_nature.json")
NATURE_GLB = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "models", "nature", "nature_pack.glb")
PACK = {
    "pine": ["PineTree_%d" % i for i in range(1, 6)],
    "oak": ["NormalTree_%d" % i for i in range(1, 6)],
    "birch": ["BirchTree_%d" % i for i in range(1, 6)],
    "maple": ["MapleTree_%d" % i for i in range(1, 6)],
    "dead": ["DeadTree_%d" % i for i in range(1, 11)],
    "willow": ["WillowTree_%d" % i for i in range(1, 4)],
    "reed": ["Reed_1", "Reed_2"],
    "lily": ["LilyPad_1", "LilyPad_2"],
    "rock": ["Rock_%d" % i for i in range(1, 6)],
    "bush": ["Bush", "Bush_Flowers", "Plant_1", "Plant_2", "Plant_Flowers"],
    "flower": ["Flower_1_Clump", "Flower_2_Clump", "Flower_3_Clump", "Flower_4_Clump", "Flower_5_Clump", "Petals_1"],
}
# Состав леса по местам: доли (сосна, дуб, берёза, клён, сухое).
MIX = {
    "north": (0.6, 0.2, 0.15, 0.0, 0.05),
    # Осенние клёны — заметными рыжими пятнами (решение автора: «очень крутые, верни»).
    "east": (0.35, 0.35, 0.15, 0.15, 0.0),
    "west": (0.1, 0.4, 0.3, 0.2, 0.0),
    "foot": (0.7, 0.0, 0.0, 0.0, 0.3),
}


def height_at(h, x, y):
    fx = min(max((x - XS[0]) / STEP, 0.0), len(XS) - 1.001)
    fy = min(max((y - YS[0]) / STEP, 0.0), len(YS) - 1.001)
    i, j = int(fx), int(fy)
    tx, ty = fx - i, fy - j
    a = h[j, i] * (1 - tx) + h[j, i + 1] * tx
    b = h[j + 1, i] * (1 - tx) + h[j + 1, i + 1] * tx
    return float(a * (1 - ty) + b * ty)


def nature(h, forest, river, dl, road_d, path_d, fbm):
    """Расстановка моделей пака по карте леса. Возвращает {модель: [x, y, z, поворот, масштаб, …]} в осях Godot
    (x, z, −y) — формат NatureScatter (scripts/levels/nature_scatter.gd). Траву по миру сажает игра сама."""
    rng = random.Random(21)
    gy_, gx_ = np.gradient(h, STEP)
    slope = np.sqrt(gx_ * gx_ + gy_ * gy_)
    d_river, surf, half = river
    inside_fort = poly_mask(PL(W["FORTRESS"]["walls"]))
    no_tree = np.zeros(GX.shape, dtype=bool)
    for poly in W["TERRACES"] + W["FIELDS"] + W["GARDENS"]:
        no_tree |= poly_mask(PL(poly))
    houses = [(it["x"], it["y"], 14.0 if it["kind"] == "watermill" else max(it["w"], it["d"]) / 2 + 3.0)
              for it in village_plan()]
    flowers = noise_field(30.0, 5.3, lambda v: noise.noise(v))
    ponds = [P(x, y) + (r,) for x, y, r in W["PONDS"]]
    ruins = [P(*t) for t in W["RUIN_TOWERS"]] + [P(t[0], t[1]) for t in W["RUIN_WALLS"]]

    def cell(x, y):
        i = int(round((x - XS[0]) / STEP))
        j = int(round((y - YS[0]) / STEP))
        return min(max(j, 0), len(YS) - 1), min(max(i, 0), len(XS) - 1)

    def free(x, y, clear_road=4.0):
        if not (XS[0] + 3 < x < XS[-1] - 3 and YS[0] + 3 < y < YS[-1] - 3):
            return False
        j, i = cell(x, y)
        if inside_fort[j, i] or dl[j, i] > -3.0 or d_river[j, i] < half[j, i] + 3.0:
            return False
        if road_d[j, i] < clear_road or path_d[j, i] < clear_road - 1.5:
            return False
        if any(math.hypot(x - px_, y - py_) < pr + 3.0 for px_, py_, pr in ponds):
            return False
        if any(math.hypot(x - rx, y - ry) < 12.0 for rx, ry in ruins):
            return False
        return not any(math.hypot(x - hx, y - hy) < r for hx, hy, r in houses)

    placed = {}

    def put(kind, x, y, s_lo=0.9, s_hi=1.3, sink=0.15, z=None):
        name = rng.choice(PACK[kind])
        zz = (height_at(h, x, y) - sink) if z is None else z
        placed.setdefault(name, []).extend([round(x, 2), round(zz, 2), round(-y, 2),
                                            round(rng.uniform(0, math.tau), 2), round(rng.uniform(s_lo, s_hi), 2)])

    def tree(region, x, y, s_lo=1.0, s_hi=1.7):
        r, acc = rng.random(), 0.0
        for kind, share in zip(("pine", "oak", "birch", "maple", "dead"), MIX[region]):
            acc += share
            if r < acc:
                put(kind, x, y, s_lo, s_hi)
                return
        put("oak", x, y, s_lo, s_hi)

    # Лес: дрожащая сетка 5 м, вероятность — по карте леса; на полянах — изредка дерево или куст.
    for y in np.arange(YS[0] + 4, YS[-1] - 4, 5.0):
        for x in np.arange(XS[0] + 4, XS[-1] - 4, 5.0):
            px_, py_ = x + rng.uniform(-2.2, 2.2), y + rng.uniform(-2.2, 2.2)
            j, i = cell(px_, py_)
            f = forest[j, i]
            if no_tree[j, i] or slope[j, i] > 1.1 or not free(px_, py_):
                continue
            if rng.random() > f ** 1.2 * 0.92:
                if f < 0.25 and rng.random() < 0.012:
                    tree("west", px_, py_, 1.0, 1.5)
                elif rng.random() < f * 0.35:
                    put("bush", px_, py_, 0.9, 1.5, 0.05)
                continue
            region = "foot" if h[j, i] > 22 else "north" if py_ > 380 else "east" if px_ > 120 else "west"
            tree(region, px_, py_)
            if rng.random() < 0.25:
                put("bush", px_ + rng.uniform(-2, 2), py_ + rng.uniform(-2, 2), 0.9, 1.6, 0.05)
    # Деревня: по дереву-два у домов.
    for hx, hy, r in houses:
        for _ in range(2):
            a = rng.uniform(0, math.tau)
            x, y = hx + math.cos(a) * (r + 5), hy + math.sin(a) * (r + 5)
            if free(x, y, 3.0):
                tree("west", x, y, 0.9, 1.3)
    # Деревня: деревья и кусты между дворами (на концепте деревня в зелени), во дворах — кусты у забора и цветы.
    for y in np.arange(-110.0, 110.0, 7.0):
        for x in np.arange(-110.0, 110.0, 7.0):
            px_, py_ = x + rng.uniform(-3, 3), y + rng.uniform(-3, 3)
            if math.hypot(px_, py_) > 110 or not free(px_, py_, 3.0):
                continue
            j, i = cell(px_, py_)
            if no_tree[j, i]:
                continue
            r = rng.random()
            if r < 0.12:
                tree("west", px_, py_, 0.9, 1.4)
            elif r < 0.3:
                put("bush", px_, py_, 0.8, 1.3, 0.05)
    for it in village_plan():
        y_ = yard(it) if "door" in it else None
        if not y_:
            continue
        (x0, y0), (x1, _), (_, y1), _ = y_[0]
        for _ in range(6):
            side = rng.randrange(4)
            t = rng.random()
            bx, by = [(x0 + (x1 - x0) * t, y0 + 0.6), (x0 + (x1 - x0) * t, y1 - 0.6),
                      (x0 + 0.6, y0 + (y1 - y0) * t), (x1 - 0.6, y0 + (y1 - y0) * t)][side]
            if math.hypot(bx - y_[1][0], by - y_[1][1]) > 2.5:
                put("bush", bx, by, 0.7, 1.1, 0.05)
        for _ in range(5):
            fx, fy = rng.uniform(x0 + 1, x1 - 1), rng.uniform(y0 + 1, y1 - 1)
            if abs(fx - it["x"]) > it["w"] / 2 + 0.8 or abs(fy - it["y"]) > it["d"] / 2 + 0.8:
                put("flower", fx, fy, 0.8, 1.2, 0.02)
    # Сухие деревья вокруг старого кладбища.
    cx, cy = P(415, 525)
    for _ in range(40):
        a, r = rng.uniform(0, math.tau), rng.uniform(55, 85)
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        if free(x, y):
            put("dead", x, y, 0.9, 1.4)
    # Ивы, тростник и кувшинки — вдоль реки.
    rp = [P(x, y) for x, y, w in W["RIVER"]]
    for (ax, ay), (bx, by) in zip(rp, rp[1:]):
        L = math.hypot(bx - ax, by - ay)
        nx_, ny_ = -(by - ay) / L, (bx - ax) / L
        for t in np.arange(0, L, 1.4):
            x, y = ax + (bx - ax) * t / L, ay + (by - ay) * t / L
            j, i = cell(x, y)
            hw = half[j, i]
            for side in (-1, 1):
                if rng.random() < 0.45:
                    o = hw + rng.uniform(0.3, 1.6)
                    put("reed", x + nx_ * o * side, y + ny_ * o * side, 0.9, 1.3, 0.1)
                if rng.random() < 0.06:
                    o = hw + rng.uniform(5, 9)
                    wx, wy = x + nx_ * o * side, y + ny_ * o * side
                    if free(wx, wy, 3.0):
                        put("willow", wx, wy, 1.0, 1.5)
                if rng.random() < 0.05:
                    o = hw - rng.uniform(1.0, 3.0)
                    put("lily", x + nx_ * o * side, y + ny_ * o * side, 0.8, 1.3, z=float(surf[j, i]) - 0.5 + 0.01)
    # Берега озера: тростник у кромки, кувшинки на тихой воде.
    lake = PL(W["LAKE"])
    for k in range(len(lake)):
        (ax, ay), (bx, by) = lake[k], lake[(k + 1) % len(lake)]
        L = math.hypot(bx - ax, by - ay)
        for t in np.arange(0, L, 2.0):
            x, y = ax + (bx - ax) * t / L, ay + (by - ay) * t / L
            if rng.random() < 0.35:
                put("reed", x + rng.uniform(-1.5, 1.5), y + rng.uniform(-1.5, 1.5), 0.9, 1.3, 0.1)
            if rng.random() < 0.04:
                put("lily", x + rng.uniform(-6, 6), y + rng.uniform(-6, 6), 0.8, 1.4, z=LAKE_Z + 0.01)
    # Утёсы по берегам реки — камни по бровке (откос там крутой, скала вместо голой земли).
    cliff = RIVER_CLIFF[0]
    if cliff is not None:
        js, is_ = np.nonzero(cliff[::2, ::2])
        for j, i in zip(js * 2, is_ * 2):
            if rng.random() < 0.35:
                put("rock", float(XS[i]) + rng.uniform(-1, 1), float(YS[j]) + rng.uniform(-1, 1), 1.2, 2.6, 0.5)
    # У омута мельницы — ивы и камыш (CANON: Ганс тайно закапывает вещи павших под ивами).
    mill = next(i for i in village_plan() if i["kind"] == "watermill")
    mm = mill_site(mill)
    for ox, oy, s_ in ((-10.5, -5.0, 1.5), (-15.0, -16.0, 1.3), (-9.0, 6.5, 1.2)):   # не перед мельницей (камера — с юга)
        put("willow", mill["x"] + ox, mill["y"] + oy, s_, s_ + 0.1, 0.2)
    for k in range(10):
        a = mm["flow"] - math.pi / 2 + rng.uniform(-0.9, 0.9)
        put("reed", mm["pool"][0] + math.cos(a) * 6.5, mm["pool"][1] + math.sin(a) * 6.5, 0.9, 1.3, 0.1)
    # Камни: скопления на каменистых выходах + валуны по лесу и у подножий.
    for x, y, r in W["ROCKS"]:
        cx, cy = P(x, y)
        for _ in range(int(r * 0.7)):
            a, rr = rng.uniform(0, math.tau), r * math.sqrt(rng.random()) * 0.8
            put("rock", cx + math.cos(a) * rr, cy + math.sin(a) * rr, 2.0, 5.5, 0.6)
    for _ in range(1800):
        x, y = rng.uniform(XS[0] + 5, XS[-1] - 5), rng.uniform(YS[0] + 5, YS[-1] - 5)
        j, i = cell(x, y)
        if free(x, y) and (forest[j, i] > 0.3 or 8 < h[j, i] < 40) and rng.random() < 0.5:
            put("rock", x, y, 0.8, 2.6, 0.3)
    # Цветочные поляны — пятнами по шуму на лугах.
    for y in np.arange(YS[0] + 4, YS[-1] - 4, 3.0):
        for x in np.arange(XS[0] + 4, XS[-1] - 4, 3.0):
            j, i = cell(x, y)
            if forest[j, i] < 0.2 and flowers[j, i] > 0.3 and not no_tree[j, i] and rng.random() < 0.6 \
                    and slope[j, i] < 0.6 and free(x, y, 3.0):
                put("flower", x + rng.uniform(-1.4, 1.4), y + rng.uniform(-1.4, 1.4), 0.9, 1.3, 0.02)
    return placed


# --- Дороги свободны ------------------------------------------------------------------------------

ROAD_SOLID_MARGIN = 0.8   # зазор от края ленты до камня, ствола или предмета, м
ROAD_CELL = 8.0           # ячейка сетки отрезков дорог, м
ROAD_CLEARED = {}         # модель → сколько убрано с дорог за сборку


def road_footprint(name, rec):
    """Радиус занятого места на масштаб 1; 0 — низкое и мягкое: на ленте запрещён только центр."""
    if name.startswith("Rock"):
        return rec["crown"]
    if "box" in rec:
        return math.hypot(rec["box"][0], rec["box"][2]) / 2
    if name in ("Pr_Roots", "Pr_Ivy", "Pr_Vine", "Pr_RiverStones"):
        return 0.0
    if name.startswith("Pr_"):
        return rec["crown"]
    if name.startswith("Bush"):
        return rec["crown"] * 0.7
    if name.startswith(("Dt_", "Grass", "Flower", "Petals", "LilyPad", "Reed", "Plant")):
        return 0.0
    return min(rec["trunk"], 0.35)                   # дерево: мера ствола у ивы и сосны завышена низкими ветками


def clear_roads(placed, road_d, path_d):
    """Последнее слово расстановки: на ленту дороги, тропы или улицы не заходит ничего, откуда бы оно ни взялось.
    Сетка road_d грубее ленты (ошибка до 1,4 м), поэтому близкие к дорогам объекты проверяются точно, по отрезкам.
    Случайные числа не тратит: лес от этого не перестраивается."""
    import json
    info = {}
    base = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "models", "nature")
    for fn in ("pack.json", "pack_extras.json"):
        with open(os.path.join(base, fn), encoding="utf-8") as f:
            info.update(json.load(f)["models"])
    grid = {}
    for kind, pts in ROAD_LINES:
        for a, b in zip(pts, pts[1:]):
            n = int(math.dist(a, b) // ROAD_CELL) + 1
            for t in range(n + 1):
                key = (int((a[0] + (b[0] - a[0]) * t / n) // ROAD_CELL), int((a[1] + (b[1] - a[1]) * t / n) // ROAD_CELL))
                grid.setdefault(key, set()).add((ROAD_HALF[kind], tuple(a), tuple(b)))

    def edge(x, y, reach):
        best = 1e9
        cx, cy = int(x // ROAD_CELL), int(y // ROAD_CELL)
        for i_ in range(cx - reach, cx + reach + 1):
            for j_ in range(cy - reach, cy + reach + 1):
                for half, a, b in grid.get((i_, j_), ()):
                    vx, vy = b[0] - a[0], b[1] - a[1]
                    t = max(0.0, min(1.0, ((x - a[0]) * vx + (y - a[1]) * vy) / (vx * vx + vy * vy + 1e-9)))
                    best = min(best, math.hypot(x - a[0] - vx * t, y - a[1] - vy * t) - half)
        return best

    for name in list(placed):
        r0 = road_footprint(name, info.get(name, {"crown": 0.5, "trunk": 0.3}))
        margin = ROAD_SOLID_MARGIN if r0 > 0.0 else 0.0
        d = placed[name]
        kept = []
        for k in range(0, len(d), 5):
            x, y, s = d[k], -d[k + 2], d[k + 4]
            clear = r0 * s + margin
            i = min(max(int(round((x - XS[0]) / STEP)), 0), len(XS) - 1)
            j = min(max(int(round((y - YS[0]) / STEP)), 0), len(YS) - 1)
            if road_d[j, i] > clear + 5.0 and path_d[j, i] > clear + 4.0:   # с запасом на грубость сетки и ширину ленты
                kept.extend(d[k:k + 5])
            elif edge(x, y, int((clear + 3.0) // ROAD_CELL) + 1) >= clear:
                kept.extend(d[k:k + 5])
            else:
                ROAD_CLEARED[name] = ROAD_CLEARED.get(name, 0) + 1
        if kept:
            placed[name] = kept
        else:
            del placed[name]


def write_roads_json():
    """Линии дорог для проверки в игре (Tools/godot/tests/world_roads_test.gd)."""
    import json
    path = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "levels", "world_roads.json")
    data = [{"kind": k, "half": ROAD_HALF[k], "pts": [[round(float(x), 2), round(float(y), 2)] for x, y in pts]}
            for k, pts in ROAD_LINES]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))


# --- Наполнение: подлесок и мелочи (Tools/blender/nature_extras.py) ------------------------------------

# Граница наполнения: None — весь мир (образец у Главного моста автор одобрил 2026-11-06).
EXTRAS_ZONE = None

# Особые места: без квестов, находки для глаза (решение автора: 10–15). x, y — центр (Blender), r — поляна без деревьев.
VIGNETTES = {
    "spring": {"kind": "spring", "x": 212.0, "y": 216.0, "r": 10.0, "pool": 4.2, "depth": 0.75},
    "falls": {"kind": "spring", "x": -560.0, "y": 165.0, "r": 9.0, "pool": 3.4, "depth": 0.7},
    "giant": {"kind": "giant", "x": 258.0, "y": 250.0, "r": 13.0, "pool": 6.5, "depth": 0.7},
    "ruin": {"kind": "ruin", "x": 58.0, "y": 178.0, "r": 11.0},
    "stones": {"kind": "stones", "x": -135.0, "y": 235.0, "r": 12.0},
    "outcrop_w": {"kind": "outcrop", "x": -240.0, "y": 45.0, "r": 13.0},
    "outcrop_s": {"kind": "outcrop", "x": -165.0, "y": -62.0, "r": 11.0},
    "marsh": {"kind": "marsh", "x": 283.0, "y": -58.0, "r": 15.0, "depth": 0.5,
              "pools": [(0.0, 0.0, 5.0), (-6.5, 3.5, 3.0), (6.0, -3.0, 3.4), (1.5, 7.0, 2.6)]},
    "arch": {"kind": "arch", "x": -175.0, "y": 335.0, "r": 9.0},
    "oak": {"kind": "oak", "x": 120.0, "y": 520.0, "r": 13.0},
    "camp": {"kind": "camp", "x": 45.0, "y": -140.0, "r": 8.0},
    "piers": {"kind": "piers", "x": 24.0, "y": 333.0, "r": 7.0},
}


def vignette_terrain(h, river):
    """Площадки особых мест: ровно, под водой — чаши. Запоминает высоту и гладь. Русло реки не засыпается."""
    d_r, _, half_r = river
    h0 = h.copy()
    for key, v in VIGNETTES.items():
        if v["kind"] == "piers":                             # обломки моста: привязка к реке, опора — на западном берегу
            (qx, qy), flow, width, surf = river_at(v["x"], v["y"])
            nx_, ny_ = math.cos(flow + math.pi / 2), math.sin(flow + math.pi / 2)
            if nx_ > 0.0:
                nx_, ny_ = -nx_, -ny_
            v.update(x=qx + nx_ * (width / 2 + 7.0), y=qy + ny_ * (width / 2 + 7.0), q=(qx, qy), n=(nx_, ny_), width=width, water=surf - 0.5)
        d = np.hypot(GX - v["x"], GY - v["y"])
        z = sample(h, v["x"], v["y"])
        v["z"] = z
        h = pad(h, np.maximum(d - v["r"] * 0.7, 0.0), z, 7.0)
        pools = [(0.0, 0.0, v["pool"])] if "pool" in v else v.get("pools", [])
        if pools:                                            # берег не ниже воды, иначе край меша воды виден прямой линией
            h = np.where(d < v["r"], np.maximum(h, z - 0.02), h)
        if pools:
            v["surface"] = z - 0.18
        for ox, oy, pr in pools:
            dp = np.hypot(GX - v["x"] - ox, GY - v["y"] - oy)
            bowl = z - 0.1 - v["depth"] * np.clip(1.0 - (dp / pr) ** 2, 0.0, 1.0)
            h = np.where(dp < pr + 0.5, np.minimum(h, bowl), h)
    w = smoothstep(half_r - 0.5, half_r + 3.5, d_r)
    return h0 * (1.0 - w) + h * w


def gameplay_points():
    """Где стоят жители и лагеря врагов (Blender x, y): рядом не ставить предметы с коллизией. Данные — из скриптов игры."""
    import re
    out = []
    for rel in (("scripts", "levels", "world_camps.gd"), ("scripts", "data", "village_quests.gd")):
        text = open(os.path.join(PROJECT, "Game", "CatsSoulDebt", *rel), encoding="utf-8").read()
        for m in re.finditer(r'"at":\s*Vector2\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)', text):
            out.append((float(m.group(1)), -float(m.group(2))))
    return out


def extras(placed, h, forest, river, dl, road_d, path_d, fbm):
    """Подлесок и мелочи по местам: лес, опушка, луг, берег, озеро, обочина, вырубка, кладбище, горы, деревня; плющ и корни
    у деревьев. Свой генератор случайных чисел: прежняя расстановка леса не меняется. Клетка 1,5 м — не больше одного
    предмета; вдали от дорог реже. Показывает участками вокруг Рэя scripts/levels/nature_scatter.gd."""
    rng = random.Random(77)
    x0, y0, x1, y1 = EXTRAS_ZONE or (XS[0] + 4, YS[0] + 4, XS[-1] - 4, YS[-1] - 4)
    # Деревья и камни не стоят в особых местах.
    for name, flat_ in list(placed.items()):
        keep = []
        for k in range(0, len(flat_), 5):
            x, y = flat_[k], -flat_[k + 2]
            if not any(math.hypot(x - v["x"], y - v["y"]) < v["r"] for v in VIGNETTES.values()):
                keep.extend(flat_[k:k + 5])
        placed[name] = keep
    gy_, gx_ = np.gradient(h, STEP)
    slope = np.sqrt(gx_ * gx_ + gy_ * gy_)
    d_river, surf, half = river
    no_go = poly_mask(PL(W["FORTRESS"]["walls"])) | (np.hypot(GX, GY) < PLAZA_R + 3.0)
    for poly in W["TERRACES"] + W["FIELDS"] + W["GARDENS"]:
        no_go |= poly_mask(PL(poly))
    for it in village_plan():
        r = 10.0 if it["kind"] == "watermill" else 3.0
        no_go |= rect_dist(it["x"], it["y"], it["w"], it["d"], it["rot"]) < r
    for x, y, r in W["PONDS"]:
        cx, cy = P(x, y)
        no_go |= np.hypot(GX - cx, GY - cy) < r + 1.0
    for v in VIGNETTES.values():
        no_go |= np.hypot(GX - v["x"], GY - v["y"]) < v["r"] * 0.85
    keep_clear = [(P(p[3], p[4]), 9.0) for p in W["POIS"]] + [(P(x, y), 9.0) for x, y in W["LANTERNS"]] + [(q, 6.0) for q in gameplay_points()]
    keep_grid = {}
    for (kx, ky), kr in keep_clear:
        keep_grid.setdefault((int(kx // 16), int(ky // 16)), []).append((kx, ky, kr))
    fern_n = noise_field(18.0, 11.3, lambda v: noise.noise(v))
    tall_n = noise_field(12.0, 12.9, lambda v: noise.noise(v))
    drift_n = noise_field(16.0, 14.1, lambda v: noise.noise(v))
    spec_n = noise_field(70.0, 15.7, lambda v: noise.noise(v))
    trees_near = {}
    for name, flat_ in placed.items():
        if "Tree" in name:
            for k in range(0, len(flat_), 5):
                trees_near.setdefault((int(flat_[k] // 4), int(-flat_[k + 2] // 4)), []).append((flat_[k], -flat_[k + 2]))
    lx, ly = P(*next((p[3], p[4]) for p in W["POIS"] if p[0] == "logging"))
    cemx, cemy = P(*next((p[3], p[4]) for p in W["POIS"] if p[0] == "cemetery"))

    def ss(a, b, x):
        t = min(1.0, max(0.0, (x - a) / (b - a)))
        return t * t * (3.0 - 2.0 * t)

    def tree_close(x, y, r):
        cx, cy = int(x // 4), int(y // 4)
        for a in range(cx - 1, cx + 2):
            for b in range(cy - 1, cy + 2):
                for tx, ty in trees_near.get((a, b), ()):
                    if math.hypot(tx - x, ty - y) < r:
                        return True
        return False

    def cell(x, y):
        return (min(max(int(round((y - YS[0]) / STEP)), 0), len(YS) - 1), min(max(int(round((x - XS[0]) / STEP)), 0), len(XS) - 1))

    def put(name, x, y, s_lo, s_hi, sink, z=None, rot=None):
        zz = (height_at(h, x, y) - sink) if z is None else z
        placed.setdefault(name, []).extend([round(x, 2), round(zz, 2), round(-y, 2),
                                            round(rng.uniform(0, math.tau) if rot is None else rot, 2), round(rng.uniform(s_lo, s_hi), 2)])

    def prop_ok(x, y, rr):
        """Предмет с коллизией: не на дереве, не на дороге и не у места интереса, жителя или лагеря."""
        j, i = cell(x, y)
        if road_d[j, i] < rr + 3.5 or path_d[j, i] < rr + 2.2 or no_go[j, i] or tree_close(x, y, rr + 0.8):
            return False
        cx, cy = int(x // 16), int(y // 16)
        for a in range(cx - 1, cx + 2):
            for b in range(cy - 1, cy + 2):
                for kx, ky, kr in keep_grid.get((a, b), ()):
                    if math.hypot(x - kx, y - ky) < kr:
                        return False
        return True

    #: вид → (модель, масштаб от, масштаб до, заглубление)
    K = {"fern_a": ("Dt_Fern_A", 0.8, 1.25, 0.02), "fern_b": ("Dt_Fern_B", 0.85, 1.35, 0.02), "fern_c": ("Dt_Fern_C", 0.8, 1.2, 0.02),
         "broad_a": ("Dt_Broad_A", 0.8, 1.2, 0.02), "broad_b": ("Dt_Broad_B", 0.8, 1.3, 0.02),
         "tuft": ("Dt_Tuft_A", 0.8, 1.25, 0.03), "tall": ("Dt_Tuft_Tall", 0.8, 1.2, 0.03), "dry": ("Dt_Tuft_Dry", 0.8, 1.2, 0.03),
         "cattail": ("Dt_Cattail", 0.85, 1.15, 0.08), "lily": ("Dt_Lily", 0.85, 1.2, 0.02), "spike": ("Dt_Spike", 0.85, 1.2, 0.02),
         "poppy": ("Dt_Poppy", 0.85, 1.2, 0.02), "umbel": ("Dt_Umbel", 0.85, 1.2, 0.02),
         "moss_a": ("Dt_Moss_A", 0.7, 1.3, 0.02), "moss_b": ("Dt_Moss_B", 0.7, 1.3, 0.02), "litter": ("Dt_Litter", 0.7, 1.2, 0.0),
         "twigs": ("Dt_Twigs", 0.7, 1.1, 0.0), "shroom": ("Dt_Shroom_Tan", 0.9, 1.4, 0.01), "shroom_r": ("Dt_Shroom_Red", 0.9, 1.3, 0.01),
         "peb_a": ("Dt_Pebbles_A", 0.8, 1.4, 0.03), "peb_b": ("Dt_Pebbles_B", 0.8, 1.4, 0.03)}
    FLAT = {"moss_a", "moss_b", "litter", "twigs"}
    MADE = {"waystone": ("Pr_Waystone", 0.6), "cairn": ("Pr_Cairn", 0.7), "barrels": ("Pr_Barrels", 1.1), "crates": ("Pr_Crates", 1.1),
            "fence": ("Pr_FenceOld", 1.8), "boat": ("Pr_Boat", 1.7), "poles": ("Pr_FishPoles", 1.5)}

    def roll(table):
        r, acc = rng.random(), 0.0
        for kind, p in table:
            acc += p
            if r < acc:
                return kind
        return None

    for y in np.arange(y0, y1, 1.5):
        for x in np.arange(x0, x1, 1.5):
            px_, py_ = float(x) + rng.uniform(-0.7, 0.7), float(y) + rng.uniform(-0.7, 0.7)
            j, i = cell(px_, py_)
            if no_go[j, i] or slope[j, i] > 0.95:
                continue
            dlv = float(dl[j, i])
            if dlv > -1.0:
                continue
            zh = float(h[j, i])
            if zh > 58.0:
                continue
            rd, pd, f = float(road_d[j, i]), float(path_d[j, i]), float(forest[j, i])
            if rd < 3.3 or pd < 1.9:
                continue
            dr = float(d_river[j, i] - half[j, i])
            if dr < -2.5:
                continue
            if rd > 80.0 and pd > 80.0 and rng.random() < 0.45:   # глубь леса и дальние луга: туда заходят редко
                continue
            from_center = math.hypot(px_, py_)
            if from_center < 72.0:                                # деревня: мелочи у заборов и домов, без предметов
                table = [("tuft", 0.07), ("umbel", 0.02), ("poppy", 0.015), ("lily", 0.006), ("peb_a", 0.012)]
            elif dr < 7.0:                                        # берег и мелководье
                table = [("cattail", 0.24 if dr < 2.5 else 0.02), ("river", 0.02 if dr < 3.5 else 0.0), ("peb_b", 0.07 if dr < 5 else 0.01),
                         ("tall", 0.1 if dr > 0 else 0.0), ("broad_a", 0.02 if dr > 1 else 0.0), ("lily", 0.015 if dr > 1 else 0.0),
                         ("fern_c", 0.03 if dr > 2 else 0.0), ("moss_a", 0.012 if dr > 0.5 else 0.0),
                         ("boat", 0.0009 if 0.6 < dr < 4 else 0.0), ("poles", 0.0007 if 0.6 < dr < 4 else 0.0)]
            elif dlv > -9.0:                                      # берег озера
                table = [("cattail", 0.12 if dlv > -4.0 else 0.0), ("peb_b", 0.05), ("tall", 0.1), ("river", 0.012), ("moss_a", 0.01),
                         ("boat", 0.0007), ("poles", 0.0006)]
            elif zh > 28.0:                                       # горы и предгорья
                table = [("peb_a", 0.02), ("dry", 0.03), ("moss_a", 0.006), ("boulder", 0.003), ("cairn", 0.0003)]
            elif rd < 6.5 or pd < 4.0:                            # обочина
                table = [("tuft", 0.1), ("peb_a", 0.03), ("umbel", 0.03), ("poppy", 0.02), ("twigs", 0.004), ("dry", 0.02),
                         ("waystone", 0.0006), ("cairn", 0.0006), ("barrels", 0.0003), ("crates", 0.0003), ("fence", 0.0006)]
            elif math.hypot(px_ - lx, py_ - ly) < 60.0:           # заброшенная вырубка
                table = [("stump", 0.022), ("twigs", 0.06), ("dry", 0.06), ("litter", 0.03), ("log", 0.004), ("tuft", 0.04), ("umbel", 0.012)]
            elif math.hypot(px_ - cemx, py_ - cemy) < 55.0:       # старое кладбище: сухо и серо, без цветов
                table = [("dry", 0.06), ("moss_a", 0.012), ("peb_b", 0.012), ("twigs", 0.015), ("umbel", 0.004)]
            elif f >= 0.45:                                       # лес
                fern = 0.03 + 0.42 * ss(-0.1, 0.35, float(fern_n[j, i]))
                table = [("fern_b", fern * 0.45), ("fern_a", fern * 0.35), ("fern_c", fern * 0.2), ("moss_b", 0.05), ("litter", 0.07),
                         ("twigs", 0.02), ("broad_b", 0.03), ("shroom", 0.014), ("shroom_r", 0.004), ("peb_a", 0.008), ("tuft", 0.02),
                         ("lily", 0.004), ("spike", 0.004), ("stump", 0.0034), ("log", 0.003), ("boulder", 0.0045),
                         ("cairn", 0.0003), ("fence", 0.00025), ("barrels", 0.0001)]
            elif f >= 0.12:                                       # опушка
                table = [("fern_a", 0.05), ("fern_c", 0.03), ("tall", 0.07), ("tuft", 0.06), ("umbel", 0.025), ("broad_b", 0.02),
                         ("peb_a", 0.008), ("moss_a", 0.01), ("stump", 0.001), ("boulder", 0.002), ("log", 0.0008)]
            else:                                                 # луг: высокая трава и цветы пятнами
                tall = 0.01 + 0.22 * ss(0.05, 0.4, float(tall_n[j, i]))
                dryness = ss(0.1, 0.45, float(fbm[j, i]))
                table = [("dry", tall * dryness), ("tall", tall * (1 - dryness) * 0.7), ("tuft", tall * (1 - dryness) * 0.3)]
                if drift_n[j, i] > 0.12:
                    sp = float(spec_n[j, i])
                    table.append(("umbel" if sp < -0.15 else "poppy" if sp < 0.05 else "spike" if sp < 0.25 else "lily", 0.6))
                table += [("peb_a", 0.004), ("moss_a", 0.003), ("boulder", 0.0011), ("cairn", 0.00025), ("fence", 0.00025), ("waystone", 0.00015)]
            kind = roll(table)
            if kind is None:
                continue
            if kind in FLAT and slope[j, i] > 0.45:
                continue
            if kind == "river":
                put("Pr_RiverStones", px_, py_, 0.7, 1.4, 0.08)
            elif kind == "boulder":
                if prop_ok(px_, py_, 1.2):
                    put(rng.choice(("Pr_Boulder_A", "Pr_Boulder_B")), px_, py_, 0.8, 1.5, 0.12)
            elif kind in MADE:
                model, rr = MADE[kind]
                if prop_ok(px_, py_, rr):
                    put(model, px_, py_, 0.9, 1.1, 0.03)
            elif kind == "stump":
                if prop_ok(px_, py_, 0.7):
                    put(rng.choice(("Pr_Stump_A", "Pr_Stump_B")), px_, py_, 0.9, 1.3, 0.04)
            elif kind == "log":
                a = rng.uniform(0, math.tau)
                ln = 3.2
                if all(prop_ok(px_ + math.cos(a) * t, py_ - math.sin(a) * t, 0.5) for t in (-ln, 0.0, ln)):
                    put(rng.choice(("Pr_Log_A", "Pr_Log_B")), px_, py_, 0.9, 1.15, 0.05, rot=a)
            else:
                name, lo, hi, sink = K[kind]
                put(name, px_, py_, lo, hi, sink)
    # Плющ и корни у деревьев: по масштабу дерева (хвойные — без плюща, у них всё в иголках).
    for name in [n for n in placed if n.startswith(("NormalTree", "MapleTree", "BirchTree", "WillowTree", "DeadTree"))]:
        flat_ = placed[name]
        for k in range(0, len(flat_), 5):
            tx, tz, ty, s = flat_[k], flat_[k + 1], -flat_[k + 2], flat_[k + 4]
            if not (x0 <= tx <= x1 and y0 <= ty <= y1):
                continue
            if rng.random() < 0.28:
                put("Pr_Ivy", tx, ty, s * 0.85, s * 0.85, 0.0, z=tz + 0.1)
            if rng.random() < 0.35:
                put("Pr_Roots", tx, ty, s * 0.85, s * 1.05, 0.05, z=tz + 0.08)
    # Деревня: бочки и ящики за домами — с другой стороны от поленницы.
    for it in village_plan():
        if it["kind"] == "building" and rng.random() < 0.6:
            sx, sy = it["side"]
            wx, wy = it["x"] - sx * (it["w"] / 2 + 1.1) - sy * 2.0, it["y"] - sy * (it["d"] / 2 + 1.1) - sx * 2.0
            wx, wy = rotate_about(wx, wy, it["x"], it["y"], it["rot"])
            j, i = cell(wx, wy)
            if path_d[j, i] > 2.0 and road_d[j, i] > 3.5:
                put(rng.choice(("Pr_Barrels", "Pr_Crates")), wx, wy, 0.85, 1.0, 0.02)
    # У старых руин: мох, обломки, трава вокруг.
    for rx, ry in [P(*t) for t in W["RUIN_TOWERS"]] + [P(t[0], t[1]) for t in W["RUIN_WALLS"]]:
        for _ in range(18):
            a, rr = rng.uniform(0, math.tau), rng.uniform(3.5, 10.0)
            ax_, ay_ = rx + math.cos(a) * rr, ry + math.sin(a) * rr
            j, i = cell(ax_, ay_)
            if road_d[j, i] > 3.3 and path_d[j, i] > 1.9 and not no_go[j, i]:
                name, lo, hi, sink = K[rng.choice(("moss_a", "moss_b", "peb_a", "peb_a", "tall", "tuft", "fern_c", "umbel"))]
                put(name, ax_, ay_, lo, hi, sink)
    vignette_plants(placed, h)


def vignette_lump(bm, rng, cx, cy, cz, r, squash=0.75, jitter=0.2, subdiv=1):
    """Неровный камень (меш в группе места)."""
    g = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in g["verts"]:
        k = 1.0 + rng.uniform(-jitter, jitter)
        v.co = Vector((cx + v.co.x * r * k, cy + v.co.y * r * k, cz + v.co.z * r * squash * k))


def vignette_tube(bm, pts, radii, sides=7, rng=None, wob=0.0):
    """Трубка по точкам (ствол, ветка, корень) с неровными кольцами."""
    rings = []
    for k, (p, r) in enumerate(zip(pts, radii)):
        a = Vector(pts[max(0, k - 1)])
        b = Vector(pts[min(len(pts) - 1, k + 1)])
        d = (b - a).normalized()
        u = d.cross(Vector((0, 0, 1)))
        if u.length < 0.01:
            u = Vector((1, 0, 0))
        u.normalize()
        w = d.cross(u)
        ring = []
        for i in range(sides):
            t = i / sides * math.tau
            rr = r * (1.0 + (rng.uniform(-wob, wob) if rng else 0.0))
            ring.append(bm.verts.new(Vector(p) + (u * math.cos(t) + w * math.sin(t)) * rr))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new([r0[i], r0[j], r1[j], r1[i]])
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    return rings


def vignette_water(bm, cx, cy, z, r, seg=18):
    vs = [bm.verts.new((cx + math.cos(i / seg * math.tau) * r, cy + math.sin(i / seg * math.tau) * r, z)) for i in range(seg)]
    bm.faces.new(vs)


def vignette_fall(bm, pts, width):
    """Струя воды: лента по точкам (x, y, z)."""
    rows = []
    for k, p in enumerate(pts):
        a, b = Vector(pts[max(0, k - 1)]), Vector(pts[min(len(pts) - 1, k + 1)])
        d = b - a
        side = Vector((-d.y, d.x, 0.0))
        if side.length < 0.001:
            side = Vector((1, 0, 0))
        side.normalize()
        rows.append((bm.verts.new(Vector(p) - side * width / 2), bm.verts.new(Vector(p) + side * width / 2)))
    for (a0, b0), (a1, b1) in zip(rows, rows[1:]):
        f = bm.faces.new([a0, b0, b1, a1])
        f.normal_update()
        if f.normal.y > 0.0:          # шейдер воды рисует только лицевую сторону: лицом на юг, к камере
            f.normal_flip()


VIGNETTE_COLORS = {"stone": (0.56, 0.54, 0.49), "rock": (0.50, 0.48, 0.44), "bark": (0.42, 0.33, 0.25), "moss": (0.30, 0.42, 0.18),
                   "water": (0.20, 0.38, 0.46), "wood": (0.48, 0.35, 0.22), "cloth": (0.60, 0.55, 0.42), "dark": (0.20, 0.19, 0.18)}


def vignettes(col, h):
    """Особые места (меши и вода; растения вокруг — vignette_plants, в extras они идут отдельно)."""
    rng = random.Random(91)
    # Родник: кольцо камней, чаша с водой, с севера груда камней и струя (ref: диорама с прудом).
    for key in ("spring", "falls"):
        v = VIGNETTES[key]
        k_ = v["pool"] / 4.2
        g = EditGroup(col, "detail:vignette_" + key, (v["x"], v["y"]), h)
        x, y, z = v["x"], v["y"], v["z"]
        r = v["pool"]
        for k in range(17):
            a = k / 17 * math.tau + rng.uniform(-0.1, 0.1)
            if 4.45 < a < 4.95:                                  # с юга (от камеры) просвет — вид на воду
                continue
            rr = rng.uniform(0.5, 1.05) * max(k_, 0.85)
            cx_, cy_ = x + math.cos(a) * (r + 0.2), y + math.sin(a) * (r + 0.2)
            vignette_lump(g.bm("rock"), rng, cx_, cy_, z + rr * 0.15, rr, 0.75, 0.14, 2)
            if rng.random() < 0.55:
                vignette_lump(g.bm("moss"), rng, cx_, cy_, z + rr * 0.68, rr * 0.62, 0.3, 0.12)
        for ox, oy, oz, rr in ((0.0, 5.4, 0.4, 1.9), (-1.9, 5.0, 0.2, 1.5), (1.9, 5.1, 0.25, 1.5), (-0.9, 5.7, 1.9, 1.25), (1.0, 5.7, 1.8, 1.2), (0.0, 6.3, 2.6, 1.1)):
            vignette_lump(g.bm("rock"), rng, x + ox * k_, y + oy * k_, z + oz * k_, rr * k_, 0.85, 0.16, 2)
        for ox, oy, oz, rr in ((-0.9, 5.2, 2.85, 0.8), (1.2, 5.3, 2.65, 0.7), (0.2, 6.0, 3.6, 0.8)):
            vignette_lump(g.bm("moss"), rng, x + ox * k_, y + oy * k_, z + oz * k_, rr * k_, 0.35, 0.12, 2)
        s_ = v["surface"]
        vignette_water(g.bm("water"), x, y, s_, r + 0.45, 22)
        vignette_fall(g.bm("water"), [(x, y + 4.45 * k_, z + 3.05 * k_), (x, y + 3.95 * k_, z + 2.2 * k_), (x, y + 3.35 * k_, z + 1.1 * k_), (x, y + 2.75 * k_, s_ + 0.03)], 1.15 * k_)
        # Кривой ствол над водой (ref: дерево аркой над прудом).
        vignette_tube(g.bm("bark"), [(x + 5.2 * k_, y + 1.0, z - 0.2), (x + 4.9 * k_, y + 1.2, z + 1.3), (x + 3.7 * k_, y + 1.0, z + 3.0), (x + 1.7 * k_, y + 0.1, z + 4.3)], (0.62, 0.48, 0.36, 0.2), 8, rng, 0.08)
        vignette_tube(g.bm("bark"), [(x + 3.7 * k_, y + 1.0, z + 3.0), (x + 4.9 * k_, y - 0.8, z + 4.2), (x + 5.0 * k_, y - 1.6, z + 5.1)], (0.26, 0.16, 0.07), 6)
        for a in (0.4, 2.0, 3.6, 5.0):
            tx_, ty_ = x + 5.2 * k_, y + 1.0
            vignette_tube(g.bm("bark"), [(tx_, ty_, z + 0.5), (tx_ + math.cos(a), ty_ + math.sin(a), z + 0.05), (tx_ + math.cos(a) * 2.0, ty_ + math.sin(a) * 2.0, z - 0.25)], (0.24, 0.17, 0.05), 5)
        g.finish(VIGNETTE_COLORS, "Poi_")
    # Исполин: огромный упавший ствол во мху над прудом с кувшинками (ref: мшистый пень с водопадиками).
    v = VIGNETTES["giant"]
    g = EditGroup(col, "detail:vignette_giant", (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    axis = [(x - 9.5, y + 6.5, z + 0.3), (x - 4.5, y + 7.0, z + 1.5), (x + 1.0, y + 7.4, z + 3.2), (x + 6.0, y + 7.6, z + 5.2), (x + 9.0, y + 7.5, z + 6.4)]
    radii = (1.75, 1.6, 1.4, 1.15, 0.85)
    vignette_tube(g.bm("bark"), axis, radii, 12, rng, 0.06)
    for k, (bx, by, bz, ex, ey, ez, rr) in enumerate(((-4.5, 7.0, 3.0, -7.0, 2.8, 6.4, 0.42), (1.0, 7.4, 4.5, 3.5, 3.0, 8.4, 0.38), (6.0, 7.6, 6.2, 9.5, 4.5, 9.2, 0.3), (-1.5, 7.0, 3.6, -3.0, 11.5, 7.2, 0.36))):
        vignette_tube(g.bm("bark"), [(x + bx, y + by, z + bz), (x + (bx + ex) / 2 + 0.3, y + (by + ey) / 2, z + (bz + ez) / 2 + 0.2), (x + ex, y + ey, z + ez)], (rr, rr * 0.62, rr * 0.2), 6, rng, 0.08)
    # Мох — наплывы по верху ствола и у воды.
    for t in np.linspace(0.0, 1.0, 15):
        k = min(int(t * 4), 3)
        f = t * 4 - k
        px_ = Vector(axis[k]).lerp(Vector(axis[k + 1]), f)
        rr = radii[k] + (radii[k + 1] - radii[k]) * f
        vignette_lump(g.bm("moss"), rng, px_.x + rng.uniform(-0.3, 0.3), px_.y - rr * 0.25 + rng.uniform(-0.25, 0.25), px_.z + rr * 0.62, rr * rng.uniform(0.75, 1.0), 0.42, 0.14, 2)
    # Мшистый край пруда: кочки по всему кругу, кроме прохода с юга — вода не упирается в голую кромку.
    for a in np.linspace(0.0, math.tau, 27)[:-1]:
        if 4.5 < a < 5.0:
            continue
        rim = v["pool"] + rng.uniform(0.1, 0.7)
        vignette_lump(g.bm("moss"), rng, x + math.cos(a) * rim, y + math.sin(a) * rim, z - 0.18, rng.uniform(0.75, 1.5), 0.42, 0.18, 2)
    vignette_water(g.bm("water"), x, y, v["surface"], v["pool"] + 0.5, 24)
    for ox in (-3.2, 1.3):
        tz = z + (1.5 if ox < 0 else 3.0)
        vignette_fall(g.bm("water"), [(x + ox, y + 5.7, tz), (x + ox + 0.05, y + 5.5, tz - 1.0), (x + ox, y + 5.3, v["surface"] + 0.03)], 0.55)
    g.finish(VIGNETTE_COLORS, "Poi_")
    # Заросшие руины: обрывки стены, упавшие блоки и плита (ref: руины в плюще, плиты в мху).
    v = VIGNETTES["ruin"]
    g = EditGroup(col, "detail:vignette_ruin", (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    rot = 0.35
    cs, sn = math.cos(rot), math.sin(rot)

    def at(ox, oy):
        return x + cs * ox - sn * oy, y + sn * ox + cs * oy
    for course, count_ in enumerate((9, 9, 8, 6, 4, 3, 2)):           # стена ступеньками, кладка — рядами блоков
        for k in range(count_):
            ox = -5.0 + k * 1.15 + (0.55 if course % 2 else 0.0)
            px_, py_ = at(ox, 3.5)
            box(g.bm("stone"), px_, py_, z - 0.1 + course * 0.72, 1.08, 1.0, 0.68, rot + rng.uniform(-0.03, 0.03))
            if course == count_ - 1 or rng.random() < 0.12 or k == count_ - 1:
                vignette_lump(g.bm("moss"), rng, px_ + rng.uniform(-0.2, 0.2), py_ + rng.uniform(-0.2, 0.2), z - 0.1 + course * 0.72 + 0.7, rng.uniform(0.5, 0.75), 0.3, 0.2)
    for course in range(5):                                           # торцевая стена — углом
        for k in range(5 - course):
            px_, py_ = at(-5.2, 2.6 - k * 1.15)
            box(g.bm("stone"), px_, py_, z - 0.1 + course * 0.72, 1.0, 1.08, 0.68, rot + rng.uniform(-0.03, 0.03))
    rotated_box(g.bm("stone"), *at(3.4, -0.6), z + 1.0, 6.2, 1.6, 0.42, math.radians(-24), rot + 0.5)      # рухнувшая плита
    for t in (-1.9, -0.6, 0.7, 1.9):                                  # мох наплывами по плите
        sx_, sy_ = at(3.4 + t * math.cos(0.5), -0.6 + t * math.sin(0.5))
        vignette_lump(g.bm("moss"), rng, sx_ + rng.uniform(-0.2, 0.2), sy_ + rng.uniform(-0.25, 0.25), z + 1.26 - t * math.tan(math.radians(-24)) * 0.92, rng.uniform(0.55, 0.85), 0.28, 0.2)
    for ox, oy, s_ in ((-1.0, -1.8, 0.9), (0.2, -3.2, 0.7), (-3.0, -3.5, 0.8), (4.7, 3.0, 0.8), (-2.6, -0.4, 0.6), (6.3, 1.2, 0.7), (1.8, -4.5, 0.55)):
        px_, py_ = at(ox, oy)
        rotated_box(g.bm("stone"), px_, py_, z + s_ * 0.2, s_ * 1.3, s_, s_ * 0.8, rng.uniform(-0.25, 0.25), rng.uniform(0, math.tau))
        if rng.random() < 0.7:
            vignette_lump(g.bm("moss"), rng, px_, py_, z + s_ * 0.75, s_ * 0.62, 0.32, 0.2)
    px_, py_ = at(-3.5, -1.5)                                         # старая стела: без знаков
    box(g.bm("stone"), px_, py_, z - 0.1, 1.5, 1.1, 0.35, rot)
    box(g.bm("stone"), px_, py_, z + 0.25, 1.0, 0.45, 2.5, rot)
    vignette_lump(g.bm("moss"), rng, px_, py_, z + 2.74, 0.55, 0.3, 0.18)
    g.finish(VIGNETTE_COLORS, "Poi_")
    vignette_stones(col, h, rng)
    for key in ("outcrop_w", "outcrop_s"):
        vignette_outcrop(col, h, rng, key)
    vignette_marsh(col, h, rng)
    vignette_arch(col, h, rng)
    vignette_oak(col, h, rng)
    vignette_camp(col, h, rng)
    vignette_piers(col, h, rng)


def vignette_stones(col, h, rng):
    """Стоячие камни на лугу: круг без знаков и надписей, два упали (ref: старые стелы)."""
    v = VIGNETTES["stones"]
    g = EditGroup(col, "detail:vignette_stones", (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    for k in range(9):
        a = k / 9 * math.tau + rng.uniform(-0.07, 0.07)
        px_, py_ = x + math.cos(a) * 7.2, y + math.sin(a) * 7.2
        if k in (2, 6):                                    # упавшие
            rotated_box(g.bm("rock"), px_, py_, z + 0.28, 3.1, 0.95, 0.7, rng.uniform(-0.06, 0.06), a + rng.uniform(-0.5, 0.5))
            vignette_lump(g.bm("moss"), rng, px_, py_, z + 0.62, 0.95, 0.28, 0.2, 2)
            continue
        tall = rng.uniform(2.7, 4.3)
        lean = rng.uniform(-0.09, 0.09)
        rotated_box(g.bm("rock"), px_, py_, z + tall / 2 - 0.25, 1.15, 0.72, tall, lean, a + math.pi / 2 + rng.uniform(-0.2, 0.2))
        rotated_box(g.bm("rock"), px_, py_, z + tall - 0.1, 0.8, 0.55, 0.5, lean + rng.uniform(-0.2, 0.2), a + math.pi / 2)
        if rng.random() < 0.75:
            vignette_lump(g.bm("moss"), rng, px_, py_, z + tall + 0.05, 0.62, 0.32, 0.2, 2)
        vignette_lump(g.bm("moss"), rng, px_ + rng.uniform(-0.5, 0.5), py_ + rng.uniform(-0.5, 0.5), z + 0.05, 0.75, 0.4, 0.2)
    box(g.bm("rock"), x, y, z - 0.1, 2.4, 1.6, 0.55, 0.4)                       # плоский камень в середине
    vignette_lump(g.bm("moss"), rng, x - 0.5, y + 0.2, z + 0.47, 0.75, 0.22, 0.2, 2)
    g.finish(VIGNETTE_COLORS, "Poi_")


def vignette_outcrop(col, h, rng, key):
    """Каменная гряда на лугу: плоские уступы один над другим, мох по верху (ref: скальные выходы в пейзажах)."""
    v = VIGNETTES[key]
    g = EditGroup(col, "detail:vignette_" + key, (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    rot = rng.uniform(0, math.tau)
    cs, sn = math.cos(rot), math.sin(rot)
    shelves = ((-6.0, 0.0, 0.1, 3.3), (-2.2, 1.0, 0.2, 3.9), (2.2, 0.4, 0.15, 3.4), (6.0, -0.8, 0.05, 2.7), (-3.6, 0.6, 1.0, 2.5), (0.2, 1.1, 1.1, 2.9), (3.2, 0.5, 0.95, 2.0), (-1.3, 1.2, 1.9, 1.8))
    for ox, oy, oz, r in shelves:
        px_, py_ = x + cs * ox - sn * oy, y + sn * ox + cs * oy
        vignette_lump(g.bm("rock"), rng, px_, py_, z + oz, r, 0.34, 0.12, 2)
        if rng.random() < 0.8:
            vignette_lump(g.bm("moss"), rng, px_ + rng.uniform(-0.6, 0.6), py_ + rng.uniform(-0.6, 0.6), z + oz + r * 0.27, r * rng.uniform(0.45, 0.7), 0.14, 0.18, 2)
    g.finish(VIGNETTE_COLORS, "Poi_")


def vignette_marsh(col, h, rng):
    """Болотце: тёмные лужи, сухие стволы в воде, «колени» корней и кочки мха (ref: болото с кипарисами)."""
    v = VIGNETTES["marsh"]
    g = EditGroup(col, "detail:vignette_marsh", (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    s_ = v["surface"]
    for ox, oy, pr in v["pools"]:
        vignette_water(g.bm("water"), x + ox, y + oy, s_, pr + 0.4, 16)
        for k in range(int(pr * 6)):                       # кочки сплошь: сетка рельефа 2 м дала бы лужам прямые края
            a = k / int(pr * 6) * math.tau + rng.uniform(-0.1, 0.1)
            vignette_lump(g.bm("moss"), rng, x + ox + math.cos(a) * (pr * 0.92), y + oy + math.sin(a) * (pr * 0.92), z - 0.2, rng.uniform(0.7, 1.25), 0.42, 0.2, 2)
    for ox, oy, tall, r in ((-2.0, 1.0, 6.5, 0.52), (2.6, -1.5, 8.0, 0.62), (-6.0, 4.5, 4.5, 0.4), (6.4, -2.0, 5.4, 0.45)):
        bx, by = x + ox, y + oy
        lean = (rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7))
        vignette_tube(g.bm("bark"), [(bx, by, s_ - 0.4), (bx + lean[0] * 0.3, by + lean[1] * 0.3, s_ + tall * 0.4), (bx + lean[0] * 0.7, by + lean[1] * 0.7, s_ + tall * 0.75), (bx + lean[0], by + lean[1], s_ + tall)], (r * 1.5, r, r * 0.62, r * 0.2), 7, rng, 0.1)
        for a in (0.3, 1.8, 3.4, 4.9):                     # раструб у воды
            vignette_tube(g.bm("bark"), [(bx, by, s_ + 0.9), (bx + math.cos(a) * r * 2.0, by + math.sin(a) * r * 2.0, s_ + 0.15), (bx + math.cos(a) * r * 3.2, by + math.sin(a) * r * 3.2, s_ - 0.3)], (r * 0.5, r * 0.34, r * 0.1), 5)
        for t, a, ln in ((0.55, rng.uniform(0, math.tau), 1.9), (0.8, rng.uniform(0, math.tau), 1.5)):
            sx_, sy_, sz_ = bx + lean[0] * t, by + lean[1] * t, s_ + tall * t
            vignette_tube(g.bm("bark"), [(sx_, sy_, sz_), (sx_ + math.cos(a) * ln * 0.6, sy_ + math.sin(a) * ln * 0.6, sz_ + 0.5), (sx_ + math.cos(a) * ln, sy_ + math.sin(a) * ln, sz_ + 1.0)], (r * 0.28, r * 0.17, r * 0.05), 5)
    for k in range(12):                                    # «колени» корней над водой
        ox, oy, pr = rng.choice(v["pools"])
        a, rr = rng.uniform(0, math.tau), rng.uniform(0.6, pr - 0.3)
        bx, by = x + ox + math.cos(a) * rr, y + oy + math.sin(a) * rr
        tall = rng.uniform(0.35, 0.95)
        vignette_tube(g.bm("bark"), [(bx, by, s_ - 0.2), (bx, by, s_ + tall * 0.6), (bx + 0.04, by, s_ + tall)], (0.28, 0.17, 0.04), 6)
    g.finish(VIGNETTE_COLORS, "Poi_")


def vignette_arch(col, h, rng):
    """Разрушенная арка у старого тракта: одна опора цела, вторая обломана, кольцо камней оборвано (ref: руины на холме)."""
    v = VIGNETTES["arch"]
    g = EditGroup(col, "detail:vignette_arch", (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    rot = 0.25
    cs, sn = math.cos(rot), math.sin(rot)

    def at(ox, oy=0.0):
        return x + cs * ox - sn * oy, y + sn * ox + cs * oy
    for side, courses in ((-1, 7), (1, 4)):
        for c in range(courses):
            px_, py_ = at(side * 3.0 + rng.uniform(-0.05, 0.05))
            box(g.bm("stone"), px_, py_, z - 0.15 + c * 0.62, 1.35, 1.25, 0.58, rot + rng.uniform(-0.04, 0.04))
    cx_z = z - 0.15 + 7 * 0.62
    R = 3.0
    for k in range(7):
        a = math.pi - (k + 0.5) * (math.pi * 0.72) / 7     # от левой опоры вправо, обрывается на 3/4 дуги
        ox, oz = math.cos(a) * R, math.sin(a) * R
        px_, py_ = at(ox)
        rotated_box(g.bm("stone"), px_, py_, cx_z + oz, 1.05, 1.15, 0.6, math.pi / 2 - a, rot)
    for ox, oy, s_ in ((3.4, -2.0, 0.85), (1.8, -3.0, 0.7), (4.6, 0.6, 0.7), (0.3, 2.4, 0.6), (2.3, 1.4, 0.75)):
        px_, py_ = at(ox, oy)
        rotated_box(g.bm("stone"), px_, py_, z + s_ * 0.2, s_ * 1.3, s_, s_ * 0.8, rng.uniform(-0.3, 0.3), rng.uniform(0, math.tau))
        if rng.random() < 0.65:
            vignette_lump(g.bm("moss"), rng, px_, py_, z + s_ * 0.74, s_ * 0.6, 0.32, 0.2)
    for a in (2.9, 2.4, 1.9, 1.5):
        ox, oz = math.cos(a) * (R + 0.2), math.sin(a) * (R + 0.2)
        px_, py_ = at(ox)
        vignette_lump(g.bm("moss"), rng, px_, py_, cx_z + oz + 0.32, 0.72, 0.3, 0.2, 2)
    g.finish(VIGNETTE_COLORS, "Poi_")


def vignette_oak(col, h, rng):
    """Огромное старое дерево на поляне: толстые корни по земле, мох (ref: стволы в плюще и трутовиках)."""
    v = VIGNETTES["oak"]
    g = EditGroup(col, "detail:vignette_oak", (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    vignette_tube(g.bm("bark"), [(x, y, z - 0.4), (x, y, z + 1.3), (x + 0.1, y, z + 2.9), (x + 0.15, y, z + 4.4)], (1.45, 1.05, 0.82, 0.6), 11, rng, 0.08)
    for k in range(9):
        a = k / 9 * math.tau + rng.uniform(-0.2, 0.2)
        ln = rng.uniform(4.2, 6.5)
        wob = rng.uniform(-0.3, 0.3)
        vignette_tube(g.bm("bark"), [(x + math.cos(a) * 0.6, y + math.sin(a) * 0.6, z + 1.4), (x + math.cos(a) * ln * 0.3, y + math.sin(a) * ln * 0.3, z + 0.65), (x + math.cos(a + wob) * ln * 0.65, y + math.sin(a + wob) * ln * 0.65, z + 0.2), (x + math.cos(a + wob) * ln, y + math.sin(a + wob) * ln, z - 0.28)], (0.6, 0.44, 0.27, 0.05), 6, rng, 0.08)
        if rng.random() < 0.75:
            mx, my = x + math.cos(a + wob) * ln * 0.55, y + math.sin(a + wob) * ln * 0.55
            vignette_lump(g.bm("moss"), rng, mx, my, z + 0.45, 0.8, 0.3, 0.2, 2)
    for z_off, ang in ((1.6, 0.8), (2.9, 3.6)):
        vignette_lump(g.bm("moss"), rng, x + math.cos(ang) * 0.82, y + math.sin(ang) * 0.82, z + z_off, 0.85, 0.75, 0.2, 2)
    g.finish(VIGNETTE_COLORS, "Poi_")


def vignette_camp(col, h, rng):
    """Брошенная стоянка у дороги: кольцо кострища без огня, навес из старой ткани."""
    v = VIGNETTES["camp"]
    g = EditGroup(col, "detail:vignette_camp", (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    for k in range(9):
        a = k / 9 * math.tau
        vignette_lump(g.bm("rock"), rng, x + math.cos(a) * 1.05, y + math.sin(a) * 1.05, z + 0.05, rng.uniform(0.22, 0.34), 0.75, 0.2)
    vignette_lump(g.bm("dark"), rng, x, y, z - 0.1, 0.95, 0.15, 0.15, 2)
    for k in range(4):
        a = rng.uniform(0, math.tau)
        rotated_box(g.bm("dark"), x + math.cos(a) * 0.3, y + math.sin(a) * 0.3, z + 0.08, 0.9, 0.1, 0.1, rng.uniform(-0.2, 0.2), a)
    tx, ty = x + 0.5, y + 4.4
    for ox in (-1.6, 1.6):
        rotated_box(g.bm("wood"), tx + ox, ty - 1.35, z + 0.72, 0.1, 0.1, 1.6, 0.0, 0.0)
        rotated_box(g.bm("wood"), tx + ox, ty + 1.35, z + 0.72, 0.1, 0.1, 1.6, 0.0, 0.0)
    for s_ in (-1, 1):
        rotated_box(g.bm("wood"), tx, ty + s_ * 1.35, z + 1.55, 3.5, 0.09, 0.09, 0.0, 0.0)
    a_, b_ = (tx - 1.75, ty - 1.5, z + 1.25), (tx + 1.75, ty - 1.5, z + 1.25)
    c_, d_ = (tx + 1.75, ty + 1.5, z + 1.75), (tx - 1.75, ty + 1.5, z + 1.75)
    bm = g.bm("cloth")
    bm.faces.new([bm.verts.new(p_) for p_ in (a_, b_, c_, d_)])
    bm.faces.new([bm.verts.new(p_) for p_ in (d_, c_, (tx + 1.75, ty + 1.8, z + 0.5), (tx - 1.75, ty + 1.8, z + 0.5))])
    g.finish(VIGNETTE_COLORS, "Poi_")


def vignette_piers(col, h, rng):
    """Обломки старого моста: опора на берегу и две в реке, кусок арки; по камню мох и плети."""
    v = VIGNETTES["piers"]
    g = EditGroup(col, "detail:vignette_piers", (v["x"], v["y"]), h)
    x, y, z = v["x"], v["y"], v["z"]
    nx_, ny_ = v["n"]
    qx, qy = v["q"]
    rot = math.atan2(ny_, nx_)
    water_z = v["water"]
    top = water_z + 6.0
    for t, tall in ((-6.0, top), (5.5, top - 2.3)):        # две опоры в реке, вторая обломана
        px_, py_ = qx + nx_ * t, qy + ny_ * t
        z0 = water_z - 2.6
        cz = z0
        c = 0
        while cz < tall:
            box(g.bm("stone"), px_, py_, cz, 2.4 - 0.05 * c, 3.4 - 0.05 * c, 0.75, rot + rng.uniform(-0.03, 0.03))
            cz += 0.75
            c += 1
        vignette_lump(g.bm("moss"), rng, px_, py_, tall + 0.1, 1.15, 0.3, 0.2, 2)
    # Опора на берегу: ступени кладки.
    for c in range(8):
        box(g.bm("stone"), x - nx_ * c * 0.25, y - ny_ * c * 0.25, z - 0.2 + c * 0.75, 3.2 - c * 0.15, 4.0, 0.74, rot + rng.uniform(-0.02, 0.02))
    vignette_lump(g.bm("moss"), rng, x - nx_ * 1.7, y - ny_ * 1.7, z + 5.9, 1.3, 0.28, 0.2, 2)
    # Кусок арки от берега к первой опоре.
    sx_, sy_ = x - nx_ * 1.6, y - ny_ * 1.6
    ex_, ey_ = qx + nx_ * 5.5, qy + ny_ * 5.5
    L = math.hypot(ex_ - sx_, ey_ - sy_)
    for k in range(4):
        t = (k + 0.5) / 7.0
        px_ = sx_ + (ex_ - sx_) * t
        py_ = sy_ + (ey_ - sy_) * t
        pz = z + 5.0 + math.sin(t * math.pi) * 2.2
        tilt = -math.atan(math.cos(t * math.pi) * 2.2 * math.pi / L)
        rotated_box(g.bm("stone"), px_, py_, pz, L / 7.0 + 0.1, 3.4, 0.7, tilt, math.atan2(ey_ - sy_, ex_ - sx_))
        if k % 2:
            vignette_lump(g.bm("moss"), rng, px_, py_, pz + 0.4, 0.95, 0.26, 0.2, 2)
    g.finish(VIGNETTE_COLORS, "Poi_")


def vignette_plants(placed, h):
    """Растения и камни у особых мест: плотнее, чем вокруг. Вода: кувшинки и рогоз."""
    rng = random.Random(92)

    def put(name, x, y, s, z=None, sink=0.02, rot=None):
        zz = (height_at(h, x, y) - sink) if z is None else z
        placed.setdefault(name, []).extend([round(x, 2), round(zz, 2), round(-y, 2),
                                            round(rng.uniform(0, math.tau) if rot is None else rot, 2), round(s, 2)])

    def ring(v, r0, r1, n, names, s_lo=0.8, s_hi=1.3):
        for _ in range(n):
            a, rr = rng.uniform(0, math.tau), rng.uniform(r0, r1)
            put(rng.choice(names), v["x"] + math.cos(a) * rr, v["y"] + math.sin(a) * rr, rng.uniform(s_lo, s_hi))
    for key in ("spring", "falls"):
        v = VIGNETTES[key]
        k_ = v["pool"] / 4.2
        ring(v, v["pool"] + 1.2, v["r"], 34, ("Dt_Fern_A", "Dt_Fern_B", "Dt_Broad_A", "Dt_Broad_B", "Dt_Lily", "Dt_Spike", "Dt_Tuft_Tall"))
        ring(v, v["pool"] + 1.0, v["r"], 10, ("Dt_Moss_A", "Dt_Moss_B", "Dt_Pebbles_A"))
        for _ in range(8):
            a, rr = rng.uniform(0, math.tau), rng.uniform(0.8, v["pool"] - 0.8)
            put(rng.choice(("LilyPad_1", "LilyPad_2")), v["x"] + math.cos(a) * rr, v["y"] + math.sin(a) * rr, rng.uniform(0.8, 1.2), z=v["surface"] + 0.01)
        put("WillowTree_2", v["x"] + 7.5 * k_, v["y"] + 3.5, 1.5, sink=0.2)
        put("Pr_Roots", v["x"] + 7.5 * k_, v["y"] + 3.5, 1.4)
        put("Pr_Vine", v["x"] + 2.9 * k_, v["y"] + 1.0, 0.8, z=v["z"] + 3.6 * k_)
    v = VIGNETTES["giant"]
    ring(v, v["pool"] + 1.0, v["r"] + 2.0, 42, ("Dt_Fern_A", "Dt_Fern_B", "Dt_Fern_B", "Dt_Broad_A", "Dt_Tuft_Tall", "Dt_Shroom_Tan", "Dt_Shroom_Red"))
    ring(v, v["pool"] + 0.8, v["r"] + 1.0, 12, ("Dt_Moss_B", "Dt_Moss_A", "Dt_Litter", "Dt_Twigs"))
    for _ in range(16):
        a, rr = rng.uniform(0, math.tau), rng.uniform(1.0, v["pool"] - 0.5)
        put(rng.choice(("LilyPad_1", "LilyPad_2")), v["x"] + math.cos(a) * rr, v["y"] + math.sin(a) * rr, rng.uniform(1.0, 1.7), z=v["surface"] + 0.01)
    for _ in range(9):
        a = rng.uniform(math.pi, math.tau)
        put("Dt_Cattail", v["x"] + math.cos(a) * (v["pool"] - 0.3), v["y"] + math.sin(a) * (v["pool"] - 0.3), rng.uniform(0.9, 1.2), sink=0.1)
    for ox, oz in ((-6.5, 2.2), (-3.0, 3.2), (2.6, 4.9), (5.6, 6.4)):
        put("Pr_Vine", v["x"] + ox, v["y"] + 5.55, 1.0, z=v["z"] + oz, rot=rng.uniform(-0.2, 0.2))
    v = VIGNETTES["ruin"]
    ring(v, 2.0, v["r"] + 1.5, 26, ("Dt_Tuft_Tall", "Dt_Tuft_A", "Dt_Umbel", "Dt_Poppy", "Dt_Fern_C", "Dt_Broad_B"))
    ring(v, 1.5, v["r"], 12, ("Dt_Moss_A", "Dt_Pebbles_A", "Dt_Pebbles_A", "Dt_Moss_B"))
    cs, sn = math.cos(0.35), math.sin(0.35)
    for ox, oz in ((-4.6, 3.9), (-3.0, 4.6), (-1.4, 3.2), (0.4, 2.5), (2.4, 1.4)):         # плющ по верху стены
        put("Pr_Vine", v["x"] + cs * ox - sn * 3.0, v["y"] + sn * ox + cs * 3.0, 0.8, z=v["z"] + oz, rot=0.35)
    put("Pr_Boulder_B", v["x"] + 8.2, v["y"] + 2.5, 1.2, sink=0.15)
    put("Pr_Boulder_A", v["x"] - 7.8, v["y"] - 3.8, 1.3, sink=0.15)
    put("NormalTree_3", v["x"] + 9.5, v["y"] + 7.0, 1.3, sink=0.15)
    put("Pr_Ivy", v["x"] + 9.5, v["y"] + 7.0, 1.1, z=v["z"] + 0.05)
    put("Pr_Roots", v["x"] + 9.5, v["y"] + 7.0, 1.2)
    v = VIGNETTES["stones"]
    ring(v, 3.0, v["r"] + 3.0, 34, ("Dt_Tuft_Tall", "Dt_Tuft_Dry", "Dt_Umbel", "Dt_Umbel", "Dt_Lily", "Dt_Tuft_A"))
    ring(v, 1.8, v["r"], 12, ("Dt_Moss_A", "Dt_Moss_B", "Dt_Pebbles_B"))
    for key in ("outcrop_w", "outcrop_s"):
        v = VIGNETTES[key]
        ring(v, 2.5, v["r"] + 3.0, 30, ("Dt_Tuft_Tall", "Dt_Tuft_A", "Dt_Poppy", "Dt_Spike", "Dt_Fern_C", "Dt_Broad_B"))
        ring(v, 2.0, v["r"] + 1.0, 12, ("Dt_Pebbles_A", "Dt_Pebbles_B", "Dt_Moss_A"))
        put("Pr_Boulder_B", v["x"] + 9.0, v["y"] - 4.0, 1.1, sink=0.15)
        put("Pr_Boulder_A", v["x"] - 8.0, v["y"] + 4.5, 1.2, sink=0.15)
    v = VIGNETTES["marsh"]
    for ox, oy, pr in v["pools"]:
        for _ in range(int(pr * 2.5)):
            a, rr = rng.uniform(0, math.tau), rng.uniform(0.5, pr - 0.3)
            put(rng.choice(("LilyPad_1", "LilyPad_2")), v["x"] + ox + math.cos(a) * rr, v["y"] + oy + math.sin(a) * rr, rng.uniform(0.8, 1.5), z=v["surface"] + 0.01)
        for _ in range(int(pr * 3)):
            a = rng.uniform(0, math.tau)
            put(rng.choice(("Dt_Cattail", "Dt_Cattail", "Dt_Tuft_Tall")), v["x"] + ox + math.cos(a) * (pr - 0.2), v["y"] + oy + math.sin(a) * (pr - 0.2), rng.uniform(0.9, 1.25), sink=0.1)
    ring(v, 9.0, v["r"] + 3.0, 34, ("Dt_Fern_B", "Dt_Fern_A", "Dt_Broad_A", "Dt_Shroom_Tan", "Dt_Tuft_Tall"))
    ring(v, 8.0, v["r"] + 2.0, 12, ("Dt_Moss_B", "Dt_Twigs", "Dt_Litter"))
    for ox, oy, oz in ((-2.0, 1.0, 3.8), (2.6, -1.5, 4.8), (6.4, -2.0, 3.0)):
        put("Pr_Vine", v["x"] + ox + 0.6, v["y"] + oy, 0.7, z=v["surface"] + oz)
    v = VIGNETTES["arch"]
    ring(v, 2.0, v["r"] + 3.0, 26, ("Dt_Tuft_Tall", "Dt_Tuft_A", "Dt_Umbel", "Dt_Poppy", "Dt_Fern_C"))
    ring(v, 1.5, v["r"], 9, ("Dt_Moss_A", "Dt_Pebbles_A", "Dt_Pebbles_A"))
    for ox, oz in ((-3.0, 4.6), (-2.2, 6.6), (-0.4, 7.2), (3.0, 2.6)):
        put("Pr_Vine", v["x"] + math.cos(0.25) * ox, v["y"] + math.sin(0.25) * ox, 0.75, z=v["z"] + oz, rot=0.25)
    v = VIGNETTES["oak"]
    put("NormalTree_2", v["x"], v["y"], 2.9, sink=0.3)
    put("Pr_Ivy", v["x"], v["y"], 3.4, z=v["z"] + 0.3)
    for _ in range(4):
        a = rng.uniform(0, math.tau)
        put("Pr_Vine", v["x"] + math.cos(a) * 3.0, v["y"] + math.sin(a) * 3.0, rng.uniform(0.9, 1.2), z=v["z"] + 6.5, rot=a)
    ring(v, 5.5, v["r"] + 3.0, 40, ("Dt_Fern_B", "Dt_Fern_A", "Dt_Broad_A", "Dt_Lily", "Dt_Spike", "Dt_Tuft_Tall"))
    ring(v, 3.0, v["r"] + 1.0, 20, ("Dt_Moss_B", "Dt_Moss_A", "Dt_Shroom_Tan", "Dt_Shroom_Red", "Dt_Shroom_Tan", "Dt_Litter"))
    v = VIGNETTES["camp"]
    put("Pr_Log_A", v["x"] - 2.6, v["y"] + 0.3, 0.75, sink=0.03, rot=1.3)
    put("Pr_Log_A", v["x"] + 2.4, v["y"] - 0.4, 0.7, sink=0.03, rot=-1.2)
    put("Pr_Barrels", v["x"] - 3.5, v["y"] + 4.2, 0.9)
    put("Pr_Crates", v["x"] + 3.8, v["y"] + 4.0, 0.9)
    ring(v, 3.5, v["r"] + 3.0, 22, ("Dt_Tuft_A", "Dt_Tuft_Dry", "Dt_Umbel", "Dt_Twigs", "Dt_Pebbles_A"))
    v = VIGNETTES["piers"]
    ring(v, 3.5, v["r"] + 3.5, 20, ("Dt_Tuft_Tall", "Dt_Tuft_A", "Dt_Umbel", "Dt_Pebbles_A", "Dt_Moss_A", "Dt_Fern_C"))
    nx_, ny_ = v["n"]
    qx, qy = v["q"]
    for t, oz in ((-6.0, 6.0), (5.5, 3.7)):
        for s_ in (-1.2, 1.2):
            put("Pr_Vine", qx + nx_ * t - ny_ * s_ + nx_ * 1.2, qy + ny_ * t + nx_ * s_ + ny_ * 1.2, 0.8, z=v["water"] + oz, rot=math.atan2(ny_, nx_) + math.pi / 2)
    put("Pr_Vine", v["x"] + nx_ * 1.6, v["y"] + ny_ * 1.6, 0.95, z=v["z"] + 5.0, rot=math.atan2(ny_, nx_) + math.pi / 2)


def preview_nature(col, placed):
    """Модели пака — экземплярами на точках (Geometry Nodes: поворот и масштаб из атрибутов) — для рендеров сверки."""
    before = set(bpy.data.objects)
    with bpy.context.temp_override(**_ui()):
        bpy.ops.import_scene.gltf(filepath=NATURE_GLB)
    lib_col = bpy.data.collections.new("Пак (образцы)")
    bpy.context.scene.collection.children.link(lib_col)
    models = {}
    for ob in [o for o in bpy.data.objects if o not in before]:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        lib_col.objects.link(ob)
        if ob.parent is None:
            models[ob.name.split(".")[0]] = ob
    lib_col.hide_render = True
    # Образцы — источники экземпляров леса, сами в мире не стоят: исключаем коллекцию из слоя (не видна
    # во вьюпорте и не мешает кучей в начале координат; экземпляры по-прежнему берут из неё геометрию).
    layer = bpy.context.view_layer.layer_collection.children.get(lib_col.name)
    if layer:
        layer.exclude = True
    # В паке нет картинок (текстуры подключает Godot) — для рендера сверки красим материалы по названию.
    tones = [("Pine", "Leaves", (0.16, 0.30, 0.18)), ("Birch", "Leaves", (0.48, 0.62, 0.26)),
             ("Maple", "Leaves", (0.72, 0.40, 0.16)), ("Willow", "Leaves", (0.50, 0.62, 0.42)),
             ("", "Leaves", (0.27, 0.45, 0.18)), ("", "Bark", (0.32, 0.24, 0.17)), ("", "Rock", (0.46, 0.45, 0.43)),
             ("", "Flower", (0.86, 0.80, 0.42)), ("", "Petal", (0.88, 0.62, 0.70)), ("", "Reed", (0.48, 0.52, 0.28)),
             ("", "Lily", (0.26, 0.44, 0.22)), ("", "", (0.30, 0.46, 0.20))]
    for ob in lib_col.objects:
        for slot in getattr(ob, "material_slots", []):
            m = slot.material
            if m is None or m.get("tinted"):
                continue
            rgb = next(c for a, b, c in tones if a in m.name and b in m.name)
            bsdf = next((nd for nd in m.node_tree.nodes if nd.type == "BSDF_PRINCIPLED"), None) if m.node_tree else None
            if bsdf:
                for link in list(bsdf.inputs["Base Color"].links):
                    m.node_tree.links.remove(link)
                bsdf.inputs["Base Color"].default_value = lin(rgb) + (1.0,)
            m["tinted"] = True
    for name, flat in placed.items():
        src = models.get(name)
        if src is None:
            continue
        arr = np.array(flat, dtype=np.float32).reshape(-1, 5)
        me = bpy.data.meshes.new("pts_" + name)
        co = np.stack([arr[:, 0], -arr[:, 2], arr[:, 1]], axis=1)   # Godot (x, z, −y) → Blender (x, y, z)
        me.vertices.add(len(co))
        me.vertices.foreach_set("co", co.astype(np.float32).ravel())
        me.attributes.new("rot", "FLOAT", "POINT").data.foreach_set("value", arr[:, 3])
        me.attributes.new("scl", "FLOAT", "POINT").data.foreach_set("value", arr[:, 4])
        ob = bpy.data.objects.new("Nature_" + name, me)
        col.objects.link(ob)
        ng = bpy.data.node_groups.new("inst_" + name, "GeometryNodeTree")
        ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
        ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
        n, l = ng.nodes, ng.links
        gi, go = n.new("NodeGroupInput"), n.new("NodeGroupOutput")
        inst = n.new("GeometryNodeInstanceOnPoints")
        info = n.new("GeometryNodeObjectInfo")
        info.inputs["Object"].default_value = src
        info.transform_space = "ORIGINAL"
        r_attr = n.new("GeometryNodeInputNamedAttribute")
        r_attr.data_type = "FLOAT"
        r_attr.inputs["Name"].default_value = "rot"
        s_attr = n.new("GeometryNodeInputNamedAttribute")
        s_attr.data_type = "FLOAT"
        s_attr.inputs["Name"].default_value = "scl"
        comb = n.new("ShaderNodeCombineXYZ")
        l.new(gi.outputs[0], inst.inputs["Points"])
        l.new(info.outputs["Geometry"], inst.inputs["Instance"])
        l.new(r_attr.outputs["Attribute"], comb.inputs["Z"])
        l.new(comb.outputs["Vector"], inst.inputs["Rotation"])
        l.new(s_attr.outputs["Attribute"], inst.inputs["Scale"])
        l.new(inst.outputs["Instances"], go.inputs[0])
        ob.modifiers.new("Экземпляры", "NODES").node_group = ng


# --- Сборка и рендеры ----------------------------------------------------------------------------

def build():
    bpy.ops.wm.read_homefile(use_empty=True)
    col = bpy.data.collections.new("Мир")
    bpy.context.scene.collection.children.link(col)
    h, fbm, ridge, detail = heights()
    h, road_d, path_d = shape(h, fbm)
    h, river, dl = water(h)
    h = bridge_banks(h, river)
    h = vignette_terrain(h, river)
    forest = forest_density(h, fbm, road_d, path_d, river, dl)
    c = colors(h, fbm, road_d, path_d, river, dl, forest)
    write_godot_data(h, fbm, road_d, path_d, river, dl, forest)
    terrain_mesh(col, h, c)
    road_ribbons(col, h, river, dl)
    placed = nature(h, forest, river, dl, road_d, path_d, fbm)
    clear_roads(placed, road_d, path_d)              # до наполнения: у убранных деревьев не появятся плющ и корни
    extras(placed, h, forest, river, dl, road_d, path_d, fbm)
    clear_roads(placed, road_d, path_d)
    write_roads_json()
    import json
    with open(NATURE_JSON, "w", encoding="utf-8") as f:
        json.dump(placed, f, separators=(",", ":"))
    preview_nature(col, placed)
    NATURE_COUNT.update({k: len(v) // 5 for k, v in placed.items()})
    ponds = water_meshes(col, river)
    # Пруды — на уровень своей глади.
    for x, y, r in W["PONDS"]:
        cx, cy = P(x, y)
        surf = POND_Z[(x, y)]
        for v in ponds.data.vertices:
            if math.hypot(v.co.x - cx, v.co.y - cy) <= r + 0.1:
                v.co.z = surf
    write_water_json()
    fortress(col, h)
    bridges(col, h)
    village(col, h)
    pois(col, h)
    details(col, h, forest)
    vignettes(col, h)
    points(col)
    np.save(os.path.join(PROJECT, "Арт", "Blender", "world_heights.npy"), h.astype(np.float32))
    np.save(os.path.join(PROJECT, "Арт", "Blender", "world_forest.npy"), forest.astype(np.float32))
    return col, h


def render(col):
    sc = bpy.context.scene
    # Eevee: листва пака — с текстурами, земля — цветом вершин (узел в материале).
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = engine
            break
        except TypeError:
            continue
    sc.world = sc.world or bpy.data.worlds.new("World")
    sc.world.use_nodes = True
    bg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.55, 0.65, 0.8, 1.0)
    bg.inputs["Strength"].default_value = 0.6
    sun = bpy.data.lights.new("Солнце", "SUN")
    sun.energy = 3.5
    sun.angle = math.radians(3)
    so = bpy.data.objects.new("Солнце", sun)
    sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    sc.view_settings.view_transform = "Standard"
    cam = bpy.data.cameras.new("Сверху")
    cam.type = "ORTHO"
    cam.ortho_scale = BX1 - BX0
    co = bpy.data.objects.new("Сверху", cam)
    sc.collection.objects.link(co)
    co.location = ((BX0 + BX1) / 2, (BY0 + BY1) / 2, 400)
    sc.camera = co
    sc.render.resolution_x, sc.render.resolution_y = 1536, 1024
    sc.render.filepath = RENDER % "top"
    with bpy.context.temp_override(**_ui()):
        bpy.ops.render.render(write_still=True)
    # Перспективы: деревня с юга и крепость с озера.
    cam2 = bpy.data.cameras.new("Вид")
    cam2.lens = 35
    cam2.clip_end = 3000
    co2 = bpy.data.objects.new("Вид", cam2)
    sc.collection.objects.link(co2)
    sc.camera = co2
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720
    views = {
        "village": ((0, -190, 110), (0, 40, 0)),
        "village_close": ((30, -75, 38), (0, 25, 4)),
        "fortress": ((-250, 330, 90), (-420, 560, 20)),
        "fortress_close": ((-330, 420, 45), (-420, 550, 18)),
        "valley": ((300, -250, 220), (-100, 300, 0)),
        "poi_mine": ((-600, 480, 18), (-636, 508, 6)),
        "poi_cave": ((-570, 350, 14), (-598, 367, 5)),
        "poi_gorge": ((-590, 215, 16), (-636, 232, 8)),
        "poi_cemetery": ((-280, 110, 30), (-301, 185, 4)),
        "poi_shrine": ((323, 600, 18), (323, 650, 4)),
        "poi_camp": ((395, 180, 14), (379, 200, 2)),
        "poi_logging": ((380, 340, 30), (359, 387, 2)),
        "poi_pier_hermit": ((230, -100, 30), (230, 0, 2)),
        "bridge_main": ((130, 120, 22), (105, 164, 4)),
        "bridge_old": ((-55, 410, 18), (-85, 438, 3)),
        "bridge_rickety": ((336, -60, 32), (336, -14, 0)),
        "bridge_gate": ((-310, 425, 14), (-360, 450, 5)),
    }
    for name, (eye, target) in views.items():
        co2.location = eye
        direction = Vector(target) - Vector(eye)
        co2.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = RENDER % ("view_" + name)
        with bpy.context.temp_override(window=window, screen=window.screen):
            bpy.ops.render.render(write_still=True)


def tint_roofs():
    """Для рендеров сверки: сланцевая и бурая черепица — та же текстура, подкрашенная (в игре это делает
    шейдер wall_xray: texture_desaturate + texture_tint, KitDress.KIT_TINT)."""
    tints = {"MI_RoundTiles_slate": (0.40, 0.46, 0.58), "MI_RoundTiles_brown": (0.62, 0.42, 0.28)}
    for name, rgb in tints.items():
        m = bpy.data.materials.get(name)
        if m is None or m.get("tinted") or not m.node_tree:
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        links = bsdf.inputs["Base Color"].links if bsdf else []
        if not links:
            continue
        src = links[0].from_socket
        gray = nt.nodes.new("ShaderNodeRGBToBW")
        mul = nt.nodes.new("ShaderNodeMix")
        mul.data_type = "RGBA"
        mul.blend_type = "MULTIPLY"
        mul.inputs["Factor"].default_value = 1.0
        nt.links.new(src, gray.inputs["Color"])
        nt.links.new(gray.outputs["Val"], mul.inputs[6])
        mul.inputs[7].default_value = lin(rgb) + (1.0,)
        nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
        m["tinted"] = True


def render_pois(names=None):
    """Рендеры мест интереса: камера в 30 м к востоку/югу от места, на 14 м над землёй, смотрит на вход.
    Вызов: exec(..., {"__name__": "__main__", "RENDER_POIS": True}). Склейка — world_pois.png."""
    h = np.load(os.path.join(PROJECT, "Арт", "Blender", "world_heights.npy"))

    def hz(x, y):
        i = int(round((x - XS[0]) / STEP))
        j = int(round((y - YS[0]) / STEP))
        return float(h[min(max(j, 0), h.shape[0] - 1), min(max(i, 0), h.shape[1] - 1)])
    render_setup()
    for o in bpy.data.objects:
        if "colonly" in o.name:
            o.hide_render = True          # ящики коллизий (в Godot невидимы) закрывали стены домов
    sc = bpy.context.scene
    co = sc.camera
    offsets = {"mine": (34, -10), "cave": (32, -8), "adit": (30, -8), "gorge": (34, -6), "cemetery": (0, -80),
               "shrine": (0, -45), "hunters": (22, -22), "logging": (20, -60), "pier": (-28, -26),
               "hermit": (-22, -20), "rubezh": (150, -150), "mill": (30, -26)}
    targets = {"mine": 8, "cave": 10, "adit": 8, "gorge": 4}
    window = bpy.context.window_manager.windows[0]
    files = []
    for pid, num, name, x, y, kind, note in W["POIS"]:
        if pid not in offsets or (names and pid not in names):
            continue
        cx, cy = P(x, y)
        tx = cx + targets.get(pid, 0)
        dx, dy = offsets[pid]
        lift = 70 if pid == "rubezh" else (30 if pid in ("cemetery", "logging") else 14)
        eye = Vector((tx + dx, cy + dy, hz(tx + dx, cy + dy) + lift))
        tgt = Vector((tx, cy, hz(tx, cy) + 3))
        co.location = eye
        co.rotation_euler = (tgt - eye).to_track_quat("-Z", "Y").to_euler()
        path = RENDER % ("poi_" + pid)
        sc.render.filepath = path
        with bpy.context.temp_override(window=window, screen=window.screen):
            bpy.ops.render.render(write_still=True)
        files.append(path)
    return files


def render_map_top():
    """Вид сверху для миникарты и карты мира: Арт/Blender/world_map_top.png (орто 3072×2048, 2 пикселя на метр,
    высокое солнце; границы — world_map_top.json)."""
    render_setup()
    for o in bpy.data.objects:
        if "colonly" in o.name:
            o.hide_render = True
    sc = bpy.context.scene
    cam = bpy.data.cameras.get("Сверху_карта") or bpy.data.cameras.new("Сверху_карта")
    cam.type = "ORTHO"
    cam.ortho_scale = 1536.0
    cam.clip_end = 2000.0
    co = bpy.data.objects.get("Сверху_карта") or bpy.data.objects.new("Сверху_карта", cam)
    if co.name not in sc.collection.objects:
        sc.collection.objects.link(co)
    co.location = ((-757 + 779) / 2, (-302 + 722) / 2, 600.0)
    co.rotation_euler = (0, 0, 0)
    bpy.data.objects["Солнце"].rotation_euler = (math.radians(20), math.radians(5), math.radians(-30))
    sc.camera = co
    sc.render.resolution_x, sc.render.resolution_y, sc.render.resolution_percentage = 3072, 2048, 100
    sc.render.filepath = os.path.join(PROJECT, "Арт", "Blender", "world_map_top.png")
    with bpy.context.temp_override(**_ui()):
        bpy.ops.render.render(write_still=True)


def render_setup():
    """Солнце, небо, камера «Вид» 1280×720 (если ещё нет)."""
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.world = sc.world or bpy.data.worlds.new("World")
    sc.world.use_nodes = True
    bg = next(n for n in sc.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.55, 0.65, 0.8, 1.0)
    bg.inputs["Strength"].default_value = 0.6
    if "Солнце" not in bpy.data.objects:
        sun = bpy.data.lights.new("Солнце", "SUN")
        sun.energy = 3.5
        so = bpy.data.objects.new("Солнце", sun)
        sc.collection.objects.link(so)
        so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    sc.view_settings.view_transform = "Standard"
    co = bpy.data.objects.get("Вид")
    if co is None:
        cam = bpy.data.cameras.new("Вид")
        cam.lens = 35
        cam.clip_end = 3000
        co = bpy.data.objects.new("Вид", cam)
        sc.collection.objects.link(co)
    sc.camera = co
    sc.render.resolution_x, sc.render.resolution_y = 1280, 720


if __name__ == "__main__":
    if globals().get("RENDER_POIS"):
        result_info = {"files": render_pois(globals().get("POI_NAMES"))}
        raise SystemExit
    # Рендеры — отдельным вызовом (RENDER_ONLY), иначе запрос к Blender не укладывается во время ожидания:
    #   1) exec(..., {"__name__": "__main__"})                 — сборка и сохранение;
    #   2) exec(..., {"__name__": "__main__", "RENDER_ONLY": True}) — рендеры сверки по открытому файлу.
    #   3) exec(..., {"__name__": "__main__", "EXPORT_ONLY": True}) — glb для Godot по открытому файлу.
    if globals().get("EXPORT_ONLY"):
        result_info = {"exported": export_godot(bpy.data.collections["Мир"])}
        raise SystemExit
    if globals().get("RENDER_ONLY"):
        render(None)
        result_info = {"rendered": True}
        raise SystemExit
    collection, heights_grid = build()
    tint_roofs()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    # Пересборка одной командой (Tools/rebuild_world.ps1, blender -b): сразу glb для Godot и вид сверху для миникарты.
    if globals().get("BUILD_EXPORT"):
        export_godot(collection)
        if globals().get("MAP_TOP"):
            render_map_top()
    result_info = {"grid": list(heights_grid.shape), "z": [float(heights_grid.min()), float(heights_grid.max())],
                   "points": len(POINTS), "nature": sum(NATURE_COUNT.values()),
                   "trees": sum(v for k, v in NATURE_COUNT.items() if "Tree" in k)}
