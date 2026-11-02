"""Вставляет кадры (лист от sprite_pipeline.py) в нужную строку листа анимаций.

Раскладка листа анимаций — как в DirectionalSprite и make_placeholder_anim.py:
строки — анимация x направление (down, up, side), столбцы — кадры.

Пример (ходьба вбок):
  python Tools/set_anim_row.py "Арт/Обработано/ray_walk_side_sheet.png" "Арт/Обработано/ray_anim.png" --anim walk --dir side
"""

import argparse

import numpy as np
from PIL import Image

from make_placeholder_anim import ANIM_LAYOUT, CELL, COLUMNS, DIRECTIONS


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("frames", help="лист кадров 64xN от sprite_pipeline.py")
    parser.add_argument("anim_sheet", help="лист анимаций, который нужно обновить")
    parser.add_argument("--anim", required=True, choices=ANIM_LAYOUT)
    parser.add_argument("--dir", required=True, choices=DIRECTIONS)
    args = parser.parse_args()

    frames = np.asarray(Image.open(args.frames).convert("RGBA"))
    count = frames.shape[1] // CELL
    if count > COLUMNS:
        raise SystemExit(f"кадров {count}, а в строке листа помещается {COLUMNS}")

    sheet = np.array(Image.open(args.anim_sheet).convert("RGBA"))
    row = ANIM_LAYOUT.index(args.anim) * len(DIRECTIONS) + DIRECTIONS.index(args.dir)
    y = row * CELL
    sheet[y:y + CELL] = 0
    sheet[y:y + CELL, :count * CELL] = frames[:CELL, :count * CELL]
    Image.fromarray(sheet, "RGBA").save(args.anim_sheet)
    print(f"строка {row} ({args.anim}/{args.dir}): вставлено кадров {count}")


if __name__ == "__main__":
    main()
