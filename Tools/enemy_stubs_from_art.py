"""Заглушки врагов и NPC из концептов автора (Арт/Генерации/Враги/<id>.webp, три вида в ряд, белый фон).
Виды вырезаются, масштабируются «по большинству» (BOX + палитра 28 цветов), вид вбок смотрит ВПРАВО (влево — отражение в игре).
Анимации — сдвиги, наклон и падение целого вида вокруг ступней (пока нет настоящих кадров от художницы).
Враги -> Game/CatsSoulDebt/assets/sprites/<id>/<id>_combat.png (формат как у Tools/enemy_placeholders.py);
NPC (silvia, fling) -> assets/sprites/villagers/<id>.png (idle 4x3, ячейка 64).

  python Tools/enemy_stubs_from_art.py [id ...]
"""

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Арт" / "Генерации" / "Враги"
SPR = ROOT / "Game" / "CatsSoulDebt" / "assets" / "sprites"

# id: (рост всего вида с рогами/копьём, вид вбок смотрит влево в исходнике?, ячейка W, H, анимации)
ENEMIES = {
    "kobold": (38, True, 64, 64, ["idle", "walk", "attack", "death"]),
    "kvald": (54, False, 96, 80, ["idle", "walk", "attack", "throw", "death"]),
    "mine_golem": (70, False, 128, 112, ["idle", "walk", "attack", "slam", "throw", "death"]),
}
NPCS = {"silvia": (52, True), "fling": (40, False)}
FEET_GAP = 4


def load_views(vid: str, height: int, flip_side: bool) -> list[Image.Image]:
    im = Image.open(SRC / f"{vid}.webp").convert("RGB")
    m = Image.new("RGB", im.size, (255, 0, 255))
    ImageDraw.floodfill(im, (0, 0), (255, 0, 255), thresh=40)
    ImageDraw.floodfill(im, (im.width - 1, im.height - 1), (255, 0, 255), thresh=40)
    a = np.asarray(im).astype(int)
    alpha = ~((a[..., 0] > 240) & (a[..., 1] < 20) & (a[..., 2] > 240))
    alpha &= ~((a.min(axis=2) > 245))          # остатки белого фона
    cols = alpha.any(axis=0)
    xs = np.where(cols)[0]
    groups, start = [], xs[0]
    for p, q in zip(xs, xs[1:]):
        if q - p > im.width * 0.012:
            groups.append((start, p))
            start = q
    groups.append((start, xs[-1]))
    while len(groups) > 3:                     # склеить самые близкие
        gaps = [groups[i + 1][0] - groups[i][1] for i in range(len(groups) - 1)]
        i = int(np.argmin(gaps))
        groups[i:i + 2] = [(groups[i][0], groups[i + 1][1])]
    if len(groups) < 3:                        # виды соприкасаются — резать по самым пустым столбцам у третей
        cnt = alpha.sum(axis=0)
        lo, hi = xs[0], xs[-1] + 1
        cuts = [lo]
        for k in (1, 2):
            mid, span = lo + (hi - lo) * k // 3, int((hi - lo) * 0.08)
            cuts.append(int(mid - span + np.argmin(cnt[mid - span:mid + span])))
        cuts.append(hi)
        groups = [(cuts[i], cuts[i + 1] - 1) for i in range(3)]
    rgba = np.dstack([np.asarray(Image.open(SRC / f"{vid}.webp").convert("RGB")), alpha.astype(np.uint8) * 255])
    full = Image.fromarray(rgba.astype(np.uint8), "RGBA")
    rows = np.where(alpha.any(axis=1))[0]
    y0, y1 = rows.min(), rows.max() + 1
    crops = []
    for x0, x1 in groups:
        sub = alpha[:, x0:x1 + 1]
        r = np.where(sub.any(axis=1))[0]
        crops.append(full.crop((x0, r.min(), x1 + 1, r.max() + 1)))
    scale = height / crops[0].height
    out = []
    for i, cr in enumerate(crops):
        w, h = max(1, round(cr.width * scale)), max(1, round(cr.height * scale))
        rgb = cr.convert("RGB").resize((w, h), Image.BOX)
        al = cr.getchannel("A").resize((w, h), Image.BOX).point(lambda v: 255 if v >= 110 else 0)
        q = rgb.quantize(28, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGBA")
        q.putalpha(al)
        if i == 2 and flip_side:
            q = q.transpose(Image.FLIP_LEFT_RIGHT)
        out.append(q)
    return out


def place(view: Image.Image, W: int, H: int, dx=0, dy=0, angle=0.0, squash=1.0, fade=1.0) -> Image.Image:
    if squash != 1.0:
        view = view.resize((view.width, max(1, round(view.height * squash))), Image.NEAREST)
    cell = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    feet = H - FEET_GAP
    cell.alpha_composite(view, ((W - view.width) // 2, feet - view.height))
    if angle:
        cell = cell.rotate(angle, resample=Image.NEAREST, center=(W // 2, feet))
    if dx or dy:
        shifted = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        shifted.alpha_composite(cell, (dx, dy))
        cell = shifted
    if fade < 1.0:
        cell.putalpha(cell.getchannel("A").point(lambda v: int(v * fade)))
    return cell


def frame(anim: str, view: int, f: int) -> dict:
    """view: 0 вниз, 1 вверх, 2 вбок (вправо). Угол > 0 — против часовой (назад для вида вбок)."""
    side = view == 2
    toward = (1, -1, 1)[view]                  # куда «вперёд»: вниз к зрителю (+y), вверх от него (-y), вбок +x
    p = dict(dx=0, dy=0, angle=0.0, squash=1.0, fade=1.0)
    if anim == "idle":
        p["dy"] = (0, -1, -1, 0)[f]
    elif anim == "walk":
        p["dy"] = (0, -1, 0, -1)[f]
        p["angle"] = (-3, 0, 3, 0)[f]
    elif anim in ("attack", "throw"):
        k = (-1.0, 1.0, 0.8, 0.2)[f]
        if side:
            p["dx"], p["angle"] = round(k * 5), -k * 8
        else:
            p["dy"] = round(k * 3 * toward)
            p["squash"] = 1.0 - 0.04 * max(k, 0)
    elif anim == "slam":
        k = (0.6, 1.0, -1.0, -0.4)[f]
        p["dy"] = (-3, -7, 2, 0)[f]
        p["squash"] = (1.0, 1.04, 0.9, 0.97)[f]
        if side:
            p["angle"] = -k * 6
    elif anim == "death":
        p["angle"] = (8, 30, 62, 88)[f] * (1 if side or view == 0 else -1)
        p["dy"] = (0, 0, 2, 3)[f]
        p["fade"] = (1, 1, 1, 0.85)[f]
    return p


def build_enemy(vid: str) -> Path:
    height, flip, W, H, anims = ENEMIES[vid]
    views = load_views(vid, height, flip)
    sheet = Image.new("RGBA", (W * 4, H * len(anims) * 3), (0, 0, 0, 0))
    for ai, anim in enumerate(anims):
        for vi in range(3):
            for f in range(4):
                sheet.alpha_composite(place(views[vi], W, H, **frame(anim, vi, f)), (f * W, (ai * 3 + vi) * H))
    out = SPR / vid / f"{vid}_combat.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return out


def build_npc(vid: str) -> Path:
    height, flip = NPCS[vid]
    views = load_views(vid, height, flip)
    sheet = Image.new("RGBA", (256, 192), (0, 0, 0, 0))
    for vi in range(3):
        for f in range(4):
            sheet.alpha_composite(place(views[vi], 64, 64, dy=0), (f * 64, vi * 64))
    out = SPR / "villagers" / f"{vid}.png"
    sheet.save(out)
    return out


if __name__ == "__main__":
    ids = sys.argv[1:] or list(ENEMIES) + list(NPCS)
    for v in ids:
        print(build_enemy(v) if v in ENEMIES else build_npc(v))
