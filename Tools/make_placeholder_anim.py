"""Собирает временный лист анимаций из статичного листа трёх видов.

Вход: лист от sprite_pipeline.py (кадры 64x64: вниз, вверх, вправо).
Выход: лист анимаций в формате игры (см. ANIM_LAYOUT ниже и directional_sprite.gd):
строки — анимация x направление, столбцы — кадры (до 4).

Анимации делаются сдвигом частей спрайта: тело покачивается, ноги шагают.
Это заглушка до настоящих кадров — формат листа тот же.

Пример:
  python Tools/make_placeholder_anim.py "Арт/Обработано/ray_sheet.png" --palette ray --out "Арт/Обработано/ray_anim.png"
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

CELL = 64
COLUMNS = 4
DIRECTIONS = ("down", "up", "side")
# Порядок строк листа: для каждой анимации — три направления подряд.
ANIM_LAYOUT = ("idle", "walk", "run", "dash")
LEG_FRACTION = 0.3  # нижняя доля фигуры, которая считается ногами


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def neighbours_transparent(opaque: np.ndarray) -> np.ndarray:
    padded = np.pad(opaque, 1)
    return ~(padded[:-2, 1:-1] & padded[2:, 1:-1] & padded[1:-1, :-2] & padded[1:-1, 2:])


def strip_outline(cell: np.ndarray, outline: tuple[int, int, int]) -> np.ndarray:
    """Убирает внешний контур, чтобы после сдвига частей нарисовать его заново."""
    opaque = cell[..., 3] > 0
    is_outline = np.all(cell[..., :3] == outline, axis=-1) & opaque
    out = cell.copy()
    out[is_outline & neighbours_transparent(opaque)] = 0
    return out


def add_outline(cell: np.ndarray, outline: tuple[int, int, int]) -> np.ndarray:
    opaque = cell[..., 3] > 0
    padded = np.pad(opaque, 1)
    grown = padded[:-2, 1:-1] | padded[2:, 1:-1] | padded[1:-1, :-2] | padded[1:-1, 2:]
    out = cell.copy()
    out[grown & ~opaque] = (*outline, 255)
    return out


def shift(layer: np.ndarray, dx: int, dy: int) -> np.ndarray:
    out = np.zeros_like(layer)
    h, w = layer.shape[:2]
    src = layer[max(-dy, 0):h - max(dy, 0), max(-dx, 0):w - max(dx, 0)]
    out[max(dy, 0):max(dy, 0) + src.shape[0], max(dx, 0):max(dx, 0) + src.shape[1]] = src
    return out


def over(base: np.ndarray, top: np.ndarray) -> np.ndarray:
    out = base.copy()
    mask = top[..., 3] > 0
    out[mask] = top[mask]
    return out


class Figure:
    """Спрайт одного направления, разрезанный на тело и левую/правую ногу."""

    def __init__(self, cell: np.ndarray):
        self.cell = cell
        rows = np.where((cell[..., 3] > 0).any(axis=1))[0]
        cols = np.where((cell[..., 3] > 0).any(axis=0))[0]
        top, bottom = rows[0], rows[-1] + 1
        self.leg_top = bottom - int(round((bottom - top) * LEG_FRACTION))
        self.center_x = (cols[0] + cols[-1] + 1) // 2

        body = cell.copy()
        body[self.leg_top:] = 0
        legs = cell.copy()
        legs[:self.leg_top] = 0
        self.body = body
        self.leg_left = legs.copy()
        self.leg_left[:, self.center_x:] = 0
        self.leg_right = legs.copy()
        self.leg_right[:, :self.center_x] = 0

    def pose(self, body_dy=0, left=(0, 0), right=(0, 0)) -> np.ndarray:
        frame = np.zeros_like(self.cell)
        frame = over(frame, shift(self.leg_left, *left))
        frame = over(frame, shift(self.leg_right, *right))
        # Если тело поднято, тянем верхний ряд ног вверх, чтобы не было щели на поясе.
        for k in range(1, -body_dy + 1):
            hip = np.zeros_like(self.cell)
            hip[self.leg_top] = self.cell[self.leg_top]
            frame = over(frame, shift(hip, 0, -k))
        return over(frame, shift(self.body, 0, body_dy))


def frames_for(fig: Figure, anim: str, direction: str) -> list[np.ndarray]:
    side = direction == "side"
    if anim == "idle":
        # Вдох-выдох: тело опускается на пиксель и возвращается.
        return [fig.pose(), fig.pose(body_dy=1), fig.pose(body_dy=1), fig.pose()]
    if anim in ("walk", "run"):
        a = 1 if anim == "walk" else 2
        if side:
            # Сбоку ноги расходятся вперёд-назад.
            step_a = fig.pose(left=(-a, 0), right=(a, 0))
            step_b = fig.pose(left=(a, 0), right=(-a, 0))
        else:
            # Спереди и сзади поочерёдно поднимается одна нога.
            step_a = fig.pose(left=(0, -a))
            step_b = fig.pose(right=(0, -a))
        passing = fig.pose(body_dy=-1 if anim == "walk" else -2)
        return [step_a, passing, step_b, passing]
    if anim == "dash":
        # Низкая стойка в рывке.
        if side:
            return [fig.pose(body_dy=1, left=(-2, 0), right=(2, 0))]
        return [fig.pose(body_dy=1, left=(-1, 0), right=(1, 0))]
    raise ValueError(anim)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("--palette", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    palettes = json.loads((Path(__file__).parent / "palettes.json").read_text(encoding="utf-8"))
    outline = hex_to_rgb(palettes[args.palette]["outline"])

    sheet = np.asarray(Image.open(args.input).convert("RGBA"))
    figures = {d: Figure(strip_outline(sheet[:, i * CELL:(i + 1) * CELL], outline))
               for i, d in enumerate(DIRECTIONS)}

    rows = []
    for anim in ANIM_LAYOUT:
        for direction in DIRECTIONS:
            frames = [add_outline(f, outline) for f in frames_for(figures[direction], anim, direction)]
            frames += [np.zeros((CELL, CELL, 4), dtype=np.uint8)] * (COLUMNS - len(frames))
            rows.append(np.concatenate(frames, axis=1))

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.concatenate(rows, axis=0), "RGBA").save(out)
    print(f"сохранено: {out} ({len(rows)} строк x {COLUMNS} кадров)")


if __name__ == "__main__":
    main()
