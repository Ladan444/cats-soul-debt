# Источники звука

CC0 — без обязательного указания авторства (авторы перечислены из уважения). **CC-BY 3.0 — автора обязательно указать** (экран «Авторы» в главном меню собирает их из `TRACKS` в `scripts/core/audio.gd`).

| Файл | Источник | Автор |
|---|---|---|
| `music/bards_tale_loop.wav` | OpenGameArt «Medieval: The Bard's Tale» | RandomMind |
| `music/old_tower_inn_loop.wav` | OpenGameArt «Medieval: The Old Tower Inn» | RandomMind |
| `music/dungeon_music.ogg` | OpenGameArt «Dungeon Ambience» (dungeon002) | yd |
| `ambient/dungeon_ambient_loop.ogg` | OpenGameArt «Loopable Dungeon Ambience» | JaggedStone |
| `ambient/forest_ambience.mp3` | OpenGameArt «Forest Ambience» | TinyWorlds |
| `ambient/birds_and_wind_ambient.ogg` | OpenGameArt «Birds and Wind — Ambient» | Spring Spring |
| `sfx/footstep_*`, `sfx/impact*` | Kenney «Impact Sounds» (kenney.nl) | Kenney |
| `sfx/` остальное | Kenney «RPG Audio» (kenney.nl) | Kenney |

Исходные архивы — `Арт/Ассеты/Звук/`.

## Звуки OpenGameArt (`sfx/oga/`, все CC0; копирует и выравнивает `python Tools/sfx_pick.py`)

| Файлы | Набор | Автор |
|---|---|---|
| `swish_*` | Swishes Sound Pack | artisticdude |
| `swing_*`, `giant_*`, `monster_*` | RPG Sound Pack | artisticdude |
| `clash_*`, `drip_*` | Fantasy Sound Effects (Tinysized SFX) | Vehicle |

## Музыка (id в `Audio.TRACKS` → файл)

Копирует и меряет громкость `python Tools/music_pick.py` (исходники — `Арт/Ассеты/Audio/OpenGameArt/`, вне бэкапа; полный список лицензий — `Арт/Ассеты/Audio/OpenGameArt_CREDITS.txt`).

| id | Файл | Дорожка | Автор | Лицензия |
|---|---|---|---|---|
| bards_tale | `music/bards_tale_loop.wav` | Medieval: The Bard's Tale | RandomMind | CC0 |
| old_tower_inn | `music/old_tower_inn_loop.wav` | Medieval: The Old Tower Inn | RandomMind | CC0 |
| dungeon | `music/dungeon_music.ogg` | Dungeon Ambience | yd | CC0 |
| death_path | `music/death_is_just_another_path.ogg` | Death Is Just Another Path | Otto Halmén | CC-BY 3.0 |
| sylvan_waltz | `music/sylvan_waltz.mp3` | Sylvan Waltz | Otto Halmén | CC-BY 3.0 |
| peaceful_place | `music/peaceful_place.ogg` | Peaceful Place | Alexandr Zhelanov | CC-BY 3.0 |
| winds_of_stories | `music/winds_of_stories.ogg` | Winds Of Stories | HorrorPen | CC-BY 3.0 |
| silent_woods | `music/secret_within_the_woods.ogg` | The Secret Within The Silent Woods | Hitctrl | CC-BY 3.0 |
| beyond_the_stars | `music/beyond_the_stars.ogg` | Beyond the Stars (Ambient) | Hitctrl | CC-BY 3.0 |
| spirit_waltz | `music/spirit_waltz.ogg` | Spirit Waltz | HorrorPen | CC-BY 3.0 |
| trading_memories | `music/trading_for_memories.mp3` | Trading It For The Memories | jimbeamdiablo | CC-BY 3.0 |
| dark_descent | `music/dark_descent.mp3` | Dark Descent | Matthew Pablo | CC-BY 3.0 |
| cave_theme | `music/cave_theme.ogg` | Cave Theme | HaelDB | CC0 |
| town_in_ruins | `music/town_in_ruins.ogg` | Town in Ruins | HaelDB | CC0 |
| midnight_creeping | `music/midnight_creeping.mp3` | Midnight Creeping | InspectorJ | CC-BY 3.0 |
| dark_forest | `music/dark_forest.mp3` | Dark Forest Theme | cynicmusic | CC0 |
| regular_battle | `music/regular_battle.mp3` | A Regular Battle | Telaron | CC-BY 3.0 |
| battle_theme_a | `music/battle_theme_a.mp3` | Battle Theme A | cynicmusic | CC0 |
| small_loss | `music/small_loss.ogg` | Small Loss | HorrorPen | CC-BY 3.0 |
| vampires_piano | `music/vampires_piano.mp3` | Vampire's Piano | TAD | CC0 |
| lurid_delusion | `music/lurid_delusion.mp3` | Lurid Delusion | Matthew Pablo | CC-BY 3.0 |

## Проверка лицензий (2026-10-27)

- В игре нет GPL и CC-BY-SA: `voice-samples` и `win-sound-2` (CC-BY-SA/GPL) не копировались; «Battle Theme A» мульти-лицензия, берём вариант CC0.
- Фон `ambient/*` (Spring Spring, TinyWorlds, JaggedStone) и `music/dungeon_music.ogg` (yd) — CC0 (проверено на страницах OpenGameArt).
- `sfx/oga/*` — наборы artisticdude, Vehicle (CC0); `sfx/` — Kenney (CC0).
- CC-BY 3.0 (автор в «Авторах» через `Audio.music_credits()`): Otto Halmén, Alexandr Zhelanov, HorrorPen, Hitctrl, jimbeamdiablo, Matthew Pablo, InspectorJ, Telaron.
