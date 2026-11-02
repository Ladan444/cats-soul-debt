"""Превью персонажей: виды + ходьба вбок, плюс GIF ходьбы для каждого.

Пример:
  python Tools/preview_characters.py ray velmor liara
"""

import sys
from pathlib import Path

from PIL import Image

OUT = Path("Арт/Обработано")
CELL = 64
ZOOM = 5
BG = (80, 80, 90, 255)


def on_bg(img: Image.Image) -> Image.Image:
    bg = Image.new("RGBA", img.size, BG)
    bg.alpha_composite(img)
    return bg


def main() -> None:
    names = sys.argv[1:]
    rows = []
    for name in names:
        views = Image.open(OUT / f"{name}_sheet.png")
        walk = Image.open(OUT / f"{name}_walk_side_sheet.png")
        row = Image.new("RGBA", (CELL * 8, CELL), BG)
        row.alpha_composite(views, (0, 0))
        row.alpha_composite(walk, (CELL * 4, 0))
        rows.append(row)

        frames = [on_bg(walk.crop((i * CELL, 0, (i + 1) * CELL, CELL))).convert("RGB")
                  .resize((CELL * 6, CELL * 6), Image.NEAREST) for i in range(walk.width // CELL)]
        frames[0].save(OUT / f"{name}_walk_side.gif", save_all=True, append_images=frames[1:], duration=125, loop=0)

    sheet = Image.new("RGBA", (CELL * 8, CELL * len(rows)), BG)
    for i, row in enumerate(rows):
        sheet.alpha_composite(row, (0, i * CELL))
    path = OUT / "characters_preview.png"
    sheet.resize((sheet.width * ZOOM, sheet.height * ZOOM), Image.NEAREST).save(path)
    print(f"превью: {path}")


if __name__ == "__main__":
    main()
