"""Вырезает элементы интерфейса из листа-образца ИИ (`Арт/Генерации/UI/ui_kit.png`, `ui_hud_b.png`)
и сводит их к пиксельной сетке игры: те же имена файлов, что у заглушек `Tools/ui_atlas.py`,
поэтому код интерфейса подхватывает новую графику сам.

  python Tools/ui_kit_pipeline.py            # всё
  python Tools/ui_kit_pipeline.py slot plank # только перечисленное

Каждый элемент: рамка на листе (px) → фон убирается заливкой от краёв → уменьшение Lanczos по
премультиплицированному цвету → адаптивная палитра (N цветов) → PNG в assets/ui.
Превью ×6 на сером фоне — `Арт/Обработано/ui_kit_preview.png`.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from sprite_pipeline import remove_background  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
GEN = ROOT / "Арт" / "Генерации" / "UI"
OUT = ROOT / "Game" / "CatsSoulDebt" / "assets" / "ui"
PREVIEW = ROOT / "Арт" / "Обработано" / "ui_kit_preview.png"

# имя файла → (лист, рамка x0,y0,x1,y1 в px листа, размер на выходе, цветов в палитре, особое)
KIT = "ui_kit.png"
HUD = "ui_hud_b.png"
ELEMENTS = {
    "slot": (KIT, (1262, 58, 1380, 175), (22, 22), 14, ""),
    "hot_slot": (KIT, (1262, 58, 1380, 175), (24, 24), 14, ""),
    "hot_slot_selected": (KIT, (1410, 58, 1530, 175), (24, 24), 14, ""),
    "slot_selected": (KIT, (1410, 58, 1530, 175), (22, 22), 14, ""),
    "spark_full": (KIT, (1222, 392, 1258, 455), (7, 9), 8, ""),
    "spark_spent": (KIT, (1415, 392, 1452, 455), (7, 9), 8, ""),
    "emblem": (HUD, (752, 727, 922, 897), (30, 30), 20, "round"),
    "wood_button": (KIT, (462, 500, 617, 655), (22, 22), 14, "btn_base"),
    "wood_button_pressed": (KIT, (462, 500, 617, 655), (22, 22), 14, "btn_base_dark"),
    "sicon_book": (KIT, (62, 500, 217, 655), (12, 12), 8, "btn_icon"),
    "sicon_map": (KIT, (262, 500, 417, 655), (12, 12), 8, "btn_icon"),
    "sicon_gear": (KIT, (462, 500, 617, 655), (12, 12), 8, "btn_icon"),
    "plank": (KIT, (45, 38, 640, 445), (44, 28), 24, "plank"),
    "close": (KIT, (668, 732, 795, 855), (14, 14), 10, ""),
    "minimap_ring": (KIT, (1263, 535, 1626, 898), (90, 90), 24, "ring"),
}


def crop_rgba(sheet: Image.Image, box: tuple[int, int, int, int], tolerance: int = 26) -> Image.Image:
    img = sheet.crop(box).convert("RGB")
    mask = remove_background(img, tolerance, holes=False)
    rgba = np.dstack([np.asarray(img), (mask * 255).astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def fit(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Вписывает в size по центру, сохраняя пропорции; Lanczos по премультиплицированному цвету."""
    w, h = img.size
    s = min(size[0] / w, size[1] / h)
    tw, th = max(1, round(w * s)), max(1, round(h * s))
    arr = np.asarray(img).astype(np.float32)
    a = arr[..., 3:4] / 255.0
    pre = np.concatenate([arr[..., :3] * a, arr[..., 3:4]], axis=2)
    ch = [np.asarray(Image.fromarray(pre[..., i]).resize((tw, th), Image.LANCZOS), dtype=np.float32) for i in range(4)]
    alpha = np.clip(ch[3] / 255.0, 0, 1)
    rgb = np.clip(np.stack(ch[:3], axis=2) / np.maximum(alpha[..., None], 1e-3), 0, 255)
    out = np.dstack([rgb, alpha * 255.0]).astype(np.uint8)
    cell = Image.new("RGBA", size, (0, 0, 0, 0))
    cell.alpha_composite(Image.fromarray(out, "RGBA"), ((size[0] - tw) // 2, (size[1] - th) // 2))
    return cell


def quantize(img: Image.Image, colors: int) -> Image.Image:
    arr = np.asarray(img)
    opaque = arr[..., 3] >= 128
    q = Image.fromarray(arr[..., :3]).quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    out = np.zeros_like(arr)
    out[..., :3] = np.asarray(q)
    out[..., 3] = np.where(opaque, 255, 0)
    return Image.fromarray(out, "RGBA")


def punch_hole(img: Image.Image, radius: float) -> Image.Image:
    """Прозрачный круг в центре (окно миникарты)."""
    arr = np.asarray(img).copy()
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    inside = (xx + 0.5 - w / 2) ** 2 + (yy + 0.5 - h / 2) ** 2 <= radius ** 2
    arr[inside, 3] = 0
    return Image.fromarray(arr, "RGBA")


def fill_plank(img: Image.Image) -> Image.Image:
    """Рамка листа-образца с прозрачной серединой → доска: середину заливаем тёмным деревом с зерном."""
    arr = np.asarray(img).copy()
    h, w = arr.shape[:2]
    rng = np.random.default_rng(7)
    base = np.array([0x62, 0x42, 0x2c], dtype=np.int16)
    grain = rng.integers(-5, 6, size=(h, w, 1))
    fill = np.clip(base + grain + np.arange(h)[:, None, None] * 0, 0, 255).astype(np.uint8)
    hole = arr[..., 3] < 128
    # заливаем только внутреннюю дыру (не внешний фон): внутренняя — та, что не касается краёв
    outside = Image.fromarray((hole * 255).astype(np.uint8))
    ImageDraw.floodfill(outside, (0, 0), 128, thresh=0)   # внешний фон помечаем 128, внутренняя дыра остаётся 255
    inner = np.asarray(outside) == 255
    arr[inner, :3] = fill[inner]
    arr[inner, 3] = 255
    return Image.fromarray(arr, "RGBA")


def button_parts(sheet: Image.Image, box: tuple[int, int, int, int]):
    """Круглая кнопка листа: (круг без иконки, иконка отдельно). Фон иконки — медиана кольца вокруг неё."""
    img = sheet.crop(box).convert("RGB")
    arr = np.asarray(img).astype(np.float32)
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w]
    r = np.sqrt((xx + 0.5 - w / 2) ** 2 + (yy + 0.5 - h / 2) ** 2) / (min(w, h) / 2)
    bg = np.median(arr[(r > 0.60) & (r < 0.68)], axis=0)
    base = arr.copy()
    base[r < 0.58] = bg
    alpha = np.where(r <= 1.0, 255, 0).astype(np.uint8)
    base_img = Image.fromarray(np.dstack([base.astype(np.uint8), alpha]), "RGBA")
    dist = np.abs(arr - bg).max(axis=2)
    ia = np.where((r < 0.58) & (dist > 38), 255, 0).astype(np.uint8)
    icon = np.dstack([arr.astype(np.uint8), ia])
    ys, xs = np.where(ia > 0)
    icon_img = Image.fromarray(icon, "RGBA").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return base_img, icon_img


# Панели 9-slice: имя → (лист, рамка, поле в px листа, поле на выходе, заливка середины RGB, цветов, убрать ли фон)
PANELS = {
    "panel_wood": (KIT, (45, 38, 640, 445), 70, 12, (0x5a, 0x3d, 0x29), 28, True),
    "panel_torn": (KIT, (45, 38, 640, 445), 70, 14, (0xe6, 0xd6, 0xb0), 28, True),
    "book_page": ("ui_book.png", (283, 85, 836, 805), 34, 8, (0xe6, 0xd6, 0xb0), 24, False),
}
CENTER = 16   # сторона растягиваемой середины текстуры, px


def nine_slice(name: str) -> Image.Image:
    sheet_name, box, src_m, out_m, fill, colors, strip_bg = PANELS[name]
    sheet = Image.open(GEN / sheet_name)
    reg = crop_rgba(sheet, box) if strip_bg else sheet.crop(box).convert("RGBA")
    w, h = reg.size
    size = out_m * 2 + CENTER
    tex = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rng = np.random.default_rng(11)
    noise = rng.integers(-4, 5, size=(CENTER, CENTER, 1)) if name != 'book_page' else np.zeros((CENTER, CENTER, 1), dtype=int)
    mid = np.clip(np.array(fill, dtype=np.int16) + noise, 0, 255).astype(np.uint8)
    tex.paste(Image.fromarray(np.dstack([mid, np.full((CENTER, CENTER, 1), 255, np.uint8)]), "RGBA"), (out_m, out_m))

    def put(src_box, dst_box):
        part = reg.crop(src_box)
        dw, dh = dst_box[2] - dst_box[0], dst_box[3] - dst_box[1]
        # растягиваем часть ровно в размер места (не вписываем по центру)
        arr = np.asarray(part).astype(np.float32)
        a = arr[..., 3:4] / 255.0
        pre = np.concatenate([arr[..., :3] * a, arr[..., 3:4]], axis=2)
        ch = [np.asarray(Image.fromarray(pre[..., i]).resize((dw, dh), Image.LANCZOS), dtype=np.float32) for i in range(4)]
        al = np.clip(ch[3] / 255.0, 0, 1)
        rgb = np.clip(np.stack(ch[:3], axis=2) / np.maximum(al[..., None], 1e-3), 0, 255)
        tex.alpha_composite(Image.fromarray(np.dstack([rgb, al * 255.0]).astype(np.uint8), "RGBA"), (dst_box[0], dst_box[1]))

    m, o, c = src_m, out_m, CENTER
    mx0, my0 = w // 2 - m, h // 2 - m   # где брать ровные участки кромки
    put((0, 0, m, m), (0, 0, o, o))
    put((w - m, 0, w, m), (o + c, 0, size, o))
    put((0, h - m, m, h), (0, o + c, o, size))
    put((w - m, h - m, w, h), (o + c, o + c, size, size))
    put((mx0, 0, mx0 + 2 * m, m), (o, 0, o + c, o))
    put((mx0, h - m, mx0 + 2 * m, h), (o, o + c, o + c, size))
    put((0, my0, m, my0 + 2 * m), (0, o, o, o + c))
    put((w - m, my0, w, my0 + 2 * m), (o + c, o, size, o + c))
    return quantize(tex, colors)


def cover_texture(out_m: int = 14, colors: int = 28) -> Image.Image:
    """Обложка книги: латунный угол из эскиза (остальные — зеркалом), ремённая кромка сверху/снизу,
    боковые кромки — те же, повёрнутые."""
    sheet = Image.open(GEN / "ui_book.png").convert("RGB")
    corner = sheet.crop((200, 50, 275, 125))
    top = sheet.crop((330, 54, 520, 92))
    bottom = sheet.crop((390, 812, 630, 852))

    def resize(img, size):
        return img.resize(size, Image.LANCZOS)

    o, c = out_m, CENTER
    size = o * 2 + c
    tex = Image.new("RGBA", (size, size), (0x2e, 0x1d, 0x14, 255))
    cor = resize(corner, (o, o)).convert("RGBA")
    t = resize(top, (c, o)).convert("RGBA")
    b = resize(bottom, (c, o)).convert("RGBA")
    tex.alpha_composite(t, (o, 0))
    tex.alpha_composite(b, (o, o + c))
    left = t.rotate(90, expand=True)     # (o, c)
    right = b.rotate(-90, expand=True)
    tex.alpha_composite(left, (0, o))
    tex.alpha_composite(right, (o + c, o))
    tex.alpha_composite(cor, (0, 0))
    tex.alpha_composite(cor.transpose(Image.FLIP_LEFT_RIGHT), (o + c, 0))
    tex.alpha_composite(cor.transpose(Image.FLIP_TOP_BOTTOM), (0, o + c))
    tex.alpha_composite(cor.transpose(Image.ROTATE_180), (o + c, o + c))
    # середина — тёмная кожа (её закрывают страницы)
    mid = Image.new("RGBA", (c, c), (0x3a, 0x22, 0x1a, 255))
    tex.alpha_composite(mid, (o, o))
    return quantize(tex, colors)


def build(name: str) -> Image.Image:
    sheet_name, box, size, colors, special = ELEMENTS[name]
    sheet = Image.open(GEN / sheet_name)
    if special.startswith("btn_"):
        base, icon = button_parts(sheet, box)
        if special == "btn_icon":
            return quantize(fit(icon, size), colors)
        out = quantize(fit(base, size), colors)
        if special == "btn_base_dark":
            arr = np.asarray(out).copy()
            arr[..., :3] = (arr[..., :3] * 0.72).astype(np.uint8)
            out = Image.fromarray(arr, "RGBA")
        return out
    if special == "round":
        # круглый вырез из картинки без удаления фона (эмблема лежит на дереве планки)
        el = sheet.crop(box).convert("RGBA")
    elif special == "plank":
        el = fill_plank(crop_rgba(sheet, box))
    else:
        el = crop_rgba(sheet, box)
    if special == "round":
        # круглая эмблема: всё за кругом — прозрачно
        w, h = el.size
        yy, xx = np.mgrid[0:h, 0:w]
        outside = (xx - w / 2) ** 2 + (yy - h / 2) ** 2 > (min(w, h) / 2) ** 2
        arr = np.asarray(el).copy()
        arr[outside, 3] = 0
        el = Image.fromarray(arr, "RGBA")
    out = quantize(fit(el, size), colors)
    if special == "ring":
        out = punch_hole(out, 34.0)
    return out


def bookmark_tab(base: str, light: str, dark: str) -> Image.Image:
    """Закладка-язычок 20×16 (торчит вправо): кожа с обводкой, строчка и латунная заклёпка."""
    img = Image.new("RGBA", (20, 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline = "#2a1e18"
    d.rectangle((0, 0, 19, 15), fill=outline)
    for x, y in [(19, 0), (19, 15), (18, 0), (18, 15), (19, 1), (19, 14)]:
        img.putpixel((x, y), (0, 0, 0, 0))
    d.rectangle((1, 1, 17, 14), fill=base)
    d.line((1, 1, 17, 1), fill=light)
    d.line((1, 14, 17, 14), fill=dark)
    for x in range(4, 17, 2):
        d.point((x, 3), fill=dark)
        d.point((x, 12), fill=dark)
    d.rectangle((3, 6, 5, 9), fill="#c9a040")
    d.point((3, 6), fill="#e8c870")
    d.point((4, 6), fill="#e8c870")
    d.point((5, 9), fill="#7a5a20")
    return img


BOOK_ART = "ui_book_frame_clean.webp"   # готовая книга автора (шахматка вместо прозрачности — фон снимается тут)
BOOK_K = 2.05                           # px арта на UI-пиксель (холст 640×360 ≈ 1360×765 / 2,125)


def clear_checker(a: np.ndarray) -> np.ndarray:
    """Маска «это шахматка вместо прозрачности»: нейтрально-светлые пиксели + светлая кайма вокруг них
    (сглаженные края картинки дают светлые пиксели, которые не проходят строгий порог — они давали белую рябь)."""
    from PIL import ImageFilter
    chroma = a.max(axis=2) - a.min(axis=2)
    core = (a.min(axis=2) > 205) & (chroma < 14)
    m = np.asarray(Image.fromarray((core * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(3))) == 255
    clear = m & core
    fringe = (a.min(axis=2) > 150) & (chroma < 34)
    for _ in range(3):
        grown = np.asarray(Image.fromarray((clear * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(3))) == 255
        clear = clear | (grown & fringe)
    return clear


def book_alpha() -> np.ndarray:
    """Книга автора: RGBA без шахматки."""
    a = np.asarray(Image.open(GEN / BOOK_ART).convert("RGB")).astype(int)
    bg = clear_checker(a)
    return np.dstack([a.astype(np.uint8), np.where(bg, 0, 255).astype(np.uint8)])


def _tile_band(arr, x0, x1, band, y0, y1):
    b = arr[band[0]:band[1], x0:x1].copy()
    n, y, flip = b.shape[0], y0, False
    while y < y1:
        seg = b[::-1] if flip else b
        h = min(n, y1 - y)
        arr[y:y + h, x0:x1] = seg[:h]
        y += n
        flip = not flip


def _erase_icon(arr, icon_box, sample_x):
    """Затирает иконку на язычке: каждая строка заполняется средним цветом столбцов слева от иконки."""
    x0, y0, x1, y1 = icon_box
    for y in range(y0, y1):
        arr[y, x0:x1, :3] = arr[y, sample_x[0]:sample_x[1], :3].mean(axis=0).astype(np.uint8)


def book_art() -> list[tuple[str, Image.Image]]:
    """Книга автора → book_frame.png (без язычков, кромка восстановлена) и четыре язычка без иконок."""
    full = book_alpha()
    tabs = {}
    for name, box, icon, sample in [
        ("tab_left", (65, 237, 224, 342), (118, 262, 168, 308), (104, 116)),
        ("tab_left_active", (65, 110, 224, 217), (126, 140, 162, 182), (100, 120)),
        ("tab_right", (1166, 125, 1306, 235), (1212, 158, 1250, 198), (1194, 1208)),
    ]:
        t = full.copy()
        x0, y0, x1, y1 = box
        sub = t[y0:y1, x0:x1].copy()
        _erase_icon(sub, (icon[0] - x0, icon[1] - y0, icon[2] - x0, icon[3] - y0), (sample[0] - x0, sample[1] - x0))
        tabs[name] = Image.fromarray(sub, "RGBA")
    tabs["tab_right_active"] = tabs["tab_left_active"].transpose(Image.FLIP_LEFT_RIGHT)
    body = full.copy()
    _tile_band(body, 160, 228, (342, 365), 100, 615)
    _tile_band(body, 1165, 1215, (364, 383), 112, 512)
    body_img = Image.fromarray(body, "RGBA").crop((160, 36, 1210, 734))
    out = []
    w, h = body_img.size
    out.append(("book_frame", quantize(fit(body_img, (round(w / BOOK_K), round(h / BOOK_K))), 56)))
    for n, img in tabs.items():
        out.append((n, quantize(fit(img, (round(img.width / BOOK_K), round(img.height / BOOK_K))), 28)))
    return out


CREAM = (0xe9, 0xd8, 0xb4)
CREAM_SHADE = (0xb8, 0xa2, 0x78)


def _draw_icon(kind: str) -> Image.Image:
    """Недостающие значки в тон авторским (кремовые на коже): ключ и лупа. Рисуем крупно и уменьшаем."""
    S = 200
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if kind == "key":
        d.ellipse((18, 18, 100, 100), fill=CREAM)
        d.ellipse((46, 46, 72, 72), fill=(0, 0, 0, 0))
        d.polygon([(82, 82), (96, 68), (172, 144), (158, 158)], fill=CREAM)
        d.polygon([(132, 104), (146, 90), (168, 112), (154, 126)], fill=CREAM)   # зубец 1
        d.polygon([(154, 126), (168, 112), (186, 130), (172, 144)], fill=CREAM)  # зубец 2
        d.arc((18, 18, 100, 100), 20, 110, fill=CREAM_SHADE, width=7)
    else:  # лупа
        d.ellipse((14, 14, 134, 134), fill=CREAM)
        d.ellipse((40, 40, 108, 108), fill=(0, 0, 0, 0))
        d.polygon([(112, 124), (126, 110), (186, 170), (172, 184)], fill=CREAM)
        d.arc((14, 14, 134, 134), 200, 290, fill=CREAM_SHADE, width=8)
    return im


def tab_icons() -> list[tuple[str, Image.Image]]:
    """Значки разделов книги 20×20: шесть вырезаны из рисунка автора (шлем, сумка, звезда, дневник, люди, мечи),
    ключ и лупа дорисованы в тон. Имена файлов — tabicon_<id раздела из Book.SECTIONS>."""
    src = Image.open(GEN / BOOK_ART).convert("RGB")
    arr = np.asarray(src).astype(np.float32)
    centers = {"sword": (143, 158), "flask": (143, 545), "soul": (143, 412), "quill": (1230, 433),
               "people": (143, 285), "skull": (1229, 305)}
    out = []
    for name, (cx, cy) in centers.items():
        r = 24
        crop = arr[cy - r:cy + r, cx - r:cx + r]
        edge = np.concatenate([crop[0], crop[-1], crop[:, 0], crop[:, -1]])
        bg = np.median(edge, axis=0)
        dist = np.abs(crop - bg).max(axis=2)
        alpha = np.clip((dist - 22) / 50.0, 0, 1)
        # перекрас в единые кремовые тона по яркости (на зелёном язычке значок иначе позеленел бы)
        lum = crop.mean(axis=2)
        t = np.clip((lum - np.percentile(lum[alpha > 0.3], 5)) / max(1.0, np.percentile(lum[alpha > 0.3], 95) - np.percentile(lum[alpha > 0.3], 5)), 0, 1)[..., None]
        dark = np.array([0x8c, 0x76, 0x54], dtype=np.float32)
        tint = dark + (np.array(CREAM, dtype=np.float32) - dark) * t
        rgba = np.dstack([tint, alpha * 255]).astype(np.uint8)
        im = Image.fromarray(rgba, "RGBA")
        ys, xs = np.where(alpha > 0.3)
        im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        out.append((f"tabicon_{name}", quantize(fit(im, (20, 20)), 12)))
    for name, kind in (("key", "key"), ("clue", "lupa")):
        out.append((f"tabicon_{name}", quantize(fit(_draw_icon(kind), (20, 20)), 8)))
    return out


def cloth_tile(size: int = 32) -> Image.Image:
    """Тёмно-зелёная ткань (полотно/сукно) для фона меню: тонкое плетение 1 px с лёгким шумом, стыкуется по краям."""
    rng = np.random.default_rng(5)
    base = np.array([0x2c, 0x42, 0x35], dtype=np.float32)
    y, x = np.mgrid[0:size, 0:size]
    weave = np.where(((x + y) % 4 < 2) ^ ((x // 2 + y // 2) % 2 == 0), 6.0, -6.0)   # шахматка нитей
    thread = np.where(x % 4 == 0, -5.0, 0.0) + np.where(y % 4 == 0, -4.0, 0.0)
    noise = rng.integers(-4, 5, size=(size, size)).astype(np.float32)
    shade = (weave + thread + noise)[..., None]
    img = np.clip(base + shade, 0, 255).astype(np.uint8)
    return Image.fromarray(np.dstack([img, np.full((size, size, 1), 255, np.uint8)]), "RGBA")


def menu_art() -> list[tuple[str, Image.Image]]:
    """Главное меню автора: рама (ui_menu_frame.webp — шахматка вместо прозрачности) и фон (ui_menu_bg.webp —
    разрез башни с рваными светлыми краями). Оба сводятся к холсту 640×360."""
    from PIL import ImageFilter
    a = np.asarray(Image.open(GEN / "ui_menu_frame.webp").convert("RGB")).astype(int)
    clear = clear_checker(a)
    # края сглажены с шахматкой — остаётся светлая «бахрома»: съедаем 3 px кромки у прозрачных областей
    for _ in range(3):
        clear = np.asarray(Image.fromarray((clear * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(3))) == 255
    frame = Image.fromarray(np.dstack([a.astype(np.uint8), np.where(clear, 0, 255).astype(np.uint8)]), "RGBA")
    # фон: серая заливка под цвет картины + сама картина без рваных светлых краёв, края мягко растушёваны
    pic = Image.open(GEN / "ui_menu_bg.webp").convert("RGB")
    w, h = pic.size
    px = np.asarray(pic).astype(np.float32)
    rows = np.median(px[:, 300:380], axis=1)                       # серый «пятна» картины по строкам
    k = np.ones(61) / 61.0                                          # сглаживаем по вертикали, чтобы не было полос
    rows = np.stack([np.convolve(np.pad(rows[:, c], 30, mode="edge"), k, mode="valid") for c in range(3)], axis=1)
    plate = Image.fromarray(np.repeat(rows[:, None, :], w, axis=1).astype(np.uint8), "RGB")
    x0, x1 = 330, 1345
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rectangle((x0, 0, x1, h), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(45))
    plate.paste(pic, (0, 0), mask)
    bg = quantize(fit(plate.convert("RGBA"), (640, 360)), 64)
    return [("menu_bg", bg), ("menu_cloth", cloth_tile()), ("menu_frame", fit(frame, (1920, 1080)))]   # рама — в полном разрешении (1080p), без сведения к 640×360: так чётче


def extras() -> list[tuple[str, Image.Image]]:
    out = book_art() + tab_icons() + menu_art() + [
        ("bookmark", bookmark_tab("#5c3a2a", "#76503a", "#3f2619")),
        ("bookmark_active", bookmark_tab("#4e6253", "#6b8573", "#34463a")),
    ]
    close = Image.open(OUT / "close.png").convert("RGBA")
    arr = np.asarray(close).astype(np.float32)
    arr[..., :3] = np.clip(arr[..., :3] * 1.25 + 8, 0, 255)
    out.append(("close_hover", Image.fromarray(arr.astype(np.uint8), "RGBA")))
    return out


def main() -> None:
    names = [n for n in sys.argv[1:] if n != 'extras'] or ([] if 'extras' in sys.argv[1:] else (list(ELEMENTS) + list(PANELS) + ['book_cover']))
    made = []
    for n in names:
        img = cover_texture() if n == 'book_cover' else nine_slice(n) if n in PANELS else build(n)
        img.save(OUT / f"{n}.png")
        made.append((n, img))
        print(f"  {n}.png {img.size}")
    if len(sys.argv) == 1 or "extras" in sys.argv[1:]:
        for n, img in extras():
            img.save(OUT / f"{n}.png")
            made.append((n, img))
            print(f"  {n}.png {img.size}")
    width = sum(i.width + 4 for _, i in made) + 4
    height = max(i.height for _, i in made) + 8
    sheet = Image.new("RGBA", (width, height), (96, 96, 112, 255))
    x = 4
    for _, i in made:
        sheet.alpha_composite(i, (x, 4))
        x += i.width + 4
    PREVIEW.parent.mkdir(exist_ok=True)
    sheet.resize((sheet.width * 6, sheet.height * 6), Image.NEAREST).save(PREVIEW)
    print("превью:", PREVIEW)


if __name__ == "__main__":
    main()
