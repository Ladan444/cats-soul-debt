"""GIF из строки листа кадров — быстро посмотреть анимацию.

Пример:
  python Tools/sheet_gif.py "Арт/Обработано/ray_attack1_side_sheet.png" --cell-w 96 --row 0 --fps 10
"""

import argparse
from pathlib import Path

from PIL import Image

CELL_H = 64


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("sheet")
    p.add_argument("--cell-w", type=int, default=64)
    p.add_argument("--cell-h", type=int, default=CELL_H)
    p.add_argument("--row", type=int, default=0)
    p.add_argument("--fps", type=float, default=8.0)
    p.add_argument("--zoom", type=int, default=5)
    p.add_argument("--out", default="")
    a = p.parse_args()

    sheet = Image.open(a.sheet).convert("RGBA")
    frames = []
    for i in range(sheet.width // a.cell_w):
        cell = sheet.crop((i * a.cell_w, a.row * a.cell_h, (i + 1) * a.cell_w, (a.row + 1) * a.cell_h))
        if cell.getbbox() is None:  # пустые ячейки в конце строки
            break
        bg = Image.new("RGBA", cell.size, (80, 80, 92, 255))
        bg.alpha_composite(cell)
        frames.append(bg.convert("RGB").resize((a.cell_w * a.zoom, a.cell_h * a.zoom), Image.NEAREST))
    out = a.out or str(Path(a.sheet).with_name(f"{Path(a.sheet).stem}_row{a.row}.gif"))
    frames[0].save(out, save_all=True, append_images=frames[1:], duration=int(1000 / a.fps), loop=0)
    print(f"GIF: {out} ({len(frames)} кадров)")


if __name__ == "__main__":
    main()
