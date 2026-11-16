"""Пиксельные текстуры замка: холодные варианты текстур Рубежа и сланцевая черепица (палитра главного меню: камень — тон
202–218°, насыщенность 0,14–0,17; PROJECT_BIBLE: «холодный синий → стальной серый»). Плотность проекта: 128 px = 3,2 м
(40 px/м). Пишет только в Арт/Blender/castle/tex/.

    python Tools/castle_textures.py
"""
import os
import random

from PIL import Image

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(PROJECT, "Game", "CatsSoulDebt", "assets", "textures", "rubezh")
OUT = os.path.join(PROJECT, "Арт", "Blender", "castle", "tex")

# Множители каналов к исходной текстуре и контраст (1 — как есть; у скалы мельче рисунок, его крупно рисует геометрия).
VARIANTS = {
    "castle_rock.png": ("rubezh_rock_cliff.png", (1.08, 1.07, 1.18), 0.80),
    "castle_stone.png": ("rubezh_wall_brick.png", (1.05, 1.03, 1.10), 1.0),
    "castle_moss.png": ("rubezh_wall_mossy.png", (1.12, 1.10, 1.16), 1.0),
    "castle_trim.png": ("rubezh_wall_brick.png", (1.18, 1.16, 1.20), 1.0),
    "castle_recess.png": ("rubezh_wall_brick.png", (0.46, 0.50, 0.54), 1.0),
    "castle_floor.png": ("rubezh_floor_flagstone.png", (1.08, 1.06, 1.14), 0.8),
}


def tint(name, mult, contrast):
    im = Image.open(os.path.join(SRC, name)).convert("RGB")
    bands = []
    for b, m in zip(im.split(), mult):
        mean = sum(i * n for i, n in enumerate(b.histogram())) / (b.width * b.height)
        bands.append(b.point(lambda v, m=m, mean=mean, k=contrast: max(0, min(255, int((mean + (v - mean) * k) * m)))))
    return Image.merge("RGB", bands)


def slate(size=128, rows=8, cols=10, seed=5):
    """Сланцевая черепица: ряды со сдвигом, тёмные швы, разброс оттенка по плитке. Бесшовна."""
    rng = random.Random(seed)
    im = Image.new("RGB", (size, size), (24, 28, 34))
    px = im.load()
    rh, cw = size // rows, size // cols
    for r in range(rows):
        shift = (cw // 2) if r % 2 else 0
        tones = [rng.randint(-9, 9) for _ in range(cols)]
        for c in range(cols):
            base = 56 + tones[c]
            for y in range(rh - 1):
                for x in range(cw - 1):
                    v = base - y * 2 + rng.randint(-2, 2)
                    px[(c * cw + x + shift) % size, r * rh + y] = (v, v + 6, v + 13)
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    for out, (name, mult, contrast) in VARIANTS.items():
        tint(name, mult, contrast).save(os.path.join(OUT, out))
    slate().save(os.path.join(OUT, "castle_slate.png"))
    print("текстуры:", OUT)


if __name__ == "__main__":
    main()
