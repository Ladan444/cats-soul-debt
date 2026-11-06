"""Приглушает яркую латунь HUD под сдержанные тона нового меню (бронза #6a5434…#c9b892).
Берёт исходник assets/ui/hud_atlas_bright.png (создаётся копией при первом запуске), пишет assets/ui/hud_atlas.png.
Запуск: python Tools/mute_hud_brass.py [насыщенность 0..1, по умолчанию 0.55]"""
import colorsys
import os
import shutil
import sys
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "Game", "CatsSoulDebt", "assets", "ui")
SRC = os.path.join(ROOT, "hud_atlas_bright.png")
DST = os.path.join(ROOT, "hud_atlas.png")
k = float(sys.argv[1]) if len(sys.argv) > 1 else 0.55

if not os.path.exists(SRC):
    shutil.copy(DST, SRC)
im = Image.open(SRC).convert("RGBA")
px = im.load()
n = 0
for y in range(im.height):
    for x in range(im.width):
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if 0.07 <= h <= 0.2 and s > 0.4 and v > 0.3:   # жёлтая латунь, не коричневое дерево
            s *= k
            v *= 0.93
            r, g, b = (int(round(c * 255)) for c in colorsys.hsv_to_rgb(h, s, v))
            px[x, y] = (r, g, b, a)
            n += 1
im.save(DST)
print("изменено пикселей:", n)
