"""Сверка планировки мира с концептом: данные Tools/world_layout.py (в пикселях концепта) поверх
Арт/Концепты/world_concept.png → Арт/Blender/world_overlay.png. Горы, холмы, озеро, река, дороги, мосты,
крепость, дома деревни, места интереса и фонари — полупрозрачными цветами и подписями.
Запуск: python Tools/world_schema.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONCEPT = os.path.join(ROOT, "Арт", "Концепты", "world_concept.png")
OUT = os.path.join(ROOT, "Арт", "Blender", "world_overlay.png")
FONT_B = "C:/Windows/Fonts/georgiab.ttf"


def main():
    W = {}
    exec(open(os.path.join(ROOT, "Tools", "world_layout.py"), encoding="utf-8").read(), W)
    base = Image.open(CONCEPT).convert("RGBA")
    over = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    f = ImageFont.truetype(FONT_B, 14)
    edge = [(x, y) for y, x in W["MOUNTAIN_EDGE"]]
    d.polygon([(0, 0)] + edge + [(0, 1024)], fill=(120, 120, 130, 90), outline=(255, 255, 255, 220))
    d.polygon(W["SOUTH_RIDGE"], fill=(120, 120, 130, 90), outline=(255, 255, 255, 220))
    d.polygon(W["HILLS"], fill=(200, 190, 80, 60), outline=(255, 240, 120, 230))
    for t in W["TERRACES"]:
        d.polygon(t, fill=(230, 200, 60, 80), outline=(255, 220, 60, 255))
    for t in W["FIELDS"] + W["GARDENS"]:
        d.polygon(t, fill=(240, 220, 100, 80), outline=(255, 230, 120, 255))
    for x, y, r in W["ROCKS"]:
        d.ellipse([x - r, y - r, x + r, y + r], outline=(255, 255, 255, 200), width=2)
    d.polygon(W["LAKE"], fill=(40, 120, 255, 70), outline=(120, 200, 255, 255))
    d.polygon(W["ISLAND"], fill=(60, 180, 60, 90), outline=(160, 255, 160, 255))
    for x, y, r in W["PONDS"]:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(40, 120, 255, 70), outline=(120, 200, 255, 255))
    for line, color in ((W["RIVER"], (120, 200, 255, 255)), (W["STREAM"], (120, 200, 255, 200))):
        d.line([(x, y) for x, y, w in line], fill=color, width=4)
    for kind, pts in W["ROADS"]:
        d.line(pts, fill=(255, 120, 40, 255) if kind == "road" else (255, 200, 60, 230), width=3)
    for name, a, b in W["BRIDGES"]:
        d.line([a, b], fill=(255, 40, 40, 255), width=5)
    F = W["FORTRESS"]
    d.polygon(F["walls"], outline=(255, 60, 255, 255), width=3)
    for x, y in F["towers"]:
        d.ellipse([x - 6, y - 6, x + 6, y + 6], fill=(255, 60, 255, 200))
    for rid, name, x, y, w, h, kind in W["VILLAGE"]:
        d.rectangle([x - 12, y - 9, x + 12, y + 9], outline=(255, 60, 60, 255), width=2)
    d.line(W["PALISADE"], fill=(160, 90, 40, 255), width=4)
    for x, y in W["LANTERNS"]:
        d.rectangle([x - 6, y - 6, x + 6, y + 6], fill=(150, 60, 220, 230), outline=(255, 255, 255, 255))
    for pid, num, name, x, y, kind, note in W["POIS"]:
        d.ellipse([x - 10, y - 10, x + 10, y + 10], fill=(255, 255, 255, 230), outline=(0, 0, 0, 255), width=2)
        d.text((x - (7 if num > 9 else 4), y - 8), str(num), fill=(0, 0, 0, 255), font=f)
    out = Image.alpha_composite(base, over)
    out.convert("RGB").save(OUT)
    # Проверка перевода в метры: размеры мира и пара расстояний.
    x0, y0, x1, y1 = W["BOUNDS"]
    print("мир: %.0f × %.0f м (x %.0f…%.0f, y %.0f…%.0f)" % (x1 - x0, y1 - y0, x0, x1, y0, y1))
    for pid, num, name, x, y, kind, note in W["POIS"]:
        mx, my = W["P"](x, y)
        print("  %2d %-28s %7.0f %7.0f" % (num, name, mx, my))
    print("сохранено:", OUT)


if __name__ == "__main__":
    main()
