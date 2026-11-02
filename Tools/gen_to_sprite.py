"""Генерация (лист из трёх видов на белом фоне) → игровые спрайты: фон в прозрачность, вид на ячейку,
уменьшение до роста в пикселях, сведение палитры. Плюс сравнительный лист с Рэем.

  python Tools/gen_to_sprite.py <лист.png> <рост_px> <выход_без_расширения> [--colors 24] [--crop-top N] [--crop-bottom N]
Пишет <выход>_front.png, _back.png, _side.png (рост — по высоте фигуры).
"""
import argparse
from pathlib import Path
from PIL import Image, ImageFilter


def mask_bg(img: Image.Image, thr: int = 240) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            if r > thr and g > thr and b > thr:
                px[x, y] = (0, 0, 0, 0)
    return img


def split_views(img: Image.Image, n: int = 3) -> list[Image.Image]:
    """Генераторы ставят виды (кадры) в равные доли листа (фигуры могут соприкасаться посохом или хвостом)."""
    w, h = img.size
    views = []
    for i in range(n):
        part = img.crop((w * i // n, 0, w * (i + 1) // n, h))
        # рамка по «сплошной» фигуре: одиночные точки шума у краёв листа раздували её и сжимали кадр
        solid = part.getchannel("A").filter(ImageFilter.MinFilter(5))
        views.append(part.crop(solid.getbbox() or part.getbbox()))
    return views


def keep_main(img: Image.Image) -> Image.Image:
    """Оставить только самую большую связную фигуру: оторванные при уменьшении клочки (кисть, край плаща) висят в воздухе."""
    px = img.load()
    w, h = img.size
    seen, best = set(), []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] and (x, y) not in seen:
                comp, stack = [], [(x, y)]
                seen.add((x, y))
                while stack:
                    cx, cy = stack.pop()
                    comp.append((cx, cy))
                    for nx in range(cx - 1, cx + 2):
                        for ny in range(cy - 1, cy + 2):
                            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and px[nx, ny][3]:
                                seen.add((nx, ny))
                                stack.append((nx, ny))
                if len(comp) > len(best):
                    best = comp
    out = Image.new("RGBA", img.size)
    op = out.load()
    for x, y in best:
        op[x, y] = px[x, y]
    return out


def frames_strip(views: list[Image.Image], height: int, colors: int, cell: tuple[int, int]) -> Image.Image:
    """Кадры анимации: общий масштаб по самому высокому кадру (иначе фигура «прыгает» по росту), ступни на 4 px
    выше низа ячейки, по центру по горизонтали."""
    scale = height / max(v.height for v in views)
    strip = Image.new("RGBA", (cell[0] * len(views), cell[1]))
    for i, v in enumerate(views):
        s = keep_main(to_sprite(v, max(1, round(v.height * scale)), colors))
        strip.alpha_composite(s, (i * cell[0] + (cell[0] - s.width) // 2, cell[1] - 4 - s.height))
    return strip


def is_metal(p: tuple) -> bool:
    """Сталь клинков: светлый и почти без цвета (мех, ткань и кожа насыщеннее)."""
    r, g, b, a = p
    return a > 0 and 150 <= max(r, g, b) <= 240 and max(r, g, b) - min(r, g, b) < 22


def to_sprite(view: Image.Image, height: int, colors: int, metal_fix: bool = False) -> Image.Image:
    scale = height / view.height
    size = (max(1, round(view.width * scale)), height)
    small = view.resize(size, Image.LANCZOS)
    # Доля металла в каждом пикселе спрайта: тонкое лезвие (меньше пикселя после уменьшения) не растворяется в фоне.
    metal = Image.new("L", view.size)
    metal.putdata([255 if is_metal(p) else 0 for p in view.get_flattened_data()])
    metal = metal.resize(size, Image.BOX)
    alpha = small.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    rgb = small.convert("RGB").quantize(colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    rgb.putalpha(alpha)
    px, mp = rgb.load(), metal.load()
    for y in range(size[1]):
        for x in range(size[0]):
            if metal_fix and mp[x, y] > 35 and px[x, y][3]:
                px[x, y] = (205, 210, 215, 255)
    return outline(rgb)


def outline(img: Image.Image, k: float = 0.3) -> Image.Image:
    """Тёмная обводка как у Рэя: пиксель снаружи силуэта — цвет соседа, затемнённый (цветная, не чёрная линия).
    Снаружи, а не по краю: иначе тонкие детали (лезвие ножа в 1–2 px) целиком становились тёмными."""
    pad = Image.new("RGBA", (img.width + 2, img.height + 2))
    pad.alpha_composite(img, (1, 1))
    src = pad.load()
    out = pad.copy()
    dst = out.load()
    w, h = pad.size
    for y in range(h):
        for x in range(w):
            if src[x, y][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < w and 0 <= y + dy < h and src[x + dx, y + dy][3]:
                    r, g, b, _ = src[x + dx, y + dy]
                    dst[x, y] = (int(r * k) + 12, int(g * k) + 8, int(b * k) + 14, 255)
                    break
    return out


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("sheet")
    p.add_argument("height", type=int)
    p.add_argument("out")
    p.add_argument("--colors", type=int, default=24)
    p.add_argument("--crop-top", type=int, default=0)
    p.add_argument("--crop-bottom", type=int, default=0)
    p.add_argument("--frames", type=int, default=0, help="лист анимации: N кадров в ряд → одна полоса <выход>.png")
    p.add_argument("--cell", default="64x64", help="ячейка кадра для --frames")
    a = p.parse_args()
    img = Image.open(a.sheet)
    img = img.crop((0, a.crop_top, img.width, img.height - a.crop_bottom))
    img = mask_bg(img.resize((img.width // 2, img.height // 2), Image.LANCZOS))
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    if a.frames:
        cw, ch = (int(v) for v in a.cell.split("x"))
        frames_strip(split_views(img, a.frames), a.height, a.colors, (cw, ch)).save(f"{out}.png")
        print(f"{out}.png")
        return
    for name, v in zip(["front", "back", "side"], split_views(img)):
        to_sprite(v, a.height, a.colors).save(f"{out}_{name}.png")
        print(f"{out}_{name}.png")


if __name__ == "__main__":
    main()
