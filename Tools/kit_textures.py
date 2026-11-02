"""Текстуры домов Quaternius Medieval Village MegaKit → пиксель-арт 40 пикселей на метр (решение автора).

Размеры — из Game/CatsSoulDebt/assets/textures/village_kit/kit.json (метров на единицу UV, пишет
Tools/blender/village_houses.py при сборке деревни). Уменьшение с учётом прозрачности, сведение к палитре
(медианное квантование), лёгкий тёплый сдвиг к палитре Брода — как у растительности (Tools/nature_textures.py).
Результат — assets/textures/village_kit/<текстура>.png, превью Арт/Обработано/kit_textures_preview.png.
Запуск: python Tools/kit_textures.py (после сборки деревни в Blender).
"""
import importlib.util
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Арт", "Ассеты", "Medieval Village MegaKit", "Medieval Village MegaKit[Standard]", "Textures")
OUT = os.path.join(ROOT, "Game", "CatsSoulDebt", "assets", "textures", "village_kit")
PREVIEW = os.path.join(ROOT, "Арт", "Обработано", "kit_textures_preview.png")
PX_PER_M = 40
COLORS = {"T_RoundTiles_BaseColor": 14, "T_VineLeaf": 8}
DEFAULT_COLORS = 16

_spec = importlib.util.spec_from_file_location("nt", os.path.join(ROOT, "Tools", "nature_textures.py"))
nt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(nt)


def main():
    with open(os.path.join(OUT, "kit.json"), encoding="utf-8") as f:
        info = json.load(f)["images"]
    tiles = []
    for name, spec in sorted(info.items()):
        src = os.path.join(SRC, name + ".png")
        im = Image.open(src)
        size = max(8, round(PX_PER_M * spec["meters_per_uv"]))
        small = nt.downscale(im, size)
        small = nt.quantize(nt.warm(small), COLORS.get(name, DEFAULT_COLORS))
        small.save(os.path.join(OUT, name + ".png"))
        tiles.append(small)
        print("%-28s %4d px (%.2f м на UV)" % (name, size, spec["meters_per_uv"]))
    cell = 200
    sheet = Image.new("RGBA", (cell * len(tiles), cell), (50, 50, 54, 255))
    for i, t in enumerate(tiles):
        sheet.alpha_composite(t.resize((cell - 8, cell - 8), Image.NEAREST), (i * cell + 4, 4))
    sheet.save(PREVIEW)


if __name__ == "__main__":
    main()
