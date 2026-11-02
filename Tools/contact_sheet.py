"""Склейка нескольких картинок (скриншоты, рендеры) в один лист — одна картинка вместо многих в разговоре.

  python Tools/contact_sheet.py out.png a.png b.png c.png [--cols 3] [--width 640] [--crop 0.3,0.1,0.7,0.6]

--width — ширина ячейки (высота — по пропорции первой картинки); --crop — доли рамки (x0,y0,x1,y1),
вырезаемой из каждой картинки до уменьшения (например, середина кадра вокруг Рэя).
"""

import argparse
import math

from PIL import Image


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("images", nargs="+")
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--width", type=int, default=640)
    ap.add_argument("--crop", default="")
    args = ap.parse_args()
    crop = [float(v) for v in args.crop.split(",")] if args.crop else None
    ims = []
    for path in args.images:
        im = Image.open(path).convert("RGB")
        if crop:
            w, h = im.size
            im = im.crop((int(w * crop[0]), int(h * crop[1]), int(w * crop[2]), int(h * crop[3])))
        ims.append(im)
    cw = args.width
    ch = int(cw * ims[0].height / ims[0].width)
    cols = min(args.cols, len(ims))
    rows = math.ceil(len(ims) / cols)
    sheet = Image.new("RGB", (cw * cols, ch * rows), (20, 18, 22))
    for i, im in enumerate(ims):
        sheet.paste(im.resize((cw, ch), Image.LANCZOS), ((i % cols) * cw, (i // cols) * ch))
    sheet.save(args.out)
    print(f"{args.out}: {sheet.width}x{sheet.height}, {len(ims)} шт.")


if __name__ == "__main__":
    main()
