"""Превращает ИИ-генерацию листа иконок в игровые иконки 14×14 (UI_SPEC, шаг 6).

Вход: картинка с несколькими иконками на однотонном фоне — в ряд или сеткой, с промежутками.
Иконки нумеруются слева направо, сверху вниз; --names задаёт имена файлов в том же порядке.
Каждая иконка вписывается в 12×12, переводится в палитру "icons" (Tools/palettes.json) методом
«по большинству», получает контур 1 px и кладётся по центру 14×14.
Файлы пишутся в Game/CatsSoulDebt/assets/ui/ поверх заглушек с тем же именем — игра подхватит их сама.

Пример:
  python Tools/icon_pipeline.py "Арт/Генерации/icons_equipment.png" --names icon_sword,icon_cloak,icon_armor,icon_amulet
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image

from sprite_pipeline import add_outline, downscale_mode, hex_to_rgb, remove_background, split_views

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Game" / "CatsSoulDebt" / "assets" / "ui"
ICON = 14
INNER = ICON - 2


def find_icons(mask: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Рамки иконок: сначала строки (по пустым рядам), внутри — столбцы."""
    boxes = []
    for y0, y1 in split_views(mask.T, min_gap=8, min_width=10):
        row = mask[y0:y1]
        for x0, x1 in split_views(row, min_gap=8, min_width=10):
            rows = np.where(row[:, x0:x1].any(axis=1))[0]
            boxes.append((x0, y0 + rows[0], x1, y0 + rows[-1] + 1))
    return boxes


def downscale_smooth(rgb: np.ndarray, alpha: np.ndarray, size: tuple[int, int], colors: int):
    """Lanczos по премультиплицированному цвету, затем адаптивная палитра на `colors` цветов."""
    a = alpha.astype(np.float32)[..., None]
    pre = np.concatenate([rgb.astype(np.float32) * a, a * 255.0], axis=2)
    chans = [np.asarray(Image.fromarray(pre[..., i]).resize(size, Image.LANCZOS), dtype=np.float32) for i in range(4)]
    out_a = np.clip(chans[3] / 255.0, 0, 1)
    safe = np.maximum(out_a, 1e-3)[..., None]
    out_rgb = np.clip(np.stack(chans[:3], axis=2) / (safe * 1.0) / 1.0, 0, 255)
    # chans[:3] уже умножены на alpha∈[0,1] (не на 255): делим обратно на alpha
    out_rgb = np.clip(np.stack(chans[:3], axis=2) / safe, 0, 255).astype(np.uint8)
    q = Image.fromarray(out_rgb).quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    return np.asarray(q), out_a


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("--names", required=True, help="имена файлов через запятую, без .png")
    parser.add_argument("--palette", default="icons")
    parser.add_argument("--tolerance", type=int, default=18)
    parser.add_argument("--no-holes", action="store_true", help="не убирать закрытые островки фона")
    parser.add_argument("--no-outline", action="store_true",
                        help="не добавлять контур (если у генерации он уже толстый; полезно для тонких предметов)")
    parser.add_argument("--dark-weight", type=float, default=1.0,
                        help="вес самого тёмного цвета палитры при уменьшении (0.3–0.5: убрать «кашу» от контура генерации)")
    parser.add_argument("--size", type=int, default=ICON,
                        help="сторона иконки в пикселях (14 — как у заглушек; 20 — крупные, почти на всю ячейку 22 px)")
    parser.add_argument("--smooth", type=int, default=0, metavar="COLORS",
                        help="не «по большинству» в палитру проекта, а Lanczos + адаптивная палитра на COLORS цветов "
                             "(детальнее и читаемее, цвета ближе к генерации; 0 — выкл.)")
    parser.add_argument("--out", default=str(OUT))
    args = parser.parse_args()

    icon_size = args.size
    inner = icon_size - 2
    names = [n.strip() for n in args.names.split(",") if n.strip()]
    palettes = json.loads((Path(__file__).parent / "palettes.json").read_text(encoding="utf-8"))
    cfg = palettes[args.palette]
    palette = [hex_to_rgb(c) for c in cfg["colors"]]
    outline = hex_to_rgb(cfg["outline"])
    accents = [palette.index(hex_to_rgb(c)) for c in cfg.get("accents", [])]

    img = Image.open(args.input).convert("RGB")
    rgb = np.asarray(img)
    mask = remove_background(img, args.tolerance, holes=not args.no_holes)
    boxes = find_icons(mask)
    print(f"найдено иконок: {len(boxes)}, имён: {len(names)}")
    if len(boxes) != len(names):
        print("ВНИМАНИЕ: число иконок и имён не совпадает — лишние пропущены")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for (x0, y0, x1, y1), name in zip(boxes, names):
        crop_rgb, crop_a = rgb[y0:y1, x0:x1], mask[y0:y1, x0:x1]
        scale = (icon_size if args.no_outline else inner) / max(crop_a.shape)
        size = (max(1, round(crop_a.shape[1] * scale)), max(1, round(crop_a.shape[0] * scale)))
        if args.smooth:
            small_rgb, small_a = downscale_smooth(crop_rgb, crop_a, size, args.smooth)
        else:
            small_rgb, small_a = downscale_mode(crop_rgb, crop_a, size, palette, accents, dark_weight=args.dark_weight)
        opaque = small_a >= 0.5
        rgba = np.zeros((*opaque.shape, 4), dtype=np.uint8)
        rgba[opaque, :3] = small_rgb[opaque]
        rgba[opaque, 3] = 255
        if not args.no_outline:
            rgba = add_outline(np.pad(rgba, ((1, 1), (1, 1), (0, 0))), outline)
        cell = np.zeros((icon_size, icon_size, 4), dtype=np.uint8)
        h, w = rgba.shape[:2]
        oy, ox = (icon_size - h) // 2, (icon_size - w) // 2
        cell[oy:oy + h, ox:ox + w] = rgba
        icon = Image.fromarray(cell, "RGBA")
        icon.save(out_dir / f"{name}.png")
        results.append(icon)
        print(f"  {name}.png")

    # Превью ×8 на сером фоне.
    if results:
        sheet = Image.new("RGBA", ((icon_size + 2) * len(results), icon_size + 2), (96, 96, 112, 255))
        for i, icon in enumerate(results):
            sheet.alpha_composite(icon, (1 + i * (icon_size + 2), 1))
        preview = ROOT / "Арт" / "Обработано" / f"{Path(args.input).stem}_icons_preview.png"
        sheet.resize((sheet.width * 8, sheet.height * 8), Image.NEAREST).save(preview)
        print(f"превью: {preview}")


if __name__ == "__main__":
    main()
