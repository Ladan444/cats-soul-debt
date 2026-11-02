"""Временные спрайты новых врагов (до арта по SPRITE_SPECS): кобольд «Крыс», квалд, голем-шахтёр.

Лист для DirectionalSprite (directions = 3): столбцы — 4 кадра, строки — анимация x вид (вниз, вверх, вбок).
Порядок анимаций должен совпадать со списком в скрипте врага (scripts/combat/<враг>.gd).
Результат — Game/CatsSoulDebt/assets/sprites/<враг>/<враг>_combat.png.

  python Tools/enemy_placeholders.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent / "Game" / "CatsSoulDebt" / "assets" / "sprites"
OUTLINE = (30, 22, 20, 255)
VIEWS = ("down", "up", "side")


def c(rgb, k=1.0):
    return tuple(max(0, min(255, int(v * k))) for v in rgb[:3]) + (255,)


def box(d, x0, y0, x1, y1, fill):
    d.rectangle([min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)], fill=fill, outline=OUTLINE)


def oval(d, x0, y0, x1, y1, fill):
    d.ellipse([min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)], fill=fill, outline=OUTLINE)


def line(d, p0, p1, fill, w=2):
    d.line([p0, p1], fill=OUTLINE, width=w + 2)
    d.line([p0, p1], fill=fill, width=w)


# --- Позы ----------------------------------------------------------------------------------
# Кадр анимации -> (покачивание, шаг лап, положение оружия 0..1 — замах/удар, наклон при смерти 0..1).

def pose(anim: str, f: int) -> dict:
    p = {"bob": 0, "step": 0, "arm": 0.0, "fall": 0.0, "throw": 0.0, "slam": 0.0}
    if anim == "idle":
        p["bob"] = (0, -1, -1, 0)[f]
    elif anim == "walk":
        p["step"] = (-2, 0, 2, 0)[f]
        p["bob"] = (0, -1, 0, -1)[f]
    elif anim == "attack":
        p["arm"] = (-1.0, 1.0, 0.8, 0.3)[f]
    elif anim == "throw":
        p["throw"] = (-1.0, 1.0, 0.6, 0.2)[f]
    elif anim == "slam":
        p["slam"] = (0.6, 1.0, -1.0, -0.4)[f]
        p["bob"] = (-2, -4, 3, 1)[f]
    elif anim == "death":
        p["fall"] = (0.15, 0.45, 0.8, 1.0)[f]
    return p


# --- Кобольд «Крыс» (банда «Рыжие упыри»): рыжий, длинная морда, острые уши, хвост, нож ---------

def kobold(d, ox, oy, view, p, W, H):
    fur, belly, cloth, blade = (196, 98, 46), (232, 178, 128), (88, 70, 60), (200, 204, 210)
    feet = oy + H - 5
    h = int(36 * (1 - 0.55 * p["fall"]))
    top = feet - h + p["bob"]
    cx = ox + W // 2 + int(p["fall"] * 8)
    side = view == "side"
    # Хвост.
    if view != "down" or side:
        tx = cx - (12 if side else 0)
        line(d, (tx, feet - 10), (tx - (8 if side else 6), feet - 2), c(fur, 0.8), 2)
    # Лапы и тело (короткая куртка).
    box(d, cx - 6 + p["step"], feet - 4, cx - 2 + p["step"], feet, c(fur, 0.7))
    box(d, cx + 2 - p["step"], feet - 4, cx + 6 - p["step"], feet, c(fur, 0.7))
    d.polygon([(cx - 8, top + 14), (cx + 8, top + 14), (cx + 9, feet - 4), (cx - 9, feet - 4)], fill=c(cloth), outline=OUTLINE)
    if view == "down":
        box(d, cx - 4, top + 16, cx + 4, feet - 6, c(belly, 0.9))
    # Голова: вид сбоку — вытянутая морда вперёд.
    if side:
        oval(d, cx - 7, top + 1, cx + 6, top + 14, c(fur))
        d.polygon([(cx + 4, top + 6), (cx + 13, top + 9), (cx + 4, top + 12)], fill=c(fur), outline=OUTLINE)
        d.point((cx + 13, top + 9), fill=OUTLINE)
        d.polygon([(cx - 4, top + 3), (cx - 2, top - 6), (cx + 2, top + 2)], fill=c(fur), outline=OUTLINE)
        d.rectangle([cx + 3, top + 6, cx + 4, top + 7], fill=(240, 200, 60, 255))
    else:
        oval(d, cx - 8, top + 1, cx + 8, top + 15, c(fur))
        for s in (-1, 1):
            d.polygon([(cx + s * 7, top + 5), (cx + s * 8, top - 6), (cx + s * 2, top + 2)], fill=c(fur), outline=OUTLINE)
        if view == "down":
            oval(d, cx - 4, top + 8, cx + 4, top + 15, c(belly))
            d.point((cx, top + 10), fill=OUTLINE)
            d.rectangle([cx - 5, top + 6, cx - 4, top + 7], fill=(240, 200, 60, 255))
            d.rectangle([cx + 4, top + 6, cx + 5, top + 7], fill=(240, 200, 60, 255))
    # Нож: замах назад (-1) -> выпад вперёд (1).
    a = p["arm"]
    if side:
        hx, hy = cx + 4 + int(a * 7), top + 18
        line(d, (hx, hy), (hx + 6 + int(a * 3), hy - 2 + int(a * 2)), c(blade), 1)
        box(d, hx - 2, hy - 1, hx + 1, hy + 2, c(fur))
    elif view == "down":
        hx, hy = cx + 9, top + 18 - int(a * 3)
        box(d, hx - 1, hy - 1, hx + 2, hy + 2, c(fur))
        line(d, (hx + 1, hy), (hx + 1, hy + 6 + int(a * 4)), c(blade), 1)
    else:
        box(d, cx + 8, top + 17, cx + 11, top + 20, c(fur))


# --- Квалд: зелёная лягушка, глаза на макушке, копьё и круглый щит -------------------------

def kvald(d, ox, oy, view, p, W, H):
    skin, belly, wood, metal, shield = (88, 134, 70), (196, 204, 140), (120, 86, 52), (176, 180, 186), (132, 96, 58)
    feet = oy + H - 5
    h = int(44 * (1 - 0.6 * p["fall"]))
    top = feet - h + p["bob"]
    cx = ox + W // 2 + int(p["fall"] * 10)
    side = view == "side"
    # Широкие лапы.
    box(d, cx - 12 + p["step"], feet - 4, cx - 4 + p["step"], feet, c(skin, 0.75))
    box(d, cx + 4 - p["step"], feet - 4, cx + 12 - p["step"], feet, c(skin, 0.75))
    # Тело-груша.
    oval(d, cx - 13, top + 14, cx + 13, feet - 2, c(skin))
    if view == "down":
        oval(d, cx - 8, top + 20, cx + 8, feet - 5, c(belly))
    # Голова — широкая, глаза-бугры сверху.
    oval(d, cx - 14, top + 4, cx + 14, top + 20, c(skin))
    for s in ((-1, 1) if not side else (1,)):
        ex = cx + s * 8 if not side else cx + 5
        oval(d, ex - 4, top, ex + 4, top + 8, c(skin))
        if view != "up":
            d.rectangle([ex - 1, top + 3, ex + 1, top + 5], fill=(20, 20, 16, 255))
    if view == "down":
        d.line([(cx - 8, top + 15), (cx + 8, top + 15)], fill=OUTLINE)
    # Копьё: замах (-1) — назад, удар (1) — вперёд; бросок грязи — комок в лапе.
    a = p["arm"]
    t = p["throw"]
    if side:
        sx = cx + 6 + int(a * 10)
        line(d, (sx - 14, top + 26), (sx + 16, top + 22), c(wood), 2)
        d.polygon([(sx + 16, top + 19), (sx + 23, top + 22), (sx + 16, top + 25)], fill=c(metal), outline=OUTLINE)
        if t:
            mx, my = cx - 6 - int(t * 4), top + 14 - int(t * 8)
            oval(d, mx - 3, my - 3, mx + 3, my + 3, c((92, 70, 44)))
        # Щит — круг на ближней стороне.
        oval(d, cx - 10, top + 18, cx + 4, feet - 6, c(shield))
        d.point((cx - 3, top + 26), fill=c(metal))
    else:
        sx = cx + 16
        line(d, (sx, top + 4 - int(a * 4)), (sx, feet - 2), c(wood), 2)
        d.polygon([(sx - 3, top + 4 - int(a * 4)), (sx, top - 4 - int(a * 4)), (sx + 3, top + 4 - int(a * 4))], fill=c(metal), outline=OUTLINE)
        if view == "down":
            oval(d, cx - 22, top + 18, cx - 6, feet - 6, c(shield))
            oval(d, cx - 16, top + 26, cx - 12, top + 30, c(metal))
            if t:
                mx, my = cx + 10, top + 12 - int(t * 8)
                oval(d, mx - 3, my - 3, mx + 3, my + 3, c((92, 70, 44)))
        else:
            box(d, cx - 20, top + 18, cx - 17, feet - 8, c(shield, 0.8))


# --- Голем-шахтёр: заколдованный баран — серая шерсть, каменные наросты с фиолетовыми рунами, рога, кайло

def golem(d, ox, oy, view, p, W, H):
    wool, stone, horn, rune, wood, metal = (150, 144, 134), (104, 104, 112), (196, 176, 136), (170, 110, 240), (110, 80, 50), (150, 154, 160)
    feet = oy + H - 6
    h = int(70 * (1 - 0.6 * p["fall"]))
    top = feet - h + p["bob"]
    cx = ox + W // 2 + int(p["fall"] * 14)
    side = view == "side"
    box(d, cx - 16 + p["step"], feet - 8, cx - 6 + p["step"], feet, c(stone, 0.8))
    box(d, cx + 6 - p["step"], feet - 8, cx + 16 - p["step"], feet, c(stone, 0.8))
    # Массивное тело: шерсть + каменные плиты.
    oval(d, cx - 24, top + 20, cx + 24, feet - 6, c(wool))
    box(d, cx - 18, top + 26, cx - 4, top + 40, c(stone))
    box(d, cx + 4, top + 34, cx + 18, top + 48, c(stone))
    d.line([(cx - 14, top + 30), (cx - 8, top + 36)], fill=c(rune), width=2)
    d.line([(cx + 8, top + 38), (cx + 14, top + 44)], fill=c(rune), width=2)
    # Голова барана с закрученными рогами.
    hx = cx + (8 if side else 0)
    oval(d, hx - 11, top + 4, hx + 11, top + 24, c(wool, 0.9))
    for s in ((-1, 1) if not side else (-1,)):
        rx = hx + s * 12
        oval(d, rx - 7, top + 2, rx + 7, top + 16, c(horn))
        oval(d, rx - 3, top + 6, rx + 3, top + 12, c(horn, 0.8))
    if view == "down":
        d.rectangle([hx - 6, top + 12, hx - 4, top + 14], fill=c(rune))
        d.rectangle([hx + 4, top + 12, hx + 6, top + 14], fill=c(rune))
    elif side:
        d.rectangle([hx + 5, top + 12, hx + 7, top + 14], fill=c(rune))
    # Кайло: замах вверх (-1) -> удар вниз-вперёд (1). Удар по земле — обе лапы вверх, потом вниз.
    a = p["arm"] if p["arm"] else p["slam"]
    t = p["throw"]
    if t:
        # Валун над головой (-1 — поднят, дальше — летит вперёд).
        bx, by = cx + int(max(t, 0) * 14), top - 6 + int(max(t, 0) * 16)
        oval(d, bx - 10, by - 9, bx + 10, by + 9, c(stone, 0.9))
    else:
        px = cx + (20 if not side else 22)
        py = top + 22 + int(a * 18)
        line(d, (px - 6, py + 18), (px, py), c(wood), 3)
        d.polygon([(px - 10, py - 2), (px + 10, py - 6), (px + 10, py - 2), (px - 10, py + 2)], fill=c(metal), outline=OUTLINE)


ENEMIES = {
    # id: (функция, ячейка W x H, анимации — порядок как в скрипте врага)
    "kobold": (kobold, 64, 64, ["idle", "walk", "attack", "death"]),
    "kvald": (kvald, 96, 80, ["idle", "walk", "attack", "throw", "death"]),
    "mine_golem": (golem, 128, 112, ["idle", "walk", "attack", "slam", "throw", "death"]),
}


def build(name: str) -> Path:
    fn, W, H, anims = ENEMIES[name]
    sheet = Image.new("RGBA", (W * 4, H * len(anims) * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(sheet)
    for ai, anim in enumerate(anims):
        for vi, view in enumerate(VIEWS):
            for f in range(4):
                fn(d, f * W, (ai * 3 + vi) * H, view, pose(anim, f), W, H)
    out = ROOT / name / f"{name}_combat.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return out


if __name__ == "__main__":
    for n in ENEMIES:
        print(build(n))
