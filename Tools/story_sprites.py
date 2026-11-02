"""Временные спрайты сюжетных сцен (до ИИ-генераций по SPRITE_SPECS): силуэт Покупателя для финала Главы 1.

Покупатель — огромный толстый кот в дорогой одежде (CANON); в финале Главы 1 он выходит из темноты, лицо в тени:
тёмный силуэт с тусклым золотом цепи и двумя янтарными точками глаз. 64×88 px (выше и шире Рэя).
Результат — Game/CatsSoulDebt/assets/sprites/story/buyer_silhouette.png.
Запуск: python Tools/story_sprites.py
"""
import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Game", "CatsSoulDebt", "assets", "sprites", "story", "buyer_silhouette.png")
W, H = 64, 88


def buyer() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    p = img.load()
    body, edge = (22, 18, 26, 255), (44, 34, 52, 255)
    cx = W / 2
    for y in range(H):
        for x in range(W):
            dx = x - cx + 0.5
            inside = False
            # Голова с ушами.
            if 6 <= y <= 24:
                inside = (dx / 11) ** 2 + ((y - 16) / 9) ** 2 <= 1
            # Кошачьи уши — треугольники остриём вверх.
            if 2 <= y <= 10 and (abs(dx + 7) < (y - 2) * 0.5 + 0.5 or abs(dx - 7) < (y - 2) * 0.5 + 0.5):
                inside = True
            # Тучное тело в широком кафтане.
            if 22 <= y <= 80:
                t = (y - 22) / 58
                half = 12 + 17 * math.sin(min(1.0, t * 1.4) * math.pi / 2) - 4 * max(0.0, t - 0.8) * 5
                inside = inside or abs(dx) <= half
            # Ноги.
            if 80 < y < H and (abs(dx + 7) < 5 or abs(dx - 7) < 5):
                inside = True
            if inside:
                p[x, y] = body
    # Светлый контур сверху-слева — отсвет фиолетового тумана.
    src = img.copy().load()
    for y in range(1, H):
        for x in range(1, W):
            if src[x, y][3] and (src[x - 1, y][3] == 0 or src[x, y - 1][3] == 0):
                p[x, y] = edge
    # Глаза и золотая цепь.
    for x, y in ((cx - 5, 15), (cx - 4, 15), (cx + 3, 15), (cx + 4, 15)):
        p[int(x), y] = (232, 176, 64, 255)
    for i in range(-12, 13):
        y = int(36 + (i / 12) ** 2 * -6 + 6)
        if (i + 12) % 3 != 0:
            p[int(cx + i), y] = (150, 112, 40, 255)
    return img


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    buyer().save(OUT)
    print("сохранено:", OUT)


if __name__ == "__main__":
    main()
