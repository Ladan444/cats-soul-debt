"""Текстуры пака растительности → пиксель-арт 40 пикселей на метр.

Источник — Арт/Ассеты/Nature Pack/textures/ (их вынимает Tools/blender/nature_pack.py),
размеры — из Game/CatsSoulDebt/assets/models/nature/pack.json (плотность текселей моделей).
Результат — assets/models/nature/textures/<имя>.png и превью Арт/Обработано/nature_textures_preview.png.

- Уменьшение с учётом прозрачности (цвет усредняется только по непрозрачным пикселям), альфа — порог 50 %.
- Цвета сводятся к нескольким (медианное квантование), лёгкий тёплый сдвиг к палитре Брода.
- Камни пака почти чёрные с зелёными пятнами — перекрашиваются по яркости в тёплый серо-бурый камень Брода;
  листва ив (её нет в паке, source — листва обычного дерева) — в серебристо-зелёный.
Запуск: python Tools/nature_textures.py
"""
import json
import os

from PIL import Image, ImageEnhance

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Арт", "Ассеты", "Nature Pack", "textures")
GAME = os.path.join(ROOT, "Game", "CatsSoulDebt", "assets", "models", "nature")
OUT = os.path.join(GAME, "textures")
PREVIEW = os.path.join(ROOT, "Арт", "Обработано", "nature_textures_preview.png")

COLORS = {"Rocks": 6, "Grass": 5}
DEFAULT_COLORS = 6
# Камень Брода (экранные цвета), от тени к свету.
ROCK_RAMP = [(70, 64, 58), (98, 90, 80), (124, 115, 102), (150, 140, 124), (176, 166, 148)]
# Листва ивы — серебристо-зелёная (из листвы обычного дерева).
WILLOW_RAMP = [(70, 104, 62), (98, 134, 80), (128, 160, 100), (160, 186, 126)]
# Тростник (из травы пака) — оливково-соломенный.
REED_RAMP = [(70, 78, 34), (104, 110, 46), (142, 138, 62), (182, 168, 92)]
RAMPS = {"Rocks": ROCK_RAMP, "WillowTree_Leaves": WILLOW_RAMP, "Reed": REED_RAMP}


def downscale(im, size):
    """Блочное усреднение с учётом альфы: прозрачные пиксели не «пачкают» край листа."""
    im = im.convert("RGBA")
    r, g, b, a = im.split()
    pre = Image.merge("RGB", [Image.composite(c, Image.new("L", im.size, 0), a) for c in (r, g, b)])
    # Премультиплицированный цвет и альфа — одним и тем же фильтром.
    small_rgb = pre.resize((size, size), Image.BOX)
    small_a = a.resize((size, size), Image.BOX)
    px = small_rgb.load()
    pa = small_a.load()
    out = Image.new("RGBA", (size, size))
    po = out.load()
    for y in range(size):
        for x in range(size):
            al = pa[x, y]
            if al < 128:
                po[x, y] = (0, 0, 0, 0)
                continue
            cr, cg, cb = px[x, y]
            k = 255.0 / al
            po[x, y] = (min(255, int(cr * k)), min(255, int(cg * k)), min(255, int(cb * k)), 255)
    return out


def quantize(im, colors):
    """Сведение к colors цветам; прозрачные пиксели не участвуют."""
    rgb = im.convert("RGB")
    a = im.getchannel("A")
    q = rgb.quantize(colors=colors, method=Image.Quantize.MEDIANCUT).convert("RGB")
    out = q.convert("RGBA")
    out.putalpha(a)
    return out


def warm(im):
    """Лёгкий сдвиг к уютной палитре Брода: чуть насыщеннее и теплее."""
    a = im.getchannel("A")
    rgb = ImageEnhance.Color(im.convert("RGB")).enhance(1.12)
    r, g, b = rgb.split()
    r = r.point(lambda v: min(255, int(v * 1.04)))
    b = b.point(lambda v: int(v * 0.94))
    out = Image.merge("RGB", (r, g, b)).convert("RGBA")
    out.putalpha(a)
    return out


def recolor(im, ramp):
    """Перекраска по яркости (с растяжкой по непрозрачным пикселям) в ступени ramp; альфа сохраняется."""
    gray = im.convert("L")
    alpha = im.getchannel("A")
    lo, hi = _extrema(gray, alpha)
    span = max(1, hi - lo)
    n = len(ramp)
    out = Image.new("RGBA", im.size)
    src, al, dst = gray.load(), alpha.load(), out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            t = (src[x, y] - lo) / span
            dst[x, y] = (*ramp[max(0, min(n - 1, int(t * n)))], al[x, y])
    return out


def _extrema(gray, alpha):
    vals = [g for g, a in zip(gray.get_flattened_data(), alpha.get_flattened_data()) if a >= 128]
    return (min(vals), max(vals)) if vals else (0, 255)


def main():
    with open(os.path.join(GAME, "pack.json"), encoding="utf-8") as f:
        images = json.load(f)["images"]
    os.makedirs(OUT, exist_ok=True)
    tiles = []
    for name, info in sorted(images.items()):
        if info.get("generated"):
            continue   # рисуется кодом (Tools/leaf_sprites.py)
        src = os.path.join(SRC, info.get("source", name) + ".png")
        size = int(info["px"])
        im = downscale(Image.open(src), size)
        if name in RAMPS:
            im = recolor(im, RAMPS[name])
        else:
            im = quantize(warm(im), COLORS.get(name, DEFAULT_COLORS))
        im.save(os.path.join(OUT, name + ".png"))
        tiles.append((name, im))
        print("%-20s %4d px" % (name, size))
    # Превью: каждая текстура увеличена до 128 px, на сером.
    cell = 136
    sheet = Image.new("RGBA", (cell * len(tiles), cell), (60, 60, 64, 255))
    for i, (_, im) in enumerate(tiles):
        big = im.resize((128, 128), Image.NEAREST)
        sheet.alpha_composite(big, (i * cell + 4, 4))
    os.makedirs(os.path.dirname(PREVIEW), exist_ok=True)
    sheet.save(PREVIEW)


if __name__ == "__main__":
    main()
