"""Текстуры окружения из ИИ-генераций (Литература/TEXTURE_PROMPTS.md) → игровые пиксельные текстуры.

Бесшовные (стены, полы...): кадр делается бесшовным (смешивание со сдвинутой на полкадра копией по окну,
шов уходит в края), уменьшается до SIZE×SIZE и сводится к своей палитре (медианное квантование) —
пиксели остаются чёткими. 40 пикселей на метр, как у спрайтов: 128 пикселей = 3,2 м.
Отдельные картинки (дверь, знамёна): белый фон убирается заливкой от краёв, картинка уменьшается
до высоты предмета в метрах × 40.

Запуск из корня проекта: python Tools/texture_pipeline.py [rubezh] [village]  (без аргументов — все наборы)
Результат: Game/CatsSoulDebt/assets/textures/<набор>/<имя>.png и превью Арт/Обработано/textures_<набор>_preview.png.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Арт" / "Генерации" / "Текстуры"
OUT = ROOT / "Game" / "CatsSoulDebt" / "assets" / "textures" / "rubezh"
PX_PER_M = 40
SIZE = 128  # 3,2 м

# Наборы: бесшовные (имя → число цветов палитры) и отдельные (имя → высота предмета в метрах).
SETS = {
    "rubezh": {
        "tiles": {
            "rubezh_wall_brick": 24, "rubezh_wall_mossy": 28, "rubezh_floor_flagstone": 28, "rubezh_floor_cobble": 24,
            "rubezh_floor_crypt": 20, "rubezh_wood_planks": 20, "rubezh_stone_trim": 20, "rubezh_iron_grate": 24,
            "rubezh_rock_cliff": 28,
        },
        "sprites": {"rubezh_door_wood": 2.6, "rubezh_banner_lion": 3.0, "rubezh_banner_cat": 3.0},
    },
    # Ивовый Брод: генерации уже пиксельные и бесшовные (вариант 2 промптов) — склейку шва не делаем,
    # плитка 256 px = 6,4 м (при 128 пучки травы и камешки сливаются в шум).
    # Значение — (цветов, размер, вырезка): побелка вырезается ровно по периоду бруса (2×2 панели).
    "village": {
        "tiles": {
            "village_grass": (24, 256, None), "village_grass_dry": (24, 256, None),
            "village_dirt_road": (20, 256, None), "village_square_cobble": (24, 256, None),
            "village_field_soil": (16, 256, None), "village_rock": (28, 256, None),
            # Галька — мельче (плитка 2,4 м, камни ~30 см): в 6,4 м камни выходили размером с Рэя.
            "village_riverbed": (28, 96, None), "village_wall_stone": (24, 256, None),
            # Дно под водой — та же галька ещё вдвое мельче (плитка 1,2 м, камни ~15 см).
            "village_riverbed_small": (24, 48, None),
            "village_wall_plaster": (20, 128, (245, 245, 1005, 1005)),
            # Мост (вариант C) — по развёртке: тёсаный камень арок и бордюра, дерево перил (волокна вертикально).
            "village_stone_dressed": (16, 128, None), "village_wood_beam": (16, 128, None),
        },
        "sprites": {},
        "seamless": False,
    },
}
# Плитки из чужой генерации (вариант того же материала в другом размере).
SOURCES = {"village_riverbed_small": "village_riverbed"}
# Холодный камень (генерация в духе Рубежа) — в тёплый камень Брода: множители каналов.
WARM = {"village_wall_stone": (1.22, 1.06, 0.84)}


def find_source(name: str) -> Path:
    # Имя могло сохраниться с лишней точкой («rubezh_wall_brick..png»).
    for p in sorted(SRC.glob(name + "*.png")):
        return p
    raise FileNotFoundError(name)


def seam_error(a: np.ndarray) -> float:
    """Насколько края не совпадают (0 — идеально бесшовно)."""
    h = np.abs(a[:, 0].astype(float) - a[:, -1].astype(float)).mean()
    v = np.abs(a[0].astype(float) - a[-1].astype(float)).mean()
    return (h + v) / 2.0


def make_seamless(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    shifted = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    # Окно: 1 в центре кадра, 0 у краёв — там берётся сдвинутая копия, у которой края «из середины».
    wy = np.sin(np.linspace(0, np.pi, h)) ** 2
    wx = np.sin(np.linspace(0, np.pi, w)) ** 2
    win = np.minimum(1.0, np.outer(wy, wx) * 2.5)[..., None]
    out = a * win + shifted * (1.0 - win)
    return Image.fromarray(out.clip(0, 255).astype(np.uint8))


def quantize(img: Image.Image, colors: int) -> Image.Image:
    return img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")


def process_tile(name: str, colors: int, size: int = SIZE, crop=None, seamless: bool = True) -> Image.Image:
    src = Image.open(find_source(SOURCES.get(name, name))).convert("RGB")
    if crop:
        src = src.crop(crop)
    else:
        side = min(src.size)
        src = src.crop(((src.width - side) // 2, (src.height - side) // 2,
                        (src.width + side) // 2, (src.height + side) // 2))
    before = seam_error(np.asarray(src.resize((size, size), Image.BOX)))
    tile = make_seamless(src) if seamless and before > 6.0 else src
    small = tile.resize((size, size), Image.BOX)
    if name in WARM:
        a = np.asarray(small).astype(np.float32) * np.array(WARM[name], np.float32)
        small = Image.fromarray(a.clip(0, 255).astype(np.uint8))
    result = quantize(small, colors)
    print(f"{name}: шов до {before:.1f}, после {seam_error(np.asarray(result)):.1f}, цветов {colors}")
    return result


def remove_white(img: Image.Image) -> Image.Image:
    """Белый фон → прозрачность: заливка от краёв по почти-белым пикселям."""
    a = np.asarray(img.convert("RGBA")).copy()
    h, w = a.shape[:2]
    whiteish = (a[..., :3].min(axis=2) > 225)
    seen = np.zeros((h, w), bool)
    stack = [(y, x) for x in range(w) for y in (0, h - 1)] + [(y, x) for y in range(h) for x in (0, w - 1)]
    while stack:
        y, x = stack.pop()
        if seen[y, x] or not whiteish[y, x]:
            continue
        seen[y, x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx]:
                stack.append((ny, nx))
    a[seen, 3] = 0
    return Image.fromarray(a)


def process_sprite(name: str, meters: float) -> Image.Image:
    src = remove_white(Image.open(find_source(name)))
    box = src.getbbox()
    src = src.crop(box)
    target_h = int(round(meters * PX_PER_M))
    target_w = max(1, int(round(src.width * target_h / src.height)))
    # Уменьшение «по большинству»: сначала по цвету, затем альфа отдельно (без полупрозрачных краёв).
    rgb = quantize(src.convert("RGB").resize((target_w, target_h), Image.BOX), 24)
    alpha = src.getchannel("A").resize((target_w, target_h), Image.BOX).point(lambda v: 255 if v > 140 else 0)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    print(f"{name}: {target_w}×{target_h} ({meters} м)")
    return out


def main() -> None:
    names = sys.argv[1:] or list(SETS)
    for set_name in names:
        build_set(set_name, SETS[set_name])


def build_set(set_name: str, cfg: dict) -> None:
    TILES, SPRITES = cfg["tiles"], cfg["sprites"]
    out = OUT.parent / set_name
    out.mkdir(parents=True, exist_ok=True)
    results = {}
    for name, spec in TILES.items():
        colors, size, crop = spec if isinstance(spec, tuple) else (spec, SIZE, None)
        if not list(SRC.glob(SOURCES.get(name, name) + "*.png")):
            print(f"{name}: генерации ещё нет — пропуск")
            continue
        results[name] = process_tile(name, colors, size, crop, cfg.get("seamless", True))
        results[name].save(out / f"{name}.png")
    for name, meters in SPRITES.items():
        results[name] = process_sprite(name, meters)
        results[name].save(out / f"{name}.png")
    # Превью: каждая бесшовная плитка 2×2 (видны стыки), увеличено ×2.
    cell = SIZE * 2 * 2
    names = [n for n in list(TILES) + list(SPRITES) if n in results]
    cols = 4
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cell + 8), rows * (cell + 8)), (24, 24, 28))
    for i, name in enumerate(names):
        im = results[name]
        if name in TILES:
            s = im.width
            tiled = Image.new("RGB", (s * 2, s * 2))
            for dy in (0, s):
                for dx in (0, s):
                    tiled.paste(im, (dx, dy))
            view = tiled.resize((cell, cell), Image.NEAREST)
        else:
            scale = max(1, min(cell // im.width, cell // im.height))
            view = Image.new("RGB", (cell, cell), (60, 60, 70))
            big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
            view.paste(big, ((cell - big.width) // 2, (cell - big.height) // 2), big)
        sheet.paste(view, ((i % cols) * (cell + 8), (i // cols) * (cell + 8)))
    preview = ROOT / "Арт" / "Обработано" / f"textures_{set_name}_preview.png"
    sheet.save(preview)
    print("превью:", preview)


if __name__ == "__main__":
    main()
