# Тексты игры — таблица-источник для перевода

`strings_ru.csv` — все **сюжетные** тексты на русском: key, ru, where, context. Собрано скриптом без правки кода (2026-10-27); код пока читает тексты из прежних мест. Перевод — потом (добавится колонка `en`).

## Формат ключей (предложение для каркаса локализации — согласовать с чатом «Интерфейс и техника»)
| Префикс | Откуда | Пример |
|---|---|---|
| `npc.<id>.<name\|first\|after\|late\|rumors>.<n>` | жители (`village_quests.gd`, VILLAGERS) | `npc.horst.first.2` |
| `shop.<id>.<title\|talk>` | торговля | `shop.marta.title` |
| `guide.*`, `spirit.*` | проводник и призрак у фонаря | `spirit.lore.3` |
| `liara_house.memory.<n>.<1\|2>` | воспоминания у дома Лиары (1 — кто, 2 — текст) | `liara_house.memory.1.2` |
| `quest.<id>.<title\|offer.n\|remind.n\|steps.n.text\|props.n.label\|finish...>` | квесты жителей и сюжетные (`chapter1`) | `quest.horst_tongs.offer.1` |
| `item.<id>.<name\|description>` | `data/items` | `item.stone_willow_sprout.name` |
| `soul.<id>.<name\|company\|memory>` | `data/souls` | `soul.soul_finn.memory` |
| `skill.<id>.<name\|description>` | `data/skills` | `skill.ghost_step.name` |
| `journal.<id>.<title\|text>` | `data/journal` | `journal.note_unsigned.text` |
| `map.<id>.title`, `map.<id>.room.<room>.<name\|note\|hint_note>` | карты журнала | `map.rubezh_f1.room.gate.note` |
| `guardian.ch<N>.c<беседа>.<реплика>` | Страж Перекрёстка | `guardian.ch1.c1.2` |
| `script.<файл>.<NNN>` | строки, зашитые в скриптах (граф, финал, находки) — **временные ключи по порядку в файле**; при переносе в таблицу получат смысловые (`velmor.step0.1` и т. п.) | `script.velmor.010` |

Правила: ключи на английском, точка — разделитель, номера с 1; при дублях ключ получает суффикс `~2`. Плейсхолдеры (`%s`) остаются как есть.

## Не вошло (зона «Интерфейс и техника»)
Меню, настройки, пауза, HUD, карта (подписи UI), читы, подсказки ввода — строки в `scripts/ui/*`, `scripts/debug/*`, `scripts/core/*`. Диалоги боя и звуки без текста.

## Пересборка
Скрипт: `python Tools/extract_strings.py` (пересобирает CSV; код игры не трогает).
