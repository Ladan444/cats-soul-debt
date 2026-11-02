# TEXTURE PROMPTS: пиксельные текстуры окружения

Решение автора: текстуры окружения — ИИ-генерации по этим промптам; я привожу их к пикселям, палитре и бесшовности.
Окружение — 3D-геометрия с пиксельными текстурами (CLAUDE.md, PROJECT_BIBLE).

## Технические требования (что получится в игре)
- **Плотность — 40 пикселей на метр**, как у спрайтов персонажей (Sprite3D, 0,025 м на пиксель): иначе кот и стена будут «разного пикселя».
- **Тайл 128×128 пикселей = 3,2×3,2 м** (в игре текстуры кладутся по трём осям). Камень кладки — 4–6 блоков на тайл по ширине.
- Генерировать крупно (1024×1024 и больше), квадратом, **ровно сверху / ровно спереди, без перспективы и без теней от света сбоку**: освещение даёт движок.
- После генерации: положить в `Арт/Генерации/Текстуры/` с понятным именем (например `rubezh_wall_brick_1.png`), я уменьшу «по большинству» до 64×64, сведу к палитре Рубежа и сделаю бесшовной.
- Лучше 2–3 варианта на текстуру: выберу тот, что лучше стыкуется.

## Общий блок стиля (в начало каждого промпта)
```
seamless tileable texture, pixel art, 16-bit HD-2D game style like Octopath Traveler, flat orthographic view straight on,
evenly lit, no directional shadows, no perspective, no vignette, no border, limited palette, crisp pixels, no anti-aliasing,
texture fills the whole square image edge to edge
```

## Негативный промпт (если генератор поддерживает)
```
perspective, 3D render, photo, realistic lighting, strong shadows, highlights from one side, vignette, frame, border, text,
watermark, objects, characters, blurry, gradient background
```

## Каменный Рубеж — набор 1 (палитра: холодный синий → стальной серый, мох, тёплое старое дерево)
| Имя файла | Где в игре | Блок предмета (после общего блока) |
|---|---|---|
| `rubezh_wall_brick` | стены всех залов | `massive dark grey-blue stone block wall, large rough rectangular blocks in uneven rows, thin dark mortar, cold steel grey and slate blue tones, a few small patches of green moss in the cracks` |
| `rubezh_wall_mossy` | стены у воды, нижние ряды | `same dark grey-blue stone block wall, heavily overgrown with green moss and dark wet water stains running down, damp and old` |
| `rubezh_floor_flagstone` | пол залов | `top-down view of a floor of large worn square flagstones, dark grey-blue stone, wet surface with small puddles reflecting light, thin moss lines between the slabs` |
| `rubezh_floor_cobble` | двор, мост | `top-down view of an old cobblestone pavement, small rounded dark grey stones, damp, moss between stones` |
| `rubezh_floor_crypt` | склеп, Большой зал | `top-down view of a floor of dark polished stone tiles with faint engraved runes and thin cracks, cold blue-black tones` |
| `rubezh_wood_planks` | казарма, трапезная, лодки, ящики | `old dark wooden planks, weathered and damp, iron nails, warm brown tones dulled by moisture` |
| `rubezh_stone_trim` | карнизы, края, саркофаги | `carved stone border ornament strip, worn gothic pattern, dark grey stone, repeating horizontally` |
| `rubezh_iron_grate` | решётки, двери, ворота | `rusty iron bars and riveted iron plates, dark metal with orange rust streaks` |
| `rubezh_rock_cliff` | стены пропасти | `rough natural dark rock cliff surface, cracks and ledges, wet, cold blue-grey, patches of moss` |

## Двери и знамёна (не бесшовные — отдельные картинки, вид строго спереди)
| Имя файла | Блок предмета |
|---|---|
| `rubezh_door_wood` | `front view of a heavy arched wooden door with iron bands and a ring handle, dark old wood, isolated on plain white background` |
| `rubezh_banner_lion` | `front view of a long hanging cloth banner, dark navy blue with a white rampant lion and a cross above it, gold fringe at the bottom, slightly torn, isolated on plain white background` (как на концептах Рубежа) |
| `rubezh_banner_cat` | `front view of a long hanging cloth banner, dark red with a gold cat face emblem, gold fringe, slightly torn, isolated on plain white background` |

Порядок: сначала `rubezh_wall_brick`, `rubezh_floor_flagstone`, `rubezh_floor_cobble` — их хватит, чтобы одеть первый этаж для проверки; остальное — по мере сил.

## Ивовый Брод — набор 2, вариант 2 (после первой попытки)
Первая попытка (2026-10-21) пришла **фотографиями**: генератор проигнорировал «pixel art», крыша-солома — фото
дома с небом, на побелке крест из бруса (брус в игре — отдельная геометрия). Фото через конвейер дают «шум»
вместо пиксель-арта (проверено: трава — зелёная рябь, скала — пятна). Поэтому:
- генерировать тем же инструментом, что и Рубеж (там стиль получился);
- **стиль — в начале промпта**, предмет — после; негативный промпт обязателен;
- если генератор умеет «стиль по образцу» — дать ему готовую текстуру Рубежа (`Арт/Обработано/textures_rubezh_preview.png`).

Общий блок (вместо прежнего):
```
pixel art game texture, 16-bit SNES era hand-pixeled tile, seamless tileable, flat orthographic view straight on,
large readable pixel clusters, limited palette of 12 colors, hard pixel edges, no anti-aliasing, evenly lit,
cozy warm village, style of Octopath Traveler and Stardew Valley environment tiles, fills the whole square edge to edge
```
Негатив (добавить к прежнему): `photo, photograph, photorealistic, realistic texture, high detail noise, film grain, sky, building, roof edge, perspective, depth of field`

| Имя файла | Предмет (после общего блока) |
|---|---|
| `village_grass` | `top-down meadow grass ground, clumps of grass drawn as small pixel tufts, 3-4 shades of saturated warm green, a few tiny yellow flower pixels` |
| `village_dirt_road` | `top-down packed dirt path, warm ochre and brown, small pebbles as 2-3 pixel dots, faint horizontal wheel ruts` |
| `village_rock` | `natural rock face, chunky angular stone shapes with dark outlines, warm grey-brown, small moss pixels` |
| `village_wall_plaster` | `plain cream lime plaster wall, subtle cracks and stains, NO wooden beams, NO timber frame` |
| `village_roof_thatch` | `flat straight-on view of straw thatch roof surface only, horizontal rows of golden straw bundles, NO house, NO sky, NO roof edge` |
| `village_roof_tiles_red` | `flat straight-on view of red clay roof tiles in overlapping horizontal rows, terracotta orange-red, dark outline under each row` |

## Мост через реку (вариант C) — 2 текстуры по развёртке
Мост выбран автором (2026-10-21). Кладка стен — `village_wall_stone`, настил — `village_square_cobble` (уже есть).
Нужны ещё две плитки: 128 px = 3,2 м, ложатся по развёртке моста (не по миру).
- `village_stone_dressed` — клиновые камни арок, бордюр, шапки столбов. **Без швов кладки**: камни режет сама
  геометрия, нарисованные швы легли бы поперёк клиньев.
- `village_wood_beam` — столбики и жерди перил. **Волокна строго вертикально**: развёртка кладёт длину бруса
  по вертикали картинки.

## Ивовый Брод — набор 2 (палитра: тёплый оранжевый → насыщенный зелёный; уют обманчив)
Тот же общий блок стиля и негативный промпт. Свет — летний полдень, без резких теней. Файлы класть туда же, в
`Арт/Генерации/Текстуры/`, с префиксом `village_`.

### Земля (вид строго сверху; рельеф большой, поэтому текстуры должны спокойно повторяться без заметных «пятен»)
| Имя файла | Где в игре | Блок предмета |
|---|---|---|
| `village_grass` | луга, холмы, выгон | `top-down view of short lush meadow grass, small tufts and blades, a few tiny yellow and white flowers, saturated warm green tones, even density, no large patches` |
| `village_grass_dry` | склоны, опушка, кладбищенский холм | `top-down view of dry trampled grass mixed with bare earth spots, olive green and straw yellow tones` |
| `village_dirt_road` | дороги и тропы | `top-down view of a packed dirt country road, warm ochre-brown earth, small pebbles, faint cart wheel ruts running horizontally` |
| `village_square_cobble` | площадь у колодца, крыльцо таверны | `top-down view of old village cobblestone pavement, rounded warm grey and sandy stones, grass sprouting between stones` |
| `village_field_soil` | огороды и пашни | `top-down view of ploughed farm field, parallel dark brown soil furrows running horizontally, small green sprouts in rows` |
| `village_rock` | горы, обрыв, стены оврага | `rough natural rock surface, layered sandstone and grey granite, cracks and ledges, warm grey-brown, small patches of moss and grass` |
| `village_riverbed` | дно и берег у брода | `top-down view of shallow riverbed, smooth round pebbles of grey, ochre and rust colours, wet sand between them` |

### Постройки (вид строго спереди)
| Имя файла | Где в игре | Блок предмета |
|---|---|---|
| `village_wall_plaster` | стены домов | `cream white lime plaster wall with dark brown half-timber wooden beams in a cross pattern, plaster slightly cracked and stained near the bottom` |
| `village_wall_stone` | цоколи, кузница, мельница, колодец | `rustic fieldstone wall, irregular rounded stones of warm grey and ochre, thick light mortar` |
| `village_wall_logs` | хижина отшельника, сараи | `wall of horizontal round logs, weathered warm brown wood, visible log ends texture, moss in the gaps` |
| `village_roof_tiles_red` | крыша таверны | `red clay roof tiles in overlapping rows, terracotta orange-red, some tiles darker and chipped, rows running horizontally` |
| `village_roof_thatch` | крыши домов | `straw thatched roof, thick golden-brown thatch bundles in horizontal layers, slightly weathered grey on top` |
| `village_roof_shingles` | кузница, лавка, мельница | `wooden roof shingles in overlapping rows, weathered grey-brown wood` |
| `village_wood_planks` | пристань, мостки, мостик, двери сараев | `old wooden planks running horizontally, warm brown and honey tones, iron nails, sun-bleached` |
| `village_fence` | изгороди огородов (не бесшовная по вертикали) | `front view of a rustic wooden picket fence section, warm brown wood, isolated on plain white background` |

### Отдельные картинки (вид строго спереди, на белом фоне)
| Имя файла | Блок предмета |
|---|---|
| `village_window_lit` | `front view of a small wooden cottage window with four panes, warm orange light glowing inside, wooden shutters, isolated on plain white background` |
| `village_door_cottage` | `front view of a rustic wooden cottage door with iron hinges and a small round window, warm brown wood, isolated on plain white background` |
| `village_sign_tavern` | `front view of a hanging wooden tavern sign with a painted black cat and a mug of ale, isolated on plain white background` |

Порядок: сначала `village_grass`, `village_dirt_road`, `village_rock`, `village_wall_plaster`, `village_roof_thatch`,
`village_roof_tiles_red` — этого хватит, чтобы деревня перестала быть «однотонной»; остальное — по мере сил.
