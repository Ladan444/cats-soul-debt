"""Игровые листы из полос кадров генераций arena.ai (Арт/Генерации/sprites_final и sprites) — временный арт до художницы.

Жители и духи — idle 4×3 (дыхание из кадра «ноги вместе»). Враги, Лиара, Вельмор — листы DirectionalSprite.
Рэя не трогает.
Нет кадров — повтор: смерть есть только вбок, slam голема и throw вверх/вниз — из attack.

  python Tools/build_art_sheets.py
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_combat_sheets as combat

ROOT = Path(__file__).resolve().parent.parent
FINAL = ROOT / "Арт" / "Генерации" / "sprites_final"
GEN = ROOT / "Арт" / "Генерации" / "sprites"
GAME = ROOT / "Game" / "CatsSoulDebt" / "assets" / "sprites"
VIEWS = ("front", "back", "side")  # строки листа: down, up, side
STAND = 1  # кадр «ноги вместе»


def strip(name: str, cw: int) -> list[Image.Image]:
    path = FINAL / f"{name}.png"
    im = Image.open(path if path.exists() else GEN / f"{name}.png").convert("RGBA")
    return [im.crop((i * cw, 0, (i + 1) * cw, im.height)) for i in range(im.width // cw)][:4]


def fit(cell: Image.Image, cw: int, ch: int, label: str = "") -> Image.Image:
    """В ячейку другого размера: по центру по X, ступни остаются на 4 px выше низа."""
    box = cell.getbbox()
    if box and label and (box[2] - box[0] > cw or box[3] - box[1] > ch - 4):
        print(f"  не влезает в {cw}×{ch}: {label} {box}")
    out = Image.new("RGBA", (cw, ch))
    out.paste(cell, ((cw - cell.width) // 2, ch - cell.height))
    return out


def breathing(cell: Image.Image) -> list[Image.Image]:
    """Верх фигуры опускается на 1 px в кадрах 3–4, ноги стоят (как в villager_sheets.py)."""
    box = cell.getbbox()
    if not box:
        return [cell] * 4
    split = box[1] + int((box[3] - box[1]) * 0.55)
    low = cell.copy()
    low.paste((0, 0, 0, 0), (0, 0, cell.width, split))
    low.alpha_composite(cell.crop((0, 0, cell.width, split)), (0, 1))
    return [cell, cell, low, low]


def idle_sheet(who: str, out: Path) -> None:
    rows = [breathing(strip(f"{who}_walk_{v}", 64)[STAND]) for v in VIEWS]
    combat.save_sheet(rows, 64, 64, out)


def enemy_rows(who: str, cw: int, ch: int, walk_cw: int, attack_cw: int) -> dict[str, list[list[Image.Image]]]:
    conv = lambda frames, n: [fit(f, cw, ch, n) for f in frames]
    walk = [conv(strip(f"{who}_walk_{v}", walk_cw), f"{who} walk {v}") for v in VIEWS]
    attack = [conv(strip(f"{who}_attack_{v}", attack_cw), f"{who} attack {v}") for v in VIEWS]
    death = conv(strip(f"{who}_death_side", attack_cw), f"{who} death")
    return {"idle": [breathing(r[STAND]) for r in walk], "walk": walk, "attack": attack, "death": [death] * 3}


def drowned() -> None:
    r = enemy_rows("drowned", 96, 80, 64, 128)
    # Вид вверх: в полосе кадры идут «стойка, подъём, замах, удар» — игре нужно «замах, удар, удар, пауза».
    up = r["attack"][1]
    r["attack"][1] = [up[2], up[3], up[3], up[0]]
    # Вбок кадр 3 — та же стойка, но сдвинут на 9 px: при выходе из удара фигура прыгала. Берём стойку.
    r["attack"][2][3] = r["idle"][2][0]
    combat.save_sheet(r["idle"] + r["walk"] + r["attack"] + r["death"], 96, 80, GAME / "drowned" / "drowned_combat.png")


def kobold() -> None:
    r = enemy_rows("kobold", 64, 64, 64, 64)
    r["walk"][2] = strip("kobold_run_side", 64)  # по спецификации ходьба кобольда — быстрый бег
    combat.save_sheet(r["idle"] + r["walk"] + r["attack"] + r["death"], 64, 64, GAME / "kobold" / "kobold_combat.png")


def kvald() -> None:
    r = enemy_rows("kvald", 96, 80, 96, 96)
    r["attack"][2][3] = r["idle"][2][0]  # кадр 3 вбок — стойка со сдвигом 12 px, при выходе из укола фигура прыгала
    throw = r["attack"][:2] + [strip("kvald_throw_side", 96)]
    combat.save_sheet(r["idle"] + r["walk"] + r["attack"] + throw + r["death"], 96, 80, GAME / "kvald" / "kvald_combat.png")


def golem() -> None:
    r = enemy_rows("golem", 128, 112, 128, 128)
    throw = r["attack"][:2] + [strip("golem_throw_side", 128)]
    rows = r["idle"] + r["walk"] + r["attack"] + r["attack"] + throw + r["death"]
    combat.save_sheet(rows, 128, 112, GAME / "mine_golem" / "mine_golem_combat.png")


def lake_creature() -> None:
    conv = lambda frames, n: [fit(f, 96, 64, n) for f in frames]
    walk = conv(strip("lake_creature_walk_front", 64), "lake walk")
    # полосы атаки и смерти 128×80: ступни на y=76, fit сохраняет их на y=60
    attack = conv(strip("lake_creature_attack_front", 128), "lake attack")
    death = conv(strip("lake_creature_death_side", 128), "lake death")
    combat.save_sheet([walk, attack, walk[:2], death], 96, 64, GAME / "lake_creature" / "lake_creature_combat.png")


def humanoid(who: str) -> None:
    """Лиара и Вельмор: run и dash — пока та же ходьба; удары у них не используются."""
    walk = [strip(f"{who}_walk_{v}", 64) for v in VIEWS]
    rows = [breathing(r[STAND]) for r in walk] + walk + walk + walk
    anim = GAME / who / f"{who}_anim.png"
    combat.save_sheet(rows, 64, 64, anim)
    combat.humanoid(anim, None, GAME / who / f"{who}_combat.png")


def main() -> None:
    for who in ("horst", "marta", "ilza", "hans", "oda", "klaus", "mika", "silvia", "agata", "larp"):
        idle_sheet(who, GAME / "villagers" / f"{who}.png")
    idle_sheet("guide", GAME / "spirits" / "guide.png")
    idle_sheet("spirit", GAME / "spirits" / "spirit.png")
    drowned()
    kobold()
    kvald()
    golem()
    lake_creature()
    humanoid("liara")
    humanoid("velmor")


if __name__ == "__main__":
    main()
