# UI PROMPTS: новый интерфейс (для ИИ-генерации)

Для кого: автор рисует/генерирует эскизы нового интерфейса, Claude (эпик `ui`) потом переносит их в игру.
Что это: эскизы-образцы (макеты экранов + лист элементов). Игра рисует интерфейс сама, из пиксельных
рамок (9-slice, `Tools/ui_atlas.py`) — поэтому нужны **образцы стиля и компоновки**, а не готовые экраны для вставки.
Исходные решения — `UI_SPEC.md`; палитра ниже взята оттуда. Текст в игре — Public Pixel Font (русский), на макетах он может быть любым.

Как пользоваться: общий блок стиля + промпт нужного экрана; негативный промпт — отдельно, если генератор его поддерживает.
Размер: 1920×1080 (в игре это холст 640×360 UI-пикселей, один UI-пиксель = 3 экранных). Просите «крупные чёткие пиксели»,
без сглаживания. Готовые картинки кладите в `Арт/Генерации/UI/` и говорите Claude.

---

## Общий блок стиля (вставлять в каждый промпт)
```
pixel art game user interface, dark fantasy medieval garrison, chunky visible pixels, crisp edges, no anti-aliasing,
1px dark outline (#2A1E18), limited warm palette: dark wood #2E1D14, wood #4F3322, light wood #76503A, leather #5C3A2A,
parchment #E6D6B0, parchment shadow #C9B387, ink #2A1E18, garrison green #4E6253, brass #C9A040 and #E8C870,
health red #B23A3A, spirit turquoise #8FD8D0 and #3E7E86, Silent Water purple #7A3CB0,
interface made of real objects: wooden planks with leather straps and brass rivets, a soldier's field journal with a leather cover,
torn parchment pages, brass bookmarks, worn and handmade, soft top-left light, HD-2D style like Octopath Traveler,
sharp pixel font, 1920x1080
```

## Негативный промпт
```
smooth gradients, blur, anti-aliasing, glossy, glass, neon, sci-fi, modern flat design, vector, 3D render, photo,
realistic text, watermark, characters faces, extra decorations covering the center, cluttered, low contrast
```

---

## 1. Лист элементов (самое полезное — стиль для всего интерфейса)
```
[общий блок стиля]
a UI kit sheet on a plain dark background, items laid out in a tidy grid with wide gaps, no scene:
1) a wooden plank panel frame with leather straps and brass rivets, stretchable (corners, edges, empty center);
2) a parchment page panel with torn edges, empty center;
3) an inventory slot, a rounded square 22x22 pixel cell, parchment shadow fill, dark wood border, in normal and selected (brass border) states;
4) a health bar: red fill with darker shadow inside a wooden trough, with a small heart icon at the left;
5) a spirit energy bar: turquoise fill inside a wooden trough, with a small flame icon at the right;
6) a row of nine small soul sparks (full turquoise and spent purple);
7) a round button with a brass rim and a book icon, another with a map icon, another with a gear icon;
8) three keycap labels (square key, wide key, round gamepad button A in green);
9) a brass claw pointer for selected menu items;
10) a leather bookmark tab with a brass pin, in normal and selected states;
11) a red-and-brass close button (X) in the corner of a frame;
12) a round minimap frame with a brass ring and a compass notch at the top
```

## 2. HUD в игре
```
[общий блок стиля]
HUD of a 2.5D game over a dim tavern scene with a small cat character in a green cloak in the middle:
bottom center a wooden plank bar with leather straps holding 4 skill slots on the left and 4 item slots on the right,
a brass emblem seal with a tower in the center between them, above the slots a red health bar on the left and a turquoise spirit energy bar on the right,
nine small soul sparks in a row above the center emblem; top right a small gold coin counter and below it a round minimap with a brass ring;
top left three small round buttons (book, map, menu) with tiny keycaps under them; the scene stays visible and uncluttered
```

## 3. Книга Рэя: страница персонажа и инвентарь
```
[общий блок стиля]
an open soldier's field journal (a book spread) with a dark leather cover and brass corners, centered on the screen over a blurred dim background,
left page: a cat knight portrait in a green cloak in the middle, equipment slots around him (weapon, cloak, armor on the left; amulet, two relics on the right),
below: four stat lines (HP, Soul, Damage, Defense) and a gold coin count;
right page: a grid of 6x3 inventory cells with small item icons, four hotbar slots to the right, below the grid an item description area with a title;
eight leather bookmark tabs with brass pins on both sides of the book (four on the left, four on the right), a red close button in the top right corner,
a row of key hints at the bottom, warm candle-like light
```

## 4. Журнал Рэя: записи и карта
```
[общий блок стиля]
an open field journal spread: left page — a list of entries with ink handwriting and small paper scraps pasted in (different handwritings),
right page — a hand-drawn parchment map of a stone fortress floor with numbered rooms, death marks as small purple crosses, explored rooms drawn, unexplored rooms as faint pencil outlines;
brass bookmark tabs on the sides (entries, people, evidence, bestiary, maps), a pressed flower and a brass pin on the page edge, wax stain, coffee ring
```

## 5. Главное меню
```
[общий блок стиля]
main menu screen: a dark diorama of a tiny stone tavern on a hill at dusk in the background, the game title "Долг Кошачьей Души" in large carved pixel letters at the top (brass and dark wood),
below on the left a vertical list of menu items without frames (Continue, New game, Settings, Credits, Exit) in light parchment text, the selected item has a brass claw pointer and glows gold,
small version number and copyright line at the bottom
```

## 6. Пауза и настройки
```
[общий блок стиля]
pause menu: the game scene blurred and dimmed behind, a vertical parchment panel in the center with a wooden frame and four brass rivets, a title "Пауза",
below: menu items (Resume, Book, World map, Settings, Main menu) with a brass claw pointer at the selected item, a red close button in the corner;
second image: a settings window as a parchment page with tabs (Video, Sound, Controls, Game), rows with a label on the left and a slider or option value on the right, brass sliders, a "Back" button at the bottom
```

## 7. Подсказки обучения и реплики
```
[общий блок стиля]
a small wooden plank hint bar at the bottom center of a dark game scene, text "Идти:" followed by four keycaps W A S D;
below it a dialogue box: a parchment page with wooden frame, a name tab "Граф Вельмор" on the top-left, two lines of text and a small brass arrow at the bottom right,
a choice list with two options and a brass claw pointer
```

---

## Что учесть при генерации
- Рамки должны **растягиваться**: углы и края самодостаточны, центр пустой. Не рисуйте декор по центру панелей.
- Иконки предметов в ячейках — отдельные (20×20, см. `ICON_PROMPTS.md`); на макетах можно заглушки.
- Текст на макете — любой; в игре он набирается шрифтом и меняется.
- Ничего, что зависит от разрешения (тонкие линии 1 px вместо 1 UI-пикселя) — всё кратно 3 экранным пикселям.
- Если хотите сменить палитру или стиль (не «дерево + пергамент») — скажите, поправлю блок стиля.
