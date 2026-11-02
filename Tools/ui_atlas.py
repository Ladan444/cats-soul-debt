"""Рисует пиксель-арт интерфейса («дерево + пергамент», см. Литература/UI_SPEC.md).

Все файлы — в размере 1 UI-пиксель = 1 пиксель; в игре интерфейс масштабируется целым числом.
Панели рассчитаны на 9-slice (поля указаны в docstring функций и в build_ui_theme.gd).

Запуск: python Tools/ui_atlas.py   (результат — Game/CatsSoulDebt/assets/ui/)
"""

import math
import random
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "Game" / "CatsSoulDebt" / "assets" / "ui"

# Палитра интерфейса — UI_SPEC, раздел 1.
WOOD_DARK = "#2E1D14"
WOOD = "#4F3322"
WOOD_GRAIN = "#45301F"
WOOD_LIGHT = "#76503A"
WOOD_SHADE = "#3A2619"
LEATHER = "#5C3A2A"
PARCHMENT = "#E6D6B0"
PARCHMENT_SHADE = "#C9B387"
PARCHMENT_DEEP = "#B39C70"
INK = "#2A1E18"
GREEN = "#4E6253"
BRASS = "#C9A040"
BRASS_LIGHT = "#E8C870"
BRASS_DARK = "#8A6A20"
BAR_BG = "#24160F"


def rgba(color: str, alpha: int = 255) -> tuple[int, int, int, int]:
    color = color.lstrip("#")
    return int(color[0:2], 16), int(color[2:4], 16), int(color[4:6], 16), alpha


def new(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def rect(img: Image.Image, x0: int, y0: int, x1: int, y1: int, color: str) -> None:
    """Заливка прямоугольника, x1/y1 включительно."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            img.putpixel((x, y), rgba(color))


def from_ascii(rows: list[str], colors: dict[str, str]) -> Image.Image:
    img = new(len(rows[0]), len(rows))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in colors:
                img.putpixel((x, y), rgba(colors[ch]))
    return img


def round_corners(img: Image.Image) -> None:
    w, h = img.size
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        img.putpixel((x, y), (0, 0, 0, 0))


# --- Панели и ячейки -----------------------------------------------------------

def panel_wood() -> Image.Image:
    """Деревянная панель 24x24, 9-slice с полями 6. Центр и края рассчитаны на тайлинг."""
    rng = random.Random(7)
    img = new(24, 24)
    rect(img, 0, 0, 23, 23, WOOD_DARK)
    rect(img, 1, 1, 22, 22, WOOD)
    # Волокна дерева: горизонтальные полосы с разрывами.
    for y in range(3, 21, 3):
        for x in range(2, 22):
            if rng.random() < 0.75:
                img.putpixel((x, y), rgba(WOOD_GRAIN))
    # Фаска: свет сверху-слева, тень снизу-справа.
    rect(img, 1, 1, 22, 1, WOOD_LIGHT)
    rect(img, 1, 1, 1, 22, WOOD_LIGHT)
    rect(img, 1, 22, 22, 22, WOOD_SHADE)
    rect(img, 22, 1, 22, 22, WOOD_SHADE)
    # Латунные заклёпки в углах.
    for cx, cy in ((3, 3), (19, 3), (3, 19), (19, 19)):
        rect(img, cx, cy, cx + 1, cy + 1, BRASS)
        img.putpixel((cx, cy), rgba(BRASS_LIGHT))
        img.putpixel((cx + 1, cy + 1), rgba(BRASS_DARK))
    round_corners(img)
    return img


def panel_parchment() -> Image.Image:
    """Пергаментная страница 24x24, 9-slice с полями 5."""
    rng = random.Random(11)
    img = new(24, 24)
    rect(img, 0, 0, 23, 23, PARCHMENT_DEEP)
    rect(img, 1, 1, 22, 22, PARCHMENT)
    rect(img, 1, 21, 22, 22, PARCHMENT_SHADE)
    rect(img, 21, 1, 22, 22, PARCHMENT_SHADE)
    for _ in range(14):  # пятна и неровности бумаги
        x, y = rng.randrange(3, 21), rng.randrange(3, 21)
        img.putpixel((x, y), rgba(PARCHMENT_SHADE))
    round_corners(img)
    return img


def panel_torn() -> Image.Image:
    """Лист рваной бумаги 32x32 (меню настроек), 9-slice с полями 8: неровный край, потёртости."""
    rng = random.Random(23)
    img = new(32, 32)
    rect(img, 0, 0, 31, 31, PARCHMENT)
    # Неровный край: по периметру выгрызаем 0–2 пикселя.
    for i in range(32):
        for edge in range(4):
            depth = rng.choice([0, 0, 1, 1, 2])
            for d in range(depth):
                x, y = [(i, d), (i, 31 - d), (d, i), (31 - d, i)][edge]
                img.putpixel((x, y), (0, 0, 0, 0))
    # Тёмная кайма у края и пятна.
    pixels = img.load()
    for y in range(32):
        for x in range(32):
            if pixels[x, y][3] == 0:
                continue
            near_edge = any(
                not (0 <= x + dx < 32 and 0 <= y + dy < 32) or pixels[x + dx, y + dy][3] == 0
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if near_edge:
                img.putpixel((x, y), rgba(PARCHMENT_DEEP))
    for _ in range(20):
        x, y = rng.randrange(4, 28), rng.randrange(4, 28)
        img.putpixel((x, y), rgba(PARCHMENT_SHADE))
    return img


CLAW = [  # латунный «коготь» — указатель выбранного пункта меню
    "XX.....",
    "XYX....",
    ".XYX...",
    "..XYYX.",
    ".XYyX..",
    "XYyX...",
    "XX.....",
]


def slot(selected: bool = False) -> Image.Image:
    """Ячейка 22x22: деревянная рамка 2 px и пергамент внутри. Не тянется."""
    img = new(22, 22)
    rect(img, 0, 0, 21, 21, BRASS if selected else WOOD_DARK)
    rect(img, 1, 1, 20, 20, WOOD_LIGHT)
    rect(img, 2, 2, 20, 20, WOOD_SHADE)
    rect(img, 2, 2, 19, 19, PARCHMENT_SHADE)
    rect(img, 3, 3, 19, 19, PARCHMENT)
    rect(img, 3, 3, 19, 3, PARCHMENT_SHADE)  # внутренняя тень сверху
    if selected:
        for x, y in ((1, 1), (20, 1), (1, 20), (20, 20)):
            img.putpixel((x, y), rgba(BRASS_LIGHT))
    round_corners(img)
    return img


def emblem_socket() -> Image.Image:
    """Гнездо центральной эмблемы 28x28: круглая деревянная оправа."""
    img = new(28, 28)
    c = 13.5
    for y in range(28):
        for x in range(28):
            d = math.hypot(x - c, y - c)
            if d <= 13.6:
                color = WOOD_DARK if d > 12.6 else (WOOD_LIGHT if (x + y) < 27 and d > 11.2 else WOOD)
                img.putpixel((x, y), rgba(color))
    return img


def bar_frame() -> Image.Image:
    """Рамка полосы 12x9, 9-slice с полями 3; внутри — пустой тёмный фон."""
    img = new(12, 9)
    rect(img, 0, 0, 11, 8, WOOD_DARK)
    rect(img, 1, 1, 10, 7, WOOD_LIGHT)
    rect(img, 1, 7, 10, 7, WOOD_SHADE)
    rect(img, 2, 2, 9, 6, BAR_BG)
    round_corners(img)
    return img


def plank() -> Image.Image:
    """Подложка хотбара 32x16, 9-slice с полями 5: тёмная доска с кожаным ремнём по низу."""
    rng = random.Random(3)
    img = new(32, 16)
    rect(img, 0, 0, 31, 15, WOOD_DARK)
    rect(img, 1, 1, 30, 14, WOOD)
    for y in (4, 7, 10):
        for x in range(2, 30):
            if rng.random() < 0.7:
                img.putpixel((x, y), rgba(WOOD_GRAIN))
    rect(img, 1, 1, 30, 1, WOOD_LIGHT)
    rect(img, 1, 12, 30, 14, LEATHER)
    rect(img, 1, 12, 30, 12, WOOD_SHADE)
    for x in range(3, 30, 4):  # стежки на ремне
        img.putpixel((x, 13), rgba(PARCHMENT_SHADE))
    round_corners(img)
    return img


# --- Иконки --------------------------------------------------------------------

HEART = [  # кошачье сердце: сердце с ушками на долях
    ".X.......X.",
    "XrX.....XrX",
    "XrrXX.XXrrX",
    "XrRrrXrrrrX",
    "XrRrrrrrrrX",
    "XrrrrrrrrrX",
    ".XrrrrrrrX.",
    "..XrrrrrX..",
    "...XrrrX...",
    "....XrX....",
    ".....X.....",
]

SOUL = [  # огонёк души
    "....X....",
    "...XcX...",
    "..XcCcX..",
    "..XcCcX..",
    ".XcCWCcX.",
    ".XcCWCcX.",
    ".XccCccX.",
    "..XcccX..",
    "...XXX...",
]

SPARK = [  # искра души — отметка смерти
    "...X...",
    "..XCX..",
    ".XCWCX.",
    "XCWWWCX",
    ".XCWCX.",
    "..XCX..",
    "...X...",
]

COIN = [  # монета Гелиос: солнце на латуни
    "..XXXXX..",
    ".XYYYYYX.",
    "XYyyOyyyX",
    "XYyOOOyyX",
    "XYOOWOOyX",
    "XYyOOOyyX",
    "XyyyOyyyX",
    ".XyyyyyX.",
    "..XXXXX..",
]

FLASK = [  # заглушка предмета: настойка
    "....XXXX....",
    "....XwwX....",
    ".....XX.....",
    "....XwwX....",
    "...XwwwwX...",
    "..XrrrrrrX..",
    ".XrRrrrrrrX.",
    ".XrRrrrrrrX.",
    ".XrrrrrrrrX.",
    "..XrrrrrrX..",
    "...XXXXXX...",
]


# --- Иконки-заглушки предметов 14x14 (до ИИ-иконок, UI_SPEC шаг 6) ---------------

ICON_INK = "#2A1E18"

ITEM_ICONS = {
    "icon_sword.png": ([
        "...........XX.",
        "..........XwX.",
        ".........XwX..",
        "........XwX...",
        ".......XwX....",
        "......XwX.....",
        "..XX.XwX......",
        "..XyXwX.......",
        "...XyX........",
        "..XbXyX.......",
        ".XbX.XX.......",
        "XbX...........",
        "XX............",
        "..............",
    ], {"X": ICON_INK, "w": "#C8CCD0", "y": BRASS, "b": "#8A6A4A"}),
    "icon_cloak.png": ([
        "....XXXXXX....",
        "...XgggggGX...",
        "...XgXXXXgX...",
        "..XggXyyXggX..",
        "..XgggXXgggX..",
        ".XgggggggggGX.",
        ".XggggggggggX.",
        ".XgdgggggggGX.",
        "XggdggggggggGX",
        "XggdgggggggggX",
        "XgdggggggggggX",
        "XggggggggggggX",
        "XgXgXgXgXgXgXX",
        ".X.X.X.X.X.X..",
    ], {"X": ICON_INK, "g": "#5A6E60", "G": "#66796C", "d": "#3F4D43", "y": BRASS}),
    "icon_armor.png": ([
        "..XXX....XXX..",
        ".XmmmXXXXmmmX.",
        "XmMmmmmmmmmMmX",
        "XmmmmXmmXmmmmX",
        "XXmmmXmmXmmmXX",
        ".XmmmmXXmmmmX.",
        ".XmmmmmmmmmmX.",
        ".XMmmmmmmmmmX.",
        ".XmmmmmmmmmmX.",
        ".XllllllllllX.",
        ".XmmmmyymmmmX.",
        ".XmmmmmmmmmmX.",
        "..XmmmmmmmmX..",
        "...XXXXXXXX...",
    ], {"X": ICON_INK, "m": "#9A9AA0", "M": "#C8CCD0", "l": "#8A6A4A", "y": BRASS}),
    "icon_amulet.png": ([
        "...cc....cc...",
        "..c........c..",
        ".c..........c.",
        ".c..........c.",
        "..c........c..",
        "...c......c...",
        "....c....c....",
        ".....XXXX.....",
        "....XyyyyX....",
        "...XyYppyyX...",
        "...XyppppyX...",
        "...XyyppyyX...",
        "....XyyyyX....",
        ".....XXXX.....",
    ], {"X": ICON_INK, "c": BRASS_DARK, "y": BRASS, "Y": BRASS_LIGHT, "p": "#7A3CB0"}),
    "icon_relic.png": ([
        "....XXXXXX....",
        "....XrRrrX....",
        "....XrRrrX....",
        ".....XrrX.....",
        "......XX......",
        "....XXXXXX....",
        "...XyYyyyyX...",
        "..XyYyyOyyyX..",
        "..XyyyOOOyyX..",
        "..XyyOOOOOyX..",
        "..XyyyOOOyyX..",
        "..XyyyyOyyyX..",
        "...XyyyyyyX...",
        "....XXXXXX....",
    ], {"X": ICON_INK, "r": "#7A2A24", "R": "#B23A3A", "y": BRASS, "Y": BRASS_LIGHT, "O": "#A87A20"}),
    "icon_key.png": ([
        "..............",
        "..............",
        "..XXXX........",
        ".XyyyyX.......",
        "XyX..XyX......",
        "XyX..XyX......",
        ".XyyyyXXXXXXX.",
        "..XXXXyyyyyyyX",
        "......XXXyXyX.",
        ".........X.X..",
        "..............",
        "..............",
        "..............",
        "..............",
    ], {"X": ICON_INK, "y": BRASS}),
    "icon_letter.png": ([
        "..............",
        ".XXXXXXXXXXXX.",
        ".XppppppppppX.",
        ".XpiiiiiiippX.",
        ".XppppppppppX.",
        ".XpiiiiippppX.",
        ".XppppppppppX.",
        ".XpiiiiiiippX.",
        ".XppppppppppX.",
        ".XpiiiippprpX.",
        ".XppppppprrrX.",
        ".XpppppppprpX.",
        ".XXXXXXXXXXXX.",
        "..............",
    ], {"X": ICON_INK, "p": PARCHMENT, "i": "#6A5A48", "r": "#B23A3A"}),
    "icon_whetstone.png": ([
        "..............",
        "..............",
        "..............",
        "........XXXX..",
        "......XXsSsX..",
        "....XXssSssX..",
        "..XXssssssXX..",
        ".XsSsssssX....",
        ".XssssssX.....",
        ".XsssXXX......",
        "..XXX.........",
        "..............",
        "..............",
        "..............",
    ], {"X": ICON_INK, "s": "#7A7A80", "S": "#A8A8B0"}),
    "icon_herb.png": ([
        "......XX......",
        ".....XgGX.....",
        "..XX.XgX.XX...",
        ".XgGXXgXXgGX..",
        ".XggXgXgXggX..",
        "..XXggXggXX...",
        "....XgXgX.....",
        "..XXgXgXgXX...",
        ".XgGXXgXXgGX..",
        "..XX.XgX.XX...",
        ".....XgX......",
        ".....XbX......",
        "....XbbbX.....",
        ".....XXX......",
    ], {"X": ICON_INK, "g": "#5E8C64", "G": "#8FBF7A", "b": "#8A6A4A"}),
}


# --- Книга, закладки, кнопки (референсы автора: книга с латунными уголками, блокнот с закладками,
# круглые деревянные кнопки, глифы клавиш) ----------------------------------------------------

LEATHER_RED = "#5E2224"
LEATHER_RED_DARK = "#3E1416"
LEATHER_RED_LIGHT = "#7A3234"
PAGE = "#EEDDB0"
PAGE_SHADE = "#D8C494"
PAGE_EDGE = "#C4AE7E"


def book_cover() -> Image.Image:
    """Кожаная обложка 32x32, 9-slice с полями 10: латунные уголки, светлая кромка сверху."""
    rng = random.Random(5)
    img = new(32, 32)
    rect(img, 0, 0, 31, 31, LEATHER_RED_DARK)
    rect(img, 1, 1, 30, 30, LEATHER_RED)
    for _ in range(30):  # потёртости кожи
        x, y = rng.randrange(2, 30), rng.randrange(2, 30)
        img.putpixel((x, y), rgba(LEATHER_RED_LIGHT if rng.random() < 0.5 else LEATHER_RED_DARK))
    rect(img, 1, 1, 30, 1, LEATHER_RED_LIGHT)
    # Латунные уголки-треугольники.
    for cx, cy, dx, dy in ((0, 0, 1, 1), (31, 0, -1, 1), (0, 31, 1, -1), (31, 31, -1, -1)):
        for i in range(7):
            for j in range(7 - i):
                img.putpixel((cx + dx * i, cy + dy * j), rgba(BRASS if i + j < 6 else BRASS_DARK))
        img.putpixel((cx + dx, cy + dy), rgba(BRASS_LIGHT))
    round_corners(img)
    return img


def book_page() -> Image.Image:
    """Страница 24x24, 9-slice с полями 6: кремовая, скруглённые углы, тень по краю."""
    img = new(24, 24)
    rect(img, 1, 0, 22, 23, PAGE_EDGE)
    rect(img, 0, 1, 23, 22, PAGE_EDGE)
    rect(img, 1, 1, 22, 22, PAGE)
    rect(img, 1, 21, 22, 22, PAGE_SHADE)
    rect(img, 2, 1, 21, 1, "#F6EACA")
    return img


def bookmark(active: bool) -> Image.Image:
    """Закладка 20x16, торчит вправо из-за края книги; влево — отражение в коде."""
    img = new(20, 16)
    body, light, dark = ((PARCHMENT, "#F6EACA", PARCHMENT_DEEP) if active
                         else (LEATHER_RED_LIGHT, "#8E4446", LEATHER_RED_DARK))
    rect(img, 0, 0, 17, 15, dark)
    rect(img, 18, 1, 18, 14, dark)
    rect(img, 19, 3, 19, 12, dark)
    rect(img, 0, 1, 17, 14, body)
    rect(img, 18, 3, 18, 12, body)
    rect(img, 0, 1, 17, 1, light)
    return img


def close_button(hover: bool) -> Image.Image:
    """Красный крестик закрытия 14x14 (как на референсе блокнота)."""
    img = new(14, 14)
    rect(img, 0, 0, 13, 13, "#5A1414")
    rect(img, 1, 1, 12, 12, "#D25050" if hover else "#B23A3A")
    rect(img, 1, 1, 12, 1, "#E87A7A")
    for i in range(7):
        for t in (0, 1):
            img.putpixel((3 + i + t, 3 + i), rgba("#F4F2EC"))
            img.putpixel((10 - i - t + 0, 3 + i), rgba("#F4F2EC"))
    round_corners(img)
    return img


def wood_button(pressed: bool) -> Image.Image:
    """Круглая деревянная кнопка 22x22 (референс автора) — для кнопок меню в HUD; иконка рисуется сверху."""
    img = new(22, 22)
    c = 10.5
    base = "#5A3A22" if pressed else "#6B4428"
    for y in range(22):
        for x in range(22):
            d = math.hypot(x - c, y - c)
            if d > 10.8:
                continue
            if d > 9.8:
                color = WOOD_DARK
            elif y in (7, 12, 16) and abs(x - c) < 7:
                color = WOOD_GRAIN if not pressed else "#4A3020"
            else:
                color = base
            # блик сверху-слева
            if not pressed and 7.5 < d <= 9.8 and x + y < 16:
                color = "#8A5A38"
            img.putpixel((x, y), rgba(color))
    if not pressed:
        rect(img, 6, 4, 7, 4, "#C89A6A")
    return img


def keycap() -> Image.Image:
    """Клавиша 12x13, 9-slice с полями 4: тёмная крышка, светлая грань, тень снизу."""
    img = new(12, 13)
    rect(img, 0, 0, 11, 12, "#1E1614")
    rect(img, 1, 1, 10, 9, "#5A4A44")
    rect(img, 1, 10, 10, 11, "#3A2E2A")
    rect(img, 1, 1, 10, 1, "#7A6A62")
    round_corners(img)
    return img


SMALL_ICONS = {  # 10x10 — для закладок и кнопок
    "sicon_sword.png": ([
        "........XX", ".......XwX", "......XwX.", ".....XwX..", "..X.XwX...",
        "..XXwX....", "...XyX....", "..XbXX....", ".XbX......", ".XX.......",
    ], {"X": ICON_INK, "w": "#C8CCD0", "y": BRASS, "b": "#8A6A4A"}),
    "sicon_flask.png": ([
        "...XXXX...", "...XwwX...", "....XX....", "...XwwX...", "..XwwwwX..",
        ".XrrrrrrX.", ".XrRrrrrX.", ".XrrrrrrX.", "..XrrrrX..", "...XXXX...",
    ], {"X": ICON_INK, "w": "#CFE0E0", "r": "#B23A3A", "R": "#E86A5A"}),
    "sicon_soul.png": ([
        "....X.....", "...XcX....", "..XcCcX...", "..XcCcX...", ".XcCWCcX..",
        ".XcCWCcX..", ".XccCccX..", "..XcccX...", "...XXX....", "..........",
    ], {"X": "#1F3F44", "c": "#8FD8D0", "C": "#CFF5EE", "W": "#FFFFFF"}),
    "sicon_key.png": ([
        "..........", ".XXX......", "XyyyX.....", "Xy.yXXXXX.", "XyyyXyyyyX",
        ".XXX.XyXyX", "......X.X.", "..........", "..........", "..........",
    ], {"X": ICON_INK, "y": BRASS}),
    "sicon_quill.png": ([
        "........XX", ".......XwX", "......XwwX", ".....XwwX.", "....XwwX..",
        "...XwwX...", "..XwXX....", "..XX......", ".X........", "X.........",
    ], {"X": ICON_INK, "w": "#F4F2EC"}),
    "sicon_map.png": ([
        "XXXXXXXXXX", "XpppPpppPX", "XpRpPpppPX", "XppRPpppPX", "XpRpPpRpPX",
        "XpppPRppPX", "XpppPpRpPX", "XpppPpppPX", "XXXXXXXXXX", "..........",
    ], {"X": ICON_INK, "p": PARCHMENT, "P": PARCHMENT_SHADE, "R": "#B23A3A"}),
    "sicon_people.png": ([
        "..X....X..", "..XX..XX..", "..XhhhhX..", "..XhhhhX..", "...XhhX...",
        "...XXXX...", "..XccccX..", ".XccccccX.", ".XccccccX.", ".XXXXXXXX.",
    ], {"X": ICON_INK, "h": "#F4F2EC", "c": "#5A6E60"}),
    "sicon_clue.png": ([
        "..XXXX....", ".XgggGX...", "XgggggGX..", "XgggggGX..", "XgggggGX..",
        ".XgggGX...", "..XXXXXX..", "......XbX.", ".......XbX", "........XX",
    ], {"X": ICON_INK, "g": "#A8D8E8", "G": "#E8FFFB", "b": "#8A6A4A"}),
    "sicon_skull.png": ([
        "..XXXXX...", ".XwwwwwX..", "XwwwwwwwX.", "XwXXwXXwX.", "XwXXwXXwX.",
        "XwwwXwwwX.", ".XwwwwwX..", "..XwXwX...", "..XXXXX...", "..........",
    ], {"X": ICON_INK, "w": "#E6D6B0"}),
    "sicon_book.png": ([
        ".XXXXXXXX.", "XrrrrrrrpX", "XrRrrrrrpX", "XrrrrrrrpX", "XrryyyrrpX",
        "XrrrrrrrpX", "XrrrrrrrpX", "XrrrrrrrpX", ".XXXXXXXX.", "..........",
    ], {"X": ICON_INK, "r": "#7A3234", "R": "#A85A5A", "p": PARCHMENT, "y": BRASS}),
    "sicon_gear.png": ([
        "....XX....", ".X.XggX.X.", "XgXggggXgX", ".XggXXggX.", "XggX..XggX",
        "XggX..XggX", ".XggXXggX.", "XgXggggXgX", ".X.XggX.X.", "....XX....",
    ], {"X": ICON_INK, "g": "#C8CCD0"}),
    # Для экранных кнопок касания: рывок (двойной шеврон) и «Действие» (кошачья лапа).
    "sicon_dash.png": ([
        "..........", "XX...XX...", "XcX..XcX..", ".XcX..XcX.", "..XcX..XcX",
        "..XcX..XcX", ".XcX..XcX.", "XcX..XcX..", "XX...XX...", "..........",
    ], {"X": "#1F3F44", "c": "#8FD8D0"}),
    "sicon_paw.png": ([
        ".XX....XX.", "XwwX..XwwX", "XwwXXXXwwX", ".XXwwwwXX.", "XXwwwwwwXX",
        "XwwwwwwwwX", "XwwwwwwwwX", ".XwwwwwwX.", "..XXXXXX..", "..........",
    ], {"X": ICON_INK, "w": "#E6D6B0"}),
}


def skill_placeholder() -> Image.Image:
    """Заглушка скилла 14x14: призрачное кольцо с искрой."""
    img = new(14, 14)
    c = 6.5
    for y in range(14):
        for x in range(14):
            d = math.hypot(x - c, y - c)
            if 5.2 <= d <= 6.6:
                img.putpixel((x, y), rgba("#1F3F44"))
            elif 4.0 <= d < 5.2:
                img.putpixel((x, y), rgba("#8FD8D0"))
    spark = from_ascii(SPARK, {"X": "#1F3F44", "C": "#8FD8D0", "W": "#F2FFFC"})
    img.alpha_composite(spark, (4, 4))
    return img


def emblem() -> Image.Image:
    """Печать Рубежа 22x22: чёрный камень, латунный обод, 9 отметин, фиолетовый центр."""
    img = new(22, 22)
    c = 10.5
    for y in range(22):
        for x in range(22):
            d = math.hypot(x - c, y - c)
            if d <= 10.6:
                if d > 9.5:
                    color = BRASS_DARK
                elif d > 8.5:
                    color = BRASS_LIGHT if (x + y) < 21 else BRASS
                else:
                    color = "#1E1A1E"
                img.putpixel((x, y), rgba(color))
    for i in range(9):
        a = -math.pi / 2 + i * 2 * math.pi / 9
        x, y = round(c + math.cos(a) * 6.3), round(c + math.sin(a) * 6.3)
        img.putpixel((x, y), rgba(BRASS))
    rect(img, 9, 9, 12, 12, "#4A2470")
    rect(img, 10, 10, 11, 11, "#9A5AD0")
    img.putpixel((10, 10), rgba("#D8B0FF"))
    return img


def minimap_ring() -> Image.Image:
    """Рамка миникарты 74×74: латунное кольцо с тёмным контуром и отметкой севера сверху (внутри — прозрачно)."""
    size, r_in, cx = 74, 34, 36.5
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    p = img.load()
    for y in range(size):
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cx) ** 2) ** 0.5
            if r_in - 0.5 <= d < r_in + 0.6:
                p[x, y] = (30, 22, 20, 255)
            elif r_in + 0.6 <= d < r_in + 2.2:
                light = (y < cx - 6) and (x < cx + 10)
                p[x, y] = (232, 200, 112, 255) if light else (176, 136, 64, 255)
            elif r_in + 2.2 <= d < r_in + 3.2:
                p[x, y] = (30, 22, 20, 255)
    # Отметка севера — треугольник над кольцом.
    for i in range(4):
        for x in range(int(cx) - 3 + i, int(cx) + 4 - i):
            p[x, i] = (30, 22, 20, 255) if i == 0 or x in (int(cx) - 3 + i, int(cx) + 3 - i) else (240, 228, 200, 255)
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    files = {
        "panel_wood.png": panel_wood(),
        "panel_parchment.png": panel_parchment(),
        "panel_torn.png": panel_torn(),
        "claw.png": from_ascii(CLAW, {"X": "#5A3A10", "Y": BRASS_LIGHT, "y": BRASS}),
        "slot.png": slot(),
        "slot_selected.png": slot(selected=True),
        "emblem_socket.png": emblem_socket(),
        "bar_frame.png": bar_frame(),
        "plank.png": plank(),
        "icon_heart.png": from_ascii(HEART, {"X": "#3A1418", "r": "#B23A3A", "R": "#E86A5A"}),
        "icon_soul.png": from_ascii(SOUL, {"X": "#1F3F44", "c": "#8FD8D0", "C": "#CFF5EE", "W": "#FFFFFF"}),
        "spark_full.png": from_ascii(SPARK, {"X": "#1F3F44", "C": "#8FD8D0", "W": "#F2FFFC"}),
        "spark_spent.png": from_ascii(SPARK, {"X": "#1A0C26", "C": "#4A2470", "W": "#7A3CB0"}),
        "icon_helios.png": from_ascii(COIN, {"X": "#5A3A10", "Y": BRASS_LIGHT, "y": BRASS, "O": "#A87A20", "W": "#FFF0B0"}),
        "icon_item_placeholder.png": from_ascii(FLASK, {"X": INK, "w": "#CFE0E0", "r": "#B23A3A", "R": "#E86A5A"}),
        "icon_skill_placeholder.png": skill_placeholder(),
        "emblem.png": emblem(),
        "book_cover.png": book_cover(),
        "book_page.png": book_page(),
        "bookmark.png": bookmark(False),
        "bookmark_active.png": bookmark(True),
        "close.png": close_button(False),
        "close_hover.png": close_button(True),
        "wood_button.png": wood_button(False),
        "wood_button_pressed.png": wood_button(True),
        "keycap.png": keycap(),
        "minimap_ring.png": minimap_ring(),
    }
    for name, (rows, colors) in SMALL_ICONS.items():
        assert all(len(r) == 10 for r in rows) and len(rows) == 10, name
        files[name] = from_ascii(rows, colors)
    # Заглушки иконок предметов и скиллов не перезаписывают уже лежащие файлы (там могут быть ИИ-иконки
    # из icon_pipeline.py). Перерисовать заглушки принудительно: python Tools/ui_atlas.py --force
    force = "--force" in sys.argv
    placeholders = {f"icon_skill_{sid}.png": skill_placeholder() for sid in ("ghost_step", "echo_strike", "watch_mark")}
    for name, (rows, colors) in ITEM_ICONS.items():
        assert all(len(r) == 14 for r in rows) and len(rows) == 14, name
        placeholders[name] = from_ascii(rows, colors)
    for name, img in placeholders.items():
        if force or not (OUT / name).exists():
            files[name] = img
    for name, img in files.items():
        img.save(OUT / name)
    print(f"сохранено {len(files)} файлов в {OUT}")

    # Превью для проверки: всё на сером фоне, x6.
    sheet = Image.new("RGBA", (400, 100), rgba("#606070"))
    x, y = 4, 4
    for img in files.values():
        if x + img.width > 396:
            x, y = 4, y + 34
        sheet.alpha_composite(img, (x, y))
        x += img.width + 4
    sheet.resize((sheet.width * 6, sheet.height * 6), Image.NEAREST).save(
        Path(__file__).resolve().parent.parent / "Арт" / "Обработано" / "ui_atlas_preview.png")


if __name__ == "__main__":
    main()
