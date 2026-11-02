# ICON PROMPTS: иконки предметов и скиллов

Шаг 6 плана UI_SPEC. Сейчас в игре стоят заглушки, нарисованные кодом (`Tools/ui_atlas.py`).
Иконки генерируются листами по несколько штук, обрабатываются `Tools/icon_pipeline.py` и встают в игру сами — поверх заглушек с тем же именем файла.

Предметы и тексты в демо-наборе — заглушки (`Tools/godot/build_demo_content.gd`). Если автор поменяет предметы, промпты нужно поправить под них.

---

## Как генерировать
1. Один лист = одна строка из таблицы ниже (3–5 иконок). Генератор лучше держит стиль, если иконок на листе немного.
2. Склеить общий блок стиля, перечень иконок «слева направо» и, если генератор поддерживает, негативный промпт.
3. Положить результат в `Арт/Генерации/` и запустить команду из таблицы (или попросить Claude).
4. Проверить превью в `Арт/Обработано/<файл>_icons_preview.png` и в игре (меню персонажа, хотбар).

Иконки в игре 20×20 px (ячейка 22): команда всех листов — `--size 20 --smooth 40` (Lanczos + адаптивная палитра на 40 цветов: читаемее, чем «по большинству» в палитру проекта; размер 14 и режим палитры остались для заглушек).

Если тонкие предметы (трава, ключ) после обработки выглядят слишком «жирно», добавьте `--no-outline`: контур у генерации уже есть, второй не нужен.

### Общий блок стиля
```
pixel art game item icons, a single row of separate icons evenly spaced with wide empty gaps between them,
each icon is one object centered in its own space, 3/4 view, bold readable silhouette, 16x16 pixel icon style,
chunky pixels, 1px dark brown outline, limited muted palette, soft light from top-left,
plain white background, no shadows, no text, no labels, no frames, medieval dark fantasy, HD-2D style like Octopath Traveler,
from left to right:
```

### Негативный промпт
```
text, labels, numbers, frame, border, slot, background scene, gradient, blur, anti-aliasing, realistic, photo, 3D render,
multiple objects in one icon, overlapping icons, hands, characters
```

---

## Листы

### Лист A — снаряжение (5 иконок)
```
1) a short worn iron garrison sword with a brass crossguard and leather-wrapped grip, diagonal;
2) a faded dusty-green hooded soldier's cloak with a patch, folded, brass clasp;
3) a thick leather chest armor with small iron plates and a brass buckle;
4) an amulet: a smooth dark lake stone with a faint violet glow in a brass setting on a thin chain;
5) a cloth military patch with an embroidered grey wolf and a chevron, frayed edges
```
Команда:
```
python Tools/icon_pipeline.py "Арт/Генерации/<файл>.png" --names icon_sword,icon_cloak,icon_armor,icon_amulet,icon_relic
```

### Лист B — предметы (5 иконок)
```
1) a grey whetstone worn down to half, a groove in the middle;
2) a small glass vial of dark red healing tincture with a cork, paper label;
3) a bunch of marsh herbs with green leaves tied with string;
4) a folded old paper note with handwriting lines and a small red stain;
5) a heavy old brass key with a round bow
```
Команда:
```
python Tools/icon_pipeline.py "Арт/Генерации/<файл>.png" --names icon_whetstone,icon_item_placeholder,icon_herb,icon_letter,icon_key
```
(`icon_item_placeholder` — это файл иконки «Настойки Лиары».)

### Лист C — скиллы, силы душ (3 иконки)
Скиллы — призрачные силы павших товарищей, поэтому в одной гамме: бирюзовый дух на тёмном.
```
1) a ghostly turquoise cat paw print dashing forward with motion trails, spectral glow;
2) a sword slash doubled by a fading turquoise echo of the same slash, spectral;
3) a glowing turquoise eye inside a watchtower crosshair mark, spectral
```
Команда:
```
python Tools/icon_pipeline.py "Арт/Генерации/<файл>.png" --names icon_skill_ghost_step,icon_skill_echo_strike,icon_skill_watch_mark
```

---

## Листы второй очереди — свои иконки предметов Главы 1 (список от чата story, 2026-10-27)

Листы A, B, C выше сгенерированы и стоят в игре. Ниже — вторая очередь: у каждого предмета своя иконка вместо общей.
Генерируйте так же: общий блок стиля + перечень «слева направо» + негативный промпт. Команда для всех листов:
`python Tools/icon_pipeline.py "Арт/Генерации/<файл>.png" --names <имена> --size 20 --smooth 40`.
Имена файлов — `icon_<id предмета>`. После обработки Claude подключает иконки в `data/items/*.tres`.
Палитра: холодные сталь и синий — Рубеж; тёплая латунь — вещи графа и Брода. Иконка читается на 14×14 px, поэтому на листе — крупный силуэт, без мелких надписей и цифр.

Уже есть иконка (повторно не нужна): настойка Лиары (`tincture_liara` = `icon_item_placeholder`), меч, плащ, броня, амулет, нашивка, точильный камень, трава, записка, ключ, три скилла.

### Лист D — сюжетные вещи графа и Лиары (5) — самое важное
```
1) a small tarnished silver heart-shaped medallion on a thin chain, engraved edge, faint warm glint;
2) a small black ebony casket with silver corner plates, sealed with burgundy wax bearing a circle-with-vertical-line mark;
3) a rolled heavy dark-green cloth banner on a short pole, one edge scorched, silver tower embroidery;
4) a heavy brass treasury key with a wide bit and ornate round bow;
5) a letter folded in four, yellowed paper, hurried handwriting, an unfinished last line, a small paw print at the fold
```
Имена: `icon_liara_medallion,icon_velmor_casket,icon_banner_third_company,icon_key_treasury,icon_jorg_letter`

### Лист E — ключи Рубежа и казарма (5)
```
1) a rusty iron key hanging on a small tag, dull;
2) a black-metal key with a cold bluish sheen, short worn bit;
3) a broken fragment of a brass key with a single tooth and a jagged torn edge;
4) a white tin signal whistle with a ring for a cord, small dent;
5) a reddish alder-wood spoon with four small notches cut into the handle
```
Имена: `icon_key_rubezh_k1,icon_key_black,icon_key_treasury_part,icon_tin_whistle,icon_carved_spoon`
(`icon_key_black` — одна иконка для `key_rubezh_k2` и `key_rubezh_k3`: римские цифры на 14 px не прочитать.)

### Лист F — вещи жителей: Хорст, Бранко, казарма (5)
```
1) heavy blacksmith quenching tongs with a badger-paw mark on the hinge;
2) a small tin dog-tag token with a stamped name on a cord;
3) a broken stub of an officer's broadsword, dark steel with a grey sheen and a twisted guard;
4) a short dagger with a handle made of bone;
5) a worn copper belt buckle with tiny tooth marks
```
Имена: `icon_horst_tongs,icon_branko_token,icon_broken_broadsword,icon_corporal_dagger,icon_soldier_buckle`

### Лист G — вещи жителей: Клаус, Мика, Ильза (5)
```
1) a tangled lump of hemp fishing net with small lead bullet weights;
2) a small oak chest with copper bands and a tower emblem on the lid;
3) a crude little pine toy boat with scratched letters on the stern;
4) a green-tarnished copper locket, slightly open, a tuft of pale fur inside;
5) a tattered storm-grey scarf with a silver tower on the hem
```
Имена: `icon_tangled_net,icon_garrison_chest,icon_wooden_boat,icon_copper_locket,icon_tattered_sash`

### Лист H — вещи жителей: мох, мази, взвар, песок, вода (5)
```
1) silvery star-shaped moss on a small piece of grey stone, faint glow;
2) three small clay ointment pots sealed with wax, a sprig of pine tied on;
3) a clay flask with a cork holding an emerald-green brew;
4) a small cloth pouch spilling violet-black sand;
5) a leather water flask with a single drop on the neck
```
Имена: `icon_star_moss,icon_stolen_ointments,icon_marta_brew,icon_black_sand,icon_spring_water`

### Лист I — документы и знаки (4)
```
1) a swollen notebook in waxed leather with ink stains;
2) a yellowed sheet with a garrison wax seal and the silhouette of a cloaked figure;
3) a pewter courier badge with claw scratches;
4) a torn scrap of paper with uneven handwriting
```
Имена: `icon_quartermaster_log,icon_unsent_report,icon_courier_badge,icon_note_unsigned`

### Лист J — реликвии и редкий материал (5)
```
1) a small grey sprout with leaves hard as slate;
2) a small green-tarnished copper bell with a worn clapper;
3) a pale candle stub with a calm steady flame that never melts;
4) a small bone with a carved rune on a cord, faintly warm;
5) a round bronze coin stamped with a small boat
```
Имена: `icon_stone_willow_sprout,icon_relic_drowned_bell,icon_relic_grave_candle,icon_bone_charm,icon_ferry_tribute`

### Листы K, L, M — обереги и нашивки (4 + 4 + 3)
Лист K:
```
1) a four-leaf clover trapped in a drop of amber resin on a cord;
2) a small heather knot tied with a blue thread;
3) a small linen knot with a clover sprig;
4) a linen ward bundle with thyme, tied with string
```
Имена: `icon_ilza_charm_clover,icon_ilza_charm_heather,icon_ilza_knot,icon_ilza_ward_linen`

Лист L:
```
1) a dried pressed clover charm in a small cloth pouch;
2) a river pebble with a hole threaded with otter hair;
3) a birch-bark knot tied with a thin cord;
4) a chunk of forge scale hanging on a cord
```
Имена: `icon_dried_clover_charm,icon_calm_water_sigil,icon_stream_blessing,icon_cinder_charm`

Лист M:
```
1) a splinter of a millstone as an amulet on a cord;
2) a whetstone in a small leather sheath;
3) a sergeant's metal badge of the second company
```
Имена: `icon_heavy_flint_charm,icon_whetstone_charm,icon_sergeant_badge`
(`amulet_lake_stone` остаётся на `icon_amulet`.)

### Лист N — меч гарнизона, 6 уровней (6)
Один и тот же меч (форма и рукоять не меняются), меняются узор клинка и блик. Генератору дайте один и тот же меч шесть раз.
```
1) a short worn iron garrison sword, plain dull blade, brass crossguard, leather grip, diagonal;
2) the same sword, straightened and cleaned, a clean edge;
3) the same sword, reforged, brighter steel with a visible fuller;
4) the same sword, hardened with oil, an officer's darker blade with a blue sheen;
5) the same sword with a willow-hardened blade, grey bark-vein pattern along the steel;
6) the same sword, "heart of the willow": three tiny sprouts on the blade, warm golden glow
```
Имена: `icon_sword_garrison,icon_sword_garrison_2,icon_sword_garrison_3,icon_sword_garrison_4,icon_sword_garrison_5,icon_sword_garrison_6`
(`icon_sword_garrison` — вместо общего `icon_sword`, который останется для простых мечей.)

### Запланировано (квест «Охота», [ПРЕДЛОЖЕНИЕ] — генерировать после одобрения автором)
Лист O:
```
1) a short ash-wood hunting bow with a twine string;
2) a bundle of simple arrows with grey feathers;
3) a steel arrowhead with a small notch mark;
4) a rag wrapped around an arrowhead on a cord
```
Имена: `icon_hunting_bow,icon_arrows,icon_valdo_arrowhead,icon_hunter_breath_charm`

Не нужны: демо-души `soul_gate_guard`, `soul_third_company`, `soul_tower_watch`; вещи павших (кружка, кости, нашивка, трубка, рисунок, гребёнка) — только если автор одобрит.

---

## Что не генерировать
Иконки HUD (кошачье сердце, огонёк души, искры-отметки, монета Гелиос, печать Рубежа), рамки, панели и «коготь» нарисованы кодом в нужном пиксельном размере. Их проще дорабатывать в `Tools/ui_atlas.py`, чем подгонять генерацию под 7–11 пикселей.

---

# Исследование и дополнительные листы (story, 2026-10-27)

Листы D–O для вещей сюжета, жителей, амулетов, меча и лука уже выше (составлены на основе записки story). Здесь — исследование типовых RPG-предметов и два листа, которых ещё не было: еда и материалы.

## Исследование: что обычно есть в RPG и что из этого нужно нам
Сводка по типовым предметным семействам в Zelda / Dark Souls / Diablo / Baldur's Gate / Octopath (по общему знанию жанра, без веб-поиска) и сопоставление с игрой. Слоты Рэя в игре: оружие, плащ, доспех, амулет, две реликвии (`item_data.gd`); категории — снаряжение, расходник, материал, ключевой предмет.

| Семейство в RPG | Типовые примеры | Нужно ли игре | Где в листах |
|---|---|---|---|
| Оружие ближнего боя | мечи разных уровней, кинжалы | да: меч гарнизона на 6 уровней, кинжал капрала | A, F, N |
| Дальнее оружие и боеприпасы | лук, стрелы, колчан | да: лук Клауса ([ПРЕДЛОЖЕНИЕ], квест «Охота») | «Запланировано» |
| Щиты, шлемы, перчатки, сапоги, кольца | Dark Souls, Diablo | **нет:** слотов нет (механики блока нет), не генерировать | — |
| Броня, плащ | нагрудник, плащ | да: иконки уже есть в листе A | A |
| Амулеты и талисманы | обереги, талисманы | да: Ильза и жители дарят амулеты за выбор в квестах | K, L, M |
| Реликвии | вещи павших, трофеи | да: две реликвии-слота, у вещей — история владельца | E, J |
| Зелья и еда | лечебные, еда, фляги | да: настойка, взвар, пирог графа, фляга Клауса | P |
| Материалы | руды, ткани, травы, кости, самоцветы | **да (решение автора 2026-10-27):** крафт есть — варка зелий и улучшение оружия «оружие + материал» | H, J, Q |
| Ключи и квестовые вещи | ключи, письма, печати, шкатулки | да, много: Рубеж и вещи жителей | D–I |
| Свитки, книги, карты | заклинания, записки, карты | записки есть; свитков нет (магия — силы душ) | I |
| Валюта | монета | нарисована кодом (Гелиос), не генерировать | — |
| Души | Dark Souls: души-предметы | в игре души — отдельные записи (`data/souls`), без инвентарной иконки; отдельный лист не нужен | — |

Решения автора: щитов/шлемов/колец не добавляем (нет слотов); **крафт есть** (зелья и улучшение оружия, 2026-10-27) — листы Q и R нужны; пирог графа, фляга Клауса и хлеб с мёдом добавляются как лечебные предметы.


## Листы

### Лист P — еда и питьё (5 иконок)
В каноне граф печёт пироги бесплатно, пироги лечат; Клаус угощает брусничным настоем на меду.
```
1) a clay flask of thick emerald herbal brew with a cork;
2) a leather water flask with one drop on the neck;
3) a round warm pie with a golden crust and a steam curl, a slice cut;
4) a small field flask of lingonberry mead tincture, red-brown, wood stopper;
5) a round golden sweet bun glazed with honey, a small honey drip
```
Команда:
```
python Tools/icon_pipeline.py "Арт/Генерации/<файл>.png" --names icon_marta_brew,icon_spring_water,icon_graf_pie,icon_klaus_flask,icon_honey_bun
```
(`icon_marta_brew` и `icon_spring_water` — предметы `marta_brew`, `spring_water`; `icon_graf_pie`, `icon_klaus_flask`, `icon_honey_bun` — предметы `graf_pie`, `klaus_flask`, `honey_bun` уже в данных (combat).)

### Лист Q — ингредиенты зелий (5 иконок)
Для варки у Марты: травы, вода, мёд. Предметы в данных частично есть (`marsh_herb`, `star_moss`, `spring_water`), остальные — [ПРЕДЛОЖЕНИЕ].
```
1) a bunch of dark marsh herbs with wet leaves tied with string;
2) a handful of red lingonberries on a small sprig;
3) a sprig of dried thyme and a few black-root pieces in a twisted paper;
4) a small clay pot of golden honey with a wooden dipper;
5) a vial of clear spring water with a faint silver sparkle
```
Команда:
```
python Tools/icon_pipeline.py "Арт/Генерации/<файл>.png" --names icon_marsh_herb,icon_lingonberry,icon_thyme_blackroot,icon_honey,icon_spring_vial
```

### Лист R — материалы улучшения оружия и зачарованные (5 иконок)
Улучшение «оружие + материал» у Хорста: простые материалы (руда, уголь, ростки ивы) и зачарованные (с отблеском озера). Предметов в данных пока только `stone_willow_sprout`; остальное — [ПРЕДЛОЖЕНИЕ].
```
1) a grey sprout with leaves hard as slate, small root ball, a faint grey sheen;
2) a chunk of raw iron ore with rust-orange veins;
3) a small pile of black forge coal with a few red embers;
4) a smooth dark lake stone with a faint violet glow inside, a thin brass wire wrapped around it;
5) a small bone shard carved with a glowing pale-turquoise rune
```
Команда:
```
python Tools/icon_pipeline.py "Арт/Генерации/<файл>.png" --names icon_stone_willow_sprout,icon_iron_ore,icon_forge_coal,icon_enchanted_lake_stone,icon_runed_bone
```
(Зачарованные материалы — бирюзовый/фиолетовый отблеск, как у духов и озера; само зачарование и эффекты — **[ОТКРЫТО]**, механика у combat/UI.)
