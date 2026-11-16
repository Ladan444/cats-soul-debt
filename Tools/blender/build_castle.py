"""Замок на скале по трём видам автора — замена крепости Каменного Рубежа на мысу (пока только в своей сцене).

Запуск из Blender (MCP), пишет только свою коллекцию «Castle» и файл Арт/Blender/castle/castle.blend:
    exec(open(r"<проект>/Tools/blender/build_castle.py", encoding="utf-8").read(), {"__name__": "__main__", "MODE": "build"})
MODE: build — собрать и сохранить; sil — силуэты спереди/сзади/справа для Tools/castle_compare.py;
      views — итоговые рендеры (4 стороны, сверху, игровая камера). DETAIL = False — только массы.
Посадка на мыс — SITE ниже, площадка и рендеры на ней — Tools/blender/castle_site.py.
В другой открытый файл не пишет: если открыт чужой .blend, сразу ошибка.

Все размеры в таблицах — в пикселях исходников (1500×1240): так их легко сверять с картинками.
X — вправо на виде спереди, Y — назад, Z — вверх от плоского среза скалы (строка 1190 → z = 0). Ось замка — x = 750.
В метры переводит S при создании меша. Оси Godot: (x, z, −y) — как у остальных генераторов.
"""
import json
import math
import os
import random

import bpy
import numpy as np
from mathutils import Vector, noise
from mathutils.bvhtree import BVHTree

PROJECT = r"C:\Users\Ladan444\Desktop\The cat's soul debt GAMEDEV"
OUT = os.path.join(PROJECT, "Арт", "Blender", "castle")
BLEND = os.path.join(OUT, "castle.blend")
MODE = globals().get("MODE", "build")
DETAIL = globals().get("DETAIL", True)

# ---------------------------------------------------------------- ПАРАМЕТРЫ ----------------------------------------
S = 0.12              # м на пиксель исходника: арка ворот 65 px ≈ 8 м, как проём ворот Рубежа в мире; скала 161×146 м на мысу 198×203 м
# Посадка (решение автора 2026-11-06): мост не меняется и приходит к подножию скалы, к началу лестницы. Низ лестницы —
# там, где мост кончается сейчас (poi-rubezh-gate в build_world.py), на плато мыса: 9 м над нулём мира, гладь озера 2 м.
# Ворота смотрят на юг, поворота нет.
SITE = {"bridge_end": (-427.0, 480.0), "ground": 9.0}
ROCK_BASE = 0         # низ скалы, px: стоит на плато мыса (z = 8 px — 9 м мира). На западе земля ниже, там юбка в build_scree
SEED = 7

# Скала: сечение на высоте z — суперэллипс с полуосями по квадрантам (xmin, xmax, ymin, ymax).
ROCK_P = 2.3
ROCK = [  # z, xmin, xmax, ymin, ymax
    (0, -693, 648, -607, 608),
    (50, -680, 640, -598, 598),
    (110, -660, 625, -585, 585),
    (165, -640, 615, -570, 572),   # уступ под нижней стеной
    (180, -590, 585, -530, 535),   # за нижней стеной
    (230, -565, 580, -495, 525),
    (300, -520, 575, -452, 500),
    (345, -480, 565, -396, 452),   # уступ под куртиной: узкий, скала подходит к самой стене
    (362, -430, 548, -345, 420),   # за куртиной
    (430, -405, 525, -320, 410),
    (465, -400, 505, -270, 395),
    (510, -340, 470, -205, 368),
    (590, -150, 380, -170, 180),
    (650, -40, 300, -140, 60),
    (680, -20, 200, -120, 20),
]
# Выступы скалы — круги на высотах: (центр x, центр y, [(z, радиус)...]). Вне таблицы круга нет.
LOBES = [
    (-515, 40, [(0, 180), (120, 150), (170, 140), (182, 70), (230, 66), (350, 60), (420, 40)]),  # низ отрога; выше уступа он внутри сетки CRAGS
    (290, -372, [(170, 120), (250, 95), (318, 76), (326, 40)]),           # площадка верхних ворот
]
# Отрог от уступа за нижней стеной — своя сетка: у полярной сетки основной скалы смещение идёт вбок от оси, спереди он гладкий, а клин до оси закрыл бы арки.
SPUR_CLEAR_X = -450    # восточнее и выше 456 px скалы отрога нет: там аркада
CRAGS = [(-510, 40, [(176, 88), (235, 90), (255, 104), (300, 102), (350, 97), (400, 88), (440, 79), (470, 73), (498, 68), (510, 30)], 112, 66),
         (390, -177, [(420, 118), (505, 98), (540, 80), (590, 62), (640, 42), (672, 38), (682, 16)], 140, 40)]  # холм малой круглой башни
SCREE_COUNT = 240     # камни осыпи у подножия
ROCK_NOISE = 18       # размах смещения скалы, px
ROCK_SEGMENTS = 520
ROCK_ROWS = 90
STAIR_CLEAR = 42      # радиус вокруг лестницы, где скала вдавлена

# Нижняя кольцевая стена.
RING = {"ext": (-610, 600, -552, 556), "p": 2.3, "z0": 92, "z1": 225, "t": 12, "n": 96}
# Проём между башнями 240 и 412: лестница проходит нижнюю стену открыто, как на арте. Края пролётов скрыты в башнях.
RING_GAP = (246, 406)
RING_TOWERS = [  # x, сторона (−1 перед, +1 зад), верх, радиус
    (-497, -1, 305, 26), (-107, -1, 290, 26), (240, -1, 255, 24), (412, -1, 300, 26), (590, -1, 255, 22),
    (465, 1, 255, 32), (198, 1, 258, 28), (-253, 1, 252, 27), (-482, 1, 255, 28),
    (-606, 1, 250, 20),   # запад, под отрогом: на картинках её нет, для вида слева
]
# Куртина.
CURTAIN = {"ext": (-447, 520, -355, 435), "p": 3.0, "z0": 270, "z1": 460, "t": 16, "n": 96}
CURTAIN_TOWERS = [(505, -1, 483, 23), (-113, 1, 478, 27), (505, 1, 470, 22)]
BUTTRESS_STEP = 105
# Надвратное укрепление: две башни и блок между ними.
GATE = {"t1": (208, -415), "t2": (370, -355), "r": 27, "z0": 318, "top1": 500, "top2": 522, "wall_top": 500,
        "depth": 62, "recess": 13, "porch": 18, "arch_w": 65, "arch_h": 108, "arch_z": 332}
# Лестница: от площадки верхних ворот к подножию, к мосту. Узлы (x, z) — с вида спереди, глубина — по поверхности скалы.
# Низ марша ближе к оси, чем в арте (284): мост приходит левее, иначе скала не влезает на мыс. Уклон и число маршей как в арте.
# Ступень 3,2 px ≈ 0,38 м: у Рэя нет подъёма на ступень, при встраивании под ступенями нужен скат-коллизия.
STAIRS = {"nodes": [(380, 258), (270, 180), (385, 118), (265, 64), (130, 8)], "landing": 78, "w": 36, "step": 3.2, "tread": 7.0,
          "land_min": 20.0, "out": -6, "foot": (74, 58)}  # out < 0: марш врезан в скалу. land_min — наименьшая площадка в марше, px
# Внутренние стены на террасах (против часовой, снаружи — справа по ходу).
INNER_WALLS = [
    ([(470, 100), (460, 230), (360, 350), (200, 400), (30, 395)], 440, 535, 12),
    ([(-360, -232), (-170, -250)], 460, 552, 12),
    ([(235, -245), (350, -222)], 460, 530, 12),
]
INNER_TOWERS = [(370, 345, 552, 28, 440)]  # x, y, верх, радиус, низ
# Донжон и венец.
DONJON = {"x": -35, "y": 21, "tiers": [  # z0, z1, r0, r1, зубцы сверху
    (560, 770, 90, 86, True), (770, 845, 71, 70, True), (845, 925, 62, 60, True), (925, 990, 41, 41, True)],
    "crown_r": 47, "crown_z": 990, "spire": [(1000, 1022, 13, 9), (1022, 1056, 7, 4.5), (1056, 1093, 4.5, 0.6)]}
BROKEN = {"x": 196, "y": 180, "z0": 540, "r": 70, "collar_z": 795, "ring_out": 61, "ring_in": 50,
          "tops": [(-180, 915), (-135, 900), (-90, 842), (-45, 905), (0, 880), (45, 900), (90, 866), (135, 905), (180, 915)]}
ROUND = {"x": 390, "y": -177, "z0": 596, "z1": 700, "r": 34, "crown_r": 41}
# Башня на отроге и стена с арками.
# Азимут −90° — лицом к виду спереди. Верх снят с арта: высокий обломок у −101°, выбоина у −64°.
SPUR = {"x": -497, "y": 40, "z0": 440, "foot": 504, "z1": 596, "r": 50, "ring_out": 52, "ring_in": 41,
        "tops": [(-180, 640), (-162, 646), (-140, 645), (-128, 634), (-116, 636), (-108, 656), (-96, 655), (-88, 636), (-76, 630), (-64, 607), (-52, 612),
                 (-42, 642), (-26, 646), (-6, 649), (20, 640), (45, 628), (90, 625), (135, 640), (180, 640)]}
# Верх аркады: от башни к куртине, по арту; доля длины, высота.
ARCADE = {"p0": (-447, 40), "p1": (-365, 34), "z0": 425, "tops": [556, 534, 524], "t": 12, "arch_z": 463, "arch_h": 58,
          "skyline": [(0.0, 560), (0.08, 552), (0.2, 538), (0.34, 530), (0.5, 534), (0.66, 526), (0.82, 530), (1.0, 522)]}
# Узкие залы со щипцами: x, y, ширина, длина, низ, карниз, конёк, поворот (конёк вдоль Y при 0°).
HALLS = [
    (-82, -120, 85, 130, 520, 680, 750, 0), (-192, -150, 65, 100, 500, 630, 685, 0), (-275, -170, 60, 90, 480, 590, 640, 0),
    (75, -130, 55, 110, 510, 650, 705, 0), (155, -150, 70, 110, 500, 640, 700, 0), (272, -110, 72, 110, 510, 640, 695, 0),
    (345, -120, 48, 80, 510, 630, 680, 0),
    (290, 150, 80, 120, 520, 670, 740, 0), (25, 150, 70, 120, 540, 720, 780, 0), (125, 180, 50, 100, 520, 640, 690, 0),
    (-100, 170, 65, 110, 520, 680, 740, 0), (-245, 210, 65, 110, 500, 660, 720, 0), (-320, 280, 50, 80, 480, 580, 620, 0),
    (-185, 270, 50, 80, 480, 620, 660, 0), (200, 290, 50, 70, 500, 610, 650, 0), (370, 230, 45, 70, 480, 590, 630, 0),
    (360, 20, 60, 100, 500, 620, 680, 90), (240, 40, 70, 150, 520, 680, 730, 90), (-240, 60, 60, 100, 480, 610, 665, 90),
    (110, 30, 120, 140, 540, 680, 725, 90),
]
# Ряды залов на террасах: y, низ, карниз, конёк, [(x, ширина)...], длина, поворот. Конёк ограничен контуром исходников.
HALL_ROWS = [
    (-240, 440, 555, 600, [(-130, 42), (-60, 46), (10, 42), (70, 38), (130, 44), (190, 36)], 36, 0),
    (-188, 460, 610, 668, [(-335, 38), (-295, 44), (-225, 46), (-165, 40), (-40, 50), (30, 46), (90, 40), (150, 48), (215, 44), (285, 46), (340, 38)], 60, 0),
    (262, 500, 600, 655, [(-60, 44), (-5, 40), (50, 44), (110, 40), (165, 44), (250, 46), (320, 42)], 70, 0),
    (-30, 480, 640, 690, [(-250, 46)], 80, 0),
    (-72, 530, 690, 745, [(-155, 40), (-28, 44), (28, 36), (128, 46), (205, 40)], 56, 0),   # верхний слой над передними рядами
    (70, 540, 690, 745, [(-175, 40), (-55, 44), (165, 42), (235, 40)], 60, 0),
]
# Ряды поперёк: x, низ, карниз, конёк, [(y, ширина)...], длина (залы смотрят щипцом на восток и запад).
HALL_COLS = [
    (-335, 480, 565, 610, [(-150, 40), (-85, 38), (-20, 40), (45, 36), (120, 40), (195, 38)], 44),
    (345, 500, 620, 672, [(-40, 42), (90, 44), (165, 40)], 60),
    (432, 470, 552, 600, [(-105, 36), (-52, 40), (8, 36), (72, 40), (140, 36)], 38),
]
# Большое окно с переплётом — только здесь: на арте их единицы, остальное мелкие окна рядами.
FOCAL_HALLS = {(-82, -120), (25, 150), (290, 150)}
# Разрушенные щипцы: начало, конец, низ, высоты верха по длине, толщина.
RUINS = [
    ((-212, 250), (-124, 292), 540, [700, 735, 778, 816, 792, 748, 772, 810, 768, 716], 18),   # под углом: и сбоку не плита
    ((-284, 282), (-212, 322), 540, [650, 690, 702, 738, 764, 728, 690], 16),
    ((-378, -62), (-332, -58), 490, [560, 610, 585, 540], 14),
    ((-300, -120), (-262, -125), 500, [640, 685, 660, 610], 12),
]
# Тонкие башенки: x, y, радиус, низ, карниз, вершина. Вершины сопоставлены по высоте между видами.
TURRETS = [
    (326, -130, 14, 590, 735, 795), (57, -80, 15, 610, 790, 855), (-105, 110, 12, 620, 800, 860), (288, -50, 11, 620, 685, 735),
    (82, -50, 12, 620, 730, 780), (50, 100, 12, 620, 720, 773), (-347, 332, 11, 470, 595, 643), (-138, -190, 13, 470, 610, 660),
    (307, -20, 9, 620, 680, 725), (110, -20, 9, 620, 690, 730), (45, -226, 10, 450, 530, 575), (385, -110, 9, 540, 590, 620),
    (125, 120, 10, 620, 690, 740), (-300, 200, 10, 500, 630, 680), (-55, -226, 9, 450, 545, 590),
]
MOSS_TINT = (0.26, 0.50, 0.22)   # множитель текстуры скалы там, где мох
FILLER_PINNACLES = 26  # мелкие башенки на залах, вершины ограничены контуром исходников
AUTO_TURRETS = 46       # дополнительные тонкие башенки с конусами на залах
MERLON_LOST = 0.035     # доля выпавших зубцов
# Квадратные башни-дома с зубцами между залами: x, y, ширина, глубина, низ, верх.
TOWER_HOUSES = [
    (-345, -205, 50, 40, 460, 606), (-262, -215, 44, 30, 460, 585), (-205, -215, 38, 30, 460, 566), (-95, -215, 44, 30, 460, 560),
    (55, -215, 40, 30, 460, 570), (120, -215, 44, 30, 460, 556), (250, -205, 50, 36, 460, 606), (318, -200, 44, 32, 460, 596),
    (-22, -128, 40, 34, 520, 696), (112, -118, 36, 32, 520, 682), (214, -112, 34, 30, 520, 664), (-150, -118, 38, 34, 500, 690),
    (40, 92, 36, 34, 540, 716), (-60, 110, 34, 32, 540, 706), (150, 108, 36, 32, 540, 690), (-200, 150, 36, 34, 520, 676),
    (60, 300, 46, 34, 500, 600), (-60, 300, 44, 34, 500, 590), (150, 320, 40, 30, 500, 585), (280, 300, 44, 32, 500, 595),
    (-250, 120, 44, 40, 480, 612), (395, -30, 40, 36, 500, 612),
]

# Материалы: цвет для чернового вида и файл текстуры (период в метрах).
MATS = {
    "rock": ((0.30, 0.27, 0.23), "castle_rock.png"),
    "stone": ((0.34, 0.32, 0.28), "castle_stone.png"),
    "trim": ((0.42, 0.40, 0.35), "castle_trim.png"),
    "roof": ((0.10, 0.12, 0.15), "castle_slate.png"),
    "dark": ((0.012, 0.012, 0.016), None),
    "cloth": ((0.028, 0.02, 0.034), None),
    "moss": ((0.30, 0.31, 0.22), "castle_moss.png"),
    "recess": ((0.10, 0.09, 0.08), "castle_recess.png"),
    "floor": ((0.30, 0.28, 0.24), "castle_floor.png"),
    "foliage": ((0.20, 0.25, 0.10), "@ExtrasFoliage.png"),   # атласы растительности проекта, 40 px/м
    "solid": ((0.20, 0.25, 0.10), "@ExtrasSolid.png"),
}
NATURE_TEX = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "models", "nature", "textures")
ATLAS = {"ivy": (374, 88, 96, 96), "ivy_thin": (2, 186, 64, 64), "vine": (68, 186, 40, 112)}  # extras_atlas.json
ATLAS_SIZE = 512.0
TEX_PERIOD = 3.2      # м на плитку: 128 px = 3,2 м (40 px/м)
PART_TONE = {"Upper": 0.92, "Inner": 0.92, "Crown": 1.02}  # глубже — темнее
MOSS_SHARE = 0.42     # порог шума: чем ниже, тем больше кладки со мхом
MAT_NAMES = list(MATS)
ROCK_M, STONE, TRIM, ROOF, DARK, CLOTH, MOSS, RECESS, FLOOR, FOLIAGE, SOLID = range(11)
TAU = math.tau
R = random.Random(SEED + 3)       # разброс мелких деталей
SPOTS = {"wall": [], "stair": []}   # места для растений на кладке и у ступеней, px (на скале их берёт castle_veg.py)
IVY = []                          # места для плюща и лиан на стенах
BUILT = []                        # готовые части: по ним плющ проверяет, есть ли под ним камень
_ROCK_BVH = []                    # дерево готовой скалы, один раз за сборку (rock_surface)
HALL_ACTUAL = {}                  # (x, y) зала -> (низ, карниз, конёк) после ограничения контуром


# ---------------------------------------------------------------- ПОСТРОЕНИЕ МЕШЕЙ ---------------------------------
class Part:
    """Меш одной части замка: вершины в px, грани с номером материала."""

    def __init__(self, name):
        self.name, self.v, self.f, self.m = name, [], [], []
        self.col = None
        self.dim = {}   # номер грани -> множитель тона
        self.fuv = {}   # номер грани -> развёртка по углам (атласы растительности)
        self.gid = 0
        self.group = {}   # номер грани -> одна цельная деталь: один тон, а не полосы по граням
        self.smooth = set()   # сглаженные грани: круглые башни и шатры
        self.cylf = {}    # номер грани -> (центр x, центр y, радиус): развёртка вокруг оси, без швов и растяжения
        self.aorange = {} # номер грани -> (низ, верх) видимой части всей стены: затенение считается по ней, а не по грани

    def darken(self, start, k):
        """Затемнить грани, добавленные после start: то, что стоит глубже, на дальнем плане читается темнее."""
        for i in range(start, len(self.f)):
            self.dim[i] = k

    def add(self, pts):
        i = len(self.v)
        self.v.extend(pts)
        return list(range(i, i + len(pts)))

    def face(self, idx, mat):
        self.f.append(tuple(idx))
        self.m.append(mat)

    def poly(self, pts, mat):
        self.face(self.add(pts), mat)


def circle(x, y, r, seg, phase=0.0):
    return [(x + r * math.cos(phase + TAU * i / seg), y + r * math.sin(phase + TAU * i / seg)) for i in range(seg)]


def prism(P, plan0, plan1, z0, z1, mat, top=True, bottom=False, top_mat=None, round_axis=None, rows=1, ao=None):
    """Призма: планы против часовой, грани наружу. round_axis (x, y, r): круглая деталь — сглаживание и развёртка вокруг оси.
    rows — строк по высоте: цвет задан в вершинах, без них стена ровная заливка. ao (низ, верх) — видимая часть для затенения."""
    n = len(plan0)
    rings = []
    for r in range(rows + 1):
        k = r / rows
        rings.append(P.add([(a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, z0 + (z1 - z0) * k) for a, b in zip(plan0, plan1)]))
    P.gid += 1
    for r in range(rows):
        a, b = rings[r], rings[r + 1]
        for i in range(n):
            j = (i + 1) % n
            fi = len(P.f)
            P.group[fi] = P.gid
            if round_axis:
                P.smooth.add(fi)
                P.cylf[fi] = round_axis
            if rows > 1 or ao:
                P.aorange[fi] = ao or (z0, z1)
            P.face((a[i], a[j], b[j], b[i]), mat)
    if top:
        P.group[len(P.f)] = P.gid
        P.face(rings[-1], mat if top_mat is None else top_mat)
    if bottom:
        P.group[len(P.f)] = P.gid
        P.face(rings[0][::-1], mat)


def cyl(P, x, y, z0, z1, r0, r1=None, seg=24, mat=STONE, top=True, rows=1, ao=None):
    r1 = r0 if r1 is None else r1
    axis = (x, y, (r0 + r1) / 2) if seg >= 6 else None
    prism(P, circle(x, y, r0, seg), circle(x, y, r1, seg), z0, z1, mat, top, round_axis=axis, rows=rows, ao=ao)


def dense_rect(x, y, w, d, rot=0.0, step=20.0):
    """Прямоугольник с точками на сторонах: стена получает сетку и по горизонтали."""
    corners = rect(x, y, w, d, rot)
    out = []
    for a, b in zip(corners, corners[1:] + corners[:1]):
        n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n)]
    return out


def cone(P, x, y, z0, z1, r, seg=10, mat=ROOF):
    ring = P.add([(px, py, z0) for px, py in circle(x, y, r, seg)])
    apex = P.add([(x, y, z1)])[0]
    P.gid += 1
    for i in range(seg):
        P.group[len(P.f)] = P.gid
        if seg >= 6:
            P.smooth.add(len(P.f))
            P.cylf[len(P.f)] = (x, y, r * 0.6)
        P.face((ring[i], ring[(i + 1) % seg], apex), mat)


def rect(x, y, w, d, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    return [(x + u * c - v * s, y + u * s + v * c) for u, v in ((-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2))]


def box(P, x, y, z0, z1, w, d, rot=0.0, mat=STONE, w1=None, d1=None, top=True):
    prism(P, rect(x, y, w, d, rot), rect(x, y, w if w1 is None else w1, d if d1 is None else d1, rot), z0, z1, mat, top)


def se_radius(theta, ext, p):
    xmin, xmax, ymin, ymax = ext
    c, s = abs(math.cos(theta)), abs(math.sin(theta))
    xa = xmax if math.cos(theta) > 0 else -xmin
    ya = ymax if math.sin(theta) > 0 else -ymin
    return ((c / xa) ** p + (s / ya) ** p) ** (-1.0 / p)


def se_path(ext, p, n):
    return [(se_radius(t, ext, p) * math.cos(t), se_radius(t, ext, p) * math.sin(t))
            for t in (TAU * i / n - math.pi for i in range(n))]


def se_y(x, ext, p, side):
    """Y на суперэллипсе при заданном X; side −1 — передняя сторона."""
    xa = ext[1] if x > 0 else -ext[0]
    ya = ext[3] if side > 0 else -ext[2]
    return side * ya * max(0.0, 1.0 - (abs(x) / xa) ** p) ** (1.0 / p)


def normal2(a, b):
    """Нормаль наружу для пути против часовой (справа по ходу)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy) or 1.0
    return dy / L, -dx / L


def wall(P, pts, z0, z1, t, mat=STONE, closed=False, skip=None, ao=None):
    """Стена по ломаной со скосами в углах; skip(x, y) — пропустить пролёт (проём ворот). ao — видимая часть для затенения."""
    n = len(pts)
    normals = []
    for i in range(n):
        p = pts[(i - 1) % n] if closed or i > 0 else pts[i]
        q = pts[(i + 1) % n] if closed or i < n - 1 else pts[i]
        nx, ny = normal2(p, q)
        normals.append((nx, ny))
    outer = [(pts[i][0] + normals[i][0] * t / 2, pts[i][1] + normals[i][1] * t / 2) for i in range(n)]
    inner = [(pts[i][0] - normals[i][0] * t / 2, pts[i][1] - normals[i][1] * t / 2) for i in range(n)]
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        if skip and skip((pts[i][0] + pts[j][0]) / 2, (pts[i][1] + pts[j][1]) / 2):
            continue
        plan = [outer[i], outer[j], inner[j], inner[i]]
        prism(P, plan, plan, z0, z1, mat, rows=max(1, int((z1 - z0) / 28)), ao=ao)
    return outer


def walk(pts, step, closed=False, start=0.0):
    """Точки вдоль ломаной через step: (x, y, нормаль x, нормаль y)."""
    out = []
    seq = pts + pts[:1] if closed else pts
    pos = start
    done = 0.0
    for a, b in zip(seq, seq[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        nx, ny = normal2(a, b)
        while pos <= done + L:
            k = (pos - done) / L
            out.append((a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, nx, ny))
            pos += step
        done += L
    return out


def merlons(P, pts, z, t, h=10, w=10, gap=8, closed=False, offset=0.0, skip=None):
    for x, y, nx, ny in walk(pts, w + gap, closed, 0.0 if closed else w / 2 + 1.0):
        if R.random() < MERLON_LOST:
            continue
        if skip and any(skip(x - ny * q, y + nx * q) for q in (0.0, w * 0.6, -w * 0.6)):     # не свисать в проём
            continue
        box(P, x + nx * offset, y + ny * offset, z, z + h * R.uniform(0.88, 1.06), w, t, math.atan2(ny, nx) + math.pi / 2)


def corbels(P, pts, z, off, closed=False, skip=None, step=9.0, h=7.0):
    """Ряд каменных консолей под поясом парапета."""
    for x, y, nx, ny in walk(pts, step, closed):
        if skip and skip(x, y):
            continue
        box(P, x + nx * (off + 1.5), y + ny * (off + 1.5), z - h, z, 4.0, 3.5, math.atan2(ny, nx) + math.pi / 2, TRIM, top=False)


def band(P, pts, z0, z1, off, mat=TRIM, closed=False, skip=None, off1=None):
    """Полоса по стене: пояс, тень под парапетом; off1 — другой вынос вверху (скос)."""
    off1 = off if off1 is None else off1
    seq = pts + pts[:1] if closed else pts
    for a, b in zip(seq, seq[1:]):
        if skip and skip((a[0] + b[0]) / 2, (a[1] + b[1]) / 2):
            continue
        nx, ny = normal2(a, b)
        P.poly([(a[0] + nx * off, a[1] + ny * off, z0), (b[0] + nx * off, b[1] + ny * off, z0),
                (b[0] + nx * off1, b[1] + ny * off1, z1), (a[0] + nx * off1, a[1] + ny * off1, z1)], mat)


def pier(P, x, y, nx, ny, t, z0, top, w):
    """Ступенчатый контрфорс: три яруса со скошенными слезниками и шатровая верхушка."""
    rot = math.atan2(ny, nx) + math.pi / 2

    def plan(wd, dp):
        c = t / 2 + dp / 2 - 1.0
        return rect(x + nx * c, y + ny * c, wd, dp, rot)
    z1, z2 = z0 + (top - z0) * 0.42, z0 + (top - z0) * 0.80
    stages = [(z0, z1, w * 1.35, 19, w * 1.25, 16), (z1, z1 + 7, w * 1.25, 16, w * 1.05, 11), (z1 + 7, z2, w * 1.05, 11, w * 0.95, 9),
              (z2, z2 + 6, w * 0.95, 9, w * 0.72, 6), (z2 + 6, top + 12, w * 0.72, 6, w * 0.66, 5)]
    for za, zb, wa, da, wb, db in stages:
        prism(P, plan(wa, da), plan(wb, db), za, zb, TRIM, top=False)
    c = t / 2 + 1.5
    ring = P.add([(px, py, top + 12) for px, py in plan(w * 0.66, 5)])
    apex = P.add([(x + nx * c, y + ny * c, top + 12 + w * 1.25)])[0]
    for i in range(4):
        P.face((ring[i], ring[(i + 1) % 4], apex), ROOF)


def ivy_site(x, y, nx, ny, z0, z1, w, kind="ivy", curve=None):
    """Место для плюща; curve (центр x, центр y, радиус): на круглой стене плитки идут по дуге, а не торчат касательной."""
    IVY.append((x, y, nx, ny, z0, z1, w, kind, curve))


def rock_surface(x, y, fallback):
    """Высота готовой скалы под точкой, px: таблица rock_top не знает о швах и уступах. Пока скалы нет — fallback."""
    if not _ROCK_BVH:
        rock = next((q for q in BUILT if q.name == "Rock"), None)
        if rock is None:
            return fallback
        _ROCK_BVH.append(BVHTree.FromPolygons(rock.v, rock.f, all_triangles=False, epsilon=0.0))
    hit = _ROCK_BVH[0].ray_cast(Vector((x, y, fallback + 120.0)), Vector((0.0, 0.0, -1.0)))
    return hit[0].z if hit[0] is not None else fallback


def rubble(P, x, y, z, n, spread, size=7.0):
    """Россыпь камней: у обломков стен и на уступах."""
    for _ in range(n):
        a, d = R.uniform(0, TAU), R.uniform(0, spread) ** 1.0
        sz = R.uniform(0.45, 1.0) * size
        px, py = x + math.cos(a) * d, y + math.sin(a) * d
        if z is None and any(abs(px - cx) < w / 2 and abs(py - cy) < d / 2 for cx, cy, w, d in ((-120, 40, 290, 320), (150, 40, 330, 380))):
            continue
        pz = rock_surface(px, py, rock_top(px, py)) if z is None else z
        box(P, px, py, pz - 5, pz + sz * R.uniform(0.3, 0.7), sz, sz * R.uniform(0.6, 1.1), R.uniform(0, 3.14), STONE)


def arch_points(w, h, n=3):
    """Контур стрельчатой арки от низа слева против часовой (u вправо, v вверх; v=0 — низ)."""
    spring = max(0.0, h - w * 0.87)
    right = []
    for i in range(n + 1):
        a = (math.pi / 3) * i / n
        right.append((-w / 2 + w * math.cos(a), spring + w * math.sin(a) * min(1.0, (h - spring) / (w * 0.87))))
    pts = [(-w / 2, 0.0), (w / 2, 0.0)] + right[:-1] + [(0.0, h)]
    pts += [(-u, v) for u, v in reversed(right[:-1])]
    return pts


def arch_decal(P, x, y, z, nx, ny, w, h, mat=DARK, off=1.5, trim=0.0):
    """Плоская арка на стене: окно или ниша; trim — каменное обрамление за ней."""
    ux, uy = -ny, nx  # вправо для смотрящего снаружи
    if trim:
        pts = arch_points(w + trim * 2, h + trim * 1.5)
        P.poly([(x + nx * off * 0.5 + ux * u, y + ny * off * 0.5 + uy * u, z - trim * 0.5 + v) for u, v in pts], TRIM)
    pts = arch_points(w, h)
    P.poly([(x + nx * off + ux * u, y + ny * off + uy * u, z + v) for u, v in pts], mat)


def arch_ring(P, x, y, z, nx, ny, w, h, band, off=1.0):
    """Каменное обрамление проёма: полоса вокруг арки от пола через вершину к полу, сам проём остаётся открытым."""
    ux, uy = -ny, nx
    inner = arch_points(w, h)
    outer = arch_points(w + band * 2, h + band * 1.5)
    inner = inner[1:] + inner[:1]
    outer = outer[1:] + outer[:1]

    def at(q):
        return (x + nx * off + ux * q[0], y + ny * off + uy * q[0], z + q[1])
    for k in range(len(inner) - 1):
        P.poly([at(outer[k]), at(outer[k + 1]), at(inner[k + 1]), at(inner[k])], TRIM)


def tracery(P, x, y, z, nx, ny, w, h):
    """Большое стрельчатое окно: тёмный проём, обрамление, средники, поперечина и круг переплёта."""
    arch_decal(P, x, y, z, nx, ny, w, h, off=1.5, trim=3.0)
    ux, uy = -ny, nx
    off = 2.3

    def at(u, v):
        return (x + nx * off + ux * u, y + ny * off + uy * u, z + v)

    def bar(u0, v0, u1, v1, wd=0.8):
        dx, dv = u1 - u0, v1 - v0
        L = math.hypot(dx, dv) or 1.0
        pu, pv = -dv / L * wd, dx / L * wd
        P.poly([at(u0 - pu, v0 - pv), at(u1 - pu, v1 - pv), at(u1 + pu, v1 + pv), at(u0 + pu, v0 + pv)], TRIM)
    spring = h * 0.60
    for u in (-w / 6, w / 6):
        bar(u, 0, u, spring)
    bar(-w / 2, spring, w / 2, spring)
    bar(-w / 2, h * 0.36, w / 2, h * 0.36, 0.6)
    cz = spring + (h - spring) * 0.42
    rr = w * 0.24
    seg = 8
    for k in range(seg):
        a0, a1 = TAU * k / seg, TAU * (k + 1) / seg
        bar(rr * math.cos(a0), cz + rr * math.sin(a0), rr * math.cos(a1), cz + rr * math.sin(a1), 0.7)
    bar(-w / 2, spring, -rr * 0.7, cz - rr * 0.7, 0.7)
    bar(w / 2, spring, rr * 0.7, cz - rr * 0.7, 0.7)


def oculus(P, x, y, z, nx, ny, r):
    """Круглое окно с каменным кольцом."""
    ux, uy = -ny, nx
    for rr, off, mat in ((r + 2.0, 1.0, TRIM), (r, 1.5, DARK)):
        P.poly([(x + nx * off + ux * rr * math.cos(TAU * k / 8), y + ny * off + uy * rr * math.cos(TAU * k / 8), z + rr * math.sin(TAU * k / 8))
                for k in range(8)], mat)


def windows_ring(P, x, y, r, z, seg, w, h, phase=0.0, trim=0.0, mat=DARK):
    for i in range(seg):
        a = phase + TAU * i / seg
        arch_decal(P, x + r * math.cos(a), y + r * math.sin(a), z, math.cos(a), math.sin(a), w, h, mat=mat, off=1.0, trim=trim)


def crown(P, x, y, z, r, seg=28, n=None, parapet=10, mh=10):
    """Венец круглой башни: консоли, расширение, парапет, зубцы."""
    cyl(P, x, y, z - 12, z, r * 0.88, r, seg, TRIM, top=False)
    cyl(P, x, y, z, z + parapet, r, None, seg, STONE)
    if DETAIL:
        if r >= 18:
            nc = int(TAU * r / 10)
            for i in range(nc):
                a = TAU * (i + 0.5) / nc
                box(P, x + (r - 1.5) * 0.92 * math.cos(a), y + (r - 1.5) * 0.92 * math.sin(a), z - 16, z - 5, 4.0, 5.5, a + math.pi / 2, TRIM, top=False)
        n = n or max(6, int(TAU * r / 18))
        for i in range(n):
            if R.random() < MERLON_LOST:
                continue
            a = TAU * (i + 0.5) / n
            box(P, x + (r - 3) * math.cos(a), y + (r - 3) * math.sin(a), z + parapet, z + parapet + mh * R.uniform(0.88, 1.05),
                TAU * r / n * 0.56, 7, a + math.pi / 2)


def round_tower(P, x, y, z0, top, r, seg=28, slits=True, foot=None):
    """Круглая башня: скошенное основание от foot, пояс, венец; top — вершина зубцов."""
    z = top - 20
    rb = r * 0.88
    foot = z0 if foot is None else foot
    far = math.hypot(x, y) or 1.0
    z0 = min(z0, rock_top(x + x / far * rb * 1.2, y + y / far * rb * 1.2) - 76)   # низ башни всегда в скале
    if DETAIL:
        cyl(P, x, y, z0, foot, rb * 1.18, None, seg, STONE, top=False)
        cyl(P, x, y, foot, foot + 30, rb * 1.18, rb, seg, STONE, top=False, rows=2, ao=(foot, z))
        cyl(P, x, y, foot + 30, z - 12, rb, None, seg, STONE, top=False, rows=max(1, int((z - foot - 42) / 22)), ao=(foot, z))
        zm = foot + 30 + (z - foot - 42) * 0.55
        cyl(P, x, y, foot + 28, foot + 31, rb + 1.2, None, seg, TRIM, top=False)
        cyl(P, x, y, zm - 1.5, zm + 1.5, rb + 1.0, None, seg, TRIM, top=False)
    else:
        cyl(P, x, y, z0, z - 12, rb, None, seg, STONE, top=False)
    crown(P, x, y, z, r, seg)
    if DETAIL and slits:
        for k in range(max(1, int((z - 12 - foot - 30) / 34))):
            a = k * 2.1 + x * 0.01 - math.pi / 2
            arch_decal(P, x + rb * math.cos(a), y + rb * math.sin(a), z - 44 - k * 34, math.cos(a), math.sin(a), 4, 14, off=1.0, trim=1.4)
        for a in (-1.2 + x * 0.013, 0.9 + y * 0.017):
            if R.random() < 0.8:
                z1 = foot + R.uniform(24, min(80, z - foot))
                ivy_site(x + rb * math.cos(a), y + rb * math.sin(a), math.cos(a), math.sin(a), foot, z1, R.uniform(12, 26), curve=(x, y, rb))
            else:
                ivy_site(x + rb * math.cos(a), y + rb * math.sin(a), math.cos(a), math.sin(a), z - 40, z - 16, 8, "vine", curve=(x, y, rb))
        SPOTS["wall"].append((x + r * 0.6 * math.cos(x), y + r * 0.6 * math.sin(x), z + 10, r * 0.28))


def broken_ring(P, x, y, z0, r_out, r_in, tops, seg, rng, mat=STONE, noise_px=9, course=0.0):
    """Кольцо стены с обломанным верхом: высота — таблица азимута с разбросом, между точками излом косой, а не ступенькой.
    course — высота ряда кладки: излом ложится по рядам, как у разобранной стены."""
    def top_at(deg):
        for (a0, z_a), (a1, z_b) in zip(tops, tops[1:]):
            if a0 <= deg <= a1:
                return z_a + (z_b - z_a) * (deg - a0) / (a1 - a0)
        return tops[-1][1]
    heights = []
    for i in range(seg):
        deg = (360.0 * i / seg + 180.0) % 360.0 - 180.0
        h = top_at(deg) + rng.uniform(-noise_px, noise_px)
        heights.append(round(h / course) * course if course else h)
    P.gid += 1
    gid = P.gid
    for i in range(seg):
        a0, a1 = TAU * i / seg, TAU * (i + 1) / seg
        c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
        h0, h1 = heights[i], heights[(i + 1) % seg]
        o0, o1 = (x + r_out * c0, y + r_out * s0), (x + r_out * c1, y + r_out * s1)
        n0, n1 = (x + r_in * c0, y + r_in * s0), (x + r_in * c1, y + r_in * s1)
        for corners, smooth in (([(*o0, z0), (*o1, z0), (*o1, h1), (*o0, h0)], (x, y, r_out)), ([(*n1, z0), (*n0, z0), (*n0, h0), (*n1, h1)], (x, y, r_in))):
            P.group[len(P.f)] = gid
            P.smooth.add(len(P.f))
            P.cylf[len(P.f)] = smooth
            P.poly(corners, mat)
        P.group[len(P.f)] = gid
        P.poly([(*o0, h0), (*o1, h1), (*n1, h1), (*n0, h0)], mat)
        if DETAIL and rng.random() < 0.3:
            am = (a0 + a1) / 2
            rm = (r_out + r_in) / 2
            SPOTS["wall"].append((x + rm * math.cos(am), y + rm * math.sin(am), (h0 + h1) / 2, (r_out - r_in) * 0.4))
            if rng.random() < 0.3:      # недовыпавший камень в изломе
                box(P, x + rm * math.cos(am), y + rm * math.sin(am), (h0 + h1) / 2 - 6, (h0 + h1) / 2 + rng.uniform(1, 4),
                    (r_out - r_in) * 0.55, (r_out - r_in) * 0.45, am + math.pi / 2 + rng.uniform(-0.2, 0.2), mat)
    cyl(P, x, y, z0 - 4, z0 + 4, r_in + 1, None, 16, ROCK_M)


def jag_wall(P, p0, p1, z0, tops, t, rng, mat=STONE, window=True, zvis=None):
    """Обломок стены: одна плита с неровным косым верхом, без ступенек. zvis — откуда стена видна (низ бывает ниже, в скале)."""
    pos, fine = [0.0], [tops[0] - rng.uniform(4, 14)]
    n_t = len(tops)
    for i, h in enumerate(tops):
        pos += [(i + 0.16 + rng.uniform(-0.05, 0.05)) / n_t, (i + 0.50) / n_t, (i + 0.84 + rng.uniform(-0.05, 0.05)) / n_t]
        fine += [h - rng.uniform(0, 9), h + rng.uniform(-3, 3), h - rng.uniform(0, 12)]
    pos.append(1.0)
    fine.append(tops[-1] - rng.uniform(4, 14))
    n = len(pos) - 1
    L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    nx, ny = normal2(p0, p1)

    def at(k, off):
        q = pos[k] if isinstance(k, int) else (pos[int(k)] + pos[int(k) + 1]) / 2
        return (p0[0] + (p1[0] - p0[0]) * q + nx * off, p0[1] + (p1[1] - p0[1]) * q + ny * off)
    hw = t / 2
    P.gid += 1
    gid = P.gid
    front = [(*at(0, hw), z0), (*at(n, hw), z0)] + [(*at(k, hw), fine[k]) for k in range(n, -1, -1)]
    P.group[len(P.f)] = gid
    P.poly(front, mat)
    back = [(*at(n, -hw), z0), (*at(0, -hw), z0)] + [(*at(k, -hw), fine[k]) for k in range(n + 1)]
    P.group[len(P.f)] = gid
    P.poly(back, mat)
    P.group[len(P.f)] = gid
    P.poly([(*at(0, -hw), z0), (*at(0, hw), z0), (*at(0, hw), fine[0]), (*at(0, -hw), fine[0])], mat)
    P.group[len(P.f)] = gid
    P.poly([(*at(n, hw), z0), (*at(n, -hw), z0), (*at(n, -hw), fine[n]), (*at(n, hw), fine[n])], mat)
    for k in range(n):       # верхний излом
        P.group[len(P.f)] = gid
        P.poly([(*at(k, hw), fine[k]), (*at(k + 1, hw), fine[k + 1]), (*at(k + 1, -hw), fine[k + 1]), (*at(k, -hw), fine[k])], mat)
        if DETAIL and rng.random() < 0.3:
            q = at(k + 0.5, 0)
            SPOTS["wall"].append((q[0], q[1], (fine[k] + fine[k + 1]) / 2, t * 0.3))
    if DETAIL:
        mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
        zv = z0 if zvis is None else zvis
        for sign in (1, -1):
            ivy_site(mx + nx * sign * hw + rng.uniform(-L * 0.3, L * 0.3) * -ny, my + ny * sign * hw + rng.uniform(-L * 0.3, L * 0.3) * nx, nx * sign, ny * sign,
                     zv + 10, zv + 10 + rng.uniform(30, 70), rng.uniform(10, 22))
        if window:
            h = min((min(tops) - zv) * 0.6, 46.0)
            if h > 14:
                for sign in (1, -1):
                    arch_decal(P, mx + nx * sign * hw, my + ny * sign * hw, min(tops) - h - 10, nx * sign, ny * sign, min(L * 0.3, 16.0), h, off=1.0, trim=2.0)


def ruin_wall(P, p0, p1, z0, tops, t, rng, zvis=None):
    """Разрушенная стена со сквозной стрельчатой аркой посередине: на арте через такие проёмы видно небо."""
    L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    zv = z0 if zvis is None else zvis
    arch_h = min((min(tops) - zv) * 0.62, 66.0)
    if L < 34 or len(tops) < 3 or arch_h < 24:
        jag_wall(P, p0, p1, z0, tops, t, rng, zvis=zvis)
        return
    arch_w = min(L * 0.36, arch_h * 0.62)
    k0, k1 = 0.5 - arch_w / L / 2, 0.5 + arch_w / L / 2
    a = (p0[0] + (p1[0] - p0[0]) * k0, p0[1] + (p1[1] - p0[1]) * k0)
    b = (p0[0] + (p1[0] - p0[0]) * k1, p0[1] + (p1[1] - p0[1]) * k1)
    mid = len(tops) // 2
    left, right = tops[:max(2, mid)], tops[-max(2, len(tops) - mid):]
    jag_wall(P, p0, a, z0, left, t, rng, window=False, zvis=zvis)
    jag_wall(P, b, p1, z0, right, t, rng, window=False, zvis=zvis)
    arch_z = min(tops) - arch_h - 8
    arcade(P, a, b, arch_z, [min(left[-1], right[0]) - 4], t, arch_z, arch_h, piers=False)
    if DETAIL:
        nx, ny = normal2(p0, p1)
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        for sign in (1, -1):
            arch_ring(P, mx + nx * sign * t / 2, my + ny * sign * t / 2, arch_z, nx * sign, ny * sign, arch_w, arch_h, 2.5, off=0.6)


def arcade(P, p0, p1, z0, tops, t, arch_z, arch_h, piers=True, top_fn=None):
    """Стена со сквозными стрельчатыми арками без крыши: столбы и перемычки над проёмами. top_fn(u) — верх по длине, если он обломан."""
    n = len(tops)
    dx, dy = (p1[0] - p0[0]), (p1[1] - p0[1])
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    nx, ny = uy, -ux  # наружу — на переднюю сторону
    rot = math.atan2(uy, ux)
    bay = L / n
    pier = bay * 0.26 if piers else 0.0
    w = bay - pier
    for i in range(n + 1 if piers else 0):
        k = i * bay
        top = top_fn(k) - 1.0 if top_fn else tops[min(i, n - 1)]
        box(P, p0[0] + ux * k, p0[1] + uy * k, z0, top, pier, t, rot)
    for i in range(n):
        ctr = (i + 0.5) * bay
        top = tops[i]
        pts = arch_points(w, arch_h, 3)[2:]  # только дуга: от правой пяты через вершину к левой
        pts = pts[::-1]                       # слева направо
        def hgt(u, ctr=ctr, top=top):
            return (top_fn(ctr + u) if top_fn else top) - arch_z
        for side in (1, -1):
            for a, b in zip(pts, pts[1:]):
                if side > 0:
                    q = [(a[0], a[1]), (b[0], b[1]), (b[0], hgt(b[0])), (a[0], hgt(a[0]))]
                else:
                    q = [(b[0], b[1]), (a[0], a[1]), (a[0], hgt(a[0])), (b[0], hgt(b[0]))]
                P.poly([(p0[0] + ux * (ctr + u) + nx * side * t / 2, p0[1] + uy * (ctr + u) + ny * side * t / 2, arch_z + v)
                        for u, v in q], STONE)
        for a, b in zip(pts, pts[1:]):  # нижняя сторона арки
            P.poly([(p0[0] + ux * (ctr + a[0]) + nx * t / 2, p0[1] + uy * (ctr + a[0]) + ny * t / 2, arch_z + a[1]),
                    (p0[0] + ux * (ctr + a[0]) - nx * t / 2, p0[1] + uy * (ctr + a[0]) - ny * t / 2, arch_z + a[1]),
                    (p0[0] + ux * (ctr + b[0]) - nx * t / 2, p0[1] + uy * (ctr + b[0]) - ny * t / 2, arch_z + b[1]),
                    (p0[0] + ux * (ctr + b[0]) + nx * t / 2, p0[1] + uy * (ctr + b[0]) + ny * t / 2, arch_z + b[1])], STONE)
        # верх перемычки
        if top_fn:
            for a, b in zip(pts, pts[1:]):
                za, zb = arch_z + hgt(a[0]), arch_z + hgt(b[0])
                P.poly([(p0[0] + ux * (ctr + a[0]) + nx * t / 2, p0[1] + uy * (ctr + a[0]) + ny * t / 2, za),
                        (p0[0] + ux * (ctr + b[0]) + nx * t / 2, p0[1] + uy * (ctr + b[0]) + ny * t / 2, zb),
                        (p0[0] + ux * (ctr + b[0]) - nx * t / 2, p0[1] + uy * (ctr + b[0]) - ny * t / 2, zb),
                        (p0[0] + ux * (ctr + a[0]) - nx * t / 2, p0[1] + uy * (ctr + a[0]) - ny * t / 2, za)], STONE)
            continue
        a, b = -w / 2, w / 2
        P.poly([(p0[0] + ux * (ctr + a) + nx * t / 2, p0[1] + uy * (ctr + a) + ny * t / 2, top),
                (p0[0] + ux * (ctr + b) + nx * t / 2, p0[1] + uy * (ctr + b) + ny * t / 2, top),
                (p0[0] + ux * (ctr + b) - nx * t / 2, p0[1] + uy * (ctr + b) - ny * t / 2, top),
                (p0[0] + ux * (ctr + a) - nx * t / 2, p0[1] + uy * (ctr + a) - ny * t / 2, top)], STONE)


def pinnacle(P, x, y, z0, tip, r, seg=6):
    """Пинакл: ствол и каменная верхушка. На арте они каменные, а не чёрные шипы."""
    z = z0 + (tip - z0) * 0.62
    cyl(P, x, y, z0, z, r, None, seg, STONE, top=False)
    cone(P, x, y, z, tip, r * 1.2, seg, TRIM)


def turret(P, x, y, r, z0, eave, tip, cap="bell"):
    """Тонкая башенка: консоль снизу, ствол, поясок, окна-щели. Верх: bell — шатёр с раструбом, crown — зубцы без шатра."""
    cyl(P, x, y, z0, eave, r, None, 12, STONE, top=False)
    if not DETAIL:
        cone(P, x, y, eave, tip, r * 1.22, 12)
        return
    cyl(P, x, y, z0 - 7, z0, r * 0.35, r, 12, TRIM, top=False)
    cyl(P, x, y, (z0 + eave) / 2 - 1, (z0 + eave) / 2 + 1, r + 0.8, None, 12, TRIM, top=False)
    for k in range(2):
        a = -math.pi / 2 + k * 2.4 + x * 0.02
        if eave - 32 - k * 34 > z0 + 3:
            arch_decal(P, x + r * math.cos(a), y + r * math.sin(a), eave - 32 - k * 34, math.cos(a), math.sin(a), 4, 13, off=0.8, trim=1.0)
    if cap == "crown":
        crown(P, x, y, eave + 8, r * 1.2, 12, n=max(6, int(r * 0.9)), parapet=4, mh=6)
        return
    cyl(P, x, y, eave - 8, eave, r, r * 1.16, 12, TRIM, top=False)
    flare = eave + (tip - eave) * 0.14
    cyl(P, x, y, eave, flare, r * 1.28, r * 0.86, 12, ROOF, top=False)    # раструб шатра
    cone(P, x, y, flare, tip, r * 0.86, 12)


def wall_strip(P, a, b, zs, cols, ao, mat=STONE):
    """Кусок стены сеткой: a→b по плану против часовой (снаружи справа), zs — высоты строк."""
    P.gid += 1
    for r in range(len(zs) - 1):
        for k in range(cols):
            q0, q1 = k / cols, (k + 1) / cols
            p0 = (a[0] + (b[0] - a[0]) * q0, a[1] + (b[1] - a[1]) * q0)
            p1 = (a[0] + (b[0] - a[0]) * q1, a[1] + (b[1] - a[1]) * q1)
            fi = len(P.f)
            P.group[fi] = P.gid
            P.aorange[fi] = ao
            P.poly([(*p0, zs[r]), (*p1, zs[r]), (*p1, zs[r + 1]), (*p0, zs[r + 1])], mat)


def hall_shell(P, x, y, w, d, z0, eave, ridge, rot, zvis=None):
    """Коробка зала: щипцы на концах, две стены, крутая крыша. Конёк вдоль местной оси v. С zvis стены идут сеткой от zvis вверх."""
    c, s = math.cos(rot), math.sin(rot)

    def T(u, v, z):
        return (x + u * c - v * s, y + u * s + v * c, z)
    hw, hd = w / 2, d / 2
    over = 3
    if zvis is None:
        prof = [(-hw, z0), (hw, z0), (hw, eave), (0, ridge), (-hw, eave)]
        P.poly([T(u, -hd, z) for u, z in prof], STONE)                 # щипец к −v
        P.poly([T(u, hd, z) for u, z in reversed(prof)], STONE)        # щипец к +v
        P.poly([T(hw, -hd, z0), T(hw, hd, z0), T(hw, hd, eave), T(hw, -hd, eave)], STONE)
        P.poly([T(-hw, hd, z0), T(-hw, -hd, z0), T(-hw, -hd, eave), T(-hw, hd, eave)], STONE)
    else:
        step = 22.0
        zvis = max(z0 + 1, min(zvis, eave - 20))
        n = max(1, int((eave - zvis) / step))
        zs = [z0] + [zvis + (eave - zvis) * k / n for k in range(n + 1)]
        ao = (zvis, eave + (ridge - eave) * 0.5)
        pts = {"a": T(-hw, -hd, 0)[:2], "b": T(hw, -hd, 0)[:2], "c": T(hw, hd, 0)[:2], "d": T(-hw, hd, 0)[:2]}
        wall_strip(P, pts["b"], pts["c"], zs, max(1, int(d / step)), ao)
        wall_strip(P, pts["d"], pts["a"], zs, max(1, int(d / step)), ao)
        cols = max(1, int(w / step))
        wall_strip(P, pts["a"], pts["b"], zs, cols, ao)
        wall_strip(P, pts["c"], pts["d"], zs, cols, ao)
        # Щипцы сверху: строки сужаются к коньку.
        rows = max(1, int((ridge - eave) / step))
        for sign, start, end in ((-1, -hw, hw), (1, hw, -hw)):
            P.gid += 1
            for r in range(rows):
                k0, k1 = r / rows, (r + 1) / rows
                z_a, z_b = eave + (ridge - eave) * k0, eave + (ridge - eave) * k1
                for i in range(cols):
                    q0, q1 = i / cols, (i + 1) / cols
                    u00, u01 = (start + (end - start) * q0) * (1 - k0), (start + (end - start) * q1) * (1 - k0)
                    u10, u11 = (start + (end - start) * q0) * (1 - k1), (start + (end - start) * q1) * (1 - k1)
                    fi = len(P.f)
                    P.group[fi] = P.gid
                    P.aorange[fi] = ao
                    if r == rows - 1:     # у конька грань сходится в точку
                        P.poly([T(u00, sign * hd, z_a), T(u01, sign * hd, z_a), T(0.0, sign * hd, ridge)], STONE)
                    else:
                        P.poly([T(u00, sign * hd, z_a), T(u01, sign * hd, z_a), T(u11, sign * hd, z_b), T(u10, sign * hd, z_b)], STONE)
    P.poly([T(hw + over, -hd, eave - 3), T(hw + over, hd, eave - 3), T(0, hd, ridge), T(0, -hd, ridge)], ROOF)
    P.poly([T(-hw - over, hd, eave - 3), T(-hw - over, -hd, eave - 3), T(0, -hd, ridge), T(0, hd, ridge)], ROOF)
    return T


def coping(P, T, u0, z0, u1, z1, v, wd=5.0, h=4.0, crockets=False):
    """Каменный бортик по скату щипца, с пучками-краббами на больших залах."""
    if u0 > u1:
        u0, z0, u1, z1 = u1, z1, u0, z0
    sign = 1.0 if v > 0 else -1.0
    vf, vb = v + sign * 1.5, v - sign * wd
    front = [T(u0, vf, z0), T(u1, vf, z1), T(u1, vf, z1 + h), T(u0, vf, z0 + h)]
    top = [T(u0, vf, z0 + h), T(u1, vf, z1 + h), T(u1, vb, z1 + h), T(u0, vb, z0 + h)]
    P.poly(front if sign < 0 else front[::-1], TRIM)
    P.poly(top if sign < 0 else top[::-1], TRIM)
    if crockets:
        L = math.hypot(u1 - u0, z1 - z0)
        for k in range(1, int(L / 15)):
            q = k / int(L / 15)
            px, py, pz = T(u0 + (u1 - u0) * q, v, z0 + (z1 - z0) * q + h)
            cone(P, px, py, pz, pz + 6, 2.0, 3, TRIM)


def strut(P, a, b, wd=4.0, th=5.0):
    """Наклонная подпора (аркбутан): a — верх у стены, b — низ у опоры."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    L = math.hypot(dx, dy) or 1.0
    sx, sy = -dy / L * wd / 2, dx / L * wd / 2
    ar, br = (a[0] - sx, a[1] - sy), (b[0] - sx, b[1] - sy)
    al, bl = (a[0] + sx, a[1] + sy), (b[0] + sx, b[1] + sy)
    P.poly([(*ar, a[2]), (*br, b[2]), (*bl, b[2]), (*al, a[2])], TRIM)
    P.poly([(*ar, a[2] - th), (*br, b[2] - th), (*br, b[2]), (*ar, a[2])], TRIM)
    P.poly([(*bl, b[2] - th), (*al, a[2] - th), (*al, a[2]), (*bl, b[2])], TRIM)


def hall_style(x, y, w, d):
    """Тип зала по месту: запад разрушен сильнее, большие окна — только у главных, остальное вперемешку."""
    if (x, y) in FOCAL_HALLS:
        return "tracery"
    rr = random.Random(int(x * 11) * 31 + int(y * 17) + SEED)
    west = x < -222 or (x < -150 and y > 150)
    if west and rr.random() < 0.6:
        return "ruin"
    k = rr.random()
    if w >= 60 and k < 0.12:
        return "tracery"
    return "lancet" if k < 0.48 else ("tiered" if k < 0.82 else "blind")


def hall_ruin(P, T, x, y, w, d, z0, zvis, eave, ridge, rng):
    """Разрушенный зал: стены с обломанным верхом, крыши нет, в щипце сквозная арка, внутри и снаружи камни."""
    hw, hd = w / 2, d / 2
    corners = [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)]
    pts = [T(u, v, 0)[:2] for u, v in corners]
    fall = rng.uniform(-1, 1)        # с какой стороны щипец обвалился
    t = 8.0

    def gable(q):
        prof = eave + (ridge - eave) * (1.0 - abs(2 * q - 1))
        return zvis + (prof - zvis) * max(0.42, min(1.0, 0.86 + fall * (q - 0.5) + rng.uniform(-0.12, 0.12)))
    side = lambda: zvis + (eave - zvis) * rng.uniform(0.58, 1.0)
    front = [gable(i / 4) for i in range(5)]
    back = [gable(i / 3) * 0.92 + zvis * 0.08 for i in range(4)]
    ruin_wall(P, pts[0], pts[1], z0, front, t, rng, zvis=zvis)
    jag_wall(P, pts[1], pts[2], z0, [side() for _ in range(max(3, int(d / 18)))], t, rng, zvis=zvis)
    jag_wall(P, pts[2], pts[3], z0, back, t, rng, zvis=zvis)
    jag_wall(P, pts[3], pts[0], z0, [side() for _ in range(max(3, int(d / 18)))], t, rng, zvis=zvis)
    if DETAIL:
        rubble(P, x, y, None, 8, min(hw, hd) * 0.8, 8.0)
        # Рёбра контрфорсов остаются стоять по углам.
        for (u, v) in corners:
            px, py, _ = T(u * 1.04, v * 1.04, 0)
            prism(P, rect(px, py, 9, 9), rect(px, py, 6, 6), z0, zvis + (eave - zvis) * rng.uniform(0.55, 1.05), STONE)


def gable_face(P, T, sign, hd, s, c, w, eave, ridge, zvis, style, rng):
    """Фасад щипца: окна по типу зала. Всегда пояса; большие чёрные окна — только у типа tracery."""
    ox, oy, _ = T(0, sign * hd, 0)
    nx, ny = -s * sign, c * sign
    H = eave - zvis

    def at(u):
        return T(u, sign * hd, 0)[:2]

    def strip(z, h=3.0):
        q0, q1 = T(-w / 2, sign * (hd + 1.5), z), T(w / 2, sign * (hd + 1.5), z)
        q2, q3 = T(w / 2, sign * (hd + 1.5), z + h), T(-w / 2, sign * (hd + 1.5), z + h)
        P.poly([q0, q1, q2, q3] if sign < 0 else [q3, q2, q1, q0], TRIM)
    strip(eave - 2)
    if style == "tracery":
        ww, hh = min(w * 0.34, 28.0), min(H * 0.62, 88.0) * rng.uniform(0.82, 1.0)
        tracery(P, ox, oy, eave - hh * 0.84, nx, ny, ww, hh)
        if ridge - eave > 30:
            oculus(P, ox, oy, eave + (ridge - eave) * 0.34, nx, ny, min(w * 0.1, 8.0))
        for u in (-w * 0.34, w * 0.34):
            px, py = at(u)
            arch_decal(P, px, py, eave - hh * 0.62, nx, ny, 6, 22, off=1.2, trim=1.4)
        strip(eave - hh * 0.84 - 7)
    elif style == "lancet":
        hh = min(H * 0.46, 46.0) * rng.uniform(0.8, 1.0)
        ww = min(w * 0.13, 8.0)
        for u, k in ((-w * 0.22, 0.76), (0.0, 1.0), (w * 0.22, 0.76)):
            px, py = at(u)
            arch_decal(P, px, py, eave - hh - 6, nx, ny, ww, hh * k, off=1.2, trim=1.6)
        strip(eave - hh - 13)
        if ridge - eave > 26:
            oculus(P, ox, oy, eave + (ridge - eave) * 0.3, nx, ny, min(w * 0.08, 5.5))
        if H > 90:
            for u in (-w * 0.25, 0.0, w * 0.25):
                px, py = at(u)
                arch_decal(P, px, py, eave - hh - 42, nx, ny, 5, 15, off=1.0, trim=1.0)
    elif style == "tiered":
        rows = 2 if H < 96 else 3
        cols = 3 if w > 46 else 2
        for r_ in range(rows):
            z = eave - 26 - r_ * 34
            for k in range(cols):
                px, py = at((k - (cols - 1) / 2) * w / (cols + 0.6))
                arch_decal(P, px, py, z, nx, ny, 6, 17, off=1.1, trim=1.2)
            strip(z - 6, 2.0)
        if ridge - eave > 24:
            arch_decal(P, ox, oy, eave + 4, nx, ny, 5, 14, off=1.1, trim=1.0)
    else:   # blind: глухие арки и одна щель
        cols = 3 if w > 44 else 2
        for k in range(cols):
            px, py = at((k - (cols - 1) / 2) * w / (cols + 0.2))
            arch_decal(P, px, py, eave - 64, nx, ny, w / (cols + 1.2), 52, mat=RECESS, off=1.0, trim=2.0)
        arch_decal(P, ox, oy, eave - 40, nx, ny, 4, 18, off=1.6)
        strip(eave - 70)
    # Нижний этаж: дверь или низкие арки там, где стена видна.
    if H > 110:
        px, py = at(rng.uniform(-w * 0.2, w * 0.2))
        arch_decal(P, px, py, zvis + 4, nx, ny, 12, 26, mat=RECESS, off=1.0, trim=2.0)


def aisle(P, T, sign, hw, hd, z0, high, aw, rng):
    """Пристройка-неф вдоль стены зала: односкатная крыша, глухая стена, окна. Ступенчатый объём вместо ровной коробки."""
    low = high - aw * 0.8
    hh = hd * rng.uniform(0.7, 0.95)
    u_in, u_out = sign * hw, sign * (hw + aw)
    if sign > 0:
        faces = [([T(u_out, -hh, z0), T(u_out, hh, z0), T(u_out, hh, low), T(u_out, -hh, low)], STONE),
                 ([T(u_out, -hh, low - 2), T(u_out, hh, low - 2), T(u_in, hh, high), T(u_in, -hh, high)], ROOF),
                 ([T(u_in, -hh, z0), T(u_out, -hh, z0), T(u_out, -hh, low), T(u_in, -hh, high)], STONE),
                 ([T(u_out, hh, z0), T(u_in, hh, z0), T(u_in, hh, high), T(u_out, hh, low)], STONE)]
    else:
        faces = [([T(u_out, hh, z0), T(u_out, -hh, z0), T(u_out, -hh, low), T(u_out, hh, low)], STONE),
                 ([T(u_out, hh, low - 2), T(u_out, -hh, low - 2), T(u_in, -hh, high), T(u_in, hh, high)], ROOF),
                 ([T(u_out, -hh, z0), T(u_in, -hh, z0), T(u_in, -hh, high), T(u_out, -hh, low)], STONE),
                 ([T(u_in, hh, z0), T(u_out, hh, z0), T(u_out, hh, low), T(u_in, hh, high)], STONE)]
    for pts, mat in faces:
        P.poly(pts, mat)
    return u_out, hh, low


def hall(P, x, y, w, d, z0, eave, ridge, rot_deg, rng):
    """Готический зал; тип (lancet, tiered, tracery, blind, ruin) меняет фасады и силуэт. Коробка — hall_shell."""
    rot = math.radians(rot_deg)
    c, s = math.cos(rot), math.sin(rot)
    ridge = limit_tip(x, y, ridge + rng.uniform(-14, 10))
    eave = min(eave + rng.uniform(-12, 8), ridge - w * 0.5)
    zvis = z0 + 14
    z0 = min(z0, ground_under(x, y, w, d, rot) - 4)      # стены доходят до скалы: снизу зал не висит
    style = hall_style(x, y, w, d)
    HALL_ACTUAL[(x, y)] = (z0, eave, ridge, style)
    first = len(P.f)
    hw, hd = w / 2, d / 2
    if style == "ruin":
        c_, s_ = c, s
        T = lambda u, v, z: (x + u * c_ - v * s_, y + u * s_ + v * c_, z)
        hall_ruin(P, T, x, y, w, d, z0, zvis, eave, ridge, rng)
        P.darken(first, rng.uniform(0.8, 1.0))
        return
    T = hall_shell(P, x, y, w, d, z0, eave, ridge, rot, zvis=zvis)
    if not DETAIL:
        return
    focal = style == "tracery"
    # Контрфорсы по углам щипцов: в арте именно они дают вертикальный ритм.
    for sign in (-1, 1):
        for u in (-hw, hw):
            px, py, _ = T(u * 0.98, sign * (hd + 1.5), 0)
            top = eave + rng.uniform(2, 12)
            prism(P, rect(px, py, 8.5, 8.5, rot), rect(px, py, 6, 6, rot), z0, top, TRIM, top=False)
            ring = P.add([(qx, qy, top) for qx, qy in rect(px, py, 6.8, 6.8, rot)])
            apex = P.add([(px, py, limit_tip(px, py, top + rng.uniform(6, 15)))])[0]
            for i in range(4):
                P.face((ring[i], ring[(i + 1) % 4], apex), TRIM)
    for sign in (-1, 1):
        coping(P, T, -hw - 2, eave - 2, 0, ridge, sign * hd, crockets=focal)
        coping(P, T, 0, ridge, hw + 2, eave - 2, sign * hd, crockets=focal)
        gable_face(P, T, sign, hd, s, c, w, eave, ridge, zvis, style, rng)
        if rng.random() < 0.5:
            nx, ny = -s * sign, c * sign
            px, py, _ = T(rng.uniform(-hw * 0.7, hw * 0.7), sign * hd, 0)
            ivy_site(px, py, nx, ny, zvis, zvis + rng.uniform(30, 90), rng.uniform(10, 22))
    # Боковые стены: окна по типу, лопатки между пролётами.
    bays = max(1, int(d / 26))
    for sign in (-1, 1):
        nx, ny = c * sign, s * sign
        for k in range(bays):
            v = -hd + (k + 0.5) * d / bays
            px, py, _ = T(sign * hw, v, 0)
            if style == "tiered":
                arch_decal(P, px, py, eave - 28, nx, ny, 5, 15, off=1.2, trim=1.1)
                if eave - zvis > 70:
                    arch_decal(P, px, py, eave - 62, nx, ny, 5, 15, off=1.2, trim=1.1)
            elif style == "blind":
                arch_decal(P, px, py, eave - 54, nx, ny, d / bays * 0.62, 42, mat=RECESS, off=1.0, trim=1.8)
            else:
                arch_decal(P, px, py, eave - 36, nx, ny, 6, 22, off=1.2, trim=1.4)
                if eave - zvis > 90:
                    arch_decal(P, px, py, eave - 72, nx, ny, 5, 14, off=1.2)
        for k in range(bays + 1):
            v = -hd + k * d / bays
            px, py, _ = T(sign * (hw + 1.5), v, 0)
            prism(P, rect(px, py, 6, 6, rot), rect(px, py, 4.5, 4.5, rot), z0, eave + 2, TRIM)
        # Пояс под карнизом с консолями: на арте он есть почти у всех зданий.
        a, b = T(sign * hw, -hd * sign, 0)[:2], T(sign * hw, hd * sign, 0)[:2]
        if sign > 0:
            band(P, [a, b], eave - 8, eave - 2, 1.4, TRIM)
            corbels(P, [a, b], eave - 8, 0.2, step=9.0, h=5.0)
        else:
            band(P, [a, b], eave - 8, eave - 2, 1.4, TRIM)
            corbels(P, [a, b], eave - 8, 0.2, step=9.0, h=5.0)
    # Неф с одной или двух сторон, опоры-подпоры у самых больших.
    if d >= 54 and w >= 40 and rng.random() < 0.45:
        for sign in ((-1, 1) if rng.random() < 0.3 else (rng.choice((-1, 1)),)):
            aw = rng.uniform(12, 20)
            high = eave - rng.uniform(22, 48)
            zb = min(z0, ground_under(*T(sign * (hw + aw / 2), 0, 0)[:2], aw, d, rot) - 4)
            u_out, hh, low = aisle(P, T, sign, hw, hd, zb, high, aw, rng)
            nx, ny = c * sign, s * sign
            n = max(1, int(hh * 2 / 24))
            for k in range(n):
                px, py, _ = T(u_out, -hh + (k + 0.5) * 2 * hh / n, 0)
                arch_decal(P, px, py, low - 26, nx, ny, 5, 16, off=1.1, trim=1.2)
    if focal and d >= 70:
        for sign in (-1, 1):
            for k in range(1, bays, 2):
                v = -hd + k * d / bays
                px, py, _ = T(sign * (hw + 2), v, 0)
                qx, qy, _ = T(sign * (hw + 20), v, 0)
                base = stand_z(qx, qy, eave - 60)
                if eave - 60 - base < 26:     # внешняя опора только там, где ей есть на что встать
                    strut(P, (px, py, eave - 8), (qx, qy, eave - 42))
                    pinnacle(P, qx, qy, base, limit_tip(qx, qy, eave - 18), 3.2)
    # Слуховые окна на длинных крышах: не у всех.
    if d >= 70 and rng.random() < 0.55:
        for sign in (-1, 1):
            for k in range(int(d / 50)):
                v = -hd + (k + 0.75) * d / int(d / 50)
                u = sign * hw * 0.55
                rz = eave + (ridge - eave) * (1 - abs(u) / hw)
                px, py, _ = T(u + sign * 2, v, 0)
                dw = min(13.0, d / 6)
                hall_shell(P, px, py, dw, hw * 0.75, rz - 12, rz + 5, rz + 5 + dw * 0.55, rot + math.pi / 2 * sign)
                fx, fy, _ = T(u + sign * (hw * 0.375 + 2), v, 0)
                arch_decal(P, fx, fy, rz - 5, c * sign, s * sign, 4, 8, off=0.8)
    # Угловые башенки: разные, и не на каждом углу.
    for u, v in ((-hw, -hd), (hw, -hd), (-hw, hd), (hw, hd)):
        px, py, _ = T(u, v, 0)
        q = rng.random()
        tip = limit_tip(px, py, eave + rng.uniform(26, 56))
        if q < 0.22 and tip > eave + 16:
            turret(P, px, py, rng.uniform(5.5, 8.0), eave - rng.uniform(30, 50), eave + rng.uniform(2, 12), tip, "crown" if rng.random() < 0.35 else "bell")
        elif q < 0.42:
            pinnacle(P, px, py, eave - 24, limit_tip(px, py, eave + rng.uniform(8, 20)), 3.0)
    if focal or rng.random() < 0.4:
        for sign in (-1, 1):
            px, py, _ = T(0, sign * hd, 0)
            tip = limit_tip(px, py, ridge + 12)
            if tip > ridge - 2:
                pinnacle(P, px, py, ridge - 10, tip, 2.4)
    # Здания немного разного тона, дальние темнее: так читается глубина.
    k = rng.uniform(0.76, 1.08) * (0.90 if y > 40 else 1.0)
    for i in range(first, len(P.f)):
        P.dim[i] = P.dim.get(i, 1.0) * k


def tower_house(P, x, y, w, d, z0, z1):
    """Квадратная башня-дом: зубцы или шатёр, пояса, окна рядами, иногда угловая башенка. Разбивают гребёнку щипцов."""
    rr = random.Random(int(x * 13) + int(y * 7) * 19 + SEED)
    z1 = min(z1, envelope(x, y) - 12)
    zvis = z0 + 10
    plan = rect(x, y, w, d)
    z0 = min(z0, ground_under(x, y, w, d, 0.0) - 4)
    first = len(P.f)
    grid = dense_rect(x, y, w, d)
    prism(P, grid, grid, z0, z1, STONE, rows=max(2, int((z1 - z0) / 24)), ao=(zvis, z1))
    if not DETAIL:
        return
    cap_roof = rr.random() < 0.3
    band(P, plan, z1 - 10, z1, 2.0, TRIM, closed=True)
    band(P, plan, z1 - 16, z1 - 10, 0.8, RECESS, closed=True)
    corbels(P, plan, z1 - 10, 0.5, closed=True, step=8.0, h=6.0)
    if cap_roof:
        ring = P.add([(px, py, z1) for px, py in rect(x, y, w + 2, d + 2)])
        apex = P.add([(x, y, limit_tip(x, y, z1 + min(w, d) * 0.9))])[0]
        for i in range(4):
            P.face((ring[i], ring[(i + 1) % 4], apex), ROOF)
    else:
        merlons(P, plan, z1, 5, h=8, w=8, gap=6, closed=True, offset=-1.5)
    rows = max(1, min(4, int((z1 - zvis) / 46)))
    for r_ in range(rows):
        band(P, plan, z1 - 22 - r_ * 46 - 28, z1 - 22 - r_ * 46 - 26, 1.0, TRIM, closed=True)
    seq = plan + plan[:1]
    for a, b in zip(seq, seq[1:]):
        nx, ny = normal2(a, b)
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        cols = 2 if L > 30 else 1
        for r_ in range(rows):
            for k in range(cols):
                q = (k + 0.5) / cols
                px, py = a[0] + (b[0] - a[0]) * q, a[1] + (b[1] - a[1]) * q
                arch_decal(P, px, py, z1 - 44 - r_ * 46, nx, ny, 5 if r_ else 6, 17 if r_ else 22, off=1.0, trim=1.2)
        if R.random() < 0.5:
            mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            ivy_site(mx, my, nx, ny, zvis, zvis + R.uniform(40, 90), R.uniform(10, 20))
    if rr.random() < 0.4:
        cx, cy = rr.choice(plan)
        turret(P, cx, cy, rr.uniform(5.5, 7.5), z1 - rr.uniform(34, 56), z1 + rr.uniform(4, 16), limit_tip(cx, cy, z1 + rr.uniform(30, 52)), "crown" if rr.random() < 0.3 else "bell")
    SPOTS["wall"].append((x, y, z1, min(w, d) * 0.3))
    k = rr.uniform(0.84, 1.04) * (0.92 if y > 40 else 1.0)
    for i in range(first, len(P.f)):
        P.dim[i] = P.dim.get(i, 1.0) * k


# Верхние контуры исходников: мелочь не должна выступать за них.
PROFILE = {}
_profile_path = os.path.join(PROJECT, "Tools", "blender", "castle_profiles.json")
if os.path.exists(_profile_path):
    with open(_profile_path, encoding="utf-8") as _f:
        PROFILE = json.load(_f)


def envelope(x, y):
    """Наибольшая z, не выходящая за верхний контур ни на одном виде."""
    if not PROFILE:
        return 1e9
    best = 1e9
    for view, px in (("front", 750 + x), ("back", 750 - x), ("right", 750 + y)):
        k = int(px // 10)
        if 0 <= k < 150:
            best = min(best, 1190 - PROFILE[view][k])
    return best


def limit_tip(x, y, tip):
    return min(tip, envelope(x, y) - 2)


def rock_top(x, y):
    """Высота поверхности скалы над точкой плана (по таблицам сечений), px."""
    r = math.hypot(x, y)
    th = math.atan2(y, x)
    lo, hi = float(ROCK_BASE), float(ROCK[-1][0])
    if r <= rock_radius(th, hi):
        lo = hi
    else:
        for _ in range(14):
            mid = (lo + hi) / 2
            if r <= rock_radius(th, mid):
                lo = mid
            else:
                hi = mid
    best = lo
    for cx, cy, tbl, _, _ in CRAGS:
        d = math.hypot(x - cx, y - cy)
        if d <= tbl[0][1]:
            a, b = tbl[0][0], tbl[-1][0]
            for _ in range(12):
                mid = (a + b) / 2
                if d <= interp(tbl, mid)[0]:
                    a = mid
                else:
                    b = mid
            best = max(best, a)
    return best


def ground_under(x, y, w, d, rot):
    """Самая низкая высота скалы под прямоугольным основанием: до неё должны доходить стены."""
    c, s_ = math.cos(rot), math.sin(rot)
    pts = [(x + u * c - v * s_, y + u * s_ + v * c) for u, v in ((-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2), (0, 0))]
    return min(rock_top(px, py) for px, py in pts)


def upper_solids():
    """Сплошные объёмы верхнего яруса: на них могут стоять мелкие детали. (вид, x, y, ш или r, глубина, низ, верх)."""
    out = [("circle", DONJON["x"], DONJON["y"], 90, 0, 540, 1000), ("circle", BROKEN["x"], BROKEN["y"], 70, 0, 540, 900),
           ("circle", ROUND["x"], ROUND["y"], 41, 0, 600, 735),
           ("rect", -120, 40, 290, 320, 500, 625), ("rect", 150, 40, 330, 380, 500, 625)]
    for x, y, w, d, z0, eave, ridge, rot in all_halls():
        hw, hd = (w, d) if rot == 0 else (d, w)
        out.append(("rect", x, y, hw, hd, z0 - 80, ridge))
    for x, y, w, d, z0, z1 in TOWER_HOUSES:
        out.append(("rect", x, y, w, d, z0 - 60, z1))
    return out


def stand_z(x, y, z):
    """Высота, на которую реально опирается деталь с низом z в этой точке: она сама, если под ней скала или здание."""
    top = rock_top(x, y)
    if z <= top + 2:
        return z
    best = top - 3
    for kind, a, b, c, d_, z0, z1 in upper_solids():
        inside = math.hypot(x - a, y - b) <= c if kind == "circle" else (abs(x - a) <= c / 2 and abs(y - b) <= d_ / 2)
        if inside:
            if z0 - 2 <= z <= z1 + 2:
                return z
            if z1 < z:
                best = max(best, z1 - 3)
    return best


# ---------------------------------------------------------------- ЧАСТИ ЗАМКА ---------------------------------------
def interp(table, z):
    if z <= table[0][0]:
        return table[0][1:]
    for a, b in zip(table, table[1:]):
        if z <= b[0]:
            k = (z - a[0]) / (b[0] - a[0])
            return tuple(p + (q - p) * k for p, q in zip(a[1:], b[1:]))
    return table[-1][1:]


def rock_radius(theta, z):
    r = se_radius(theta, interp(ROCK, z), ROCK_P)
    dx, dy = math.cos(theta), math.sin(theta)
    for cx, cy, tbl in LOBES:
        if z < tbl[0][0] - 1e-6 and tbl[0][0] > 0 or z > tbl[-1][0]:
            continue
        rl = interp(tbl, z)[0]
        dc = dx * cx + dy * cy
        disc = rl * rl - (cx * cx + cy * cy) + dc * dc
        if disc > 0 and dc > 0:
            r = max(r, dc + math.sqrt(disc))
    return r


def gate_landing():
    """Центр лица верхних ворот и нормаль наружу."""
    G = GATE
    (ax, ay), (bx, by) = G["t1"], G["t2"]
    nx, ny = normal2((ax, ay), (bx, by))
    return (ax + bx) / 2 - nx * G["recess"], (ay + by) / 2 - ny * G["recess"], nx, ny


def stair_points():
    """Узлы лестницы в 3D: первый — край площадки перед верхними воротами, глубина остальных — по поверхности скалы."""
    mx, my, nx, ny = gate_landing()
    out = [(mx + nx * STAIRS["landing"], my + ny * STAIRS["landing"], GATE["arch_z"])]
    for x, z in STAIRS["nodes"]:
        out.append((x, se_y(x, interp(ROCK, z), ROCK_P, -1) - STAIRS["out"], z))
    return out


def dist_seg(p, a, b):
    ab = [b[i] - a[i] for i in range(3)]
    ap = [p[i] - a[i] for i in range(3)]
    k = max(0.0, min(1.0, sum(u * v for u, v in zip(ab, ap)) / (sum(u * u for u in ab) or 1.0)))
    return math.sqrt(sum((ap[i] - ab[i] * k) ** 2 for i in range(3)))


def smooth01(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _h01(p, a, b, c, k):
    h = math.sin(p[0] * a + p[1] * b + p[2] * c) * k
    return h - math.floor(h)


def rock_zone(z, q):
    """Высота q в той же полосе скалы, что и z: ступень не перескакивает через уступы под стенами."""
    for a, b in ((ROCK_BASE, 165.0), (180.0, 345.0), (362.0, float(ROCK[-1][0]))):
        if a <= z <= b:
            return max(a, min(b, q))
    return z


def rock_cell(x0, y0, z, c, s_, radius_at):
    """Смещение поверхности. Колонны Вороного: у каждой своя плоская грань, между ними острое ребро и тёмный шов.
    Ступени: стенка стоит отвесно на среднем радиусе своей ступени, потом короткий уступ назад. Шаг у каждой колонны свой:
    так скала идёт вертикальными блоками, отступающими вверх, а не наклонным скатом. radius_at(z) — радиус по таблице."""
    pos = Vector((x0 / 56.0, y0 / 56.0, z / 460.0))
    d, pts = noise.voronoi(pos, distance_metric='DISTANCE', exponent=2.5)
    p0 = pts[0]
    h0, h1, h2 = _h01(p0, 12.9898, 78.233, 37.719, 43758.5453), _h01(p0, 93.989, 67.345, 11.135, 24634.6345), _h01(p0, 41.2, 29.7, 57.9, 14357.1)
    du = (-s_ * (pos.x - p0.x) + c * (pos.y - p0.y)) * 56.0
    big = (h0 - 0.5) * 20.0 + (h1 - 0.5) * 0.50 * du
    seam = max(0.0, 1.0 - (d[1] - d[0]) / 0.14)

    pos2 = Vector((x0 / 24.0, y0 / 24.0, z / 110.0))
    d2, pts2 = noise.voronoi(pos2, distance_metric='DISTANCE', exponent=2.5)
    p1 = pts2[0]
    g0, g1, g2 = _h01(p1, 39.346, 11.135, 83.155, 24634.6345), _h01(p1, 7.13, 91.7, 23.1, 9135.3), _h01(p1, 61.9, 17.3, 47.7, 31283.1)
    du2 = (-s_ * (pos2.x - p1.x) + c * (pos2.y - p1.y)) * 24.0
    dz2 = (pos2.z - p1.z) * 110.0
    small = (g0 - 0.5) * 8.0 + (g1 - 0.5) * 0.60 * du2 + (g2 - 0.45) * 0.16 * dz2
    seam2 = max(0.0, 1.0 - (d2[1] - d2[0]) / 0.18)

    period = 60.0 + h0 * 70.0
    phase = h1 * 3.7
    u = z / period + phase
    k = math.floor(u)
    fr = u - k
    ledge = smooth01(0.84, 0.98, fr)
    z_mid = rock_zone(z, (k + 0.5 - phase) * period)
    z_next = rock_zone(z, (k + 1.5 - phase) * period)
    here = radius_at(z)
    terrace = radius_at(z_mid) * (1.0 - ledge) + radius_at(z_next) * ledge - here

    fine = noise.fractal(Vector((x0 / 17.0, y0 / 17.0, z / 44.0)), 1.0, 2.0, 2)
    low = noise.noise(Vector((x0 / 190.0, y0 / 190.0, z / 300.0)))
    disp = big + small + terrace + fine * 2.0 + low * 7.0 - seam * seam * 16.0 - seam2 * seam2 * 5.0
    patch = noise.noise(Vector((x0 / 46.0, y0 / 46.0, z / 34.0))) * 0.5 + 0.5
    speck = noise.noise(Vector((x0 / 14.0, y0 / 14.0, z / 11.0))) * 0.5 + 0.5
    return disp, 0.72 + 0.40 * h0 + (g0 - 0.5) * 0.20, patch, speck


def wall_cap(z):
    """Наибольший вынос скалы на высоте z: у стен она держится за контуром, чтобы не прорасти сквозь кладку. Переходы плавные."""
    for z0, z1, a, b in ((150, 170, 20.0, 2.0), (170, 235, 2.0, 2.0), (235, 272, 2.0, 20.0), (335, 350, 20.0, 2.0), (350, 420, 2.0, 2.0), (420, 452, 2.0, 20.0)):
        if z0 <= z < z1:
            return a + (b - a) * (z - z0) / (z1 - z0)
    return 20.0


def wall_floor(z):
    """Наибольшая глубина шва у подошв стен: скала не должна уходить из-под них."""
    for z0, z1, a, b in ((60, 130, -60.0, -8.0), (130, 176, -8.0, -8.0), (250, 326, -60.0, -10.0), (326, 356, -10.0, -10.0)):
        if z0 <= z < z1:
            return a + (b - a) * (z - z0) / (z1 - z0)
    return -60.0


def rock_colors(R, Z, tone, patch, speck):
    """Цвет по готовой поверхности (массивы строка × сектор): впадины темнее, рёбра светлее, мох на уступах и в щелях, пятнами."""
    def blur(A, ri, rj):
        out = A.copy()
        for _ in range(ri):
            out = (out + np.roll(out, 1, axis=1) + np.roll(out, -1, axis=1)) / 3.0
        for _ in range(rj):
            up = np.vstack([out[:1], out[:-1]])
            dn = np.vstack([out[1:], out[-1:]])
            out = (out + up + dn) / 3.0
        return out
    wide = blur(R, 7, 3)
    near = blur(R, 1, 1)
    conc = wide - R              # > 0 — впадина относительно окрестности
    edge = R - near              # > 0 — ребро
    dr = np.gradient(R, axis=0)
    dz = np.maximum(np.gradient(Z, axis=0), 0.5)
    slope = -dr / dz             # > 0 — поверхность смотрит вверх
    t = np.clip((slope - 0.45) / 0.8, 0.0, 1.0)
    up = t * t * (3 - 2 * t)
    t = np.clip((conc - 2.0) / 8.0, 0.0, 1.0)
    crevice = t * t * (3 - 2 * t)
    t = np.clip((patch - 0.46) / 0.16, 0.0, 1.0)
    blot = t * t * (3 - 2 * t)
    t = np.clip((speck - 0.42) / 0.22, 0.0, 1.0)
    grain = t * t * (3 - 2 * t)
    moss = np.clip(up * (0.62 + 0.38 * grain) + crevice * (0.30 + 0.55 * grain) + blot * (0.30 + 0.66 * grain), 0.0, 1.0)
    shade = np.clip(0.86 - conc * 0.056, 0.14, 1.08) * (1.0 + np.clip(edge, 0.0, 4.0) * 0.10) * tone
    shade = np.clip(shade, 0.0, 1.0)
    rgb = np.empty(R.shape + (4,), dtype=np.float32)
    for k in range(3):
        rgb[..., k] = np.clip(shade * ((1.0 - moss) + MOSS_TINT[k] * moss), 0.0, 1.0)
    rgb[..., 3] = 1.0
    return [tuple(q) for q in rgb.reshape(-1, 4).tolist()]


def stair_profile():
    """Марши лестницы сверху вниз: группы ступеней и площадки между ними. Элемент: (a, b, длина, [(вид, s0, z0, s1, z1, ступеней)])."""
    nodes = stair_points()
    out = []
    for a, b in zip(nodes, nodes[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        rise = a[2] - b[2]
        n = max(1, int(round(rise / STAIRS["step"])))
        tread = min(STAIRS["tread"], L / n)
        spare = L - n * tread
        land = min(int(spare / STAIRS["land_min"]), max(0, n - 1))
        land_len = spare / land if land else 0.0
        if not land:
            tread = L / n
        per = n / (land + 1)
        dz = rise / n
        pos, z = 0.0, a[2]
        pieces = []
        for g in range(land + 1):
            count = int(round((g + 1) * per)) - int(round(g * per))
            s0, z0 = pos, z
            pos += count * tread
            z -= count * dz
            pieces.append(("steps", s0, z0, pos, z, count))
            if g < land:
                pieces.append(("land", pos, z, pos + land_len, z, 0))
                pos += land_len
        out.append((a, b, L, pieces))
    return out


def stair_shelf(seg):
    """След лестницы по секторам сетки: (высота, радиус) точек по всей ширине с бортами и на площадках поворотов.
    Марш идёт под углом к радиусу, его края попадают в другие секторы, чем середина. Под следом скала подпирает, над ним отступает."""
    out = {}
    half = STAIRS["w"] / 2 + 7.0

    def put(x, y, z):
        idx = int(round((math.atan2(y, x) + math.pi) / TAU * seg)) % seg
        r = math.hypot(x, y)
        for di in (-1, 0, 1):
            out.setdefault((idx + di) % seg, []).append((z, r))
    across = (-1.0, -0.5, 0.0, 0.5, 1.0)
    for a, b, L, pieces in stair_profile():
        ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        for kind, s0, z0, s1, z1, _n in pieces:
            n = max(1, int((s1 - s0) / 4.0))
            for k in range(n + 1):
                q = k / n
                ss = s0 + (s1 - s0) * q
                x, y = a[0] + ux * ss, a[1] + uy * ss
                for o in across:
                    put(x - uy * half * o, y + ux * half * o, z0 + (z1 - z0) * q)
    h = (STAIRS["w"] + 10) / 2
    for x, y, z in stair_points()[1:-1]:
        for u in across:
            for v in across:
                put(x + u * h, y + v * h, z)
    return out


def rock_grid(P, xyz, rows, seg, closed_top=True, bottom=False):
    base = P.add(xyz)
    for j in range(rows - 1):
        for i in range(seg):
            P.face((base[j * seg + i], base[j * seg + (i + 1) % seg], base[(j + 1) * seg + (i + 1) % seg], base[(j + 1) * seg + i]), ROCK_M)
    if closed_top:
        P.face([base[(rows - 1) * seg + i] for i in range(seg)], ROCK_M)
    if bottom:
        P.face([base[i] for i in reversed(range(seg))], ROCK_M)


def build_scree(P):
    """Осыпь у подножия: камни разной величины на плато вокруг скалы, в обход площадки у моста. Стоит на земле мира,
    поэтому отдельный объект: на видах сверки с артом земли нет, там он скрыт (place)."""
    origin = site_origin()
    colors = []
    placed = 0
    for _ in range(SCREE_COUNT * 3):
        if placed >= SCREE_COUNT:
            break
        th = R.uniform(-math.pi, math.pi)
        z = float(STAIRS["nodes"][-1][1])
        rr = rock_radius(th, z) + R.uniform(-2, 8) + R.random() ** 2 * 34
        x, y = rr * math.cos(th), rr * math.sin(th)
        wx, wy = origin[0] + x * S, origin[1] + y * S
        if not (-520.0 < wx < -330.0 and wy > 468.0):     # на мысу, не в воде
            continue
        if abs(x - STAIRS["nodes"][-1][0]) < 70 and y < 0:     # перед лестницей и у моста проход свободен
            continue
        size = R.random() ** 2.2 * 20 + 4
        n = 6
        plan = [(math.cos(TAU * i / n + R.uniform(-0.3, 0.3)) * size * R.uniform(0.7, 1.15), math.sin(TAU * i / n + R.uniform(-0.3, 0.3)) * size * R.uniform(0.6, 1.1)) for i in range(n)]
        h = size * R.uniform(0.45, 0.85)
        rows = []
        tone = R.uniform(0.5, 0.92)
        for zz, q, k in ((z - 6, 1.0, 0.5), (z + h * 0.45, 0.92, 0.8), (z + h, 0.48, 1.0)):
            ids = []
            for u, v in plan:
                ids.append(P.add([(x + u * q + R.uniform(-1, 1), y + v * q + R.uniform(-1, 1), zz + (R.uniform(-1.5, 1.5) if k > 0.6 else 0.0))])[0])
                colors.append((tone * k, tone * k, tone * k, 1.0))
            rows.append(ids)
        for a, b in zip(rows, rows[1:]):
            for i in range(n):
                P.face((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]), ROCK_M)
        P.face(rows[-1], ROCK_M)
        placed += 1
    # Юбка: скала стоит на плато, но на западе мыс спускается к воде (земля до 2 м). Без неё низ скалы висел бы.
    seg = 140
    levels = ((-64, 18.0), (-40, 12.0), (-18, 6.0), (0, 2.0), (6, -6.0))
    verts = []
    for z, off in levels:
        for i in range(seg):
            th = TAU * i / seg - math.pi
            r = rock_radius(th, 0.0)
            c, s_ = math.cos(th), math.sin(th)
            n = noise.noise(Vector((r * c / 40.0, r * s_ / 40.0, z / 30.0))) if z < 0 else 0.0
            verts.append(((r + off + n * 9.0) * c, (r + off + n * 9.0) * s_, z))
            tone = 0.55 + noise.noise(Vector((r * c / 25.0, r * s_ / 25.0, z / 20.0))) * 0.2
            colors.append((tone, tone, tone, 1.0))
    rock_grid(P, verts, len(levels), seg, closed_top=False)
    P.col = colors


def build_rock(P):
    """Скала: плотная полярная сетка. Сначала смещение rock_cell, потом сглаживание на шаг (иначе рёбра — зубцы сетки),
    потом выемки лестницы и ворот, цвет — по готовой поверхности."""
    top_z = ROCK[-1][0]
    rows = sorted(set([ROCK_BASE + (top_z - ROCK_BASE) * i / (ROCK_ROWS - 1) for i in range(ROCK_ROWS)]
                      + [t[0] for t in ROCK if t[0] >= ROCK_BASE]))
    seg = ROCK_SEGMENTS
    shelves = stair_shelf(seg) if DETAIL else {}
    mx, my, gnx, gny = gate_landing()
    gtx, gty = -gny, gnx
    G = GATE
    nr = len(rows)
    RR = np.zeros((nr, seg))
    ZZ = np.zeros((nr, seg))
    TN = np.zeros((nr, seg))
    PA = np.zeros((nr, seg))
    SP = np.zeros((nr, seg))
    for j, z in enumerate(rows):
        for i in range(seg):
            th = TAU * i / seg - math.pi
            r = rock_radius(th, z)
            c, s_ = math.cos(th), math.sin(th)
            x0, y0 = r * c, r * s_
            disp, tone, patch, speck = rock_cell(x0, y0, z, c, s_, lambda q, th=th: rock_radius(th, q))
            disp = 0.0 if z <= ROCK_BASE else max(wall_floor(z), min(disp, wall_cap(z)))
            RR[j, i] = max(1.0, r + disp)
            ZZ[j, i] = z + (noise.noise(Vector((x0 / 45.0, y0 / 45.0, z / 45.0))) * 2.0 if 2.0 < z < rows[-1] - 2 else 0.0)
            TN[j, i], PA[j, i], SP[j, i] = tone, patch, speck
    # Сглаживание на один шаг: иначе ребро колонны идёт по сетке квадратными зубцами.
    def soften(A, keep):
        soft = (A + np.roll(A, 1, axis=1) + np.roll(A, -1, axis=1)) / 3.0
        up = np.vstack([soft[:1], soft[:-1]])
        dn = np.vstack([soft[1:], soft[-1:]])
        return A * keep + (soft + up + dn) / 3.0 * (1.0 - keep)
    RR = soften(RR, 0.65)
    # Под подошвой башни нижней стены скала доходит до её наружного края: ствол не торчит столбом.
    for x, side, _top, r in RING_TOWERS:
        ty = se_y(x, RING["ext"], RING["p"], side)
        dist, a0 = math.hypot(x, ty), math.atan2(ty, x)
        d = r + 6.0
        ha = math.asin(min(0.99, d / dist))
        for i in range(int(round((a0 - ha + math.pi) / TAU * seg)), int(round((a0 + ha + math.pi) / TAU * seg)) + 1):
            a = TAU * i / seg - math.pi - a0
            disc = d * d - (dist * math.sin(a)) ** 2
            if disc <= 0.0:
                continue
            outer = dist * math.cos(a) + math.sqrt(disc)
            for j, z in enumerate(rows):
                if 60.0 < z < 162.0 and RR[j, i % seg] < outer:
                    RR[j, i % seg] += (outer - RR[j, i % seg]) * smooth01(60.0, 110.0, z)
    # Выемка лестницы: переход «подпора → выемка» лежит ниже проступи, в толще ступени. Края сглажены, запас 4 px покрывает сглаживание.
    delta = np.zeros_like(RR)
    for i, entries in shelves.items():
        for j in range(nr):
            rz0 = RR[j, i]
            zz = ZZ[j, i]
            filled = rz0
            for zs, rp in entries:          # сначала подпора снизу: скала выходит под самый дальний край следа
                dz = zz - zs
                if -90.0 < dz <= -12.0:
                    k = 1.0 if dz > -30.0 else (dz + 90.0) / 60.0
                    filled = max(filled, rz0 + (rp + 4.0 - rz0) * k)
            rz = filled
            for zs, rp in entries:          # потом выемка сверху: она важнее, ступени не должны быть засыпаны
                dz = zz - zs
                if -12.0 < dz < 40.0:
                    k = 1.0 if dz < 14.0 else 1.0 - (dz - 14.0) / 26.0
                    rz = min(rz, filled + (rp - 4.0 - filled) * k)
            delta[j, i] = rz - rz0
    RR = RR + soften(delta, 0.4)
    verts = []
    for j, z in enumerate(rows):
        for i in range(seg):
            th = TAU * i / seg - math.pi
            c, s_ = math.cos(th), math.sin(th)
            rz, zz = RR[j, i], ZZ[j, i]
            # Выемка у верхних ворот: скала не заходит в арку.
            if G["arch_z"] - 26 < zz < G["arch_z"] + G["arch_h"] + 46:
                px, py = rz * c, rz * s_
                front = gnx * (px - mx) + gny * (py - my)
                side = gtx * (px - mx) + gty * (py - my)
                if front > -6.0 and abs(side) < 96.0:
                    denom = gnx * c + gny * s_
                    if denom > 0.05:
                        rz = (gnx * mx + gny * my - 6.0) / denom
            RR[j, i] = rz
            verts.append((rz * c, rz * s_, zz))
    rock_grid(P, verts, nr, seg, bottom=True)
    colors = rock_colors(RR, ZZ, TN, PA, SP)
    for cx, cy, tbl, cseg, crows in CRAGS:
        zs = [tbl[0][0] + (tbl[-1][0] - tbl[0][0]) * i / (crows - 1) for i in range(crows)]
        cverts = []
        RR = np.zeros((crows, cseg))
        ZZ = np.zeros((crows, cseg))
        TN = np.zeros((crows, cseg))
        PA = np.zeros((crows, cseg))
        SP = np.zeros((crows, cseg))
        for j, z in enumerate(zs):
            r = interp(tbl, z)[0]
            for i in range(cseg):
                th = TAU * i / cseg
                c, s_ = math.cos(th), math.sin(th)
                x0, y0 = cx + r * c, cy + r * s_
                disp, tone, patch, speck = rock_cell(x0, y0, z, c, s_, lambda q: interp(tbl, q)[0])
                disp = max(-14.0 if z > 440 else -26.0, min(disp, 2.0 if z < 240 else 14.0)) * min(1.0, r / 50.0)   # у нижней стены не выходит за контур, под башней без провалов
                RR[j, i] = r + disp
                if cx < 0 and z > 456 and c > 0.05:
                    RR[j, i] = min(RR[j, i], (SPUR_CLEAR_X - cx) / c)
                ZZ[j, i], TN[j, i], PA[j, i], SP[j, i] = z, tone, patch + (0.05 if cx < 0 else 0.0), speck
        soft = (RR + np.roll(RR, 1, axis=1) + np.roll(RR, -1, axis=1)) / 3.0
        RR = RR * 0.5 + soft * 0.5
        for j, z in enumerate(zs):
            for i in range(cseg):
                th = TAU * i / cseg
                cverts.append((cx + RR[j, i] * math.cos(th), cy + RR[j, i] * math.sin(th), z))
        rock_grid(P, cverts, crows, cseg)
        colors += rock_colors(RR, ZZ, TN, PA, SP)
    P.col = colors


def on_walkway(x, y, z):
    """Точка (px) на лестнице или площадках: там Рэй идёт по чистому камню, растений нет."""
    stair = stair_points()
    margin = STAIRS["w"] / 2 + 8
    if any(dist_seg((x, y, z), a, b) < margin for a, b in zip(stair, stair[1:])):
        return True
    mx, my, nx, ny = gate_landing()
    L = STAIRS["landing"]
    if z > GATE["arch_z"] - 40 and math.hypot(x - (mx + nx * L / 2), y - (my + ny * L / 2)) < L * 0.5 + 58:
        return True
    fx, fy, fz = stair[-1]
    fw, fd = STAIRS["foot"]
    return abs(x - fx) < fw / 2 + 8 and abs(y - (fy - fd * 0.28)) < fd / 2 + 8 and z < fz + 20


def build_ivy(P):
    """Плющ и лианы: плоские грани с вырезом по атласу, чуть над кладкой. Плитка без камня под всеми углами не ставится."""
    verts, polys = [], []
    for part in BUILT:
        base = len(verts)
        verts.extend(Vector(v) for v in part.v)
        polys.extend([base + i for i in f] for f in part.f)
    bvh = BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=0.0)
    limit = 0.34 / S
    colors = []
    dropped = 0
    for x, y, nx, ny, z0, z1, w, kind, curve in IVY:
        tx, ty, tw, th_ = ATLAS["vine" if kind == "vine" else ("ivy_thin" if R.random() < 0.72 else "ivy")]
        cell_w = tw / 40.0 / S       # размер плитки в px модели при 40 px/м
        cell_h = th_ / 40.0 / S
        if kind == "vine":
            cols, rows = 1, max(1, int((z1 - z0) / cell_h + 0.5))
        else:
            cols, rows = max(1, int(w / cell_w + 0.5)), max(1, int((z1 - z0) / cell_h + 0.5))
        tone = R.uniform(0.62, 1.0)
        tint = (tone * 0.46, tone * 0.40, tone * 0.95, 1.0)     # листва атласа → холодная тёмная зелень палитры меню
        for r_ in range(rows):
            for c_ in range(cols):
                off = R.uniform(1.0, 1.7)
                u = (c_ - cols / 2 + 0.5) * cell_w + R.uniform(-2, 2)
                zb = z0 + r_ * cell_h + R.uniform(-2, 2)
                hw = cell_w / 2
                if curve:           # по дуге: плитка лежит на стене, а не торчит касательной
                    ccx, ccy, rr = curve
                    a = math.atan2(y - ccy, x - ccx) + u / rr
                    da = hw / rr
                    quad = [(ccx + (rr + off) * math.cos(a + q), ccy + (rr + off) * math.sin(a + q)) for q in (-da, da)]
                else:
                    ux, uy = -ny, nx
                    bx, by = x + nx * off + ux * u, y + ny * off + uy * u
                    quad = [(bx - ux * hw, by - uy * hw), (bx + ux * hw, by + uy * hw)]
                corners = [(*quad[0], zb), (*quad[1], zb), (*quad[1], zb + cell_h), (*quad[0], zb + cell_h)]
                if any(bvh.find_nearest(Vector(q))[3] > limit for q in corners):
                    dropped += 1
                    continue
                ids = P.add(corners)
                colors += [tint] * 4
                fi = len(P.f)
                P.face(ids, FOLIAGE)
                u0, u1 = tx / ATLAS_SIZE, (tx + tw) / ATLAS_SIZE
                if R.random() < 0.5:
                    u0, u1 = u1, u0
                v0, v1 = 1.0 - (ty + th_) / ATLAS_SIZE, 1.0 - ty / ATLAS_SIZE
                P.fuv[fi] = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    P.col = colors
    return dropped


def wall_detail(P, pts, z1, t, closed, buttress=None, niche=None, skip=None, foot=None):
    """Зубцы, пояс на консолях, тень машикулей, контрфорсы, ниши, скос у подошвы, плющ. foot — где стена выходит из скалы."""
    if not DETAIL:
        return
    skip = skip or (lambda x, y: False)
    merlons(P, pts, z1, 6, closed=closed, offset=t / 2 - 3, skip=skip)
    band(P, pts, z1 - 12, z1, t / 2 + 2.5, TRIM, closed, skip)
    band(P, pts, z1 - 19, z1 - 12, t / 2 + 1.0, RECESS, closed, skip)
    corbels(P, pts, z1 - 12, t / 2, closed, skip)
    if foot is not None:
        band(P, pts, foot, foot + 26, t / 2 + 7, STONE, closed, skip, off1=t / 2 + 0.2)
        band(P, pts, foot + 25, foot + 28, t / 2 + 1.0, TRIM, closed, skip)
    if buttress:
        step, z0, top, w = buttress
        for x, y, nx, ny in walk(pts, step, closed, step / 2):
            if skip(x, y):
                continue
            # Низ контрфорса — ниже поверхности скалы у его внешнего края: снизу он не обрывается в воздухе.
            qx, qy = x + nx * (t / 2 + 10), y + ny * (t / 2 + 10)
            pier(P, x, y, nx, ny, t, max(z0 - 40, min(z0, rock_surface(qx, qy, rock_top(qx, qy)) - 6)), top, w)
    if niche:
        step, z, w, h = niche
        for x, y, nx, ny in walk(pts, step, closed, step):
            if skip(x, y):
                continue
            if w > 10:  # глубокая каменная ниша со щелью-окном
                arch_decal(P, x + nx * t / 2, y + ny * t / 2, z, nx, ny, w, h, mat=RECESS, off=1.2, trim=3.0)
                arch_decal(P, x + nx * t / 2, y + ny * t / 2, z + h * 0.3, nx, ny, 4.5, h * 0.42, off=1.8)
            else:
                arch_decal(P, x + nx * t / 2, y + ny * t / 2, z, nx, ny, w, h, off=1.2, trim=1.2)
    base = z1 - 70 if foot is None else foot
    for x, y, nx, ny in walk(pts, 19, closed, 7):
        if skip(x, y):
            continue
        q = R.random()
        if q < 0.13:
            ivy_site(x + nx * t / 2, y + ny * t / 2, nx, ny, base + 2, base + R.uniform(24, min(95, z1 - base - 8)), R.uniform(14, 40))
        elif q < 0.42:
            ivy_site(x + nx * t / 2, y + ny * t / 2, nx, ny, z1 - 22 - R.uniform(10, 42), z1 - 20, 8, "vine")
        if R.random() < 0.10:
            SPOTS["wall"].append((x, y, z1, t * 0.4))


def gate_front(P, a, b, z0, top, arch_z, arch_w, arch_h, t):
    """Лицо ворот с настоящим сквозным проёмом: столбы, перемычка, откосы арки; за ним — тёмная глубина."""
    L = math.hypot(b[0] - a[0], b[1] - a[1])
    mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    w_side = (L - arch_w) / 2
    for sign in (-1, 1):  # столбы по сторонам проёма
        cx = mx + ux * sign * (arch_w + w_side) / 2
        cy = my + uy * sign * (arch_w + w_side) / 2
        box(P, cx, cy, z0, top, w_side, t, math.atan2(uy, ux))
    arcade(P, (mx - ux * arch_w / 2, my - uy * arch_w / 2), (mx + ux * arch_w / 2, my + uy * arch_w / 2), arch_z, [top], t,
           arch_z, arch_h, piers=False)


def portcullis(P, x, y, nx, ny, z, w, h):
    """Опущенная решётка: стальные прутья перед тёмным проёмом, ячейка около 0,5 м."""
    ux, uy = -ny, nx
    for k in range(-5, 6):
        u = k * w / 11.0
        rise = h * (1.0 - (abs(u) / (w / 2)) ** 2 * 0.42)
        box(P, x + ux * u, y + uy * u, z, z + rise, 1.3, 1.3, math.atan2(uy, ux), ROOF)
    for v in range(1, int(h * 0.62 / (h / 9.0))):
        vz = z + v * h / 9.0
        box(P, x, y, vz, vz + 1.3, w * 0.98, 1.0, math.atan2(uy, ux), ROOF)


def stair_crossing():
    """Где лестница пересекает нижнюю стену: точка, высота, нормаль наружу."""
    nodes = stair_points()
    ext, p = RING["ext"], RING["p"]
    best = None
    for (ax, ay, az), (bx, by, bz) in zip(nodes, nodes[1:]):
        for i in range(61):
            k = i / 60
            x, y = ax + (bx - ax) * k, ay + (by - ay) * k
            d = abs(math.hypot(x, y) - se_radius(math.atan2(y, x), ext, p))
            if best is None or d < best[0]:
                best = (d, x, y, az + (bz - az) * k)
    _, x, y, z = best
    a = math.atan2(y, x)
    return x, y, z, math.cos(a), math.sin(a)


def build_ring(P):
    ext, p = RING["ext"], RING["p"]
    pts = se_path(ext, p, RING["n"])

    def in_gap(x, y):
        return y < 0 and RING_GAP[0] < x < RING_GAP[1]
    wall(P, pts, RING["z0"], RING["z1"], RING["t"], closed=True, skip=in_gap, ao=(162, RING["z1"]))
    wall_detail(P, pts, RING["z1"], RING["t"], True, buttress=(92, 150, RING["z1"] - 4, 12), niche=(46, 192, 4, 16), skip=in_gap, foot=164)
    stair = stair_points()
    for x, side, top, r in RING_TOWERS:
        y = se_y(x, ext, p, side)
        z0 = RING["z0"] - 20
        for a, b in zip(stair, stair[1:]):
            for i in range(41):
                k = i / 40
                sx, sy, sz = a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k
                if math.hypot(sx - x, sy - y) < r + STAIRS["w"] / 2 + 6:
                    z0 = 100
        round_tower(P, x, y, z0, top, r, foot=160)


def build_curtain(P):
    ext, p = CURTAIN["ext"], CURTAIN["p"]
    pts = se_path(ext, p, CURTAIN["n"])
    wall(P, pts, CURTAIN["z0"], CURTAIN["z1"], CURTAIN["t"], closed=True, ao=(340, CURTAIN["z1"]))
    wall_detail(P, pts, CURTAIN["z1"], CURTAIN["t"], True, buttress=(BUTTRESS_STEP, 335, CURTAIN["z1"], 14),
                niche=(BUTTRESS_STEP, 372, 26, 50), skip=lambda x, y: abs(x - 290) < 130 and y < 0, foot=340)
    if DETAIL:
        band(P, pts, 430, 433, CURTAIN["t"] / 2 + 1.0, TRIM, True, lambda x, y: abs(x - 290) < 130 and y < 0)
    for x, side, top, r in CURTAIN_TOWERS:
        round_tower(P, x, se_y(x, ext, p, side), 340, top, r, foot=350)


def build_gate(P):
    G = GATE
    (ax, ay), (bx, by) = G["t1"], G["t2"]
    nx, ny = normal2((ax, ay), (bx, by))
    back = G["recess"]
    fx, fy = -nx * back, -ny * back  # передняя плоскость блока отступает от оси башен
    plan = [(ax + fx, ay + fy), (bx + fx, by + fy), (bx - nx * G["depth"], by - ny * G["depth"]), (ax - nx * G["depth"], ay - ny * G["depth"])]
    start = len(P.f)
    prism(P, plan, plan, G["z0"], G["wall_top"], STONE)
    P.darken(start, 0.74)
    round_tower(P, ax, ay, G["z0"] - 40, G["top1"], G["r"], seg=20, foot=G["z0"] + 6)
    round_tower(P, bx, by, G["z0"] - 40, G["top2"], G["r"], seg=20, foot=G["z0"] + 6)
    # Лицо ворот выдвинуто вперёд от блока: в арке видна настоящая глубина.
    t = G["porch"]
    ox, oy = nx * t / 2, ny * t / 2
    start = len(P.f)
    gate_front(P, (ax + fx + ox, ay + fy + oy), (bx + fx + ox, by + fy + oy), G["z0"], G["wall_top"], G["arch_z"], G["arch_w"], G["arch_h"], t)
    P.darken(start, 0.82)
    if not DETAIL:
        return
    merlons(P, [(ax + fx, ay + fy), (bx + fx, by + fy)], G["wall_top"], 6)
    mx, my = (ax + bx) / 2 + fx, (ay + by) / 2 + fy
    arch_decal(P, mx, my, G["arch_z"], nx, ny, G["arch_w"] + 2, G["arch_h"] + 2, off=0.5)
    arch_ring(P, mx + nx * t, my + ny * t, G["arch_z"], nx, ny, G["arch_w"], G["arch_h"], 6.0, off=1.2)
    portcullis(P, mx, my, nx, ny, G["arch_z"], G["arch_w"] - 2, G["arch_h"] - 2)
    ux, uy = -ny, nx
    for sign in (-1, 1):  # выцветшие знамёна: перекладина, три складки, косицы
        bx_, by_ = mx + ux * sign * 52 + nx * (t + 1.5), my + uy * sign * 52 + ny * (t + 1.5)
        box(P, bx_ - nx * 0.5, by_ - ny * 0.5, 464, 466, 26, 2.4, math.atan2(uy, ux), TRIM)
        for k in range(3):
            u0, u1 = -9 + k * 6, -3 + k * 6
            off0 = 1.0 + (k % 2) * 1.4
            bot = 402 if k == 1 else 392
            q0 = (bx_ + ux * u0 + nx * off0, by_ + uy * u0 + ny * off0)
            q1 = (bx_ + ux * u1 + nx * off0, by_ + uy * u1 + ny * off0)
            P.poly([(*q0, bot), (*q1, bot), (*q1, 464), (*q0, 464)], CLOTH)
    # Пояс на консолях под зубцами, тень машикулей, ниша с тёмной щелью над аркой.
    face = [(ax + fx, ay + fy), (bx + fx, by + fy)]
    band(P, face, G["wall_top"] - 14, G["wall_top"], t + 3, TRIM)
    band(P, face, G["wall_top"] - 22, G["wall_top"] - 14, t + 1.2, RECESS)
    corbels(P, face, G["wall_top"] - 14, t + 0.5)
    ivy_site(mx + ux * -52 + nx * (t + 1), my + uy * -52 + ny * (t + 1), nx, ny, G["z0"] + 16, G["z0"] + 72, 18)
    ivy_site(mx + ux * 44 + nx * (t + 1), my + uy * 44 + ny * (t + 1), nx, ny, G["wall_top"] - 58, G["wall_top"] - 20, 8, "vine")


def slope_wall(P, a, b, za, zb, h, depth, t):
    """Наклонная стенка вдоль марша, путь a→b против часовой (снаружи справа): обе стороны, верх и торцы."""
    nx, ny = normal2(a, b)
    ao, bo = (a[0] + nx * t / 2, a[1] + ny * t / 2), (b[0] + nx * t / 2, b[1] + ny * t / 2)
    ai, bi = (a[0] - nx * t / 2, a[1] - ny * t / 2), (b[0] - nx * t / 2, b[1] - ny * t / 2)
    a0, b0, a1, b1 = max(0.0, za - depth), max(0.0, zb - depth), za + h, zb + h
    P.gid += 1
    for pts, mat in (([(*ao, a0), (*bo, b0), (*bo, b1), (*ao, a1)], STONE), ([(*bi, b0), (*ai, a0), (*ai, a1), (*bi, b1)], STONE),
                     ([(*ao, a1), (*bo, b1), (*bi, b1), (*ai, a1)], TRIM), ([(*ai, a0), (*ao, a0), (*ao, a1), (*ai, a1)], STONE),
                     ([(*bo, b0), (*bi, b0), (*bi, b1), (*bo, b1)], STONE)):
        P.group[len(P.f)] = P.gid
        P.poly(pts, mat)


def build_stairs(P):
    """Ступени группами с площадками между ними, марши врезаны в скалу. Парапет низкий, снаружи по профилю ступеней, изнутри бортик."""
    w = STAIRS["w"]
    for a, b, L, pieces in stair_profile():
        ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        rot = math.atan2(uy, ux) + math.pi / 2
        nx, ny = math.cos(rot), math.sin(rot)
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        if nx * mx + ny * my < 0:      # наружу, от оси замка
            nx, ny = -nx, -ny

        def at(ss, off=0.0):
            return (a[0] + ux * ss + nx * off, a[1] + uy * ss + ny * off)
        for kind, s0, z0, s1, z1, n in pieces:
            if kind == "steps":
                t = (s1 - s0) / max(1, n)
                dz = (z0 - z1) / max(1, n)
                for i in range(n):
                    x, y = at(s0 + (i + 0.5) * t)
                    z = z0 - (i + 1) * dz
                    plan = rect(x, y, w, t + 0.6, rot)
                    start = len(P.f)
                    prism(P, plan, plan, max(0.0, z - 16), max(1.0, z), TRIM, top_mat=FLOOR)
                    q = at(s0 + (i + 0.5) * t, w / 2 + 2.5)
                    border = rect(q[0], q[1], 5.0, t + 0.6, rot)
                    prism(P, border, border, max(0.0, z - 14), z + 4.0, TRIM)
                    P.darken(start, R.uniform(0.78, 0.98))
                    if R.random() < 0.55:
                        side = R.choice((-1, 1))
                        q = at(s0 + (i + 0.5) * t, side * (w / 2 + R.uniform(0, 5)))
                        SPOTS["stair"].append((q[0], q[1], z + 0.5, 4.0))
            else:
                x, y = at((s0 + s1) / 2)
                plan = rect(x, y, w, s1 - s0 + 0.6, rot)
                start = len(P.f)
                prism(P, plan, plan, max(0.0, z0 - 16), max(1.0, z0), TRIM, top_mat=FLOOR)
                P.darken(start, R.uniform(0.62, 0.8))
            # Стенки по профилю. Снаружи подпорная кладка: марш не висит над выемкой нижнего, сверху на ней борт ступенями
            # (на площадках — низкий парапет). Изнутри бортик у скалы; у самой верхней площадки он начинается позже, иначе торчит на ней.
            for off, h, depth, th_ in ((w / 2 + 2.5, 4.0 if kind == "land" else -1.0, 70.0, 5.0), (-(w / 2 + 2.0), 3.0, 10.0, 4.0)):
                start_s, za = s0, z0
                if off < 0 and s0 == 0.0 and a == stair_points()[0]:
                    start_s = s0 + 12.0
                    za = z0 + (z1 - z0) * 12.0 / (s1 - s0)
                q0, q1 = at(start_s, off), at(s1, off)
                zb = z1
                tx, ty = normal2(q0, q1)
                face = (nx, ny) if off > 0 else (-nx, -ny)
                if tx * face[0] + ty * face[1] < 0:
                    q0, q1, za, zb = q1, q0, zb, za
                slope_wall(P, q0, q1, za, zb, h, depth, th_)
            if kind == "land" and DETAIL:
                q = at(s0, w / 2 + 2.5)
                box(P, q[0], q[1], z0, z0 + 11, 6.5, 6.5, rot, TRIM)
    nodes = stair_points()
    for x, y, z in nodes[1:-1]:  # площадки на поворотах
        plan = rect(x, y, w + 10, w + 10)
        prism(P, plan, plan, max(0.0, z - 48), z + 0.5, TRIM, top_mat=FLOOR)
    # Площадка у подножия: сюда приходит мост. Уходит в землю, без высокой стенки.
    x, y, z = nodes[-1]
    fw, fd = STAIRS["foot"]
    plan = rect(x, y - fd * 0.28, fw, fd)
    prism(P, plan, plan, max(0.0, z - 44), z + 0.6, TRIM, top_mat=FLOOR)
    if DETAIL:   # столбы у начала лестницы
        for sign in (-1, 1):
            px, py = x + sign * (w / 2 + 9), y + 2
            prism(P, rect(px, py, 11, 11), rect(px, py, 9, 9), z - 6, z + 17, STONE, top=False)
            prism(P, rect(px, py, 11.5, 11.5), rect(px, py, 12.5, 12.5), z + 17, z + 20, TRIM)
            ivy_site(px, py - 5, 0.0, -1.0, z + 1, z + 15, 10)
        rubble(P, x + 34, y + 6, z, 6, 12, 7.0)
        rubble(P, x - 34, y + 6, z, 6, 12, 7.0)
    # Площадка перед верхними воротами: на неё прибывает Рэй из этажа 1 (7 м ≈ 58 px от лица ворот). Снизу — кладка до скалы.
    mx, my, nx, ny = gate_landing()
    L = STAIRS["landing"]
    cx, cy = mx + nx * L / 2, my + ny * L / 2
    rot = math.atan2(ny, nx) + math.pi / 2
    prism(P, rect(cx, cy, 104, L, rot), rect(cx, cy, 92, L, rot), GATE["arch_z"] - 62, GATE["arch_z"], TRIM, top_mat=FLOOR)
    if DETAIL:
        ux, uy = -ny, nx
        for sign in (-1, 1):
            q0 = (mx + ux * sign * 43, my + uy * sign * 43)
            q1 = (q0[0] + nx * L, q0[1] + ny * L)
            a0, a1 = (q1, q0) if sign > 0 else (q0, q1)
            slope_wall(P, a0, a1, GATE["arch_z"], GATE["arch_z"], 9.0, 2.0, 5.0)


def build_spur(P, rng):
    Q = SPUR
    x, y, r, foot, z1 = Q["x"], Q["y"], Q["r"], Q["foot"], Q["z1"]
    ao = (foot, z1)
    cyl(P, x, y, Q["z0"], foot, r + 9, None, 28, STONE, top=False)                       # юбка уходит в скалу
    cyl(P, x, y, foot, foot + 20, r + 9, r, 28, STONE, top=False, rows=2, ao=ao)
    cyl(P, x, y, foot + 20, z1, r, r - 2, 28, STONE, top=False, rows=5, ao=ao)
    cyl(P, x, y, foot + 19, foot + 22, r + 1.4, None, 28, TRIM, top=False)
    cyl(P, x, y, z1 - 6, z1 + 4, r - 2, r + 2, 28, TRIM, top=False)
    broken_ring(P, x, y, z1, Q["ring_out"], Q["ring_in"], Q["tops"], 64, rng, noise_px=4, course=4.0)
    if DETAIL:
        for a in (-math.pi / 2 - 0.85, -math.pi / 2 + 0.85, -math.pi / 2, math.pi / 2 - 0.7, math.pi / 2 + 0.7, math.pi):
            tracery(P, x + (r - 1) * math.cos(a), y + (r - 1) * math.sin(a), foot + 30, math.cos(a), math.sin(a), 18, 46)
        for deg in (-142, -101, -46, 125, 180):     # оконца только там, где над ними уцелела кладка
            a = math.radians(deg)
            arch_decal(P, x + Q["ring_out"] * math.cos(a), y + Q["ring_out"] * math.sin(a), z1 + 14, math.cos(a), math.sin(a), 7, 17, off=1.0, trim=1.4)
        for a in (-1.9, 0.4, 2.6):
            ivy_site(x + r * math.cos(a), y + r * math.sin(a), math.cos(a), math.sin(a), foot + 22, foot + 22 + R.uniform(24, 60), 22, curve=(x, y, r))
    A = ARCADE
    (ax, ay), (bx, by) = A["p0"], A["p1"]
    L = math.hypot(bx - ax, by - ay)
    knots = A["skyline"]

    def top_fn(u):
        k = max(0.0, min(1.0, u / L))
        h = knots[-1][1]
        for (k0, h0), (k1, h1) in zip(knots, knots[1:]):
            if k0 <= k <= k1:
                h = h0 + (h1 - h0) * (k - k0) / (k1 - k0)
                break
        return h + 2.5 * math.sin(u * 0.73) + 2.0 * math.sin(u * 1.9)     # излом, одинаковый с обеих сторон стены
    n, t = len(A["tops"]), A["t"]
    arcade(P, A["p0"], A["p1"], A["z0"], A["tops"], t, A["arch_z"], A["arch_h"], top_fn=top_fn)
    if DETAIL:      # обрамления арок, импосты и базы столбов
        ux, uy = (bx - ax) / L, (by - ay) / L
        nx, ny = uy, -ux
        rot = math.atan2(uy, ux)
        bay = L / n
        pier_w = bay * 0.26
        w = bay - pier_w
        spring = A["arch_z"] + max(0.0, A["arch_h"] - w * 0.87)
        for i in range(n):
            mx, my = ax + ux * (i + 0.5) * bay, ay + uy * (i + 0.5) * bay
            for side in (1, -1):
                arch_ring(P, mx + nx * side * t / 2, my + ny * side * t / 2, A["arch_z"], nx * side, ny * side, w, A["arch_h"], 2.2, off=0.5)
        for i in range(1, n):
            px, py = ax + ux * i * bay, ay + uy * i * bay
            box(P, px, py, spring - 1.0, spring + 2.0, pier_w + 2.4, t + 2.0, rot, TRIM)
            box(P, px, py, A["arch_z"], A["arch_z"] + 6.0, pier_w + 2.4, t + 2.0, rot, TRIM)


def subdivide(pts, step):
    """Длинные пролёты — на куски: мох ложится на грань целиком и иначе выглядит сплошным прямоугольником."""
    out = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(1, n + 1)]
    return out


def build_inner(P):
    for pts, z0, z1, t in INNER_WALLS:
        z0 = min(z0, min(rock_top(*q) for q in pts) - 6)    # стена стоит на скале по всей длине
        pts = subdivide(pts, 36)
        wall(P, pts, z0, z1, t, ao=(z1 - 90, z1))
        wall_detail(P, pts, z1, t, False, buttress=(44, z0 + 10, z1 - 4, 9), niche=(44, z1 - 58, 15, 30), foot=z0 + 24)
    for x, y, top, r, z0 in INNER_TOWERS:
        round_tower(P, x, y, z0, top, r)


def varied_hall(x, y, w, d, z0, eave, ridge, rot):
    """Зал из ряда со своим лицом: сдвиг, другие размеры и уклон; часть развёрнута коньком вдоль фронта. Иначе — гребёнка."""
    rr = random.Random(int(x * 7) + int(y * 13) * 37 + SEED * 1000)
    x += rr.uniform(-5, 5)
    y += rr.uniform(-14, 14)
    w *= rr.uniform(0.82, 1.18)
    d *= rr.uniform(0.8, 1.3)
    eave += rr.uniform(-30, 20)
    ridge = eave + w * rr.uniform(0.62, 1.25)
    if rot == 0 and rr.random() < 0.24:
        w, d, rot = w * 0.78, max(w * 1.25, 48.0), 90
    return (x, y, w, d, z0, eave, ridge, rot)


_HALLS_CACHE = []


def all_halls():
    if not _HALLS_CACHE:
        _HALLS_CACHE.extend(HALLS)
        for y, z0, eave, ridge, items, d, rot in HALL_ROWS:
            _HALLS_CACHE.extend(varied_hall(x, y, w, d, z0, eave, ridge, rot) for x, w in items)
        for x, z0, eave, ridge, items, d in HALL_COLS:
            _HALLS_CACHE.extend(varied_hall(x, y, w, d, z0, eave, ridge, 90) for y, w in items)
    return _HALLS_CACHE


def build_upper(P, rng):
    # Сплошное ядро под залами: между ними нигде не просвечивает небо. Тёмное: на арте между зданиями глубокая тень.
    for x, y, w, d, z1 in ((-120, 40, 290, 320, 625), (150, 40, 330, 380, 625)):
        start = len(P.f)
        prism(P, rect(x, y, w, d), rect(x, y, w, d), 500, z1, STONE, top_mat=ROOF)
        P.darken(start, 0.5)
    for h in all_halls():
        hall(P, *h, rng)
    for q in TOWER_HOUSES:
        tower_house(P, *q)
    for p0, p1, z0, tops, t in RUINS:
        ruin_wall(P, p0, p1, z0, tops, t, rng)
        L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        if L >= 40:
            nx, ny = normal2(p0, p1)
            for q, top in ((p0, tops[0]), (p1, tops[-1])):      # поперечные стенки уходят вглубь здания, вниз по высоте
                back = (q[0] - nx * L * 0.42, q[1] - ny * L * 0.42)
                a, b = (q, back) if q is p1 else (back, q)
                n_ = 4
                heights = [z0 + (top - z0) * (0.92 - 0.14 * k) for k in range(n_)]
                jag_wall(P, a, b, z0, heights if q is p1 else heights[::-1], t * 0.8, rng, window=False)
    for x, y, r, z0, eave, tip in TURRETS:
        turret(P, x, y, r, stand_z(x, y, z0), eave, tip)
    if not DETAIL:
        return
    halls = [h for h in all_halls() if HALL_ACTUAL[(h[0], h[1])][3] != "ruin"]
    placed = tries = 0
    while placed < FILLER_PINNACLES and tries < 2000:
        tries += 1
        h = rng.choice(halls)
        u, v = rng.uniform(-h[2] / 2, h[2] / 2), rng.uniform(-h[3] / 2, h[3] / 2)
        x, y = (h[0] + u, h[1] + v) if h[7] == 0 else (h[0] - v, h[1] + u)
        _, ea, ri, _style = HALL_ACTUAL[(h[0], h[1])]
        tip = limit_tip(x, y, ri + rng.uniform(4, 22))
        if tip < ea + (ri - ea) * (1 - abs(u) / (h[2] / 2)) + 5 or abs(u) > h[2] * 0.42:     # над крышей, не на самом краю
            continue
        pinnacle(P, x, y, ea - 20, tip, rng.uniform(2.6, 4.0))
        placed += 1
    placed = tries = 0
    while placed < AUTO_TURRETS and tries < 2000:
        tries += 1
        h = rng.choice(halls)
        u, v = rng.uniform(-h[2] / 2, h[2] / 2), rng.uniform(-h[3] / 2, h[3] / 2)
        x, y = (h[0] + u, h[1] + v) if h[7] == 0 else (h[0] - v, h[1] + u)
        _, ea, ri, _style = HALL_ACTUAL[(h[0], h[1])]
        eave = ea + rng.uniform(4, 40)
        tip = limit_tip(x, y, eave + rng.uniform(28, 74))
        if tip < eave + 20 or tip < ea + (ri - ea) * (1 - abs(u) / (h[2] / 2)) + 8 or abs(u) > h[2] * 0.4:
            continue
        turret(P, x, y, rng.uniform(5.0, 9.5), ea - rng.uniform(40, 70), eave, tip, "crown" if rng.random() < 0.28 else "bell")
        placed += 1


def ribs(P, x, y, r, z0, z1, n, w=5.0, d=4.0, phase=0.0):
    """Вертикальные рёбра-лопатки на круглой башне."""
    for i in range(n):
        a = phase + TAU * i / n
        box(P, x + r * math.cos(a), y + r * math.sin(a), z0, z1, w, d, a + math.pi / 2, TRIM)


def build_crown(P, rng):
    D = DONJON
    x, y = D["x"], D["y"]
    for z0, z1, r0, r1, dents in D["tiers"]:
        cyl(P, x, y, z0 - 20, z1 - 16, r0, r1, 28, STONE, top=False, rows=max(2, int((z1 - z0) / 20)), ao=(z0, z1))
        if dents:
            crown(P, x, y, z1 - 16, r1 * 1.04, 28, parapet=7, mh=9)
        if DETAIL:
            ribs(P, x, y, r1 + 0.5, z0, z1 - 28, 14 if r1 > 50 else 10, phase=0.1)
            windows_ring(P, x, y, r1, z0 + (z1 - z0) * 0.25, 8, 7, 28, 0.2 + z0, trim=1.8)
            if r1 > 80:   # нижний ярус: ряд глухих арок
                windows_ring(P, x, y, r1, z0 + 40, 16, 15, 44, 0.3, trim=2.0, mat=RECESS)
            # Пинаклы по воротнику яруса.
            for k in range(8):
                a = TAU * (k + 0.5) / 8 + z0
                px, py = x + r1 * 1.02 * math.cos(a), y + r1 * 1.02 * math.sin(a)
                pinnacle(P, px, py, z1 - 30, limit_tip(px, py, z1 + 12), 3.0)
            cyl(P, x, y, z0 + (z1 - z0) * 0.52 - 8, z0 + (z1 - z0) * 0.52 - 5, r1 + 1.2, None, 28, TRIM, top=False)
            windows_ring(P, x, y, r1, z0 + (z1 - z0) * 0.52, 10, 4, 14, 0.5 + z0)
    cyl(P, x, y, D["crown_z"] - 18, D["crown_z"], 41, D["crown_r"], 24, TRIM, top=False)
    cyl(P, x, y, D["crown_z"], D["crown_z"] + 12, D["crown_r"], None, 24, STONE)
    if DETAIL:
        for i in range(14):
            a = TAU * (i + 0.5) / 14
            box(P, x + 44 * math.cos(a), y + 44 * math.sin(a), D["crown_z"] + 12, D["crown_z"] + 24, 12, 7, a + math.pi / 2)
    for z0, z1, r0, r1 in D["spire"]:
        cyl(P, x, y, z0, z1, r0, r1, 8, TRIM if z0 < 1050 else ROOF, top=False)
    B = BROKEN
    bx, by = B["x"], B["y"]
    cyl(P, bx, by, B["z0"], B["collar_z"] - 12, B["r"], B["r"] - 2, 28, STONE, top=False, rows=12, ao=(640, B["collar_z"]))
    cyl(P, bx, by, B["collar_z"] - 12, B["collar_z"], B["r"] - 2, B["r"] + 3, 28, TRIM, top=False)
    cyl(P, bx, by, B["collar_z"], B["collar_z"] + 4, B["r"] + 3, B["ring_out"], 28, STONE, top=False)
    broken_ring(P, bx, by, B["collar_z"] + 4, B["ring_out"], B["ring_in"], B["tops"], 56, rng, noise_px=15)
    if DETAIL:
        ribs(P, bx, by, B["r"] - 0.5, 640, B["collar_z"] - 14, 18)
        windows_ring(P, bx, by, B["r"] - 1, 720, 9, 7, 26, 0.4, trim=1.8)
        windows_ring(P, bx, by, B["r"] - 1, 662, 12, 5, 16, 0.1, trim=1.2)
        nc = int(TAU * B["r"] / 10)
        for i in range(nc):
            a = TAU * (i + 0.5) / nc
            box(P, bx + (B["r"] + 0.5) * math.cos(a), by + (B["r"] + 0.5) * math.sin(a), B["collar_z"] - 20, B["collar_z"] - 11, 4.0, 5.0, a + math.pi / 2, TRIM, top=False)
        for a in (-2.4, -0.7, 1.1, 2.6):
            ivy_site(bx + B["r"] * math.cos(a), by + B["r"] * math.sin(a), math.cos(a), math.sin(a), 650, R.uniform(700, 770), R.uniform(14, 30), curve=(bx, by, B["r"]))
            ivy_site(bx + B["ring_out"] * math.cos(a + 0.5), by + B["ring_out"] * math.sin(a + 0.5), math.cos(a + 0.5), math.sin(a + 0.5), B["collar_z"] + 6, B["collar_z"] + R.uniform(24, 50), R.uniform(10, 20), curve=(bx, by, B["ring_out"]))
        for _ in range(10):
            a = R.uniform(0, TAU)
            rubble(P, bx + (B["ring_out"] + 5) * math.cos(a), by + (B["ring_out"] + 5) * math.sin(a), B["collar_z"] + 4, 2, 4, 6.0)
        windows_ring(P, bx, by, B["ring_out"], 830, 8, 5, 16, 0.1)
    RD = ROUND
    cyl(P, RD["x"], RD["y"], RD["z0"], RD["z1"] - 12, RD["r"], None, 20, STONE, top=False, rows=5, ao=(630, RD["z1"]))
    crown(P, RD["x"], RD["y"], RD["z1"], RD["crown_r"], 18, parapet=14, mh=12)
    if DETAIL:
        windows_ring(P, RD["x"], RD["y"], RD["r"], 655, 5, 4, 16, -math.pi / 2)


# ---------------------------------------------------------------- BLENDER ------------------------------------------
def linear(c):
    return (c[0], c[1], c[2], 1.0)


def make_materials():
    out = []
    for name, (col, tex) in MATS.items():
        full = "Castle_" + name
        m = bpy.data.materials.get(full) or bpy.data.materials.new(full)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        for n in [n for n in nt.nodes if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL")]:
            nt.nodes.remove(n)
        bsdf.inputs["Roughness"].default_value = 0.95
        bsdf.inputs["Specular IOR Level"].default_value = 0.0 if tex is None else 0.25
        bsdf.inputs["Base Color"].default_value = linear(col)
        path = ""
        if tex:
            path = os.path.join(NATURE_TEX, tex[1:]) if tex.startswith("@") else os.path.join(OUT, "tex", tex)
        if tex and os.path.exists(path):
            node = nt.nodes.new("ShaderNodeTexImage")
            node.image = bpy.data.images.load(path, check_existing=True)
            node.interpolation = "Closest"
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "Col"
            mul = nt.nodes.new("ShaderNodeMix")
            mul.data_type = "RGBA"
            mul.blend_type = "MULTIPLY"
            mul.inputs[0].default_value = 1.0
            nt.links.new(node.outputs["Color"], mul.inputs[6])
            nt.links.new(vc.outputs["Color"], mul.inputs[7])
            nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
            if name == "foliage":
                nt.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
                m.surface_render_method = "DITHERED"
        out.append(m)
    return out


def face_tones(P, rng):
    """Мох на мелких гранях кладки. Тон — плавные пятна по месту и небольшой разброс на цельную деталь: без полос по граням."""
    tones = []
    jitter = {}
    for i, f in enumerate(P.f):
        mat = P.m[i]
        xs, ys, zs = zip(*(P.v[k] for k in f))
        cx, cy, cz = sum(xs) / len(f), sum(ys) / len(f), sum(zs) / len(f)
        if mat == STONE and max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)) < 70:
            if noise.noise(Vector((cx / 90.0, cy / 90.0, cz / 70.0))) > MOSS_SHARE:
                P.m[i] = MOSS
        g = P.group.get(i)
        j = jitter.setdefault(g, rng.uniform(0.95, 1.04)) if g is not None else rng.uniform(0.97, 1.03)
        patch = 1.0 + 0.10 * noise.noise(Vector((cx / 70.0, cy / 70.0, cz / 55.0)))
        tones.append(j * patch * PART_TONE.get(P.name, 1.0) * P.dim.get(i, 1.0))
    return tones


def box_uv(me, P):
    """Развёртка по доминирующей оси нормали грани, в метрах: плотность 40 px/м на любой грани."""
    uv = me.uv_layers.new(name="UV0").data
    co = me.vertices
    vals = [0.0] * (len(me.loops) * 2)
    for poly in me.polygons:
        nx, ny, nz = poly.normal
        ax, ay, az = abs(nx), abs(ny), abs(nz)
        for li in poly.loop_indices:
            x, y, z = co[me.loops[li].vertex_index].co
            if az >= ax and az >= ay:
                u, v = x, y
            elif ax >= ay:
                u, v = y if nx > 0 else -y, z
            else:
                u, v = -x if ny > 0 else x, z
            vals[li * 2], vals[li * 2 + 1] = u / TEX_PERIOD, v / TEX_PERIOD
    # Круглые детали: развёртка вокруг оси, плотность везде 40 px/м, без шва на смене проекции.
    for fi, (cx, cy, rb) in P.cylf.items():
        poly = me.polygons[fi]
        a0 = math.atan2(poly.center.y - cy * S, poly.center.x - cx * S)
        for li in poly.loop_indices:
            q = co[me.loops[li].vertex_index].co
            dx, dy = q.x - cx * S, q.y - cy * S
            da = 0.0 if math.hypot(dx, dy) < 1e-4 else (math.atan2(dy, dx) - a0 + math.pi) % TAU - math.pi
            vals[li * 2], vals[li * 2 + 1] = (a0 + da) * rb * S / TEX_PERIOD, q.z / TEX_PERIOD
    for fi, corners in P.fuv.items():   # атласы растительности: развёртка задана при постройке
        for li, (u, v) in zip(me.polygons[fi].loop_indices, corners):
            vals[li * 2], vals[li * 2 + 1] = u, v
    uv.foreach_set("uv", vals)


def to_object(P, coll, mats, rng):
    tones = face_tones(P, rng)
    me = bpy.data.meshes.new("Castle_" + P.name)
    me.from_pydata([(x * S, y * S, z * S) for x, y, z in P.v], [], P.f)
    used = sorted(set(P.m))
    for k in used:
        me.materials.append(mats[k])
    slot = {k: i for i, k in enumerate(used)}
    me.polygons.foreach_set("material_index", [slot[k] for k in P.m])
    me.update()
    if P.smooth:
        flags = [False] * len(me.polygons)
        for fi in P.smooth:
            flags[fi] = True
        me.polygons.foreach_set("use_smooth", flags)
    box_uv(me, P)
    # Цвет — на углы граней: у скалы по вершинам (мох, трещины), у кладки по граням.
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.find("Col")
    flat = [1.0] * (len(me.loops) * 4)
    for poly in me.polygons:
        if P.col:
            for li in poly.loop_indices:
                flat[li * 4:li * 4 + 4] = P.col[me.loops[li].vertex_index]
            continue
        # Кладка: запечённое затенение — низ грани темнее, пятна сырости, зелень у подошвы высоких стен.
        t = tones[poly.index]
        ids = [me.loops[li].vertex_index for li in poly.loop_indices]
        zs = [P.v[k][2] for k in ids]
        zmin, zmax = P.aorange.get(poly.index, (min(zs), max(zs)))
        span = zmax - zmin
        vertical = abs(poly.normal.z) < 0.5
        for li, k in zip(poly.loop_indices, ids):
            x, y, z = P.v[k]
            h = max(0.0, min(1.0, (z - zmin) / span)) if span > 1e-3 else 1.0
            if vertical and span > 26:
                ao = 0.66 + 0.40 * h
            elif vertical:
                ao = 0.84 + 0.20 * h
            else:
                ao = 1.0
            stain = 1.0 + 0.30 * noise.noise(Vector((x / 44.0, y / 44.0, z / 28.0))) + 0.14 * noise.noise(Vector((x / 15.0, y / 15.0, z / 38.0)))
            v = max(0.0, min(1.0, t * ao * stain))
            mossy = noise.noise(Vector((x / 60.0, y / 60.0, z / 40.0)))
            if vertical and span > 26 and ((h < 0.5 and mossy > 0.05) or mossy > 0.28):      # зелень у подошвы и пятнами выше
                flat[li * 4:li * 4 + 4] = (v * 0.72, v * 0.86, v * 0.72, 1.0)
            elif not vertical and mossy > 0.12 and P.m[poly.index] in (STONE, TRIM, MOSS):   # мох на верхних гранях
                flat[li * 4:li * 4 + 4] = (v * 0.56, v * 0.74, v * 0.56, 1.0)
            else:
                flat[li * 4:li * 4 + 4] = (v, v, v, 1.0)
    attr.data.foreach_set("color", flat)
    ob = bpy.data.objects.new("Castle_" + P.name, me)
    coll.objects.link(ob)
    return ob


def clear_own():
    path = bpy.data.filepath
    if path and os.path.normcase(path) != os.path.normcase(BLEND):
        raise RuntimeError("Открыт чужой файл, замок туда не пишется: " + path)
    coll = bpy.data.collections.get("Castle")
    if coll:
        for ob in list(coll.objects):
            me = ob.data
            bpy.data.objects.remove(ob)
            if me and me.users == 0:
                bpy.data.meshes.remove(me)
    else:
        coll = bpy.data.collections.new("Castle")
        bpy.context.scene.collection.children.link(coll)
    if not path:  # стартовая сцена: убрать куб по умолчанию
        cube = bpy.data.objects.get("Cube")
        if cube:
            bpy.data.objects.remove(cube)
    return coll


def build():
    rng = random.Random(SEED)
    R.seed(SEED + 3)
    for lst in SPOTS.values():
        lst.clear()
    IVY.clear()
    BUILT.clear()
    _ROCK_BVH.clear()
    HALL_ACTUAL.clear()
    os.makedirs(OUT, exist_ok=True)
    coll = clear_own()
    mats = make_materials()
    stats = {}
    stats_ivy = 0
    for name, fn in (("Rock", build_rock), ("Scree", build_scree if DETAIL else None), ("Ring", build_ring), ("Curtain", build_curtain), ("Gate", build_gate),
                     ("Stairs", build_stairs if DETAIL else None), ("Spur", lambda P: build_spur(P, rng)),
                     ("Inner", build_inner), ("Upper", lambda P: build_upper(P, rng)), ("Crown", lambda P: build_crown(P, rng)),
                     ("Ivy", build_ivy if DETAIL else None)):
        if fn is None:
            continue
        seed = SEED * 1000 + sum(ord(ch) * 31 ** k for k, ch in enumerate(name)) % 9973
        R.seed(seed)
        rng.seed(seed + 1)
        P = Part(name)
        dropped = fn(P)
        if name == "Ivy":
            stats_ivy = dropped
        elif name != "Scree":
            BUILT.append(P)
        to_object(P, coll, mats, rng)
        stats[name] = sum(len(f) - 2 for f in P.f)
    stats["всего_треугольников"] = sum(v for v in stats.values())
    root = bpy.data.objects.new("Castle_Root", None)
    coll.objects.link(root)
    for ob in coll.objects:
        if ob is not root:
            ob.parent = root
    with open(os.path.join(OUT, "castle_spots.json"), "w", encoding="utf-8") as f:   # места для растений: castle_veg.py
        json.dump({k: [[round(c, 1) for c in q] for q in v] for k, v in SPOTS.items()}, f, separators=(",", ":"))
    stats["плющ, мест"] = len(IVY)
    stats["плитки плюща без опоры, не поставлены"] = stats_ivy if DETAIL else 0
    stats["места растений"] = {k: len(v) for k, v in SPOTS.items()}
    place(False)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    return stats


def site_origin():
    """Положение начала модели в метрах мира: низ лестницы — там, где кончается мост, на плато мыса."""
    x, y, z = stair_points()[-1]
    return (SITE["bridge_end"][0] - x * S, SITE["bridge_end"][1] - y * S, SITE["ground"] - z * S)


def place(on_site):
    """on_site: модель на мысу в координатах мира; иначе начало в нуле (для сверки с артом и видов)."""
    root = bpy.data.objects.get("Castle_Root")
    if root:
        root.location = site_origin() if on_site else (0.0, 0.0, 0.0)
        scree = bpy.data.objects.get("Castle_Scree")
        if scree:
            scree.hide_render = not on_site    # стоит на земле мира: без неё висела бы в воздухе
        bpy.context.view_layer.update()


CAMS = {  # положение относительно центра кадра, поворот Эйлера
    "front": ((0, -1, 0), (90, 0, 0)), "back": ((0, 1, 0), (90, 0, 180)),
    "right": ((1, 0, 0), (90, 0, 90)), "left": ((-1, 0, 0), (90, 0, -90)),
}


def set_camera(view):
    scene = bpy.context.scene
    cam = bpy.data.objects.get("Camera")
    if cam is None:
        cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.clip_end = 5000.0
    cam.data.sensor_fit = "AUTO"   # castle_site.py ставит вертикальный: иначе масштаб кадра сверки другой
    D = 2000 * S
    if view in CAMS:
        (u, v, w), rot = CAMS[view]
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 1500 * S
        cam.location = (u * D, v * D, 570 * S)
        cam.rotation_euler = tuple(math.radians(a) for a in rot)
    elif view == "top":
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 1500 * S
        cam.location = (0, 0, 1500 * S)
        cam.rotation_euler = (0, 0, 0)
    else:  # как в игре: FOV 30, наклон диорамы, с юго-востока, издалека
        cam.data.type = "PERSP"
        cam.data.sensor_width = 36
        cam.data.lens = 36 / (2 * math.tan(math.radians(30) / 2))
        target = Vector((0, 0, 380 * S))
        pos = target + Vector((0.42, -0.72, 0.42)).normalized() * (3700 * S)
        cam.location = pos
        cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()


def render_silhouettes():
    scene = bpy.context.scene
    place(False)
    site = bpy.data.collections.get("CastleSite")
    if site:
        site.hide_render = True
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.render_aa = "OFF"
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = 1500, 1240
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    for view in ("front", "back", "right"):
        set_camera(view)
        scene.render.filepath = os.path.join(OUT, "sil_%s.png" % view)
        bpy.ops.render.render(write_still=True)
    return {"sil": True}


def render_culled():
    """Вид спереди с отсечением задних граней (как в Godot): вывернутые грани и окна пропадут."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.render_aa = "FXAA"
    scene.display.shading.show_backface_culling = True
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = 1500, 1240
    scene.render.resolution_percentage = 100
    scene.render.image_settings.color_mode = "RGBA"
    for view in ("front", "back", "right"):
        set_camera(view)
        scene.render.filepath = os.path.join(OUT, "cull_%s.png" % view)
        bpy.ops.render.render(write_still=True)
    scene.display.shading.show_backface_culling = False
    return {"cull": True}


def setup_light(view="front"):
    """Солнце привязано к камере (слева сверху от неё): все стороны освещены одинаково, как на артах."""
    scene = bpy.context.scene
    sun = bpy.data.objects.get("CastleSun")
    if sun is None:
        sun = bpy.data.objects.new("CastleSun", bpy.data.lights.new("CastleSun", "SUN"))
        scene.collection.objects.link(sun)
    sun.data.energy = 3.6
    sun.data.angle = math.radians(4)
    az = {"front": 0, "back": 180, "right": 90, "left": -90, "top": 0}.get(view, 30)
    sun.rotation_euler = (math.radians(62), 0, math.radians(az - 52))
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
    bg.inputs[0].default_value = (0.55, 0.58, 0.62, 1.0)
    bg.inputs[1].default_value = 0.60


def render_views(names=("front", "back", "right", "left", "top", "game"), percent=100):
    scene = bpy.context.scene
    place(False)
    site = bpy.data.collections.get("CastleSite")
    if site:
        site.hide_render = True
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.film_transparent = False
    scene.render.resolution_x, scene.render.resolution_y = 1500, 1240
    scene.render.resolution_percentage = percent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    for view in names:
        setup_light(view)
        set_camera(view)
        scene.render.filepath = os.path.join(OUT, "view_%s.png" % view)
        bpy.ops.render.render(write_still=True)
    return {"views": list(names)}


if __name__ == "__main__":
    if MODE == "build":
        result = build()
    elif MODE == "sil":
        result = render_silhouettes()
    elif MODE == "cull":
        result = render_culled()
    elif MODE == "views":
        result = render_views(globals().get("VIEWS", ("front", "back", "right", "left", "top", "game")))
    globals()["RESULT"] = result
