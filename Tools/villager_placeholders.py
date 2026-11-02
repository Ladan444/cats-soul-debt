"""Временные спрайты жителей Ивового Брода (до арта художников): простой пиксельный зверь в одежде.

Лист для Npc/DirectionalSprite: ячейка 64x64, 4 кадра idle (покачивание), 3 строки — вид спереди, сзади, сбоку.
Результат — Game/CatsSoulDebt/assets/sprites/villagers/<id>.png.

  python Tools/villager_placeholders.py
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "Game" / "CatsSoulDebt" / "assets" / "sprites" / "villagers"
CELL = 64
OUTLINE = (30, 22, 20, 255)

# id: (мех, светлое пятно морды, одежда, уши: "round" / "point" / "small" / "droop", рост 0..1, полоса на морде)
VILLAGERS = {
    "horst": ((96, 92, 88), (225, 222, 214), (92, 62, 40), "small", 0.95, True),     # барсук, кожаный фартук
    "marta": ((120, 92, 66), (214, 190, 160), (126, 58, 52), "spines", 0.78, False),  # ежиха, клетчатая шаль
    "ilza": ((150, 150, 158), (208, 206, 210), (112, 120, 136), "point", 0.86, False),  # серая кошка, полинявшее платье
    "hans": ((128, 86, 54), (176, 136, 98), (190, 180, 160), "small", 1.0, False),   # бобр, фартук в муке
    "oda": ((112, 96, 78), (186, 168, 140), (70, 66, 58), "small", 0.9, False),      # выдра, просмолённый плащ
    "klaus": ((150, 140, 124), (206, 198, 184), (84, 98, 72), "droop", 0.98, False),   # пёс-овчар, безрукавка
}


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (255,)


def figure(d: ImageDraw.ImageDraw, ox: int, oy: int, spec, view: str, bob: int) -> None:
    fur, light, cloth, ears, height, stripe = spec
    fur4, light4, cloth4 = shade(fur, 1), shade(light, 1), shade(cloth, 1)
    feet_y = oy + 59
    h = int(40 * height)
    top = feet_y - h + bob
    # Тело — одежда (трапеция), лапы.
    body_top = top + 15
    d.polygon([(ox + 24, body_top), (ox + 40, body_top), (ox + 43, feet_y - 3), (ox + 21, feet_y - 3)], fill=cloth4, outline=OUTLINE)
    d.rectangle([ox + 24, feet_y - 3, ox + 29, feet_y], fill=shade(fur, 0.7), outline=OUTLINE)
    d.rectangle([ox + 35, feet_y - 3, ox + 40, feet_y], fill=shade(fur, 0.7), outline=OUTLINE)
    # Руки.
    d.rectangle([ox + 19, body_top + 3, ox + 23, body_top + 14], fill=fur4, outline=OUTLINE)
    d.rectangle([ox + 41, body_top + 3, ox + 45, body_top + 14], fill=fur4, outline=OUTLINE)
    # Уши.
    hx0, hx1 = ox + 22, ox + 42
    if ears == "point":
        d.polygon([(hx0 + 1, top + 4), (hx0 + 3, top - 5), (hx0 + 8, top + 2)], fill=fur4, outline=OUTLINE)
        d.polygon([(hx1 - 1, top + 4), (hx1 - 3, top - 5), (hx1 - 8, top + 2)], fill=fur4, outline=OUTLINE)
    elif ears == "droop":
        d.ellipse([hx0 - 4, top + 2, hx0 + 4, top + 13], fill=shade(fur, 0.8), outline=OUTLINE)
        d.ellipse([hx1 - 4, top + 2, hx1 + 4, top + 13], fill=shade(fur, 0.8), outline=OUTLINE)
    elif ears == "spines":
        for k in range(6):
            x = hx0 - 2 + k * 5
            d.polygon([(x, top + 6), (x + 2, top - 4 + (k % 2) * 2), (x + 5, top + 6)], fill=shade(fur, 0.75), outline=OUTLINE)
    else:
        d.ellipse([hx0, top - 1, hx0 + 6, top + 5], fill=fur4, outline=OUTLINE)
        d.ellipse([hx1 - 6, top - 1, hx1, top + 5], fill=fur4, outline=OUTLINE)
    # Голова.
    d.ellipse([hx0, top + 1, hx1, top + 18], fill=fur4, outline=OUTLINE)
    if view == "down":
        d.ellipse([ox + 27, top + 9, ox + 37, top + 17], fill=light4)
        if stripe:
            d.rectangle([ox + 31, top + 2, ox + 33, top + 10], fill=light4)
        d.rectangle([ox + 27, top + 8, ox + 28, top + 9], fill=OUTLINE)
        d.rectangle([ox + 36, top + 8, ox + 37, top + 9], fill=OUTLINE)
        d.rectangle([ox + 31, top + 12, ox + 33, top + 13], fill=OUTLINE)
    elif view == "side":
        d.ellipse([ox + 36, top + 8, ox + 45, top + 16], fill=light4, outline=OUTLINE)
        d.rectangle([ox + 36, top + 7, ox + 37, top + 8], fill=OUTLINE)
        d.rectangle([ox + 44, top + 11, ox + 45, top + 12], fill=OUTLINE)
    else:  # сзади — затылок, без морды
        d.arc([hx0 + 3, top + 4, hx1 - 3, top + 16], 200, 340, fill=shade(fur, 0.8))


def spirit_figure(d: ImageDraw.ImageDraw, ox: int, oy: int, kind: str, view: str, bob: int) -> None:
    """Проводник (сова в капюшоне с фонарём) и призрак у фонаря (чёрный плащ, маска-череп барана)."""
    feet = oy + 59
    top = feet - 42 + bob
    if kind == "guide":
        cloak, hood, face = (92, 78, 66, 255), (70, 58, 50, 255), (236, 228, 214, 255)
    else:
        cloak, hood, face = (28, 24, 30, 255), (40, 34, 42, 255), (226, 220, 204, 255)
    # Плащ — колокол до земли.
    d.polygon([(ox + 24, top + 14), (ox + 40, top + 14), (ox + 46, feet), (ox + 18, feet)], fill=cloak, outline=OUTLINE)
    # Капюшон/голова.
    d.ellipse([ox + 21, top, ox + 43, top + 20], fill=hood, outline=OUTLINE)
    if kind == "guide":
        if view != "up":
            d.ellipse([ox + 26, top + 4, ox + 38, top + 17], fill=face)            # лицевой диск сипухи
            d.rectangle([ox + 29, top + 9, ox + 30, top + 10], fill=OUTLINE)
            d.rectangle([ox + 34, top + 9, ox + 35, top + 10], fill=OUTLINE)
        # Фонарь в лапе: латунь и фиолетовое стекло.
        lx = ox + 46 if view != "up" else ox + 16
        d.line([(lx, top + 18), (lx, top + 24)], fill=(60, 50, 40, 255))
        d.rectangle([lx - 3, top + 24, lx + 3, top + 32], fill=(150, 112, 50, 255), outline=OUTLINE)
        d.rectangle([lx - 2, top + 26, lx + 2, top + 30], fill=(170, 120, 230, 255))
    else:
        if view != "up":
            d.ellipse([ox + 25, top + 3, ox + 39, top + 18], fill=face, outline=OUTLINE)   # маска-череп
            d.rectangle([ox + 28, top + 8, ox + 30, top + 10], fill=(10, 8, 12, 255))
            d.rectangle([ox + 34, top + 8, ox + 36, top + 10], fill=(10, 8, 12, 255))
            d.point([(ox + 29, top + 9), (ox + 35, top + 9)], fill=(200, 230, 255, 255))
        # Закрученные рога.
        d.arc([ox + 14, top - 2, ox + 26, top + 12], 90, 360, fill=face, width=2)
        d.arc([ox + 38, top - 2, ox + 50, top + 12], 180, 450, fill=face, width=2)


def sheet(spec) -> Image.Image:
    img = Image.new("RGBA", (CELL * 4, CELL * 3), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for row, view in enumerate(("down", "up", "side")):
        for col, bob in enumerate((0, 1, 1, 0)):
            figure(d, col * CELL, row * CELL, spec, view, bob)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    only_spirits = "--spirits" in sys.argv
    for vid, spec in ({} if only_spirits else VILLAGERS).items():
        sheet(spec).save(OUT / f"{vid}.png")
        print("готово:", vid)
    # Проводник и призрак у фонарей душ (assets/sprites/spirits/).
    out2 = OUT.parent / "spirits"
    out2.mkdir(parents=True, exist_ok=True)
    for kind in ("guide", "spirit"):
        img = Image.new("RGBA", (CELL * 4, CELL * 3), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        for row, view in enumerate(("down", "up", "side")):
            for col, bob in enumerate((0, 1, 1, 0)):
                spirit_figure(d, col * CELL, row * CELL, kind, view, bob)
        img.save(out2 / f"{kind}.png")
        print("готово:", kind)


if __name__ == "__main__":
    main()
