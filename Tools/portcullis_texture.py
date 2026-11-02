"""Сквозная решётка Рубежа (опускная, для дверей на ключ и сюжетных) из кованой текстуры rubezh_iron_grate.

Плитка 128×128 = 3,2 м (40 px/м, как остальные текстуры Рубежа): вертикальные прутья через 0,4 м,
поперечные полосы через 1,6 м; между ними — прозрачно (альфа-вырез в игре). Цвет и ржавчина прутьев
берутся из rubezh_iron_grate, края прутьев темнее — объём.
Запуск: python Tools/portcullis_texture.py → Game/CatsSoulDebt/assets/textures/rubezh/rubezh_portcullis.png
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "Game", "CatsSoulDebt", "assets", "textures", "rubezh")
SIZE = 128
BAR_STEP, BAR_W = 16, 4        # вертикальные прутья: 0,4 м шаг, 10 см толщина
RAIL_STEP, RAIL_W = 64, 5      # поперечины: 1,6 м шаг


def main():
    src = Image.open(os.path.join(TEX, "rubezh_iron_grate.png")).convert("RGB")
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px, sp = out.load(), src.load()
    for y in range(SIZE):
        for x in range(SIZE):
            bx, ry = x % BAR_STEP, y % RAIL_STEP
            on_bar, on_rail = bx < BAR_W, ry < RAIL_W
            if not (on_bar or on_rail):
                continue
            r, g, b = sp[x % src.width, y % src.height]
            # Край прута/полосы темнее середины — читается как круглый пруток.
            edge = (on_bar and bx in (0, BAR_W - 1) and not on_rail) or (on_rail and ry in (0, RAIL_W - 1) and not on_bar)
            k = 0.62 if edge else 1.0
            px[x, y] = (int(r * k), int(g * k), int(b * k), 255)
    path = os.path.join(TEX, "rubezh_portcullis.png")
    out.save(path)
    print("сохранено:", path)


if __name__ == "__main__":
    main()
