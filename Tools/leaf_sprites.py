"""Пиксельные листья и мелочь для частиц окружения (падающие листья, пух, лепестки) — рисуются кодом.

Решение автора: листья по образцу скана осенних листьев, но в нашем пикселе и палитре Брода.
Атлас — Game/CatsSoulDebt/assets/textures/vfx/leaves.png: ячейки 16×16, строки — формы, столбцы — окраска
(зелёный, жёлто-зелёный, жёлтый, оранжевый, красный, бурый). Последняя строка — пух, лепестки, искра.
Превью ×6 — Арт/Обработано/leaves_preview.png.
Запуск: python Tools/leaf_sprites.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Game", "CatsSoulDebt", "assets", "textures", "vfx", "leaves.png")
PREVIEW = os.path.join(ROOT, "Арт", "Обработано", "leaves_preview.png")
CELL = 16

# Формы: «#» — лист, «|» — прожилка/черешок (светлее), «.» — пусто. Контур добавляется сам (тёмный край).
SHAPES = {
    "maple": [
        "....#......#....",
        "....##..#..##...",
        ".....###.###....",
        ".#...###.###..#.",
        ".##.#########.##",
        "..######|#####..",
        "...#####|####...",
        ".######.|.#####.",
        "..######|######.",
        "....####|####...",
        "......##|##.....",
        "........|.......",
        "........|.......",
    ],
    "oak": [
        "......##......",
        ".....####.....",
        "....##|###....",
        ".....#|##.....",
        "...###|####...",
        "....##|###....",
        "..####|#####..",
        "...###|####...",
        "....##|###....",
        "...###|####...",
        ".....#|##.....",
        "......|.......",
        "......|.......",
    ],
    "birch": [
        ".....#.....",
        "....###....",
        "...##|##...",
        "..###|###..",
        ".####|####.",
        ".####|####.",
        "..###|###..",
        "...##|##...",
        "....#|#....",
        ".....|.....",
        ".....|.....",
    ],
    "willow": [
        "..#..",
        "..#..",
        ".###.",
        ".#|#.",
        ".#|#.",
        ".#|#.",
        ".#|#.",
        ".#|#.",
        ".#|#.",
        "..|..",
        "..#..",
    ],
    "round": [
        "..####..",
        ".######.",
        "###|####",
        "###|####",
        "####|###",
        ".###|##.",
        "..##|#..",
        "....|...",
    ],
    "ash": [
        "......#......",
        ".#...###...#.",
        "###..#|#..###",
        ".###.#|#.###.",
        "..##.#|#.##..",
        ".#####|#####.",
        "..##..|..##..",
        "......|......",
        "......|......",
    ],
}
# Окраски: (контур, тень, основной, свет) — экранные цвета, палитра Брода (тёплый → насыщенный зелёный).
TINTS = [
    ((38, 62, 26), (62, 104, 40), (92, 142, 52), (140, 186, 74)),       # зелёный
    ((60, 70, 24), (110, 128, 40), (156, 170, 56), (204, 210, 96)),     # жёлто-зелёный
    ((96, 66, 18), (176, 128, 30), (226, 178, 48), (250, 222, 118)),    # жёлтый
    ((98, 42, 16), (178, 80, 28), (222, 124, 44), (248, 176, 88)),      # оранжевый
    ((82, 22, 18), (150, 40, 30), (196, 62, 40), (232, 112, 72)),       # красный
    ((58, 38, 24), (98, 66, 42), (132, 92, 58), (170, 128, 86)),        # бурый (сухой)
]


def draw_leaf(shape, tint):
    outline, shade, base, light = tint
    h, w = len(shape), max(len(r) for r in shape)
    grid = [r.ljust(w, ".") for r in shape]
    img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    ox, oy = (CELL - w) // 2, (CELL - h) // 2
    px = img.load()
    filled = {(x, y) for y in range(h) for x in range(w) if grid[y][x] != "."}
    for x, y in filled:
        c = grid[y][x]
        edge = any((x + dx, y + dy) not in filled for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if c == "|":
            col = light if (x, y - 1) in filled or (x, y + 1) in filled else outline
            # Черешок под листом — тёмный.
            if not any((x + dx, y) in filled and grid[y][x + dx] == "#" for dx in (-1, 1)):
                col = shade
        elif edge:
            col = outline
        elif (x + y) % 5 == 0 or x < w // 2 - 1 and y > h // 2:
            col = shade
        else:
            col = base
        px[ox + x, oy + y] = (*col, 255)
    return img


def draw_small():
    """Пух одуванчика, два лепестка (белый и розовый), пыльца/искра (2×2), мотылёк-блик."""
    cells = []
    fluff = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    p = fluff.load()
    for x, y in ((7, 6), (6, 7), (8, 7), (7, 8), (7, 7)):
        p[x, y] = (250, 248, 236, 255)
    for x, y in ((5, 5), (9, 5), (5, 9), (9, 9)):
        p[x, y] = (226, 222, 206, 255)
    p[7, 9], p[7, 10] = (190, 180, 150, 255), (150, 140, 110, 255)
    cells.append(fluff)
    for col in ((250, 246, 236), (240, 172, 190)):
        petal = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        p = petal.load()
        for x, y in ((7, 6), (6, 7), (7, 7), (8, 7), (7, 8), (6, 8), (8, 8), (7, 9)):
            p[x, y] = (*col, 255)
        p[7, 9] = tuple(int(v * 0.8) for v in col) + (255,)
        cells.append(petal)
    spark = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    p = spark.load()
    for x, y in ((7, 7), (8, 7), (7, 8), (8, 8)):
        p[x, y] = (255, 236, 170, 255)
    cells.append(spark)
    return cells


def draw_butterfly():
    """Бабочка — 2 кадра взмаха (крылья раскрыты / сложены), белая: цвет даёт частица."""
    open_w = ["#.....#", "##...##", "###.###", ".##|##.", "..#|#..", ".##.##."]
    shut_w = ["..#.#..", "..#.#..", "..###..", "...|...", "..#|#..", "...#..."]
    img = Image.new("RGBA", (16, 8), (0, 0, 0, 0))
    p = img.load()
    for off, shape in ((0, open_w), (8, shut_w)):
        for y, row in enumerate(shape):
            for x, c in enumerate(row):
                if c == "#":
                    p[off + x, y + 1] = (250, 250, 244, 255)
                elif c == "|":
                    p[off + x, y + 1] = (60, 50, 40, 255)
    return img


def draw_lilypad():
    """Текстура кувшинок 32×16: слева лист, справа лист с цветком (развёртку задаёт nature_pack.py)."""
    img = Image.new("RGBA", (32, 16), (0, 0, 0, 0))
    p = img.load()
    dark, base, light = (36, 78, 40), (62, 116, 52), (100, 152, 70)
    for half in (0, 16):
        for y in range(16):
            for x in range(16):
                dx, dy = x - 7.5, y - 7.5
                d = (dx * dx + dy * dy) ** 0.5
                if d > 7.6:
                    continue
                col = dark if d > 6.6 else (light if (x + y) % 4 == 0 and d < 5 else base)
                if abs(dx) < 0.6 and dy > 0:      # прожилка к вырезу
                    col = dark
                p[half + x, y] = (*col, 255)
    for x, y, c in ((23, 6, (250, 244, 236)), (24, 6, (250, 244, 236)), (22, 7, (240, 200, 210)),
                    (25, 7, (240, 200, 210)), (23, 7, (250, 220, 120)), (24, 7, (250, 220, 120)),
                    (23, 8, (250, 244, 236)), (24, 8, (250, 244, 236)), (23, 5, (240, 200, 210))):
        p[x, y] = (*c, 255)
    return img


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    lily = os.path.join(ROOT, "Game", "CatsSoulDebt", "assets", "models", "nature", "textures", "LilyPad.png")
    os.makedirs(os.path.dirname(lily), exist_ok=True)
    draw_lilypad().save(lily)
    rows = len(SHAPES) + 1
    atlas = Image.new("RGBA", (CELL * len(TINTS), CELL * rows), (0, 0, 0, 0))
    for r, shape in enumerate(SHAPES.values()):
        for c, tint in enumerate(TINTS):
            atlas.alpha_composite(draw_leaf(shape, tint), (c * CELL, r * CELL))
    for c, img in enumerate(draw_small()):
        atlas.alpha_composite(img, (c * CELL, len(SHAPES) * CELL))
    atlas.save(OUT)
    # Полосы кадров для частиц (кадр выбирается случайно): летние листья и мелочь (пух, лепестки, пыльца).
    summer = [(s, t) for s in ("oak", "birch", "round", "willow", "ash", "maple") for t in (0, 1)]
    summer += [("birch", 2), ("round", 2), ("willow", 2), ("oak", 5)]
    strip = Image.new("RGBA", (CELL * len(summer), CELL), (0, 0, 0, 0))
    for i, (s, t) in enumerate(summer):
        strip.alpha_composite(draw_leaf(SHAPES[s], TINTS[t]), (i * CELL, 0))
    strip.save(OUT.replace("leaves.png", "leaves_summer.png"))
    small = draw_small()
    strip = Image.new("RGBA", (CELL * len(small), CELL), (0, 0, 0, 0))
    for i, img in enumerate(small):
        strip.alpha_composite(img, (i * CELL, 0))
    strip.save(OUT.replace("leaves.png", "fluff.png"))
    draw_butterfly().save(OUT.replace("leaves.png", "butterfly.png"))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    bg = Image.new("RGBA", atlas.size, (40, 44, 40, 255))
    bg.alpha_composite(atlas)
    bg.resize((atlas.width * 6, atlas.height * 6), Image.NEAREST).save(PREVIEW)
    print("атлас:", OUT, atlas.size)


if __name__ == "__main__":
    main()
