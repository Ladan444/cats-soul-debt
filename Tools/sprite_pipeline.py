"""Превращает ИИ-генерацию листа видов персонажа в игровые спрайты.

Вход: картинка с видами персонажа слева направо на однотонном фоне
(по SPRITE_SPECS: вниз, вверх, вправо).
Выход (в --out):
  <name>_sheet.png          — лист 64x64 на кадр, кадры: вниз, вверх, вправо;
  <name>_sheet_alt.png      — то же, но уменьшено усреднением (старый метод, для сравнения);
  <name>_preview.png        — увеличенное превью обоих вариантов.

Пример:
  python Tools/sprite_pipeline.py "Арт/Генерации/ray.png" --name ray --palette ray
"""

import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

CELL = 64
BASELINE_Y = 60
SENTINEL = (255, 0, 255)


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def remove_background(img: Image.Image, tolerance: int, holes: bool = False, holes_tolerance: int | None = None) -> np.ndarray:
    """Заливает фон от краёв картинки и возвращает маску переднего плана.

    holes=True дополнительно убирает закрытые островки цвета фона (просветы между прядями,
    между рукой и телом). Не включать для персонажей, у которых есть части цвета фона (белая шерсть Рэя).
    """
    work = img.convert("RGB").copy()
    w, h = work.size
    seeds = [(x, 0) for x in range(0, w, 16)] + [(x, h - 1) for x in range(0, w, 16)]
    seeds += [(0, y) for y in range(0, h, 16)] + [(w - 1, y) for y in range(0, h, 16)]
    for seed in seeds:
        if work.getpixel(seed) != SENTINEL:
            ImageDraw.floodfill(work, seed, SENTINEL, thresh=tolerance)
    arr = np.asarray(work)
    mask = ~np.all(arr == SENTINEL, axis=2)
    if holes:
        src = np.asarray(img.convert("RGB")).astype(np.int16)
        bg = np.median(src[[0, -1]].reshape(-1, 3), axis=0)
        mask &= np.abs(src - bg).max(axis=2) > (tolerance if holes_tolerance is None else holes_tolerance)
    return mask


def split_views(mask: np.ndarray, min_gap: int, min_width: int) -> list[tuple[int, int]]:
    """Делит маску на фигуры по пустым столбцам."""
    cols = mask.any(axis=0)
    runs, start, gap = [], None, 0
    for x, filled in enumerate(cols):
        if filled:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                runs.append((start, x - gap + 1))
                start, gap = None, 0
    if start is not None:
        runs.append((start, len(cols)))
    return [r for r in runs if r[1] - r[0] >= min_width]


def downscale(rgb: np.ndarray, alpha: np.ndarray, size: tuple[int, int]) -> tuple[np.ndarray, np.ndarray]:
    """Уменьшение усреднением с учётом прозрачности (фон не подмешивается в цвет)."""
    a = alpha.astype(np.float32)
    premul = rgb.astype(np.float32) * a[..., None]
    small_a = np.asarray(Image.fromarray(a).resize(size, Image.BOX))
    channels = [np.asarray(Image.fromarray(premul[..., c]).resize(size, Image.BOX)) for c in range(3)]
    small_rgb = np.stack(channels, axis=-1) / np.maximum(small_a[..., None], 1e-6)
    return np.clip(small_rgb, 0, 255), small_a


def downscale_mode(rgb: np.ndarray, alpha: np.ndarray, size: tuple[int, int],
                   palette: list[tuple[int, int, int]], accents: list[int],
                   accent_share: float = 0.2,
                   dark_weight: float = 1.0) -> tuple[np.ndarray, np.ndarray]:
    """Уменьшение «по большинству»: исходник сначала переводится в палитру, затем каждый
    итоговый пиксель получает самый частый цвет своего блока. Промежуточных грязных тонов нет.
    Цвета-акценты (глаза, шрамы) побеждают, если занимают в блоке хотя бы accent_share."""
    pal = np.array(palette, dtype=np.uint8)
    idx = palette_indices(rgb, palette)
    h, w = alpha.shape
    tw, th = size
    ys = np.linspace(0, h, th + 1).round().astype(int)
    xs = np.linspace(0, w, tw + 1).round().astype(int)
    out_rgb = np.zeros((th, tw, 3), dtype=np.uint8)
    out_a = np.zeros((th, tw), dtype=np.float32)
    for j in range(th):
        for i in range(tw):
            block_a = alpha[ys[j]:ys[j + 1], xs[i]:xs[i + 1]]
            out_a[j, i] = block_a.mean()
            values = idx[ys[j]:ys[j + 1], xs[i]:xs[i + 1]][block_a]
            if values.size == 0:
                continue
            counts = np.bincount(values, minlength=len(palette))
            raw = counts.copy()
            if dark_weight != 1.0:
                counts = counts.astype(np.float32)
                counts[0] *= dark_weight   # тёмный контур генерации не должен съедать мелкие иконки
            best = counts.argmax()
            accent_hits = [a for a in accents if raw[a] >= accent_share * values.size]
            if accent_hits:
                best = max(accent_hits, key=lambda a: counts[a])
            out_rgb[j, i] = pal[best]
    return out_rgb, out_a


def palette_indices(rgb: np.ndarray, palette: list[tuple[int, int, int]]) -> np.ndarray:
    pal_lab = srgb_to_lab(np.array(palette, dtype=np.float32))
    lab = srgb_to_lab(rgb.astype(np.float32))
    flat = lab.reshape(-1, 3)
    result = np.empty(flat.shape[0], dtype=np.int64)
    for start in range(0, flat.shape[0], 200_000):
        chunk = flat[start:start + 200_000]
        result[start:start + 200_000] = np.linalg.norm(chunk[:, None, :] - pal_lab[None], axis=-1).argmin(axis=1)
    return result.reshape(rgb.shape[:2])


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def map_to_palette(rgb: np.ndarray, palette: list[tuple[int, int, int]]) -> np.ndarray:
    pal = np.array(palette, dtype=np.float32)
    dist = np.linalg.norm(srgb_to_lab(rgb)[..., None, :] - srgb_to_lab(pal)[None, None, :, :], axis=-1)
    return pal[dist.argmin(axis=-1)].astype(np.uint8)


def adaptive_palette(rgb: np.ndarray, opaque: np.ndarray, colors: int) -> np.ndarray:
    pixels = rgb[opaque].astype(np.uint8).reshape(1, -1, 3)
    pal_img = Image.fromarray(pixels).quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
    flat = pal_img.getpalette()[:colors * 3]
    palette = [tuple(flat[i:i + 3]) for i in range(0, len(flat), 3)]
    return map_to_palette(rgb, palette)


def add_outline(rgba: np.ndarray, color: tuple[int, int, int]) -> np.ndarray:
    """Внешний контур 1 px по 4 соседям."""
    opaque = rgba[..., 3] > 0
    grown = opaque.copy()
    grown[1:] |= opaque[:-1]
    grown[:-1] |= opaque[1:]
    grown[:, 1:] |= opaque[:, :-1]
    grown[:, :-1] |= opaque[:, 1:]
    edge = grown & ~opaque
    out = rgba.copy()
    out[edge] = (*color, 255)
    return out


def head_center_x(sprite: np.ndarray, fraction: float = 0.35) -> int:
    """Центр по X верхней части фигуры (головы) — опора для кадров анимации."""
    opaque = sprite[..., 3] > 0
    rows = np.where(opaque.any(axis=1))[0]
    top = rows[0]
    head = opaque[top:top + max(1, int((rows[-1] - top) * fraction))]
    cols = np.where(head.any(axis=0))[0]
    return (cols[0] + cols[-1] + 1) // 2


def body_center_x(sprite: np.ndarray, threshold: float = 0.6) -> int:
    """Центр по X корпуса: среднее столбцов, где непрозрачных пикселей ≥ threshold от максимума.
    Тонкие меч, хвост и дуга взмаха почти не влияют — кадры атак и ходьбы не «прыгают»."""
    counts = (sprite[..., 3] > 0).sum(axis=0)
    strong = np.where(counts >= counts.max() * threshold)[0]
    return int(round(strong.mean()))


def place_in_cell(sprite: np.ndarray, anchor_x: int | None = None, cell_w: int = CELL, cell_h: int = CELL) -> np.ndarray:
    """Ставит спрайт в ячейку cell_w×cell_h: ступни на линии cell_h-4; по X — опорная точка (или центр рамки) в центр.
    Если спрайт не помещается, лишнее обрезается с предупреждением."""
    cell = np.zeros((cell_h, cell_w, 4), dtype=np.uint8)
    h, w = sprite.shape[:2]
    x0 = cell_w // 2 - (w // 2 if anchor_x is None else anchor_x)
    y0 = (cell_h - (CELL - BASELINE_Y)) - h + 1
    sx0, sy0 = max(0, -x0), max(0, -y0)
    dx0, dy0 = max(0, x0), max(0, y0)
    cw, ch = min(w - sx0, cell_w - dx0), min(h - sy0, cell_h - dy0)
    if cw > 0 and ch > 0:
        cell[dy0:dy0 + ch, dx0:dx0 + cw] = sprite[sy0:sy0 + ch, sx0:sx0 + cw]
    if cw < w or ch < h:
        print(f"  ВНИМАНИЕ: кадр {w}x{h} обрезан ячейкой {cell_w}x{cell_h} — увеличьте --cell-w/--cell-h")
    return cell


def checker(width: int, height: int, size: int) -> Image.Image:
    yy, xx = np.mgrid[0:height, 0:width]
    tile = ((xx // size + yy // size) % 2).astype(np.uint8)
    return Image.fromarray(np.where(tile[..., None] == 1, 70, 90).repeat(3, axis=2).astype(np.uint8))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("--name", required=True)
    parser.add_argument("--palette", required=True, help="ключ из Tools/palettes.json")
    parser.add_argument("--height", type=int, default=48, help="итоговый рост вместе с контуром")
    parser.add_argument("--tolerance", type=int, default=18, help="допуск заливки фона")
    parser.add_argument("--holes", action="store_true",
                        help="убирать закрытые островки фона (для тёмных персонажей; не для белой шерсти)")
    parser.add_argument("--holes-tolerance", type=int, default=None,
                        help="свой допуск для островков фона (напр. 4 — убрать только чисто белый фон внутри дуги взмаха, "
                             "не трогая почти белую шерсть Рэя); включает --holes")
    parser.add_argument("--anchor", choices=("bbox", "head", "body"), default="bbox",
                        help="выравнивание по X: центр рамки, голова или корпус (для атак с мечом — body)")
    parser.add_argument("--cell-w", type=int, default=CELL,
                        help="ширина ячейки (96 — для атак с мечом и дугой взмаха); высота всегда 64")
    parser.add_argument("--cell-h", type=int, default=CELL,
                        help="высота ячейки (80 — если оружие поднимается над головой); ступни — на 4 px выше низа")
    parser.add_argument("--rows", type=int, default=0,
                        help="резать лист на N равных горизонтальных полос (если брызги/капли склеивают строки)")
    parser.add_argument("--ref-frame", type=int, default=-1,
                        help="номер кадра (с 0), чей рост = --height; по умолчанию — самый высокий кадр. "
                             "Для атак указывайте кадр, где оружие не торчит выше головы и ниже ног")
    parser.add_argument("--grid", action="store_true",
                        help="лист — сетка: строки сохраняются строками результата (иначе один ряд)")
    parser.add_argument("--flip", default="", help="номера кадров (с 0) через запятую, которые отразить по горизонтали")
    parser.add_argument("--smooth", type=int, default=0,
                        help="размер фильтра «по большинству» на исходнике (нечётный, 5–15): убирает мелкую фактуру "
                             "у очень детальных генераций, оставляя крупные цветовые пятна")
    parser.add_argument("--alpha-threshold", type=float, default=0.5,
                        help="доля непрозрачных пикселей блока, при которой итоговый пиксель остаётся видимым. "
                             "0.65–0.75 убирает светлую кайму по краю у генераций на белом фоне")
    parser.add_argument("--out", default="Арт/Обработано")
    args = parser.parse_args()

    palettes = json.loads((Path(__file__).parent / "palettes.json").read_text(encoding="utf-8"))
    pal_cfg = palettes[args.palette]
    palette = [hex_to_rgb(c) for c in pal_cfg["colors"]]
    outline = hex_to_rgb(pal_cfg["outline"])
    flips = {int(i) for i in args.flip.split(",") if i.strip()}

    img = Image.open(args.input).convert("RGB")
    mask = remove_background(img, args.tolerance, args.holes or args.holes_tolerance is not None, args.holes_tolerance)
    if args.smooth > 1:
        # Фон заливается цветом контура, иначе фильтр затянет белый фон на края фигуры (светлый ореол).
        arr = np.array(img)
        arr[~mask] = outline
        img = Image.fromarray(arr).filter(ImageFilter.ModeFilter(args.smooth))
    rgb_full = np.asarray(img)

    # Кадры: (номер строки, вырезка цвета, вырезка маски).
    crops = []
    if args.rows > 0:
        bounds = np.linspace(0, mask.shape[0], args.rows + 1).round().astype(int)
        row_ranges = list(zip(bounds[:-1], bounds[1:]))
        args.grid = True
    elif args.grid:
        row_ranges = split_views(mask.T, min_gap=12, min_width=10)
    else:
        row_ranges = [(0, mask.shape[0])]
    for row_i, (ry0, ry1) in enumerate(row_ranges):
        views = split_views(mask[ry0:ry1], min_gap=12, min_width=20 if args.grid else 40)
        print(f"строка {row_i}: найдено кадров {len(views)} -> {views}")
        for x0, x1 in views:
            rows = np.where(mask[ry0:ry1, x0:x1].any(axis=1))[0]
            y0, y1 = ry0 + rows[0], ry0 + rows[-1] + 1
            crops.append((row_i, rgb_full[y0:y1, x0:x1], mask[y0:y1, x0:x1]))

    # Общий масштаб: рост эталонного кадра (или самого высокого) = рост без контура.
    ref_h = crops[args.ref_frame][2].shape[0] if args.ref_frame >= 0 else max(c[2].shape[0] for c in crops)
    scale = (args.height - 2) / ref_h
    print(f"масштаб: 1/{1 / scale:.1f}")

    accents = [palette.index(hex_to_rgb(c)) for c in pal_cfg.get("accents", [])]
    # Основной вариант — уменьшение «по большинству»; второй (alt) — старое усреднение, для сравнения.
    sheets = {"main": [], "alt": []}
    for index, (_row, rgb, alpha) in enumerate(crops):
        if index in flips:
            rgb, alpha = rgb[:, ::-1], alpha[:, ::-1]
        size = (max(1, round(alpha.shape[1] * scale)), max(1, round(alpha.shape[0] * scale)))
        mode_rgb, mode_a = downscale_mode(rgb, alpha, size, palette, accents)
        box_rgb, box_a = downscale(rgb, alpha, size)
        for kind, mapped, small_a in (("main", mode_rgb, mode_a),
                                      ("alt", map_to_palette(box_rgb, palette), box_a)):
            opaque = small_a >= args.alpha_threshold
            rgba = np.zeros((*opaque.shape, 4), dtype=np.uint8)
            rgba[opaque, :3] = mapped[opaque]
            rgba[opaque, 3] = 255
            rgba = add_outline(np.pad(rgba, ((1, 1), (1, 1), (0, 0))), outline)
            anchor = {"head": head_center_x, "body": body_center_x}.get(args.anchor, lambda _s: None)(rgba)
            sheets[kind].append(place_in_cell(rgba, anchor, args.cell_w, args.cell_h))

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    images = {}
    n_rows = len(row_ranges)
    n_cols = max(sum(1 for c in crops if c[0] == r) for r in range(n_rows))
    empty = np.zeros((args.cell_h, args.cell_w, 4), dtype=np.uint8)
    for kind, cells in sheets.items():
        rows_img = []
        for r in range(n_rows):
            row_cells = [cell for cell, c in zip(cells, crops) if c[0] == r]
            row_cells += [empty] * (n_cols - len(row_cells))
            rows_img.append(np.concatenate(row_cells, axis=1))
        sheet = Image.fromarray(np.concatenate(rows_img, axis=0), "RGBA")
        suffix = "" if kind == "main" else "_alt"
        path = out_dir / f"{args.name}_sheet{suffix}.png"
        sheet.save(path)
        images[kind] = sheet
        print(f"сохранено: {path}")

    zoom = 6
    w, h = images["main"].size
    preview = checker(w * zoom, h * zoom * 2 + zoom * 4, zoom * 4)
    for i, kind in enumerate(("main", "alt")):
        big = images[kind].resize((w * zoom, h * zoom), Image.NEAREST)
        preview.paste(big, (0, i * (h * zoom + zoom * 4)), big)
    preview_path = out_dir / f"{args.name}_preview.png"
    preview.save(preview_path)
    print(f"превью: {preview_path}")


if __name__ == "__main__":
    main()
