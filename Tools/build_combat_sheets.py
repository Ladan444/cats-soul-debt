"""Собирает игровые листы для боя из обработанного арта (Арт/Обработано) и кладёт их в игру.

Формат листа — как у DirectionalSprite: столбцы — кадры (4), строки — анимация × направление
(down, up, side; у существ с одним видом — одна строка на анимацию). Ступни — на линии cell_h - 4.

  Рэй, Вельмор, Лиара  96×80: idle, walk, run, dash, attack1, attack2, attack3
                       (ходьба 64×64 переносится в центр ячейки; удары есть только вбок —
                       вверх/вниз пока играют боковые, у Вельмора и Лиары вместо ударов idle)
  Утопший солдат       96×80: idle, walk, attack, death (ходьба и смерть — временные, из idle)
  Тварь Тихой Воды     96×64, один вид: idle, leap, hurt, death (вариант 2 по выбору автора)
  Чучело               64×64, один вид: idle (рисуется здесь же)

Запуск из корня проекта: python Tools/build_combat_sheets.py
"""
from __future__ import annotations

import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Арт" / "Обработано"
GAME = ROOT / "Game" / "CatsSoulDebt" / "assets" / "sprites"
COLS = 4


def cells(sheet: Image.Image, cw: int, ch: int) -> list[list[Image.Image]]:
    """Режет лист на строки кадров."""
    rows = []
    for y in range(sheet.height // ch):
        rows.append([sheet.crop((x * cw, y * ch, (x + 1) * cw, (y + 1) * ch)) for x in range(sheet.width // cw)])
    return rows


def pad(cell: Image.Image, cw: int, ch: int) -> Image.Image:
    """Переносит кадр в ячейку побольше: по центру по X, ступни остаются на 4 px выше низа."""
    out = Image.new("RGBA", (cw, ch))
    out.alpha_composite(cell.convert("RGBA"), ((cw - cell.width) // 2, ch - cell.height))
    return out


def shifted(cell: Image.Image, dx: int, dy: int) -> Image.Image:
    out = Image.new("RGBA", cell.size)
    out.paste(cell, (dx, dy), cell)
    return out


def row_of(frames: list[Image.Image]) -> list[Image.Image]:
    """Дополняет строку до 4 кадров повтором последнего (пустые хвосты листа — тоже кадры)."""
    frames = [f for f in frames]
    while len(frames) < COLS:
        frames.append(frames[-1])
    return frames[:COLS]


def save_sheet(rows: list[list[Image.Image]], cw: int, ch: int, out: Path) -> None:
    sheet = Image.new("RGBA", (cw * COLS, ch * len(rows)))
    for y, row in enumerate(rows):
        for x, frame in enumerate(row_of(row)):
            sheet.alpha_composite(frame, (x * cw, y * ch))
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"{out.relative_to(ROOT)}: {sheet.width}×{sheet.height}, строк {len(rows)}")


def dissolve(cell: Image.Image, steps: int = 4, seed: int = 7) -> list[Image.Image]:
    """Временная смерть: фигура рассыпается — пиксели гаснут, остаток оседает и уходит в фиолетовый."""
    rng = random.Random(seed)
    w, h = cell.size
    order = [(x, y) for y in range(h) for x in range(w) if cell.getpixel((x, y))[3] > 0]
    rng.shuffle(order)
    frames = []
    for i in range(steps):
        keep = 1.0 - (i + 1) / (steps + 0.5)
        f = Image.new("RGBA", (w, h))
        for x, y in order[: int(len(order) * keep)]:
            r, g, b, a = cell.getpixel((x, y))
            t = (i + 1) / steps * 0.6
            color = (int(r + (0x6a - r) * t), int(g + (0x3a - g) * t), int(b + (0xa8 - b) * t), a)
            ny = min(h - 4, y + (i + 1) * 2 * (y > h // 3))
            f.putpixel((x, ny), color)
        frames.append(f)
    return frames


# --- Рэй и облики ------------------------------------------------------------------

def humanoid(anim: Path, attacks: list[Path] | None, out: Path) -> None:
    base = cells(Image.open(anim).convert("RGBA"), 64, 64)
    rows: list[list[Image.Image]] = [[pad(c, 96, 80) for c in r] for r in base]  # 4 анимации × 3 вида
    if attacks:
        for a in attacks:
            side = cells(Image.open(a).convert("RGBA"), 96, 80)[0]
            rows += [side, side, side]  # down, up, side: вверх/вниз — пока боковой удар
    else:
        idle = rows[:3]
        for _ in range(3):
            rows += [r[:1] for r in idle]
    save_sheet(rows, 96, 80, out)


# --- Утопший солдат ----------------------------------------------------------------

def drowned() -> None:
    views = [pad(c, 96, 80) for c in cells(Image.open(SRC / "drowned_sheet.png").convert("RGBA"), 96, 64)[0]]
    attack = cells(Image.open(SRC / "drowned_attack_sheet.png").convert("RGBA"), 96, 80)  # down, up, side
    rows: list[list[Image.Image]] = []
    for v in views:  # idle: еле заметное «дыхание» — оседает на пиксель
        rows.append([v, v, shifted(v, 0, 1), shifted(v, 0, 1)])
    for v in views:  # walk (временно, до генерации): переваливается с ноги на ногу
        rows.append([shifted(v, 0, 1), shifted(v, 1, 0), shifted(v, 0, 1), shifted(v, -1, 0)])
    rows += attack[:3]
    for i, v in enumerate(views):
        rows.append(dissolve(v, seed=11 + i))
    save_sheet(rows, 96, 80, GAME / "drowned" / "drowned_combat.png")


# --- Тварь Тихой Воды (вариант 2) --------------------------------------------------

def lake_creature() -> None:
    # Исходный лист обработан ячейками 64×64 (кадры по 64 px) — режем так же и переносим в центр 96×64.
    # Резать сразу по 96 нельзя: кадры рассекаются пополам (так было до 2026-10-22).
    src = [[pad(c, 96, 64) for c in row[:4]] for row in cells(Image.open(SRC / "lake_creature_v2_sheet.png").convert("RGBA"), 64, 64)]
    hurt = src[2][:2]  # в хвосте строки урона — соринки от брызг, их не берём
    rows = [src[0], src[1], hurt, src[3]]
    save_sheet(rows, 96, 64, GAME / "lake_creature" / "lake_creature_combat.png")


# --- Тренировочное чучело -----------------------------------------------------------

DUMMY = [
    "..........XXXXXX..........",
    ".........XssssssX.........",
    "........XssSsssssX........",
    "........XsXssssXsX........",
    "........XssssssssX........",
    "........XsssXXsssX........",
    ".........XssssssX.........",
    "..........XrrrrX..........",
    "...XXXXXXXXwwwwXXXXXXXXX..",
    "..XwwwwwwwwWWWWwwwwwwwwwX.",
    "..XWWWWWWWWwwwwWWWWWWWWWX.",
    "...XXXXXXXXssssXXXXXXXXX..",
    ".......XsssssssssssX......",
    "......XsSssssssssSssX.....",
    "......XssssrrrrrssssX.....",
    "......XsssssssssssssX.....",
    "......XsSsssssssssSsX.....",
    "......XssssrrrrrssssX.....",
    "......XsssssssssssssX.....",
    ".......XssSsssssSssX......",
    "........XXXXwwwwXXXX......",
    "...........XwwwwX.........",
    "...........XwWWwX.........",
    "...........XwwwwX.........",
    "...........XwWWwX.........",
    "...........XwwwwX.........",
    "...........XwWWwX.........",
    "...........XwwwwX.........",
    "........XXXXwwwwXXXX......",
    ".......XwwwwwwwwwwwwX.....",
    ".......XXXXXXXXXXXXXX.....",
]
DUMMY_COLORS = {"X": "#2a1e18", "s": "#c8a860", "S": "#9a7a40", "r": "#7a2a24",
                "w": "#6b4a32", "W": "#4a3020"}


def dummy() -> None:
    w, h = max(len(r) for r in DUMMY), len(DUMMY)
    img = Image.new("RGBA", (w, h))
    for y, line in enumerate(DUMMY):
        for x, ch in enumerate(line):
            if ch in DUMMY_COLORS:
                c = DUMMY_COLORS[ch].lstrip("#")
                img.putpixel((x, y), (int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16), 255))
    cell = Image.new("RGBA", (64, 64))
    cell.alpha_composite(img, ((64 - w) // 2, 60 - h))
    save_sheet([[cell]], 64, 64, GAME / "dummy" / "dummy.png")


# --- Страж Перекрёстка (заглушка до генерации) ---------------------------------------

def guardian_placeholder() -> None:
    """Старый козёл в длинном сером плаще, с посохом и колокольчиком: простые формы + контур."""
    from PIL import ImageDraw
    img = Image.new("RGBA", (34, 56))
    d = ImageDraw.Draw(img)
    d.polygon([(10, 22), (22, 22), (27, 55), (4, 55)], fill="#3a3a40")            # плащ
    d.line([(10, 23), (5, 54)], fill="#55555c", width=1)                          # светлая кромка
    d.polygon([(12, 26), (20, 26), (19, 40), (13, 40)], fill="#2c2c32")            # тень под капюшоном
    d.line([(29, 14), (29, 55)], fill="#5a4030", width=2)                          # посох
    d.ellipse([(26, 26), (31, 31)], fill="#c9a040")                                # колокольчик
    d.ellipse([(25, 33), (30, 37)], fill="#b8b2a6")                                # рука на посохе
    d.ellipse([(11, 9), (21, 21)], fill="#b8b2a6")                                 # голова
    d.ellipse([(13, 15), (19, 25)], fill="#a8a296")                                # вытянутая морда
    d.polygon([(13, 23), (19, 23), (16, 33)], fill="#e6e2d8")                      # борода
    d.ellipse([(6, 13), (11, 16)], fill="#b8b2a6")                                 # уши в стороны
    d.ellipse([(21, 13), (26, 16)], fill="#b8b2a6")
    d.arc([(5, 1), (15, 13)], 120, 330, fill="#6a5a48", width=2)                   # рога, загнутые назад
    d.arc([(17, 1), (27, 13)], 210, 60, fill="#6a5a48", width=2)
    img.putpixel((14, 16), (200, 255, 176, 255))                                   # бледные глаза
    img.putpixel((18, 16), (200, 255, 176, 255))
    # Контур 1 px тёмным, как у остальных спрайтов.
    out = Image.new("RGBA", (img.width + 2, img.height + 2))
    for y in range(out.height):
        for x in range(out.width):
            if img.getpixel((x - 1, y - 1))[3] if 0 < x <= img.width and 0 < y <= img.height else 0:
                continue
            near = any(0 <= x - 1 + dx < img.width and 0 <= y - 1 + dy < img.height
                       and img.getpixel((x - 1 + dx, y - 1 + dy))[3] > 0
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if near:
                out.putpixel((x, y), (26, 22, 20, 255))
    out.alpha_composite(img, (1, 1))
    cell = Image.new("RGBA", (64, 64))
    cell.alpha_composite(out, ((64 - out.width) // 2, 60 - out.height + 1))
    save_sheet([[cell]], 64, 64, GAME / "guardian" / "guardian_placeholder.png")


if __name__ == "__main__":
    attacks = [SRC / f"ray_attack{i}_side_sheet.png" for i in (1, 2, 3)]
    humanoid(GAME / "ray" / "ray_anim.png", attacks, GAME / "ray" / "ray_combat.png")
    humanoid(GAME / "velmor" / "velmor_anim.png", None, GAME / "velmor" / "velmor_combat.png")
    humanoid(GAME / "liara" / "liara_anim.png", None, GAME / "liara" / "liara_combat.png")
    drowned()
    lake_creature()
    dummy()
    guardian_placeholder()
