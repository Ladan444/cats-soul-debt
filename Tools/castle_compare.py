"""Сверка модели замка с исходными видами: наложения контуров и IoU.

    python Tools/castle_compare.py profiles        — снять верхние контуры исходников в Tools/blender/castle_profiles.json
    python Tools/castle_compare.py                 — сравнить Арт/Blender/castle/sil_<вид>.png с исходниками

Цвета наложения: зелёный — совпало, красный — есть только в исходнике, синий — лишнее в модели.
Верх и низ считаются отдельно (граница — строка TOP_ROW): верх — башни и шпили, низ — скала и стены.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SRC = r"C:\Users\Ladan444\Downloads\castle_3d"
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJECT, "Арт", "Blender", "castle")
PROFILES = os.path.join(PROJECT, "Tools", "blender", "castle_profiles.json")
VIEWS = ("front", "back", "right")
TOP_ROW = 700


def mask(path):
    return np.asarray(Image.open(path).convert("RGBA"))[:, :, 3] > 128


def iou(a, b):
    union = (a | b).sum()
    return float((a & b).sum()) / float(union) if union else 0.0


def profiles():
    """Верхний контур каждого вида по клеткам 10 px: самая низкая верхушка в клетке (для ограничения мелких шпилей)."""
    data = {}
    for view in VIEWS:
        m = mask(os.path.join(SRC, "castle_%s.png" % view))
        top = np.where(m.any(axis=0), m.argmax(axis=0), 1240)
        data[view] = [int(top[x:x + 10].max()) for x in range(0, 1500, 10)]
    with open(PROFILES, "w", encoding="utf-8") as f:
        json.dump(data, f)
    print("профили записаны:", PROFILES)


def compare():
    report = {}
    sources = {v: mask(os.path.join(SRC, "castle_%s.png" % v)) for v in VIEWS}
    for view in VIEWS:
        src = sources[view]
        model = mask(os.path.join(OUT, "sil_%s.png" % view))
        img = np.full(src.shape + (3,), 245, dtype=np.uint8)
        img[src & model] = (70, 170, 90)
        img[src & ~model] = (220, 50, 50)
        img[~src & model] = (50, 90, 230)
        report[view] = {"iou": round(iou(src, model), 3),
                        "top": round(iou(src[:TOP_ROW], model[:TOP_ROW]), 3),
                        "low": round(iou(src[TOP_ROW:], model[TOP_ROW:]), 3)}
        pic = Image.fromarray(img)
        r = report[view]
        ImageDraw.Draw(pic).text((30, 24), "%s  IoU %.3f   top %.3f   low %.3f" % (view, r["iou"], r["top"], r["low"]),
                                 fill=(20, 20, 20), font=ImageFont.load_default(44))
        pic.save(os.path.join(OUT, "overlay_%s.png" % view))
    # Предел: насколько сами исходники спереди и сзади совпадают (зеркало по оси x = 750).
    mirrored = sources["back"][:, ::-1]
    report["исходники спереди/сзади"] = {"iou": round(iou(sources["front"], mirrored), 3),
                                         "top": round(iou(sources["front"][:TOP_ROW], mirrored[:TOP_ROW]), 3),
                                         "low": round(iou(sources["front"][TOP_ROW:], mirrored[TOP_ROW:]), 3)}
    with open(os.path.join(OUT, "iou.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    for key, val in report.items():
        print(key, val)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "profiles":
        profiles()
    else:
        compare()
