"""Дорисовать клинок поверх кадров листа: у генераций тонкий нож при уменьшении до 36–48 px пропадает.

  python Tools/sprite_blade.py <лист.png> <ячейка 64x64> "<кадр>:x0,y0,x1,y1" [...] [--width 2]
Координаты — внутри ячейки кадра: x0,y0 — кулак (рукоять), x1,y1 — кончик. Лезвие светлое, с тёмной обводкой.
"""
import argparse
from PIL import Image, ImageDraw

STEEL = (214, 220, 226, 255)
EDGE = (40, 34, 44, 255)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("sheet")
    p.add_argument("cell")
    p.add_argument("blades", nargs="+")
    p.add_argument("--width", type=int, default=2)
    a = p.parse_args()
    cw, ch = (int(v) for v in a.cell.split("x"))
    img = Image.open(a.sheet).convert("RGBA")
    d = ImageDraw.Draw(img)
    for spec in a.blades:
        frame, coords = spec.split(":")
        ox = int(frame) * cw
        x0, y0, x1, y1 = (int(v) for v in coords.split(","))
        line = [(ox + x0, y0), (ox + x1, y1)]
        d.line(line, fill=EDGE, width=a.width + 2)
        d.line(line, fill=STEEL, width=a.width)
    img.save(a.sheet)


if __name__ == "__main__":
    main()
