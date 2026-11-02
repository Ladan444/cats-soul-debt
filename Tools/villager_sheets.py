"""Игровые листы жителей из обработанных генераций (Арт/Обработано/villager_<id>_sheet.png от sprite_pipeline.py):
4 кадра idle × 3 вида (вниз, вверх, вбок), ячейка 64. Дыхание — верх фигуры (голова, плечи) опускается на 1 px
в кадрах 3–4, ноги стоят. Результат — Game/CatsSoulDebt/assets/sprites/villagers/<id>.png (вместо заглушек).

  python Tools/villager_sheets.py [id ...]

Режим «готовые кадры художника» (Арт/Художник/<id>/frame_NN.png, 48×48, без масштабирования): ARTIST[<id>] — номера
кадров для видов down/up/side (4 кадра; если кадр один — дыхание как выше). Кадр кладётся пиксель в пиксель в центр
ячейки 64, ступни на строке 60 (как у остальных жителей).

  python Tools/villager_sheets.py --artist ilza
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Арт" / "Обработано"
OUT = ROOT / "Game" / "CatsSoulDebt" / "assets" / "sprites" / "villagers"
ARTIST = {"ilza": {"down": [12], "up": [11], "side": [1, 2, 3, 4]}}
IDS = ["horst", "marta", "ilza", "hans", "oda", "klaus", "mika"]


def build(vid: str) -> None:
    src = np.asarray(Image.open(SRC / f"villager_{vid}_sheet.png").convert("RGBA"))
    sheet = np.zeros((192, 256, 4), np.uint8)
    for view in range(3):
        cell = src[:, view * 64:(view + 1) * 64]
        rows = np.where(cell[..., 3].any(axis=1))[0]
        split = rows.min() + int((rows.max() - rows.min()) * 0.55)
        for f, dy in enumerate((0, 0, 1, 1)):
            c = cell.copy()
            if dy:
                upper = cell[:split]
                c[:split] = 0
                mask = upper[..., 3] > 0
                c[1:split + 1][mask] = upper[mask]
            sheet[view * 64:(view + 1) * 64, f * 64:(f + 1) * 64] = c
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(sheet).save(OUT / f"{vid}.png")
    print("готово:", vid)


def breathe(cell: np.ndarray, f: int) -> np.ndarray:
    rows = np.where(cell[..., 3].any(axis=1))[0]
    split = rows.min() + int((rows.max() - rows.min()) * 0.55)
    c = cell.copy()
    if f >= 2:
        upper = cell[:split]
        c[:split] = 0
        mask = upper[..., 3] > 0
        c[1:split + 1][mask] = upper[mask]
    return c


def build_artist(vid: str) -> None:
    folder = ROOT / "Арт" / "Художник" / vid
    sheet = np.zeros((192, 256, 4), np.uint8)
    for view, name in enumerate(("down", "up", "side")):
        nums = ARTIST[vid][name]
        for f in range(4):
            fr = np.asarray(Image.open(folder / f"frame_{nums[f % len(nums)]:02d}.png").convert("RGBA"))
            rows = np.where(fr[..., 3].any(axis=1))[0]
            cell = np.zeros((64, 64, 4), np.uint8)
            cell[60 - rows.max():60 - rows.max() + 48, 8:56] = fr
            if len(nums) == 1:
                cell = breathe(cell, f)
            sheet[view * 64:(view + 1) * 64, f * 64:(f + 1) * 64] = cell
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray(sheet).save(OUT / f"{vid}.png")
    print("готово (художник):", vid)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--artist"]:
        for vid in sys.argv[2:] or ARTIST:
            build_artist(vid)
    else:
        for vid in sys.argv[1:] or IDS:
            build(vid)
