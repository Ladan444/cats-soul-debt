"""Рисует недостающие иконки предметов 20×20 скриптом (в тон иконок из листов автора: тёмный контур, мягкие тона):
honey, agata_ingredients, honey_bun; tincture_liara берётся копией флакона icon_item_placeholder (это и есть настойка).
Крупно (×8) → Lanczos → адаптивная палитра, как в icon_pipeline.py --smooth. Запуск: python Tools/draw_item_icons.py
Когда художница нарисует настоящие иконки — просто заменить файлы icon_<id>.png в Game/CatsSoulDebt/assets/ui/."""
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Game" / "CatsSoulDebt" / "assets" / "ui"
K = 8
S = 20 * K
OUTLINE = (42, 30, 24, 255)


def canvas():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def outlined(d, shape, fill, w=K):
    """shape: ('ellipse'|'rrect'|'poly', args) с тёмным контуром толщиной w."""
    kind, a = shape
    if kind == "ellipse":
        d.ellipse(a, fill=fill, outline=OUTLINE, width=w)
    elif kind == "rrect":
        d.rounded_rectangle(a[0], radius=a[1], fill=fill, outline=OUTLINE, width=w)
    else:
        d.polygon(a, fill=fill, outline=OUTLINE)
        d.line(list(a) + [a[0]], fill=OUTLINE, width=w, joint="curve")


def finish(im: Image.Image, name: str, colors: int = 14) -> None:
    arr = np.asarray(im.resize((20, 20), Image.LANCZOS)).astype(np.float32)
    a = np.clip(arr[..., 3] / 255.0, 0, 1)
    rgb = Image.fromarray(arr[..., :3].astype(np.uint8)).quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    out = np.dstack([np.asarray(rgb), np.where(a >= 0.5, 255, 0).astype(np.uint8)])
    Image.fromarray(out, "RGBA").save(OUT / f"icon_{name}.png")
    print("  icon_%s.png" % name)


def honey():
    im, d = canvas()
    outlined(d, ("rrect", ((34, 44, 126, 144), 30)), (222, 160, 48, 255))          # горшок
    d.rounded_rectangle((44, 56, 70, 130), radius=12, fill=(246, 206, 96, 255))     # блик
    outlined(d, ("rrect", ((28, 22, 132, 52), 10)), (138, 94, 58, 255))             # крышка-тряпица
    d.line([(32, 50), (128, 50)], fill=(228, 200, 150, 255), width=K // 2)           # бечёвка
    d.polygon([(100, 52), (118, 52), (116, 86), (109, 94), (102, 86)], fill=(240, 180, 56, 255))   # потёк
    outlined(d, ("rrect", ((52, 96, 108, 128), 8)), (232, 214, 176, 255), w=K // 2)  # этикетка
    d.line([(60, 108), (100, 108)], fill=(138, 94, 58, 255), width=K // 2)
    finish(im, "honey")


def agata_ingredients():
    im, d = canvas()
    outlined(d, ("ellipse", (26, 44, 134, 148)), (150, 154, 160, 255))               # мешочек
    d.ellipse((42, 62, 80, 112), fill=(190, 194, 198, 255))                          # блик
    outlined(d, ("poly", [(56, 50), (66, 20), (76, 44), (86, 16), (96, 46), (106, 50)]), (120, 124, 132, 255))  # стянутая горловина
    d.line([(52, 52), (108, 52)], fill=(138, 94, 58, 255), width=K)                  # бечёвка
    d.polygon([(100, 78), (114, 78), (106, 96), (118, 96), (98, 126), (104, 104), (94, 104)], fill=(250, 220, 90, 255), outline=OUTLINE)  # искра «грозы»
    d.ellipse((38, 112, 46, 120), fill=(176, 122, 224, 255))
    d.ellipse((60, 126, 66, 132), fill=(176, 122, 224, 255))
    finish(im, "agata_ingredients")


def honey_bun():
    im, d = canvas()
    outlined(d, ("ellipse", (14, 48, 146, 146)), (206, 140, 62, 255))                # булка
    d.chord((30, 56, 132, 116), 180, 360, fill=(236, 176, 84, 255))                  # румяная корка
    d.ellipse((42, 62, 76, 80), fill=(250, 214, 140, 255))                           # блик
    outlined(d, ("poly", [(34, 78), (126, 78), (122, 96), (112, 92), (108, 112), (98, 98), (88, 118), (78, 100), (64, 116), (56, 96), (44, 100)]), (244, 190, 60, 255), w=K // 2)   # мёд
    d.line([(24, 128), (136, 128)], fill=(150, 96, 48, 255), width=K)               # низ
    finish(im, "honey_bun")


if __name__ == "__main__":
    honey()
    agata_ingredients()
    honey_bun()
    shutil.copyfile(OUT / "icon_item_placeholder.png", OUT / "icon_tincture_liara.png")
    print("  icon_tincture_liara.png (копия флакона)")
    # подключаем иконки к предметам
    for item, icon in [("honey", "honey"), ("agata_ingredients", "agata_ingredients"), ("honey_bun", "honey_bun"), ("tincture_liara", "tincture_liara")]:
        f = ROOT / "Game" / "CatsSoulDebt" / "data" / "items" / f"{item}.tres"
        s = f.read_text(encoding="utf-8")
        s2 = s.replace("res://assets/ui/icon_item_placeholder.png", f"res://assets/ui/icon_{icon}.png")
        if s2 != s:
            f.write_text(s2, encoding="utf-8", newline="")
