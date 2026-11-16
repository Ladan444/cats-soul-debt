"""Игровые листы из полос кадров генераций arena.ai (Арт/Генерации/sprites_final и sprites) — временный арт до художницы.

Жители и духи — idle 4×3 (дыхание из кадра «ноги вместе»). Враги, Лиара, Вельмор — листы DirectionalSprite.
Рэй: только удары вниз и вверх (ray()); покой, ходьба, бег, рывок и удары вбок остаются из build_combat_sheets.py.
Нет кадров — повтор: смерть есть только вбок, slam голема и throw вверх/вниз — из attack.

  python Tools/build_art_sheets.py
"""
from __future__ import annotations

import sys
from collections import Counter
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


def _ray_palette(sheet: Image.Image) -> list[tuple[int, int, int]]:
    """Цвета Рэя в игре: покой, ходьба и бег (строки 0–8)."""
    counts = Counter(p[:3] for p in sheet.crop((0, 0, 96 * 4, 80 * 9)).get_flattened_data() if p[3] > 200)
    return [c for c, _ in counts.most_common(48)]


def _to_palette(cell: Image.Image, palette: list[tuple[int, int, int]], gain: float = 1.18) -> Image.Image:
    """Кадры генерации темнее и серее покоя: чуть светлее и к ближайшему цвету Рэя."""
    out = cell.copy()
    px = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            q = (min(255, int(r * gain)), min(255, int(g * gain)), min(255, int(b * gain)))
            px[x, y] = min(palette, key=lambda c: (c[0] - q[0]) ** 2 * 2 + (c[1] - q[1]) ** 2 * 4 + (c[2] - q[2]) ** 2) + (255,)
    return out


def _fur_of_head(cell: Image.Image) -> set[tuple[int, int]]:
    """Шерсть головы: связные светлые пиксели от центра морды, без клинка и росчерка."""
    px = cell.load()
    light = lambda x, y: px[x, y][3] > 200 and sum(px[x, y][:3]) >= 3 * 165
    seed = next((x, y) for y in range(34, 46) for x in range(40, 56) if light(x, y))
    seen, stack = {seed}, [seed]
    while stack:
        x, y = stack.pop()
        for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= q[0] < cell.width and 20 <= q[1] < 54 and q not in seen and light(*q):
                seen.add(q)
                stack.append(q)
    return seen


def _with_ray_head(cell: Image.Image, idle: Image.Image) -> Image.Image:
    """Вид вниз: голова из покоя. В кадрах удара она шире, глаза серые, уши без розового (замечание автора)."""
    top, chin_idle = 31, 47  # строки покоя: верх ушей и подбородок
    fur = _fur_of_head(cell)
    rows: dict[int, list[int]] = {}
    for x, y in fur:
        rows.setdefault(y, []).append(x)
    first, chin = min(rows), max(rows)
    xs = sorted(p[0] for p in fur)
    center = (xs[len(xs) // 10] + xs[-len(xs) // 10 - 1]) // 2
    out = cell.copy()
    px = out.load()

    def span(y: int, near: tuple[int, ...]) -> tuple[int, int] | None:
        used = [rows[y + d] for d in near if y + d in rows]
        return (min(map(min, used)), max(map(max, used))) if used else None

    for y in range(first - 3, chin + 2):  # своя голова с контуром
        sp = span(y, (0, 1, 2, -1, -2))
        if sp:
            for x in range(max(sp[0] - 2, 0), min(sp[1] + 3, out.width)):
                px[x, y] = (0, 0, 0, 0)
    for y in range(first - 4, chin - 3):  # обрывки контура: стираем только тёмное, клинок рядом светлый
        sp = span(y, (0, 1, 2, 3, 4))
        if sp:
            for x in range(max(sp[0] - 6, 0), min(sp[1] + 7, out.width)):
                if px[x, y][3] > 0 and sum(px[x, y][:3]) < 3 * 70:
                    px[x, y] = (0, 0, 0, 0)
    head = idle.crop((0, top, 96, chin_idle + 2))
    box = head.getbbox()
    head = head.crop(box)
    out.alpha_composite(head, (center - head.width // 2, chin - (chin_idle - top - box[1])))
    return out


def ray() -> None:
    """Удары вниз и вверх на все три удара комбо (одна полоса; третий идёт медленнее — тайминг в player.gd).
    Полоса вбок (ray_attack_side) не годится: Рэй на ней не похож на себя (автор), там остаются удары из игры."""
    path = GAME / "ray" / "ray_combat.png"
    sheet = Image.open(path).convert("RGBA")
    palette = _ray_palette(sheet)
    idle = sheet.crop((0, 0, 96, 80))

    def cells(name: str) -> list[Image.Image]:
        # Полоса 128×80 → ячейка 96×80; ступни на 1 px ниже, как в покое (y = 77).
        out = []
        for f in strip(name, 128):
            c = Image.new("RGBA", (96, 80))
            c.paste(f.crop((16, 0, 112, 79)), (0, 1))
            out.append(_to_palette(c, palette))
        return out

    down = [_with_ray_head(c, idle) for c in cells("ray_attack_front")]
    up = cells("ray_attack_back")
    # Строки: 4 анимации × 3 вида, затем attack1–3 × (вниз, вверх, вбок).
    for attack in range(3):
        row = 12 + attack * 3
        for view, frames in ((0, down), (1, up)):
            sheet.paste((0, 0, 0, 0), (0, (row + view) * 80, 96 * 4, (row + view + 1) * 80))
            for i, c in enumerate(frames):
                sheet.alpha_composite(c, (i * 96, (row + view) * 80))
    sheet.save(path)
    print(f"{path}: удары вниз и вверх обновлены")


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
    ray()


if __name__ == "__main__":
    main()
