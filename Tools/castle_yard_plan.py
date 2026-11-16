"""План внутреннего двора замка в SVG. Контуры сняты с готовой модели (Tools/blender/castle_yard_scan.py → лучи сверху), таблицы — только
для подписей и контуров залов внутри массива. Единицы данных — px исходника (0,12 м). На листе север вверху.

    python Tools/castle_yard_plan.py

Пишет Арт/Blender/castle/yard_plan.svg и yard_plan_check.png (контуры плана поверх вида модели сверху view_top.png)."""
import json
import math
import os
from collections import deque

import numpy as np
from PIL import Image, ImageDraw

SP = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Арт", "Blender", "castle")
OUT = os.path.join(SP, "yard_plan.svg")

d = np.load(os.path.join(SP, "yard_scan.npz"))
meta = json.load(open(os.path.join(SP, "yard_scan.json"), encoding="utf-8"))
Z, PART, ROCKZ, xs, ys = d["Z"], d["PART"], d["ROCKZ"], d["xs"], d["ys"]
parts = meta["parts"]
S = meta["S"]
STEP = meta["step"]
XX, YY = np.meshgrid(xs, ys)
THRESH = meta["gate"]["arch_z"]      # порог ворот — ноль высот на плане
pid = {n: i for i, n in enumerate(parts)}


# ---------------------------------------------------------------- геометрия
def offset(path, dist):
    """Смещение замкнутого пути: dist > 0 — наружу."""
    area = sum(path[i][0] * path[(i + 1) % len(path)][1] - path[(i + 1) % len(path)][0] * path[i][1] for i in range(len(path))) / 2
    sign = 1.0 if area > 0 else -1.0
    n = len(path)
    out = []
    for i in range(n):
        ax, ay = path[(i - 1) % n]
        bx, by = path[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        L = math.hypot(dx, dy) or 1.0
        out.append((path[i][0] + dy / L * dist * sign, path[i][1] - dx / L * dist * sign))
    return out


def in_poly(poly, X, Y):
    px = np.array([p[0] for p in poly])
    py = np.array([p[1] for p in poly])
    inside = np.zeros(X.shape, dtype=bool)
    for i in range(len(poly)):
        x0, y0, x1, y1 = px[i], py[i], px[i - 1], py[i - 1]
        inside ^= ((y0 > Y) != (y1 > Y)) & (X < (x1 - x0) * (Y - y0) / (y1 - y0 + 1e-12) + x0)
    return inside


def blur(A, sigma):
    """Гаусс тремя проходами скользящего среднего."""
    r = max(1, int(round(sigma)))
    out = A.astype(np.float64)
    for _ in range(3):
        for axis in (0, 1):
            pad = [(0, 0), (0, 0)]
            pad[axis] = (r + 1, r)
            c = np.cumsum(np.pad(out, pad, mode="edge"), axis=axis)
            if axis == 0:
                out = (c[2 * r + 1:, :] - c[:-2 * r - 1, :]) / (2 * r + 1)
            else:
                out = (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)
    return out


def contours(field, level):
    """Marching squares: замкнутые контуры в индексах сетки (j, i → координаты плана)."""
    f = np.pad(field, 1, mode="constant", constant_values=level - 1.0)
    above = f >= level
    case = (above[:-1, :-1] * 1 + above[:-1, 1:] * 2 + above[1:, 1:] * 4 + above[1:, :-1] * 8)
    links = {}

    def pt(edge):
        kind, j, i = edge
        if kind == "h":      # между (j,i) и (j,i+1)
            a, b = f[j, i], f[j, i + 1]
            return (i + (level - a) / (b - a), float(j))
        a, b = f[j, i], f[j + 1, i]
        return (float(i), j + (level - a) / (b - a))

    def add(e0, e1):
        links.setdefault(e0, []).append(e1)
        links.setdefault(e1, []).append(e0)
    for j, i in zip(*np.nonzero((case != 0) & (case != 15))):
        c = case[j, i]
        B, R, T, L = ("h", j, i), ("v", j, i + 1), ("h", j + 1, i), ("v", j, i)
        table = {1: [(L, B)], 2: [(B, R)], 3: [(L, R)], 4: [(R, T)], 5: [(L, T), (B, R)], 6: [(B, T)], 7: [(L, T)], 8: [(L, T)], 9: [(B, T)],
                 10: [(L, B), (R, T)], 11: [(R, T)], 12: [(L, R)], 13: [(B, R)], 14: [(L, B)]}
        for e0, e1 in table[int(c)]:
            add(e0, e1)
    loops = []
    seen = set()
    for start in links:
        if start in seen:
            continue
        loop = [start]
        seen.add(start)
        prev, cur = None, start
        while True:
            nxt = [e for e in links[cur] if e != prev]
            if not nxt:
                break
            e = nxt[0]
            if e == start:
                break
            if e in seen:
                break
            loop.append(e)
            seen.add(e)
            prev, cur = cur, e
        if len(loop) >= 4:
            pts = [pt(e) for e in loop]
            loops.append([(xs[0] + (px - 1) * STEP, ys[0] + (py - 1) * STEP) for px, py in pts])
    return loops


def simplify(loop, tol):
    """Дуглас — Пекер для замкнутого контура, tol в px модели."""
    n = len(loop)
    if n < 8:
        return loop
    far = max(range(n), key=lambda k: (loop[k][0] - loop[0][0]) ** 2 + (loop[k][1] - loop[0][1]) ** 2)

    def dp(pts):
        keep = [0, len(pts) - 1]
        stack = [(0, len(pts) - 1)]
        while stack:
            a, b = stack.pop()
            ax, ay = pts[a]
            bx, by = pts[b]
            dx, dy = bx - ax, by - ay
            L = math.hypot(dx, dy) or 1.0
            best, bi = 0.0, None
            for k in range(a + 1, b):
                q = abs((pts[k][0] - ax) * dy - (pts[k][1] - ay) * dx) / L
                if q > best:
                    best, bi = q, k
            if bi is not None and best > tol:
                keep.append(bi)
                stack += [(a, bi), (bi, b)]
        return [pts[k] for k in sorted(keep)]
    return dp(loop[:far + 1])[:-1] + dp(loop[far:] + loop[:1])[:-1]


def poly_area(loop):
    return abs(sum(loop[i][0] * loop[(i + 1) % len(loop)][1] - loop[(i + 1) % len(loop)][0] * loop[i][1] for i in range(len(loop)))) / 2


# ---------------------------------------------------------------- лист
K = 0.96            # единиц листа на px модели (8 единиц = 1 м)
OX, OY = 44.0, 128.0
PANEL_X = 1400.0
W, H = 1720, 1400


def SX(x):
    return round(OX + (x + 720.0) * K, 1)


def SY(y):
    return round(OY + (640.0 - y) * K, 1)


def path_of(loops):
    return " ".join("M" + " L".join(f"{SX(x)} {SY(y)}" for x, y in loop) + " Z" for loop in loops)


EXPORT = {}


def mask_paths(mask, tol=1.6, min_area=30.0, sigma=0.0, name=None):
    f = blur(mask.astype(np.float64), sigma) if sigma else mask.astype(np.float64)
    loops = contours(f, 0.5)
    res = [simplify(q, tol) for q in loops if poly_area(q) >= min_area]
    if name:
        EXPORT[name] = res
    return res


out = []
add = out.append
BG, ROCK0, GRID = "#111418", "#20262c", "#2c343c"
RING, CURT, GATE, STAIR = "#59646f", "#c9d3dc", "#d9a65e", "#b9b08a"
BLD, BLDL, TOWER = "#3a3f49", "#59606c", "#4a505c"
INNER, TEXT, SUB = "#a78bb5", "#e6ecf1", "#a0adb9"
BANDS = ["#23403f", "#2b5048", "#366151", "#44735b", "#568767", "#6d9c78", "#88b18c"]    # двор снизу вверх
FONT = "'Segoe UI', 'Noto Sans', Arial, sans-serif"


def text(x, y, s, size=15, fill=TEXT, anchor="start", weight="400", halo=True):
    style = f' stroke="{BG}" stroke-width="3.2" stroke-opacity="0.75" paint-order="stroke"' if halo else ""
    add(f'<text x="{round(x, 1)}" y="{round(y, 1)}" font-size="{size}" fill="{fill}" text-anchor="{anchor}" font-weight="{weight}"{style}>{s}</text>')


def fill_path(loops, fill, extra=""):
    add(f'<path d="{path_of(loops)}" fill="{fill}" fill-rule="evenodd" {extra}/>')


add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="{FONT}">')
add('<title>Двор замка: план с модели</title>')
add(f'<rect width="{W}" height="{H}" fill="{BG}"/>')

# Контуры стен и маски
inner_face = offset(meta["curtain"]["path"], -meta["curtain"]["t"] / 2)
inside = in_poly(inner_face, XX, YY)
add(f'<clipPath id="дворы"><path d="M' + " L".join(f"{SX(x)} {SY(y)}" for x, y in inner_face) + ' Z"/></clipPath>')

# Скала снаружи куртины
add('<g id="скала-снаружи">')
fill_path(mask_paths(np.isfinite(Z), 2.0, 500.0, 1.0), ROCK0)
add('</g>')

# Сетка 10 м от центра модели
add('<g id="сетка-10м">')
step_m = 10.0 / S
for k in range(-6, 7):
    gx = k * step_m
    add(f'<line x1="{SX(gx)}" y1="{SY(640)}" x2="{SX(gx)}" y2="{SY(-640)}" stroke="{GRID}" stroke-width="{1.2 if k == 0 else 0.7}"/>')
for k in range(-5, 6):
    gy = k * step_m
    add(f'<line x1="{SX(-720)}" y1="{SY(gy)}" x2="{SX(680)}" y2="{SY(gy)}" stroke="{GRID}" stroke-width="{1.2 if k == 0 else 0.7}"/>')
add('</g>')

# Нижняя стена и лестница (для привязки)
add('<g id="нижняя-стена">')
fill_path(mask_paths(PART == pid["Ring"], 1.6, 40.0), RING)
add('</g>')
add('<g id="лестница">')
fill_path(mask_paths(PART == pid["Stairs"], 1.6, 40.0), STAIR)
add('</g>')

# Высоты двора: сглаженная поверхность скалы (колонны шумят, форма важнее)
rock = np.where(np.isfinite(ROCKZ), ROCKZ, 0.0)
smooth = blur(rock, 3.0)
levels = [THRESH + m / S for m in (5, 10, 15, 20, 25, 30)]
add('<g id="двор-высоты" clip-path="url(#дворы)">')
add('<path d="M' + " L".join(f"{SX(x)} {SY(y)}" for x, y in inner_face) + f' Z" fill="{BANDS[0]}"/>')
for lv, col in zip(levels, BANDS[1:]):
    field = np.where(inside, smooth, lv - 1.0)
    loops = [simplify(q, 1.2) for q in contours(field, lv) if poly_area(q) >= 120.0]
    add(f'<path d="{path_of(loops)}" fill="{col}" fill-rule="evenodd" stroke="#0f1c1c" stroke-width="0.7" stroke-opacity="0.45"/>')
add('</g>')

# Здания: массив, как он виден сверху
occupied = np.isin(PART, [pid["Upper"], pid["Crown"]]) & inside
massif = mask_paths(occupied, 1.6, 25.0, name="здания")
add('<g id="здания">')
add(f'<clipPath id="массив"><path d="{path_of(massif)}" clip-rule="evenodd"/></clipPath>')
fill_path(massif, BLD, f'stroke="{BLDL}" stroke-width="0.8"')
add('</g>')

# Границы отдельных залов и башен-домов из таблиц генератора — внутри массива
add('<g id="залы-контуры" clip-path="url(#массив)" fill="none" stroke="#6a7280" stroke-width="0.7" stroke-opacity="0.6">')
for x, y, w, dd, _z0, _e, _r, rot in meta["halls"]:
    a = math.radians(rot)
    c, s = math.cos(a), math.sin(a)
    pts = [(x + u * c - v * s, y + u * s + v * c) for u, v in ((-w / 2, -dd / 2), (w / 2, -dd / 2), (w / 2, dd / 2), (-w / 2, dd / 2))]
    add('<polygon points="%s"/>' % " ".join(f"{SX(a_)},{SY(b_)}" for a_, b_ in pts))
for x, y, w, dd, _z0, _z1 in meta["tower_houses"]:
    add(f'<rect x="{SX(x - w / 2)}" y="{SY(y + dd / 2)}" width="{round(w * K, 1)}" height="{round(dd * K, 1)}"/>')
add('</g>')

# Главные башни
add('<g id="башни">')
for key, rr in (("donjon", meta["donjon_r"]), ("broken", meta["broken"]["r"]), ("round", meta["round"]["r"] + 7)):
    q = meta["donjon"] if key == "donjon" else meta[key]
    add(f'<circle cx="{SX(q["x"])}" cy="{SY(q["y"])}" r="{round(rr * K, 1)}" fill="{TOWER}" stroke="{CURT}" stroke-width="1.4"/>')
add('</g>')

add('<g id="внутренние-стены">')
fill_path(mask_paths((PART == pid["Inner"]) & inside, 1.6, 20.0, name="внутренние"), INNER)
add('</g>')

add('<g id="куртина">')
fill_path(mask_paths(PART == pid["Curtain"], 1.6, 40.0, name="куртина"), CURT)
# Куртина там, где сверху её закрывает скала
axis = meta["curtain"]["path"]
hidden = []
for x, y in axis:
    i = int(round((x - xs[0]) / STEP))
    j = int(round((y - ys[0]) / STEP))
    near = PART[j - 3:j + 4, i - 3:i + 4]
    hidden.append(bool((near == pid["Rock"]).any() and not np.isin(near, [pid["Curtain"], pid["Gate"]]).any()))
runs, cur = [], []
for k in range(len(axis)):
    if hidden[k]:
        cur.append(axis[k])
    elif cur:
        runs.append(cur)
        cur = []
if cur:
    runs.append(cur)
HIDDEN_M = sum(math.hypot(q[i + 1][0] - q[i][0], q[i + 1][1] - q[i][1]) for q in runs for i in range(len(q) - 1)) * S
for q in runs:
    if len(q) >= 2:
        add('<polyline points="%s" fill="none" stroke="%s" stroke-width="3.2" stroke-dasharray="7 5"/>' % (" ".join(f"{SX(a_)},{SY(b_)}" for a_, b_ in q), CURT))
add('</g>')
add('<g id="ворота">')
fill_path(mask_paths(PART == pid["Gate"], 1.6, 40.0, name="ворота"), GATE)
add('</g>')
add('<g id="отрог">')
fill_path(mask_paths(PART == pid["Spur"], 1.6, 20.0, name="отрог"), "#7fa8c9")
add('</g>')


# ---------------------------------------------------------------- измерения
free = (PART == pid["Rock"]) & inside
cell = (STEP * S) ** 2


def probe(x0, y0, dx, dy, limit=400):
    """От внутренней грани куртины по лучу до первой постройки; (длина в px, точки)."""
    x, y = x0, y0
    start = None
    for k in range(int(limit / 1.5)):
        i = int(round((x - xs[0]) / STEP))
        j = int(round((y - ys[0]) / STEP))
        here_in = bool(inside[j, i])
        if here_in and start is None:
            start = (x, y)
        if start is not None:
            if not here_in or PART[j, i] != pid["Rock"]:
                return math.hypot(x - start[0], y - start[1]), start, (x, y)
        x += dx * 1.5
        y += dy * 1.5
    return 0.0, start, (x, y)


def m(v):
    return f"{v * S:.0f}".replace(".", ",")


def height_at(x, y):
    i = int(round((x - xs[0]) / STEP))
    j = int(round((y - ys[0]) / STEP))
    return (smooth[j, i] - THRESH) * S


probes = {"юг": (0, -420, 0, 1), "север": (-60, 470, 0, -1), "запад": (-520, -110, 1, 0), "восток": (560, 0, -1, 0), "сев-вост": (130, 470, 0, -1)}
widths = {}
add('<g id="размеры">')
for name, (x0, y0, dx, dy) in probes.items():
    L, a, b = probe(x0, y0, dx, dy)
    widths[name] = L * S
    add(f'<line x1="{SX(a[0])}" y1="{SY(a[1])}" x2="{SX(b[0])}" y2="{SY(b[1])}" stroke="{TEXT}" stroke-width="1.4"/>')
    for q in (a, b):
        add(f'<circle cx="{SX(q[0])}" cy="{SY(q[1])}" r="2.6" fill="{TEXT}"/>')
    mx_, my_ = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    if dy:
        text(SX(mx_) + 8, SY(my_) + 5, f"{m(L)} м", 14, TEXT, weight="600")
    else:
        text(SX(mx_), SY(my_) - 8, f"{m(L)} м", 14, TEXT, "middle", "600")
add('</g>')

# Вход: ось ворот
g = meta["gate"]
nx, ny = g["normal"]
mx, my = g["mid"]
profile = []
for k in range(0, 400, 3):
    sv = -k
    x_, y_ = mx + nx * sv, my + ny * sv
    i_, j_ = int(round((x_ - xs[0]) / STEP)), int(round((y_ - ys[0]) / STEP))
    profile.append((k, parts[PART[j_, i_]] if PART[j_, i_] >= 0 else "-", float(Z[j_, i_]), float(ROCKZ[j_, i_])))
first_rock = next(q[0] for q in profile if q[1] == "Rock")
rise = next((q[0] for q in profile if q[1] == "Rock" and q[0] > first_rock and q[2] > THRESH + 6 / S), None)
first_bld = next((q[0] for q in profile if q[0] > first_rock and q[1] != "Rock"), None)
LEDGE_M = (rise - first_rock) * S if rise else 0.0
top_after = max(q[2] for q in profile if first_rock <= q[0] <= (first_bld or 400) and q[1] == "Rock")
GATE_TO_BLD_M = ((first_bld or first_rock) - first_rock) * S
b_gate = (mx - nx * (first_bld or first_rock), my - ny * (first_bld or first_rock))
add('<g id="вход">')
add(f'<line x1="{SX(mx + nx * 40)}" y1="{SY(my + ny * 40)}" x2="{SX(b_gate[0])}" y2="{SY(b_gate[1])}" stroke="{TEXT}" stroke-width="2" stroke-dasharray="8 6"/>')
ax_, ay_ = SX(b_gate[0]), SY(b_gate[1])
ux, uy = (-nx, ny)      # направление на листе (Y перевёрнут)
add(f'<polygon points="{ax_},{ay_} {round(ax_ - ux * 13 - uy * 6, 1)},{round(ay_ - uy * 13 + ux * 6, 1)} {round(ax_ - ux * 13 + uy * 6, 1)},{round(ay_ - uy * 13 - ux * 6, 1)}" fill="{TEXT}"/>')
add('</g>')

# Отметки высот на дворе: только там, где видна скала
add('<g id="отметки">')
spots = [(-250, -300), (0, -318), (0, -272), (150, -300), (-400, -200), (-405, 120), (-300, 370), (-60, 405), (-20, 340), (300, 395), (440, 250), (480, -40), (455, -130), (345, -255), (238, -318), (120, -35)]
used = []
for x, y in spots:
    i = int(round((x - xs[0]) / STEP))
    j = int(round((y - ys[0]) / STEP))
    if not free[j, i]:
        continue
    h = height_at(x, y)
    add(f'<circle cx="{SX(x)}" cy="{SY(y)}" r="2.2" fill="{BG}"/>')
    text(SX(x) + 6, SY(y) + 5, f"+{h:.0f}".replace("+-", "−"), 12, TEXT)
    used.append((x, y, round(h, 1)))
add('</g>')

# Подписи
add('<g id="подписи">')
q = meta["donjon"]
text(SX(q["x"]), SY(q["y"]) + 5, "Донжон", 15, TEXT, "middle", "600")
q = meta["broken"]
text(SX(q["x"]), SY(q["y"]) + 5, "Обломанная башня", 13, TEXT, "middle", "600")
q = meta["round"]
text(SX(q["x"]), SY(q["y"]) + 5, "Малая", 12, TEXT, "middle", "600")
q = meta["spur"]
text(SX(q["x"]), SY(q["y"]) + 5, "Отрог", 13, BG, "middle", "600", halo=False)
text(SX(-130), SY(-325), "ДВОР", 18, TEXT, "middle", "600")
text(SX(-210), SY(385), "ДВОР", 18, TEXT, "middle", "600")
text(SX(-405), SY(-90), "ДВОР", 18, TEXT, "middle", "600")
text(SX(120), SY(-35) + 24, "Верх скалы среди зданий", 13, TEXT, "middle")
text(SX(40), SY(-395) + 2, "Куртина", 15, CURT, "middle", "600")
text(SX(-120), SY(-520), "Нижняя стена", 14, "#8b97a3", "middle")
text(SX(430), SY(-385), "Ворота", 15, GATE, weight="600")
text(SX(382), SY(-580), "Лестница к мосту", 14, STAIR)
text(SX(-405), SY(62), "Аркада", 12, TEXT, "middle")
add('</g>')

# Заголовок
add('<g id="заголовок">')
text(44, 58, "Внутренний двор замка: план с модели", 30, TEXT, weight="600", halo=False)
text(44, 90, "Контуры сняты сверху с самой модели (castle.blend). Север вверху, сетка 10 м от центра модели.", 16, SUB, halo=False)
add('</g>')

# Север и масштаб
nx0, ny0 = 1330, 62
add('<g id="север">')
add(f'<line x1="{nx0}" y1="{ny0 + 30}" x2="{nx0}" y2="{ny0 - 22}" stroke="{TEXT}" stroke-width="2"/>')
add(f'<polygon points="{nx0},{ny0 - 32} {nx0 - 6},{ny0 - 18} {nx0 + 6},{ny0 - 18}" fill="{TEXT}"/>')
text(nx0, ny0 + 50, "С", 15, TEXT, "middle", "600", halo=False)
add('</g>')

# Панель справа
h_, w_ = free.shape
k0 = first_rock + 3
sx_, sy_ = mx - nx * k0, my - ny * k0
seed = (int(round((sy_ - ys[0]) / STEP)), int(round((sx_ - xs[0]) / STEP)))
seen = np.zeros(free.shape, dtype=bool)
seen[seed] = True
dq = deque([seed])
while dq:
    j, i = dq.popleft()
    for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        a_, b_ = j + dj, i + di
        if 0 <= a_ < h_ and 0 <= b_ < w_ and free[a_, b_] and not seen[a_, b_]:
            seen[a_, b_] = True
            dq.append((a_, b_))
ring_area = float(seen.sum()) * cell
pockets = float(free.sum()) * cell - ring_area
ins_area = float(inside.sum()) * cell
bld_area = float(occupied.sum()) * cell
gy, gx = np.gradient(blur(rock, 4.0), STEP)
slope = np.degrees(np.arctan(np.hypot(gx, gy)))
sv = slope[seen]
bins = [float((sv < 15).mean()), float(((sv >= 15) & (sv < 30)).mean()), float(((sv >= 30) & (sv < 45)).mean()), float((sv >= 45).mean())]
ringz = Z[seen]
behind_z = next(q[2] for q in profile if q[1] == "Rock")
behind = (behind_z - THRESH) * S


def R(v, nd=0):
    return f"{v:.{nd}f}".replace(".", ",")


add('<g id="панель">')
px = PANEL_X
y = 170


def head(t_):
    global y
    y += 42
    text(px, y, t_, 18, TEXT, weight="600", halo=False)


def row(t_):
    global y
    y += 23
    text(px, y, t_, 14, SUB, halo=False)


y -= 42
head("Форма")
for t_ in ("Кольцо скальных террас между куртиной", "и зданиями. Ровного пола нет: скала", "поднимается от стены к зданиям."):
    row(t_)
head("Размеры")
for t_ in (f"За куртиной всего: {R(ins_area)} м²", f"Здания: {R(bld_area)} м²", f"Кольцо двора: {R(ring_area)} м²", f"Карманы между зданиями: {R(pockets)} м²",
           f"Ширина: юг {R(widths['юг'])} м, запад {R(widths['запад'])} м,", f"восток {R(widths['восток'])} м, север {R(widths['север'])} м",
           f"За внутренней стеной на северо-востоке: {R(widths['сев-вост'])} м"):
    row(t_)
head("Вход")
for t_ in ("Один, через верхние ворота (пунктир).", f"Порог ворот: {R(meta['origin'][2] + THRESH * S, 1)} м мира.", f"Сразу за воротами скала выше порога", f"на {R(behind, 1)} м, ступеней нет.",
           f"Этот уступ шириной {R(LEDGE_M, 1)} м, дальше", f"подъём до +{R((top_after - THRESH) * S)} м; до внутренней стены {R(GATE_TO_BLD_M)} м."):
    row(t_)
head("Уклон кольца")
row(f"до 15°: {R(bins[0] * 100)} %   15–30°: {R(bins[1] * 100)} %")
row(f"30–45°: {R(bins[2] * 100)} %   круче: {R(bins[3] * 100)} %")
head("Высота от порога ворот")
y += 6
for col, lab in zip(BANDS, ["0–5 м", "5–10 м", "10–15 м", "15–20 м", "20–25 м", "25–30 м", "выше 30 м"]):
    y += 25
    add(f'<rect x="{px}" y="{y - 15}" width="34" height="19" fill="{col}"/>')
    text(px + 44, y, lab, 14, SUB, halo=False)
head("Обозначения")
y += 4
for col, lab in ((CURT, "Куртина и её башни"), (GATE, "Ворота"), (STAIR, "Лестница, площадка"), (BLD, "Здания"), (INNER, "Внутренние стены"), (RING, "Нижняя стена"), (ROCK0, "Скала снаружи куртины")):
    y += 25
    add(f'<rect x="{px}" y="{y - 15}" width="34" height="19" fill="{col}" stroke="{GRID}"/>')
    text(px + 44, y, lab, 14, SUB, halo=False)
y += 25
add(f'<line x1="{px}" y1="{y - 6}" x2="{px + 34}" y2="{y - 6}" stroke="{CURT}" stroke-width="3.2" stroke-dasharray="7 5"/>')
text(px + 44, y, "Куртина, закрытая скалой сверху", 14, SUB, halo=False)
y += 42
add(f'<rect x="{px}" y="{y}" width="80" height="7" fill="{TEXT}"/>')
add(f'<rect x="{px + 80}" y="{y}" width="80" height="7" fill="#7f8c98"/>')
add(f'<rect x="{px + 160}" y="{y}" width="80" height="7" fill="{TEXT}"/>')
for v, q in ((0, 0), (10, 80), (20, 160), (30, 240)):
    text(px + q, y - 6, f"{v} м" if v else "0", 12, SUB, "middle", halo=False)
PANEL_END = y + 20
add('</g>')

add('</svg>')
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out))
print("bytes", os.path.getsize(OUT), "panel_end", PANEL_END)
print(json.dumps({"inside": round(ins_area), "bld": round(bld_area), "ring": round(ring_area), "pockets": round(pockets), "w": {k.encode("ascii", "ignore").decode() or str(i): round(v, 1) for i, (k, v) in enumerate(widths.items())},
                  "behind_m": round(behind, 1), "ledge_m": round(LEDGE_M, 1), "top_after_m": round((top_after - THRESH) * S, 1), "gate_to_bld_m": round(GATE_TO_BLD_M, 1), "slope": [round(b * 100) for b in bins],
                  "hidden_curtain_m": round(HIDDEN_M, 1), "spots": used, "ring_z_pct": [round(float(np.percentile(ringz, p))) for p in (1, 25, 50, 75, 99)],
                  "profile": [(q[0], q[1][:3], round(q[2])) for q in profile[:70:4]]}))
# Проверка: контуры плана поверх настоящего вида сверху (1 px модели = 1 точка, центр кадра — начало модели)
im = Image.open(os.path.join(SP, "view_top.png")).convert("RGB")
iw, ih = im.size
dr = ImageDraw.Draw(im)
cols = {"куртина": (255, 240, 120), "здания": (255, 90, 90), "внутренние": (230, 120, 255), "ворота": (255, 170, 60), "отрог": (120, 200, 255)}
for name, loops in EXPORT.items():
    for loop in loops:
        pts = [(iw / 2 + x * iw / 1500.0, ih / 2 - y * iw / 1500.0) for x, y in loop]
        dr.line(pts + pts[:1], fill=cols[name], width=1)
im.save(os.path.join(SP, "yard_plan_check.png"))
