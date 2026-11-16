"""Текстуры дополнений к паку растительности — пиксель-арт 40 пикселей на метр, две картинки-атласа:
ExtrasFoliage.png — то, что качается на ветру (папоротник, плющ, трава, цветы),
ExtrasSolid.png — неподвижное (кора, мох, камень, грибы, листовой опад).
Рисуется процедурно, цвета — короткие рамповые палитры (тени холоднее, свет теплее, как в PROJECT_BIBLE).
Раскладка плиток — assets/models/nature/extras_atlas.json: {картинка: {плитка: [x, y, w, h]}}; её читает
Tools/blender/nature_extras.py при сборке моделей. Запуск: python Tools/nature_extras_textures.py
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "Game", "CatsSoulDebt", "assets", "models", "nature")
OUT = os.path.join(GAME, "textures")
SIZE = 512
rng = random.Random(404)

FERN = [(50, 84, 40), (70, 110, 46), (98, 138, 54), (132, 164, 68)]
FERN_DARK = [(36, 66, 40), (52, 90, 46), (74, 116, 54), (102, 142, 66)]
BROAD = [(24, 66, 56), (36, 92, 70), (58, 124, 84), (96, 156, 104)]
IVY = [(24, 50, 28), (38, 76, 34), (60, 104, 40), (92, 134, 52)]
GRASS = [(58, 88, 32), (82, 112, 38), (112, 138, 50), (150, 164, 70)]
STRAW = [(134, 122, 62), (164, 148, 76), (192, 172, 92), (222, 202, 124)]
REED = [(64, 80, 36), (94, 108, 44), (130, 136, 60)]
CATTAIL = [(70, 44, 28), (98, 62, 36)]
BARK = [(40, 30, 24), (58, 44, 32), (78, 60, 42), (100, 80, 56)]
BARK_GREY = [(52, 48, 44), (72, 66, 58), (94, 86, 74), (116, 108, 92)]
RINGS = [(112, 84, 54), (146, 112, 72), (176, 140, 94)]
MOSS = [(50, 76, 30), (60, 88, 32), (72, 102, 36), (88, 118, 42)]
STONE = [(68, 64, 60), (92, 88, 80), (118, 112, 100), (146, 138, 122)]
STONE_COLD = [(60, 66, 70), (80, 88, 92), (104, 112, 112), (132, 138, 134)]
LITTER = [(92, 58, 32), (126, 78, 36), (160, 104, 44), (70, 54, 34), (176, 136, 58)]
CAP_TAN = [(120, 84, 52), (156, 116, 72), (190, 152, 100)]
CAP_RED = [(120, 32, 28), (160, 44, 34), (196, 66, 44)]
STEM = [(190, 178, 150), (222, 212, 184)]
FUNGUS = [(120, 92, 56), (170, 136, 84), (214, 186, 128)]


class Atlas:
    """Плитки — полками слева направо; между плитками запас 2 пикселя, чтобы nearest не хватал соседа."""

    def __init__(self, name):
        self.name = name
        self.im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        self.x = self.y = 2
        self.row = 0
        self.tiles = {}

    def add(self, tile, img):
        w, h = img.size
        if self.x + w + 2 > SIZE:
            self.x, self.y, self.row = 2, self.y + self.row + 2, 0
        assert self.y + h <= SIZE, "атлас %s переполнен на %s" % (self.name, tile)
        self.im.paste(img, (self.x, self.y))
        self.tiles[tile] = [self.x, self.y, w, h]
        self.x += w + 2
        self.row = max(self.row, h)

    def save(self):
        self.im.save(os.path.join(OUT, self.name + ".png"))


def blank(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def pal(p, t):
    """t 0..1 → цвет рампы, непрозрачный."""
    return p[min(len(p) - 1, max(0, int(t * len(p))))] + (255,)


def blotch(w, h, p, cells=6, spots=None):
    """Непрозрачная плитка: пятна рампы по ячеистому шуму (без плавных градиентов, как текстуры мира)."""
    img = blank(w, h)
    pts = [(rng.uniform(0, w), rng.uniform(0, h), rng.random()) for _ in range(spots or (w * h // (cells * cells)))]
    px = img.load()
    for y in range(h):
        for x in range(w):
            best = min(pts, key=lambda q: (min(abs(q[0] - x), w - abs(q[0] - x))) ** 2 + (min(abs(q[1] - y), h - abs(q[1] - y))) ** 2)
            px[x, y] = pal(p, best[2])
    return img


# --- Листва -------------------------------------------------------------------------------

def frond(w, h, p, curl=0.0):
    """Вайя папоротника: основание слева, кончик справа; листочки парами короче к кончику."""
    img = blank(w, h)
    d = ImageDraw.Draw(img)
    mid = h / 2
    for x in range(1, w - 2, 3):
        t = x / w
        ln = (h / 2 - 1) * (math.sin(min(t * 1.25, 1.0) * math.pi) ** 0.65) * (1.0 - t * 0.2)
        if t < 0.08:
            continue
        for s, shade in ((-1, 0.72), (1, 0.45)):
            c = pal(p, shade + rng.uniform(-0.12, 0.12))
            tip = (x + 3, mid + s * ln)
            d.polygon([(x, mid), (x + 2, mid), tip], fill=c)
            d.point(tip, fill=pal(p, 0.95))
    d.line([(0, mid), (w - 1, mid)], fill=pal(p, 0.05))
    return img


def lance(w, h, p):
    """Широкий заострённый лист (основание слева, кончик справа), светлая средняя жилка."""
    img = blank(w, h)
    d = ImageDraw.Draw(img)
    mid = h / 2
    top, bot = [], []
    for x in range(w):
        t = x / (w - 1)
        hw = (h / 2 - 0.5) * (math.sin(math.pi * t ** 0.7) ** 0.8)
        top.append((x, mid - hw))
        bot.append((x, mid + hw))
    d.polygon(top + bot[::-1], fill=pal(p, 0.4))
    d.polygon(top + [(x, mid) for x in range(w - 1, -1, -1)], fill=pal(p, 0.65))
    for x in range(4, w - 4, 5):
        d.line([(x, mid), (x + 3, mid - (h / 2) * 0.55)], fill=pal(p, 0.15))
        d.line([(x, mid), (x + 3, mid + (h / 2) * 0.55)], fill=pal(p, 0.05))
    d.line([(1, mid), (w - 2, mid)], fill=pal(p, 0.95))
    return img


def ivy_leaf(d, x, y, r, c, vein):
    """Лист плюща: пятиконечный ромб-клякса в несколько пикселей."""
    d.polygon([(x, y - r), (x + r, y - r * 0.2), (x + r * 0.55, y + r * 0.8), (x, y + r * 0.35), (x - r * 0.55, y + r * 0.8), (x - r, y - r * 0.2)], fill=c)
    d.point((x, y), fill=vein)


def ivy_sheet(w, h, p, density=1.0):
    """Плотная куртина плюща: листья поверх веточек, край рваный (шейдер режет по альфе)."""
    img = blank(w, h)
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / 26 * density)):
        x, y = rng.uniform(1, w - 2), rng.uniform(1, h - 2)
        t = 1.0 - y / h
        ivy_leaf(d, x, y, rng.uniform(2.2, 3.6), pal(p, min(0.99, max(0.0, t * 0.55 + rng.uniform(-0.05, 0.5)))), pal(p, 0.95))
    return img


def vine(w, h, p):
    """Свисающая плеть: сверху гуще, книзу редеет и сужается (основание наверху картинки)."""
    img = blank(w, h)
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / 18)):
        y = h * rng.random() ** 1.7
        spread = (w / 2 - 2) * (1 - y / h) ** 0.6
        x = w / 2 + rng.uniform(-spread, spread)
        ivy_leaf(d, x, y, rng.uniform(2.0, 3.2), pal(p, rng.uniform(0.1, 0.99)), pal(p, 0.95))
    return img


def tuft(w, h, p, heads=False, blades=26):
    """Куст высокой травы: лезвия из одной точки внизу расходятся и гнутся; heads — метёлки семян."""
    img = blank(w, h)
    d = ImageDraw.Draw(img)
    for i in range(blades):
        x0 = w / 2 + rng.uniform(-w * 0.14, w * 0.14)
        lean = rng.uniform(-0.45, 0.45)
        tall = rng.uniform(0.55, 1.0) * (h - 2)
        c = pal(p, rng.random())
        pts = []
        for k in range(7):
            t = k / 6
            pts.append((x0 + lean * tall * t * t, h - 1 - tall * t))
        d.line(pts, fill=c, width=2 if rng.random() < 0.3 else 1)
        if heads and rng.random() < 0.45:
            tx, ty = pts[-1]
            for k in range(5):
                d.point((tx + rng.choice((-1, 0, 1)), ty + k), fill=pal(p, 0.99))
    return img


def cattails(w, h):
    img = blank(w, h)
    d = ImageDraw.Draw(img)
    for i in range(9):
        x0 = w / 2 + rng.uniform(-w * 0.3, w * 0.3)
        tall = rng.uniform(0.6, 0.98) * (h - 2)
        lean = rng.uniform(-0.1, 0.1)
        top = (x0 + lean * tall, h - 1 - tall)
        d.line([(x0, h - 1), top], fill=pal(REED, rng.random()))
        if rng.random() < 0.55:
            d.rectangle([top[0] - 1, top[1] + 1, top[0] + 1, top[1] + 8], fill=pal(CATTAIL, rng.random()))
    for i in range(10):
        x0 = w / 2 + rng.uniform(-w * 0.35, w * 0.35)
        d.line([(x0, h - 1), (x0 + rng.uniform(-8, 8), h - 1 - rng.uniform(0.3, 0.7) * h)], fill=pal(REED, rng.random()))
    return img


def flower_stalk(w, h, petal, heart, leaf, kind):
    """Цветы в профиль: стебли с листьями снизу, венчики разного вида (kind: lily, spike, poppy, umbel)."""
    img = blank(w, h)
    d = ImageDraw.Draw(img)
    n = {"lily": 3, "spike": 3, "poppy": 5, "umbel": 5}[kind]
    for i in range(n):
        x0 = w / 2 + rng.uniform(-w * 0.22, w * 0.22)
        tall = rng.uniform(0.62, 0.92) * (h - 6)
        lean = rng.uniform(-0.22, 0.22)
        top = (x0 + lean * tall, h - 1 - tall)
        d.line([(x0, h - 1), top], fill=pal(leaf, 0.4))
        for k in range(3):
            t = rng.uniform(0.1, 0.65)
            sx, sy = x0 + lean * tall * t, h - 1 - tall * t
            s = rng.choice((-1, 1))
            d.polygon([(sx, sy), (sx + s * rng.uniform(5, 9), sy - rng.uniform(1, 5)), (sx + s * 3, sy + 1)], fill=pal(leaf, rng.random()))
        tx, ty = top
        if kind == "lily":
            for a, r in ((-2.4, 5), (-1.57, 6), (-0.7, 5), (-3.0, 4), (-0.15, 4)):
                d.line([(tx, ty), (tx + math.cos(a) * r, ty + math.sin(a) * r)], fill=petal[1], width=2)
            d.point((tx, ty), fill=heart)
            d.point((tx, ty - 1), fill=heart)
        elif kind == "spike":
            for k in range(7):
                yy = ty + k * 1.6
                d.rectangle([tx - 1 - (k % 2), yy, tx + 1 + (k % 2), yy + 1], fill=petal[k % 2])
        elif kind == "poppy":
            d.ellipse([tx - 3, ty - 2, tx + 3, ty + 2], fill=petal[0])
            d.point((tx - 1, ty - 1), fill=petal[1])
            d.point((tx, ty), fill=heart)
        else:
            for k in range(9):
                d.point((tx + rng.uniform(-5, 5), ty + rng.uniform(-1.6, 1.2)), fill=petal[rng.randrange(2)])
            for s in (-3, 0, 3):
                d.line([(tx, ty + 6), (tx + s, ty + 1)], fill=pal(leaf, 0.6))
    return img


# --- Неподвижное --------------------------------------------------------------------------

def bark(w, h, p):
    """Кора: вертикальные (по v) борозды — рваные полосы рампы."""
    img = blank(w, h)
    px = img.load()
    cols = [rng.random() for _ in range(w)]
    for x in range(w):
        for y in range(h):
            t = cols[x] + 0.25 * math.sin(y * 0.35 + x * 2.1) + rng.uniform(-0.1, 0.1)
            px[x, y] = pal(p, t)
    return img


def rings(s):
    img = blank(s, s)
    px = img.load()
    c = (s - 1) / 2
    for y in range(s):
        for x in range(s):
            r = math.hypot(x - c, y - c)
            if r <= c:
                px[x, y] = pal(RINGS, (math.sin(r * 1.5) + 1) / 2 * 0.99) if r < c - 1.5 else pal(BARK, 0.4)
    return img


def cap(w, h, p, spots=None):
    """Шляпка гриба: тёмный край внизу, блик сверху; spots — белые пятна мухомора."""
    img = blank(w, h)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = 1.0 - y / max(1, h - 1)
            px[x, y] = pal(p, t * 0.8 + rng.uniform(-0.1, 0.1))
    if spots:
        d = ImageDraw.Draw(img)
        for _ in range(int(w * h / 30)):
            xx, yy = rng.randrange(w), rng.randrange(h)
            d.rectangle([xx, yy, xx + 1, yy + 1], fill=spots)
    return img


def scatter(w, h, draw, n):
    img = blank(w, h)
    d = ImageDraw.Draw(img)
    for _ in range(n):
        draw(d, rng.uniform(2, w - 3), rng.uniform(2, h - 3))
    return img


def litter_leaf(d, x, y):
    c = LITTER[rng.randrange(len(LITTER))] + (255,)
    a = rng.uniform(0, math.pi)
    dx, dy = math.cos(a) * 2.5, math.sin(a) * 2.5
    d.polygon([(x - dx, y - dy), (x - dy * 0.5, y + dx * 0.5), (x + dx, y + dy), (x + dy * 0.5, y - dx * 0.5)], fill=c)


def twig(d, x, y):
    a = rng.uniform(0, math.pi)
    ln = rng.uniform(6, 16)
    c = pal(BARK, rng.random())
    d.line([(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], fill=c)


def moss_patch(s, p):
    """Пятно мха: плотная середина, к краю редеет пикселями (режется по альфе)."""
    img = blank(s, s)
    px = img.load()
    c = (s - 1) / 2
    blobs = [(rng.uniform(c * 0.4, c * 1.6), rng.uniform(c * 0.4, c * 1.6), rng.uniform(c * 0.4, c * 0.7)) for _ in range(7)]
    for y in range(s):
        for x in range(s):
            v = max(1.0 - math.hypot(x - bx, y - by) / br for bx, by, br in blobs)
            if v > rng.uniform(0.0, 0.32):
                px[x, y] = pal(p, min(0.99, v * 0.9 + rng.uniform(-0.15, 0.25)))
    return img


def planks(w, h, p, n=4):
    """Старые доски: ряды поперёк v, у каждой свой тон, щели тёмные, волокна вдоль u."""
    img = blank(w, h)
    px = img.load()
    bh = h // n
    tones = [rng.uniform(0.25, 0.8) for _ in range(n + 1)]
    for y in range(h):
        row = y // bh
        for x in range(w):
            t = tones[row] + 0.18 * math.sin(x * 0.28 + row * 3.1 + y * 0.9) + rng.uniform(-0.08, 0.08)
            px[x, y] = pal(p, 0.0 if y % bh == 0 else t)
    return img


def bark_tile(s):
    """Кора для мешей мира (шейдер wall_xray, плитка кладётся по оси нормали): рваные трещины без направления."""
    pts = [(rng.uniform(0, s), rng.uniform(0, s)) for _ in range(s * s // 90)]
    img = Image.new("RGB", (s, s))
    px = img.load()
    for y in range(s):
        for x in range(s):
            ds = sorted((min(abs(a - x), s - abs(a - x))) ** 2 + (min(abs(b - y), s - abs(b - y))) ** 2 for a, b in pts)[:2]
            edge = math.sqrt(ds[1]) - math.sqrt(ds[0])
            v = 0.62 if edge < 1.0 else 0.86 if edge < 2.2 else 1.0
            v += rng.uniform(-0.04, 0.04)
            px[x, y] = (int(208 * v), int(200 * v), int(186 * v))
    return img


def build():
    os.makedirs(OUT, exist_ok=True)
    bark_tile(128).save(os.path.join(ROOT, "Game", "CatsSoulDebt", "assets", "textures", "village", "village_bark.png"))
    fol = Atlas("ExtrasFoliage")
    fol.add("fern", frond(80, 30, FERN))
    fol.add("fern_dark", frond(80, 30, FERN_DARK))
    fol.add("fern_small", frond(52, 22, FERN))
    fol.add("broad", lance(72, 18, BROAD))
    fol.add("broad_small", lance(40, 12, FERN))
    fol.add("tuft", tuft(64, 56, GRASS))
    fol.add("tuft_tall", tuft(72, 84, GRASS, heads=True, blades=34))
    fol.add("tuft_dry", tuft(72, 72, STRAW, heads=True, blades=30))
    fol.add("cattail", cattails(64, 92))
    fol.add("lily", flower_stalk(56, 64, [(232, 230, 214, 255), (250, 248, 236, 255)], (226, 176, 60, 255), BROAD, "lily"))
    fol.add("spike", flower_stalk(48, 72, [(58, 104, 190, 255), (104, 156, 226, 255)], (250, 250, 250, 255), FERN, "spike"))
    fol.add("poppy", flower_stalk(56, 44, [(176, 44, 40, 255), (214, 74, 54, 255)], (40, 30, 26, 255), FERN, "poppy"))
    fol.add("umbel", flower_stalk(64, 56, [(226, 226, 214, 255), (244, 244, 234, 255)], (214, 196, 110, 255), FERN_DARK, "umbel"))
    fol.add("ivy", ivy_sheet(96, 96, IVY))
    fol.add("ivy_thin", ivy_sheet(64, 64, IVY, 0.55))
    fol.add("vine", vine(40, 112, IVY))
    fol.save()

    sol = Atlas("ExtrasSolid")
    sol.add("bark", bark(96, 96, BARK))
    sol.add("bark_grey", bark(96, 96, BARK_GREY))
    sol.add("rings", rings(32))
    sol.add("moss", blotch(96, 96, MOSS, 2))
    sol.add("stone", blotch(96, 96, STONE, 7))
    sol.add("stone_cold", blotch(96, 96, STONE_COLD, 7))
    sol.add("cap_tan", cap(24, 14, CAP_TAN))
    sol.add("cap_red", cap(24, 14, CAP_RED, (236, 232, 220, 255)))
    sol.add("stem", cap(8, 12, STEM))
    sol.add("fungus", cap(24, 10, FUNGUS))
    sol.add("moss_patch", moss_patch(72, [(50, 76, 30), (66, 96, 32), (84, 114, 38), (106, 136, 48)]))
    sol.add("moss_patch_dark", moss_patch(72, [(30, 52, 26), (44, 72, 28), (66, 96, 32), (92, 124, 40)]))
    sol.add("litter", scatter(96, 96, litter_leaf, 150))
    sol.add("twigs", scatter(96, 64, twig, 18))
    sol.add("planks", planks(96, 64, [(52, 40, 30), (84, 64, 44), (112, 88, 60), (138, 112, 78)]))
    sol.add("planks_grey", planks(96, 64, [(50, 48, 44), (78, 74, 66), (104, 98, 86), (130, 124, 108)]))
    sol.add("iron", blotch(16, 16, [(38, 36, 36), (56, 52, 50), (78, 66, 58)], 3))
    sol.save()

    with open(os.path.join(GAME, "extras_atlas.json"), "w", encoding="utf-8") as f:
        json.dump({"size": SIZE, "ExtrasFoliage": fol.tiles, "ExtrasSolid": sol.tiles}, f, ensure_ascii=False, indent=0)
    # Превью — чтобы посмотреть глазами: оба атласа рядом, ×2, на сером фоне.
    prev = Image.new("RGBA", (SIZE * 4, SIZE * 2), (120, 120, 120, 255))
    for k, a in enumerate((fol, sol)):
        big = a.im.resize((SIZE * 2, SIZE * 2), Image.NEAREST)
        prev.alpha_composite(big, (SIZE * 2 * k, 0))
    path = os.path.join(ROOT, "Арт", "Обработано", "nature_extras_preview.png")
    prev.convert("RGB").crop((0, 0, SIZE * 4, 620)).save(path)
    print("ok", path, fol.y + fol.row, sol.y + sol.row)


if __name__ == "__main__":
    build()
