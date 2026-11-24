# Technology — Долг Кошачьей Души

ENGINE: godot
ENGINE VERSION: 4.7.2
DIMENSION: 3D
LANGUAGE: GDScript
PLATFORMS: Windows (itch.io)

## Decision
- context: 2.5D action-adventure, 3D-мир с billboard-спрайтами, одна глава, релиз на itch.io.
- options: Godot — открытый, быстрый, уже используется; Unity — мощнее, но тяжелее и не нужен; Unreal — избыточен для 2.5D.
- choice and why: Godot 4.7.2, Forward+, потому что проект уже собран, тесты и экспорт работают.
- consequences: GDScript, пиксельные текстуры nearest, экспорт Windows; Blender для 3D-ассетов.

## Budgets
60 FPS на слабом ПК, 100–180 FPS на текущей машине; draw calls — по сцене; сборка около 300 МБ; загрузка мира участками.

## Project structure
`Game/CatsSoulDebt/` — проект Godot: `scenes/`, `scripts/`, `assets/`, `data/`; `Tools/` — генераторы, тесты, сборка; `Литература/` — канон и техноты; `Проект/` — релиз.
