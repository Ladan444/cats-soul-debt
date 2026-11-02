# SPRITE SPECS: спецификации спрайтов персонажей

Эпик 2, задача 2.1. Документ нужен, чтобы ИИ-генерации разных персонажей выглядели как одна игра.
Лор и внешность — по `CANON.md`; при расхождении верен CANON.

Палитры подобраны на глаз по концептам. Это стартовая точка: после первых генераций уточним точные цвета.

---

## 1. Общие правила для всех спрайтов

### Размеры и сетка
- **Рост персонажа:** около 48 px от ступней до кончиков ушей. Крупные персонажи (боссы) — до 64–80 px.
- **Пропорции:** чиби, примерно 2,5–3 головы в высоту (как на листе Рэя с TURNAROUND). Голова около 18 px.
- **Ячейка кадра:** 64×64 px. Ступни стоят на линии y = 60, по центру ячейки (x = 32). У всех персонажей одинаково — так они не «прыгают» при смене анимации.
- **Лист анимации:** одна строка = одна анимация в одном направлении, кадры слева направо.

### Направления
Рисуются 3 направления: **вниз** (к камере), **вверх** (от камеры), **вправо** (боком). Влево движок получает отражением «вправо». Поэтому детали, которые нельзя отражать (шрам Рэя на левой щеке, шрам графа), на боковом виде должны выглядеть приемлемо в обе стороны: на виде сбоку шрам можно не показывать.

### Стиль
- **Контур:** 1 px, тёмный цветной (тёмно-коричневый или тёмно-фиолетовый), не чисто чёрный. Внутренние линии — светлее контура.
- **Свет:** нейтральный, мягкий, сверху-спереди. Двух-трёхтоновая заливка: основной цвет, тень, редкий блик. Без цветного освещения, без бликов от свечей, без падающих теней на земле: свет, тени и атмосферу добавит движок.
- **Палитра:** около 16 цветов на персонажа (см. таблицы ниже). Крупным тканевым поверхностям (плащи, мантии) давать 3–4 близких приглушённых оттенка — так сохраняется фактура ткани (решение автора по Рэю). Без градиентов и сглаживания (anti-aliasing) по краю: фон должен уходить в прозрачность чисто.
- **Фон:** прозрачный или однотонный, который легко вырезать.
- **Читаемость:** силуэт персонажа должен узнаваться залитым одним цветом.

### Что делает движок, а не арт
- Призрачное состояние Рэя (Главы 2–5): прозрачность, глитч, смещение цвета — шейдер. Отдельный арт не нужен.
- Свечение кристалла и магии — glow в движке; в арте достаточно ярких светлых пикселей.
- Освещение, тени, туман.

### Пайплайн
1. Генерируете персонажа в крупном размере по промптам ниже (лист с видами спереди, сзади и сбоку).
2. Скрипт `Tools/sprite_pipeline.py` приводит картинку к сетке 48 px, ограничивает палитру до палитры персонажа и убирает фон.
3. Дорабатываете вручную в пиксельном редакторе (Aseprite, LibreSprite, Pixelorama).
4. Анимации: ИИ плохо держит последовательность кадров. Генерируем ключевые позы, промежуточные кадры дорисовываем. Можно попробовать специализированные генераторы пиксель-арта, которые умеют повороты и анимации (например, PixelLab или Retro Diffusion), — их возможности стоит проверить перед выбором.

---

## 2. Рэй

**Референсы:** основной — лист с TURNAROUND (`alPK248f...png`). Дополнительно — реалистичный кот в капюшоне (`1792425138399-...png`): капюшон плаща, кожаные ремни через грудь, нашивка на рукаве. Синий плащ со сцен Рубежа — не канон.

**Силуэт:** небольшой собранный солдат, прямая выправка. Узнаётся по большим белым ушам, зелёному плащу-накидке до колен и белому хвосту с серым кончиком.

**Ключевые детали (в порядке важности):**
1. Белая шерсть, янтарные глаза с вертикальным зрачком, хмурые брови.
2. Выцветший зелёный плащ гарнизона с капюшоном (капюшон обычно откинут) и заплаткой на локте.
3. Зелёный шейный платок.
4. Тёмно-серый мундир в вертикальную полоску, чёрный пояс с пряжкой.
5. Кожаный наплечник на одном плече, ремень через грудь.
6. Коричневые штаны, чёрные ботинки с красными шнурками.
7. Короткий железный меч гарнизона на поясе.
8. Тонкий шрам на левой щеке (виден только на виде спереди, 1–2 пикселя).

**Палитра:**

| Роль | HEX |
|---|---|
| Шерсть | `#F4F2EC` |
| Шерсть, тень | `#C9C6BE` |
| Уши внутри, нос | `#E8A0A0` |
| Глаза | `#E0A030` |
| Плащ, свет | `#66796C` |
| Плащ | `#5A6E60` |
| Плащ, полутень | `#4E6253` |
| Плащ, тень | `#3F4D43` |
| Платок | `#3F7A4A` |
| Мундир | `#3E3E44` |
| Мундир, полоска/блик | `#5A5A62` |
| Штаны | `#5C4038` |
| Ботинки | `#222226` |
| Шнурки, шрам | `#B23A3A` |
| Кожа (наплечник, ремни) | `#8A6A4A` |
| Металл (меч, пряжка) | `#9A9AA0` |
| Контур | `#2A2228` |

**Анимации (минимум для прототипа):**

| Анимация | Кадры | Направления |
|---|---|---|
| Idle (дыхание, движение хвоста) | 4 | 3 |
| Walk | 4 | 3 |
| Run | 4 | 3 |
| Dash (рывок) | 1 | 3 |
| Interact (взять, открыть) | 3 | 3 |
| Hurt | 2 | 3 |
| Death (падение) | 6 | только вниз |
| Атаки | — | после выбора стиля боя |

---

## 3. Граф Вельмор

**Референсы:** лист `AmsojFny...png` (основной), реалистичный портрет `1792425454631-...png` (выражение лица, жест протянутой руки).

**Силуэт:** выше и стройнее Рэя (около 54–56 px), длинные волосы, вытянутая элегантная фигура, жилет с острым низом, длинный тонкий хвост.

**Пропорции — исключение из общего правила (решение автора):** Вельмор рисуется во «взрослых» пропорциях, около 6 голов, а не чиби. Это выделяет падшего ангела среди жителей Брода. Цена: голова при росте 56 px — около 9–10 px, поэтому лицо упрощается до глаза, шрама и пряди.

**Ключевые детали:**
1. Чёрная шерсть, золотые глаза; один глаз слепой, через него шрам — метка наказания.
2. Длинные чёрные волосы с белой прядью.
3. Бордовый жилет, кремовая рубашка с длинными рукавами.
4. Тёмные перчатки (всегда — под ними контракт).
5. Золотая цепочка карманных часов.
6. Чёрные брюки, чёрные туфли.
7. Аксессуары в руках для отдельных анимаций: пирог, кружка, свиток контракта.

**Палитра:**

| Роль | HEX |
|---|---|
| Шерсть | `#2B2523` |
| Шерсть/волосы, полутень | `#3B3330` |
| Шерсть, блик | `#4E4542` |
| Волосы, блик | `#625854` |
| Белая прядь | `#D8D8DC` |
| Глаза | `#E8B030` |
| Шрам | `#8A5A6A` |
| Жилет, свет | `#7E2E3A` |
| Жилет | `#6E2430` |
| Жилет, полутень | `#5A1E28` |
| Жилет, тень | `#4A1820` |
| Рубашка | `#EDE3CC` |
| Рубашка, тень | `#C8BCA4` |
| Брюки, туфли | `#1C1817` |
| Перчатки | цвета шерсти (в генерациях почти не отличаются) |
| Золото (часы, пуговицы) | `#C9A040` |
| Контур | `#140F14` |

**Анимации:**

| Анимация | Кадры | Направления |
|---|---|---|
| Idle (лёгкое покачивание, хвост) | 4 | 3 |
| Walk | 6 | 3 |
| Talk (жест рукой) | 4 | вниз, вправо |
| Offer hand (протягивает руку — сделка) | 4 | вниз, вправо |
| Contract (разворачивает свиток) | 6 | только вниз |
| Wink / тень на лице (катсцены) | 2 | только вниз |

---

## 4. Лиара

**Референсы:** лист антропоморфной лисы-чиби `Ne0mFM7h...png` (основной), реалистичная лиса `1792425360741-...png` (детали посоха, капюшона). Старый лист с девушкой с лисьими ушами (`Kn7_hJtH...png`) — не канон, только для палитры и аксессуаров.

**Силуэт:** чуть ниже Рэя (около 44–46 px), длинная роба колоколом, пышный рыжий хвост, высокий посох с кристаллом выше головы.

**Ключевые детали:**
1. Рыжая шерсть, светлая грудка и мордочка, тёмные кончики ушей.
2. Медово-карие глаза, мягкое выражение лица.
3. Длинная рыжая коса.
4. Пыльно-голубая роба с капюшоном, кремовый фартук в пятнах чернил и трав.
5. Серебряный медальон-сердце.
6. Кривой деревянный посох с голубым кристаллом.
7. Кожаная сумка через плечо с травами.

**Палитра:**

| Роль | HEX |
|---|---|
| Шерсть | `#E08A4A` |
| Шерсть, тень | `#B0643A` |
| Светлая шерсть | `#F6E6D0` |
| Кончики ушей, лапы | `#4A2E22` |
| Глаза | `#B06A2A` |
| Роба, свет | `#7A9EBE` |
| Роба | `#6A90B0` |
| Роба, полутень | `#5A7FA0` |
| Роба, тень | `#4E6E8C` |
| Фартук | `#EFE6D6` |
| Пятна | `#9A6A40` |
| Кожа (сумка) | `#8A5A3A` |
| Дерево посоха | `#6A4228` |
| Кристалл | `#9EE6F6` |
| Кристалл, блик | `#E0FAFF` |
| Серебро | `#C8CCD0` |
| Контур | `#2E1E1A` |

**Анимации** (Лиара появляется в воспоминаниях Главы 2 и в сердце печати в Главе 4):

| Анимация | Кадры | Направления |
|---|---|---|
| Idle | 4 | 3 |
| Walk | 6 | 3 |
| Talk / смех | 4 | вниз, вправо |
| Heal (поднимает посох) | 6 | вниз, вправо |
| Sleep (вечный сон, катсцена) | 2 | только вниз |

**Отдельный объект: Лиара в печати.** Кристалл 48×64 px, внутри угадывается силуэт лисы. Цикл свечения — 8 кадров. Палитра: кристалл + тёмный камень круга.

---

## 5. Пока без спецификаций

- **Командир / Покупатель.** Облик (регалии с концепта или мундир командира) решим позже. На концепте: огромный толстый серый кот, красная мантия, чёрно-золотые доспехи, пояс с черепом; по размеру — босс, 64–80 px.
- **Восемь командиров-стражей, Страж Перекрёстка, жители Брода, враги.** Концептов нет.

---

## 6. Промпты для генерации

Промпты на английском: генераторы понимают его лучше. Каждый промпт = общий блок стиля + блок персонажа.

### Общий блок стиля
```
pixel art character sprite sheet, HD-2D style like Octopath Traveler, chibi proportions 2.5-3 heads tall,
anthropomorphic animal character, three views side by side: front view, back view, right side view,
same character in every view, standing neutral pose, full body,
flat soft neutral lighting from top-front, 2-3 tone cel shading, 1px dark colored outline,
limited palette, crisp pixels, no anti-aliasing, plain white background, no ground shadow, no text, no labels
```

### Негативный промпт (если генератор поддерживает)
```
blurry, gradient, soft edges, anti-aliasing, 3D render, realistic, photo, human face, human ears on a human,
text, watermark, labels, multiple characters, cropped, dramatic lighting, colored lighting, background scene
```

### Рэй
```
young white cat soldier, white fur, amber eyes with slit pupils, serious frowning expression,
thin scar on left cheek, big white cat ears with pink inside, white tail,
faded green garrison cloak with hood down and a patch on the elbow, green neckerchief,
dark grey vertically striped military tunic, black belt with buckle, leather shoulder pauldron on one shoulder,
leather strap across chest, brown trousers, black boots with red laces, short iron sword at the hip
```

### Граф Вельмор
```
elegant tall black cat gentleman, black fur, golden eyes, one eye blind with a scar across it,
long black hair with a single white streak, burgundy waistcoat over a cream long-sleeved shirt,
dark leather gloves, gold pocket watch chain, black trousers, black shoes, long thin black tail,
polite charming smile hiding menace
```

### Лиара
```
young anthropomorphic red fox girl healer, ginger fur with cream muzzle and chest, dark brown ear tips,
honey brown eyes, gentle smile, long ginger braid, dusty blue hooded robe, cream apron with ink and herb stains,
silver heart-shaped locket, brown leather satchel with herbs, tall crooked wooden staff with a glowing light blue crystal,
big fluffy fox tail
```

### Анимации (цикл ходьбы и бега)
Решение автора: циклы ходьбы и бега — по 4 кадра. Формат листа анимаций в игре — см. `CLAUDE.md` (DirectionalSprite).
ИИ лучше держит одно направление за раз, поэтому генерируем по картинке на направление. Пример для ходьбы вбок:
```
pixel art sprite sheet, walk cycle animation, 4 frames in a single horizontal row, evenly spaced with empty space between frames,
the same character in every frame, right side view facing right, full body, frame 1: right leg forward, frame 2: legs passing,
frame 3: left leg forward, frame 4: legs passing, HD-2D style like Octopath Traveler, chibi proportions 2.5-3 heads tall,
flat soft neutral lighting, 2-3 tone cel shading, 1px dark colored outline, limited palette, crisp pixels, no anti-aliasing,
plain white background, no ground shadow, no text, no labels, <блок персонажа>
```
Для других направлений заменить `right side view facing right` на `front view facing the viewer` или `back view facing away`, для бега — `walk cycle` на `run cycle` и добавить `leaning forward, cloak flowing behind`.

---

## 7. Бой (COMBAT_SPEC.md) — анимации Рэя и враги

Решение автора: сначала генерируем арт, потом собираем бой. Порядок приоритета:
1. Комбо Рэя **вбок** (3 картинки — по одной на удар).
2. Утопший солдат: лист видов, затем ходьба вбок и атака вбок.
3. Тварь Тихой Воды: один лист со всеми анимациями (она симметрична — направления не нужны).
4. Комбо Рэя вниз и вверх, «получил урон» — после того как бой заработает.

### 7.1 Комбо Рэя
Каждый удар — 4 кадра: замах, удар (со «смазом» дуги), проводка, возврат в стойку. Меч в правой руке.
Блок стиля — как у ходьбы (раздел 6), меняется только описание анимации:
```
pixel art sprite sheet, sword attack animation, 4 frames in a single horizontal row, evenly spaced with wide empty space between frames,
the same character in every frame, right side view facing right, full body,
<УДАР>,
HD-2D style like Octopath Traveler, chibi proportions 2.5-3 heads tall, flat soft neutral lighting, 2-3 tone cel shading,
1px dark colored outline, limited palette, crisp pixels, no anti-aliasing, plain white background, no ground shadow, no text, no labels,
<блок Рэя из раздела 6, но с мечом в руке: "short iron sword in right hand" вместо "short iron sword at the hip">
```
| Удар | `<УДАР>` |
|---|---|
| 1 | `frame 1: sword pulled back to wind up, frame 2: fast horizontal slash forward with a white motion arc, frame 3: follow-through with the sword across the body, frame 4: returning to guard stance` |
| 2 | `frame 1: sword raised behind the shoulder, frame 2: fast backhand diagonal slash with a white motion arc, frame 3: follow-through low, frame 4: returning to guard stance` |
| 3 | `frame 1: both hands raise the sword high overhead, frame 2: heavy downward overhead strike with a big white motion arc, frame 3: sword hits the ground with small dust, frame 4: rising back to guard stance` |

Для видов вниз/вверх: `front view facing the viewer` / `back view facing away`.

### 7.2 Утопший солдат
**Идея:** солдат гарнизона, павший в Ночь Рубежа и поднятый Тихой Водой. На нём тот же зелёный плащ, что у Рэя, — это его бывшие товарищи. **[ПРЕДЛОЖЕНИЕ]** вид — антропоморфный кот, как большинство гарнизона.

**Силуэт:** чуть выше Рэя (~50 px), сгорбленный, голова опущена, с плаща и шерсти стекает вода, ржавый меч волочится.

**Ключевые детали:** серо-синяя мокрая шерсть; пустые светящиеся фиолетовые глаза (сила Хозяина); рваный выцветший зелёный плащ гарнизона, тёмный от воды; ржавый шлем; водоросли на плечах; ржавый меч.

**Анимации:** idle 4 (покачивание, капли), walk 4, замах 2 (глаза вспыхивают — читаемый сигнал), удар 2, hurt 2, death 4 (оседает и растекается водой).

**Промпт (лист видов):**
```
pixel art character sprite sheet, HD-2D style like Octopath Traveler, chibi proportions 2.5-3 heads tall, anthropomorphic animal character,
three views side by side: front view, back view, right side view, same character in every view, standing neutral pose, full body,
flat soft neutral lighting from top-front, 2-3 tone cel shading, 1px dark colored outline, limited palette, crisp pixels, no anti-aliasing,
plain white background, no ground shadow, no text, no labels,
drowned undead cat soldier, hunched posture, head hanging low, wet matted grey-blue fur, empty glowing violet eyes,
torn faded dark green garrison cloak soaked with water, rusted iron helmet, strands of lake weed on the shoulders,
water dripping from the fur and cloak, rusted short sword dragging in one hand, eerie and sad
```
Ходьба и атака — тем же блоком анимации, что у Рэя (раздел 6 и 7.1), с описанием солдата; для атаки:
`frame 1: slowly raising the rusted sword, eyes flaring violet, frame 2: holding the sword high, frame 3: heavy chopping strike down, frame 4: sword stuck low, exhausted`.

### 7.3 Тварь Тихой Воды
**Идея:** сгусток фиолетового тумана и озёрной воды, оторвавшийся от Хозяина. Без лица — только два светящихся глаза.

**Силуэт:** низкий, ~24–28 px, капля/клякса с «пальцами» тумана по краям. Симметричная — рисуется в одном направлении, влево и вправо — отражением.

**Анимации:** idle 4 (пульсирует), прыжок 4 (присед — отрыв — полёт — приземление), бросок 2, hurt 2, death 4 (рассеивается).

**Промпт (один лист, 4 ряда):**
```
pixel art sprite sheet of a small creature, 4 rows of animation frames, evenly spaced with wide empty space between frames,
row 1: idle pulsing, 4 frames; row 2: hop, 4 frames: squash down, leap up, in the air, land; row 3: hurt, 2 frames; row 4: dissolving into mist, 4 frames,
the same creature in every frame, side view, HD-2D style like Octopath Traveler, flat soft lighting, 2-3 tone cel shading,
1px dark colored outline, limited palette, crisp pixels, no anti-aliasing, plain white background, no ground shadow, no text, no labels,
small blob of violet mist and dark lake water, no face, only two glowing pale cyan eyes, wispy tendrils of fog around the edges,
semi-liquid body, glossy dark purple core
```
Если 4 ряда выходят плохо — генерировать по одному ряду на картинку.

### 7.5 Следующие генерации (бой уже в игре, эти кадры заменят временные)
Сейчас в игре: удары Рэя вверх и вниз играют боковой удар, ходьба солдата — покачивание его стойки, смерть солдата — рассыпание. Готовые промпты (каждая строка таблицы — отдельная картинка):

**Удары Рэя вниз и вверх.** Блок — как в 7.1, но вместо `right side view facing right`:
- вниз — `front view facing the viewer, the slash arc sweeps toward the viewer`;
- вверх — `back view facing away from the viewer, the slash arc sweeps away from the viewer`.

| Картинка | Направление | `<УДАР>` из таблицы 7.1 |
|---|---|---|
| 1 | вниз | удар 1 |
| 2 | вниз | удар 2 |
| 3 | вниз | удар 3 |
| 4 | вверх | удар 1 |
| 5 | вверх | удар 2 |
| 6 | вверх | удар 3 |

**Ходьба Утопшего солдата вбок** — упрощённая (прошлая генерация вышла слишком детальной и при уменьшении «замылилась»):
```
pixel art sprite sheet, slow shambling walk cycle, 4 frames in a single horizontal row, evenly spaced with wide empty space between frames,
the same character in every frame, right side view facing right, full body, frame 1: right leg drags forward, frame 2: body sways down,
frame 3: left leg drags forward, frame 4: body sways down, HD-2D style like Octopath Traveler, chibi proportions 2.5-3 heads tall,
SIMPLE SHAPES, LARGE FLAT COLOR AREAS, FEW DETAILS, bold readable silhouette, flat soft neutral lighting, 2-3 tone cel shading,
1px dark colored outline, limited palette of 8 colors, crisp pixels, no anti-aliasing, plain white background, no ground shadow, no text, no labels,
drowned undead cat soldier, hunched posture, head hanging low, wet grey-blue fur, glowing violet eyes,
torn dark green cloak, rusted helmet, rusted short sword dragging on the ground
```
Для ходьбы вниз и вверх — `front view facing the viewer` / `back view facing away`.

**Смерть солдата** (по желанию — сейчас рассыпание делает скрипт): тем же блоком, `death animation, frame 1: staggering, frame 2: falling to the knees, frame 3: collapsing into a puddle of dark water, frame 4: only a puddle and the rusted helmet remain`.

После обработки: `python Tools/build_combat_sheets.py` собирает игровые листы (функции `humanoid` и `drowned` — вставить новые строки вместо временных).

### 7.6 Страж Перекрёстка (старый козёл)
Сейчас в игре — нарисованная скриптом заглушка (`assets/sprites/guardian/guardian_placeholder.png`). Нужен лист видов (как у героев, рост ~54 px — выше Рэя, сутулый) и idle 4 кадра анфас (покачивается, колокольчик качается). Промпт видов:
```
pixel art character sprite sheet, HD-2D style like Octopath Traveler, chibi proportions 2.5-3 heads tall, anthropomorphic animal character,
three views side by side: front view, back view, right side view, same character in every view, standing neutral pose, full body,
flat soft neutral lighting from top-front, 2-3 tone cel shading, 1px dark colored outline, limited palette, crisp pixels, no anti-aliasing,
plain white background, no ground shadow, no text, no labels,
very old thin anthropomorphic goat, hunched posture, long horns curving backward, long white beard down to the chest,
pale glowing eyes with horizontal pupils, long faded grey hooded travelling cloak, leaning on a tall wooden staff
with a small brass bell, calm, ancient and mysterious, not evil
```
Idle — блоком анимации из раздела 6: `idle animation, 4 frames, front view facing the viewer, slow breathing, the bell on the staff swings slightly`.

### 7.7 Жители Ивового Брода
Сейчас в игре — заглушки скрипта `Tools/villager_placeholders.py`. Истории и внешность — `NPC_DRAFTS.md` и CANON.
Каждому нужен **лист видов** (спереди, сзади, сбоку) и **idle 4 кадра** анфас. Жители ходят мало — ходьба потом.

**Рост** (Рэй — 48 px): Хорст ~46 (кряжистый, широкий), Марта ~40 (низкая, сгорбленная), Ильза ~46, Ганс ~50 (самый
крупный), Ода ~46 (гибкая, вытянутая), Клаус ~50 (высокий, сутулый), Мика ~26.

**Промпт вида** = общий блок стиля (раздел 6) + блок жителя. Первая генерация (2026-10-23) вышла с реалистичными
пропорциями — голова ~1/6 роста, у Рэя ~1/3; на 48 px головы жителей получились крошечными. Поэтому в блоке ниже
чиби-пропорции стоят в начале (как у Рэя: голова ~40 % роста, без «милоты» — пробная каваи-лиса вышла слишком детской),
а к генерации лучше приложить лист Рэя (`assets/sprites/ray/ray_base.png`) как референс пропорций:
```
CHIBI pixel art character sprite sheet, head is about 40% of the total height, compact body, short legs,
small serious eyes, NOT kawaii, NOT anime big eyes, grounded melancholic tone, same proportions as a JRPG pixel sprite,
HD-2D style like Octopath Traveler, anthropomorphic animal character,
three views side by side: front view, back view, right side view, same character in every view, standing neutral pose, full body,
flat soft neutral lighting from top-front, 2-3 tone cel shading, 1px dark colored outline, limited palette, crisp pixels, no anti-aliasing,
plain white background, no ground shadow, no text, no labels,
<блок жителя>
```

**Хорст — кузнец (барсук):**
```
old stocky anthropomorphic badger blacksmith, broad shoulders, grey fur with the classic white stripe down the face,
one eye slightly watery and squinting, burn scars on the forearms up to the elbows, sleeves rolled up,
heavy brown leather apron with soot stains over a rough linen shirt, thick leather gloves tucked in the belt,
small smith hammer hanging at the hip, dark trousers, heavy boots, gruff tired expression
```

**Марта — лавочница (ежиха):**
```
old short anthropomorphic hedgehog shopkeeper woman, slightly hunched, grey-tipped brown spines on the back of the head and back,
round copper-rimmed glasses on a black nose, warm checkered red and brown wool shawl over a dark green dress,
linen apron with small pockets, little wooden abacus in one hand, a clean cloth over the shoulder,
strict but kind expression
```

**Ильза — швея, вдова солдата (кошка):**
```
young tired anthropomorphic grey tabby cat seamstress woman, soft grey striped fur, sad green eyes the color of river weed,
slightly drooping shoulders, faded blue-grey dress with neat visible patches, simple linen apron with a needle and thread pinned on it,
woven linen charm bracelets on the wrist, gentle melancholic expression
```

**Мика — сын Ильзы (котёнок)** — отдельный маленький лист, ~26 px:
```
very small anthropomorphic kitten boy, light grey tabby fur, floppy ears, small dark curious eyes, oversized linen shirt,
holding a tiny carved wooden toy boat, shy pose
```

**Ганс — мельник (бобр):**
```
big heavy anthropomorphic beaver miller, brown fur, one chipped front tooth, wide flat scaly tail with old scars,
coarse sackcloth apron dusted with white flour over a worn brown leather vest, rolled sleeves, flour on the fur and whiskers,
wooden pole hook over the shoulder, calm slow good-natured expression
```

**Ода — лодочница погребальной пристани (выдра):**
```
lean anthropomorphic otter boatwoman, sleek grey-brown fur, long thick tail, calm transparent eyes,
long tarred dark canvas cloak with a deep hood pulled back, rope coiled on one shoulder, small oar or paddle in one hand,
wood shavings and wax stains on the cloak, serene quiet expression, mysterious but kind
```

**Клаус — отставной сержант (пёс-овчар):**
```
old shaggy anthropomorphic sheepdog veteran, long grey and white shaggy fur, torn left ear, grey muzzle,
stiff upright military posture despite age, faded green garrison wool vest without insignia, linen shirt, canvas trousers tucked into
worn soldier boots, bandaged right knee, holding a fishing rod like a spear, stern barking expression with hidden warmth
```

**Idle** — блоком анимации из раздела 6:
`idle animation, 4 frames in a single horizontal row, front view facing the viewer, slow breathing, small shift of weight` + блок жителя.
Свои детали idle: Хорст — `wiping hands on the apron`, Марта — `adjusting the glasses`, Ильза — `holding her shawl`,
Ганс — `scratching the back of the head`, Ода — `the hood edge moving in the wind`, Клаус — `standing at attention then slouching`.

**Обработка:** `python Tools/sprite_pipeline.py "Арт/Генерации/<файл>" --name <id> --palette <ключ> --height <рост>` (палитру
снять с генерации медианным квантованием, как у `drowned`), затем лист idle 4×3 — в `assets/sprites/villagers/<id>.png`
вместо заглушки (формат тот же: ячейка 64, строки — вид спереди, сзади, сбоку).

### 7.8 Проводник, Призрак у фонаря, Лисёнок, Тиль
Черновик к `SPRITE_SPECS.md` (раздел 7.7). Формат тот же: **промпт вида** = блок пропорций и стиля + блок персонажа;
**idle** = блок анимации из раздела 6 + блок персонажа + своя деталь idle.
Канон: `CANON.md` → «Окрестности Ивового Брода» (Проводник, Призрак у фонаря) и «Жители» (Дети, Тиль).

#### Правило пропорций (решение автора)
Чиби как у Рэя: голова около 40 % роста, маленькие серьёзные глаза, **не** каваи и **не** аниме-глаза, тон приземлённый
и меланхоличный. Первые генерации жителей вышли с реалистичными маленькими головами, тестовый лисёнок — слишком милым;
поэтому ограничения стоят в начале промпта и дублируются в негативном промпте. К генерации лучше прикладывать лист Рэя
как референс пропорций.

#### Рост (Рэй — 48 px)

| Персонаж | Рост, px | Почему |
|---|---|---|
| Проводник (сова) | ~50 | чуть выше Рэя за счёт капюшона; фонарь в лапе ниже макушки |
| Призрак у фонаря | ~56 (с рогами) | выше всех жителей, как Вельмор; рога маски — верхние 8–10 px |
| Лисёнок | ~28 | ровесник Мики (~26), чуть выше за счёт ушей |
| Тиль (вол) | ~54 | самый крупный житель (Ганс ~50), широкий и тяжёлый |

#### Общий блок вида (для всех четырёх)
```
CHIBI pixel art character sprite sheet, head is about 40% of the total height, compact body, short legs,
small serious eyes, NOT kawaii, NOT anime big eyes, grounded melancholic tone, same proportions as a JRPG pixel sprite,
HD-2D style like Octopath Traveler, anthropomorphic animal character,
three views side by side: front view, back view, right side view, same character in every view, standing neutral pose, full body,
flat soft neutral lighting from top-front, 2-3 tone cel shading, 1px dark colored outline, limited palette, crisp pixels, no anti-aliasing,
plain white background, no ground shadow, no text, no labels,
<блок персонажа>
```

#### Негативный промпт (раздел 6 + против «милоты» и маленьких голов)
```
blurry, gradient, soft edges, anti-aliasing, 3D render, realistic, photo, human face, human ears on a human,
text, watermark, labels, multiple characters, cropped, dramatic lighting, colored lighting, background scene,
kawaii, moe, anime eyes, big sparkly eyes, huge pupils, blush stickers, cute mascot, realistic proportions, small head, tall body
```
Для двух сверхъестественных (Проводник, Призрак) добавить:
```
glow, aura, bloom, light rays, translucent, transparent, see-through, ghostly blur, smoke, mist, particles, sparkles
```

#### Общий блок idle
```
pixel art sprite sheet, idle animation, 4 frames in a single horizontal row, evenly spaced with wide empty space between frames,
the same character in every frame, front view facing the viewer, full body, slow breathing, small shift of weight, <деталь idle>,
CHIBI proportions, head is about 40% of the total height, small serious eyes, NOT kawaii, NOT anime big eyes,
HD-2D style like Octopath Traveler, flat soft neutral lighting, 2-3 tone cel shading, 1px dark colored outline, limited palette,
crisp pixels, no anti-aliasing, plain white background, no ground shadow, no text, no labels,
<блок персонажа>
```

---

#### 1. Проводник — сова у фонарей душ
Канон: сова в капюшоне со своим фонарём стоит у фонарей душ; переносит к любому зажжённому фонарю; видят его только
мёртвые (Рэй — мёртв и жив одновременно). Референс настроения — сипуха в капюшоне с фонарём.

**Силуэт:** закутанная фигура-«колокол» в глубоком капюшоне, из капюшона светит белый лицевой диск сипухи; в
вытянутой лапе-крыле — фонарь на коротком крюке. Узнаётся по капюшону + фонарю даже залитым одним цветом.

**[ПРЕДЛОЖЕНИЕ]** Фонарь Проводника — маленькая родня фонарей душ (канон: гранёный латунный, фиолетовое стекло,
светлый вихрь-огонёк), чтобы игрок сразу связал сову с фонарями.

```
old quiet anthropomorphic barn owl guide, white heart-shaped facial disc, small dark solemn eyes, small pale beak,
golden-buff plumage with fine grey speckles on the shoulders and chest, no ear tufts,
deep hood of a long weathered dark grey-brown travelling cloak, the hood pulled up over the head, the white face visible inside,
cloak reaching the ground with a frayed hem, wing-hands with feather fingers, small dark talons showing under the hem,
holding up a small faceted brass hand lantern on a short iron hook staff, violet glass panes with a pale light swirl inside,
a few old brass tokens on a cord at the chest, patient, watchful and sorrowful, a guide for the dead, not menacing
```
**Idle:** `the head tilts slowly to one side and back like an owl, one slow blink, the lantern sways slightly on the hook`.

**Что добавит движок (арт — непрозрачный):** свет фонаря (OmniLight + glow по ярким пикселям стекла), лёгкое мерцание
или полупрозрачность «вижу только я» — шейдером (как призрачное состояние Рэя). В арте: стекло фонаря — 2–3 светлых
пикселя без ореола; глаза тёмные, без свечения; края силуэта чёткие, без дымки.

---

#### 2. Призрак у фонаря
Канон: иногда, с шансом, у фонаря стоит сущность, которую видят только мёртвые; шепчет обрывки лора, подсказывает про
тайники и души рядом, меняет гелиосы и души на редкие вещи. Референс — фигура в чёрном плаще с черепом-маской
рогатого зверя.

**Мир антропоморфный — это зверь, не человек:** под маской — чёрный баран (шерсть на кистях, копыта, тонкий хвост,
свои короткие уши торчат из-под маски). Маска — выбеленный череп большого барана с закрученными рогами.
**Отличать от Стража Перекрёстка** (старый козёл): у Стража серый плащ, белая борода, посох с колокольчиком, лицо
открыто и доброе; у Призрака — чёрный плащ, лица нет, только маска, никакой бороды и посоха.

```
tall thin mysterious anthropomorphic black ram spirit merchant, wearing a bleached ram skull as a mask over the whole face,
large curled ram horns of the skull, dark empty eye sockets with two tiny pale pinpoint eyes deep inside,
short black furry ears poking out from under the mask, long ragged black hooded cloak worn over the horns, hood hanging open,
cloak falling to the ground in torn strips, thin black-furred hands with long dark claws, one hand half raised in a beckoning gesture,
dark cloven hooves under the hem, thin black tail with a tuft, a belt of small worn leather pouches, bone charms and old coins on cords,
silent, uncanny and patient, whispering secrets, not a monster, not a demon
```
**Idle:** `slow swaying, the masked head tilts slightly as if listening, the beckoning claw-fingers curl and uncurl`.

**Что добавит движок (арт — непрозрачный):** появление/исчезновение, полупрозрачность, дрожание и смещение цвета —
шейдером; светящиеся точки глаз — glow по светлым пикселям. В арте: плащ плотный чёрный (3–4 оттенка, см. правило
тканей), края без дымки и «хвостов тумана» (туман у фонаря — частицы `Ambience`). Обработка — с `--holes` (тёмный
персонаж, как Вельмор).

---

#### 3. Лисёнок — играет с Микой у колодца
Канон: дети — лисёнок и котёнок, играют у колодца, гоняют кур. Пара к Мике (~26 px): тот тихий и вислоухий, лисёнок —
заводила, но тоже не «милашка», а деревенский ребёнок семьи гарнизона.

```
small anthropomorphic red fox kid boy, about seven years old, ginger fur with cream muzzle and chest, dark brown ear tips and paws,
small dark serious eyes, slightly scruffy fur on the cheeks, big bushy fox tail with a white tip,
patched faded brown linen tunic too big for him with sleeves rolled up, rope belt, short trousers with muddy knees, barefoot,
a scraped knee with a small cloth bandage, holding a short stick like a toy sword,
lively but a little sad-eyed village child of a garrison family, not cute mascot
```
**Idle:** `restless, bouncing slightly on the toes, the tail swishing side to side, tapping the stick against his leg`.

**Попутно — к блоку Мики (7.7):** там стоит `big curious eyes` — это против нового правила. Предлагаю заменить на
`small dark curious eyes` и добавить в начало тот же блок пропорций.

---

#### 4. Тиль — пахарь (вол)
Канон: Тиль — пахарь, вол; фоновый житель на пашне днём, пара реплик (`VILLAGE_SPEC.md`).

```
big heavy anthropomorphic ox ploughman, broad sloping shoulders, reddish-brown short fur with a pale muzzle,
short thick curved horns, small tired gentle eyes, wet dark nose, a frayed straw hat pushed back between the horns,
coarse undyed linen shirt with sleeves rolled up, sweat cloth around the thick neck, brown work trousers rolled to the shins,
rope belt, mud on the hooves and shins, holding a long wooden ox goad stick, a small water gourd at the hip,
tail with a dark tuft, slow, patient and quietly weary, a man of the fields
```
**Idle:** `slow heavy breathing, chewing slowly, wiping the brow with the sweat cloth, the tail tuft flicks`.

---

#### Обработка
`python Tools/sprite_pipeline.py "Арт/Генерации/<файл>" --name <id> --palette <ключ> --height <рост>` — палитру снять
с генерации медианным квантованием (как у `drowned`); `--holes` — для Призрака и, если просветы останутся, для Тиля.
Лист idle 4×3 (ячейка 64) — `python Tools/villager_sheets.py`. Предлагаемые id: `owl_guide`, `lantern_ghost`, `fox_kid`, `til`.

### 7.4 Что рисую сам (без генерации)
Дуги взмахов и эффекты скиллов, вспышки попаданий, цифры урона, тренировочное чучело, фонарь душ, монеты на месте смерти.

### Советы
- Генерируйте каждого персонажа отдельно, по одному листу видов.
- Если генератор поддерживает референс-изображение, давайте ему соответствующий концепт-лист.
- Делайте несколько вариантов и выбирайте тот, где проще читается силуэт: мелкие детали всё равно упростятся при переводе в 48 px.

---

## 7.9 Враги демо по концептам автора: кобольд «Крыс», квалд, голем-шахтёр (2026-10-29)
Механики — `COMBAT_SPEC.md` 3а. Концепты — `Арт/Концепты/Персонажи/` (`kobold.png`, `qvald.png`, `golem_miner.png`); к генерации и для художницы
прикладывать концепт как референс силуэта и палитры. Заглушки в игре — `Tools/enemy_placeholders.py`; настоящий лист заменяет их один к одному.
Формат листов — DirectionalSprite: 4 кадра в строке, строки — анимация × вид (вниз, вверх, вбок; влево — отражение).
**Это враги, не чиби-жители:** пропорции берём с концептов (голова крупная и читаемая, но не каваи).

| Враг | Файл в игре | Ячейка | Рост | Строки (порядок) |
|---|---|---|---|---|
| Кобольд «Крыс» | `kobold/kobold_combat.png` | 64×64 | ~38 px | idle, walk (быстрый бег), attack (замах ножом, выпад, выпад, возврат), death |
| Квалд | `kvald/kvald_combat.png` | 96×80 | ~48 px | idle, walk, attack (замах копьём, выпад, выпад, возврат), throw (замах комком грязи, бросок, 2 кадра возврата), death |
| Голем-шахтёр | `mine_golem/mine_golem_combat.png` | 128×112 | ~70 px | idle, walk, attack (кайло вверх, удар, удар, возврат), slam (поднять оружие, выше, удар в землю, возврат), throw (валун над головой, бросок, 2 возврата), death |

Ступни — на 4 px выше низа ячейки. Щит квалда на виде спереди — в левой лапе, копьё — в правой. Мини-босс шахты — тот же лист (игра увеличивает в 1,25 раза).
Замечание: в тексте combat голем — «заколдованный баран», а на концепте автора — каменный рогатый великан в шлеме-блоке; рисуем по концепту
(рога, каменные наросты, фиолетовые руны, кайло), мех барана — серая шерсть в просветах камня. Уточнить у автора, если разойдётся с каноном.

### Блоки персонажей
**Кобольд:** `small hunched kobold bandit, big pointed orange-red ears, long snout, messy brown tuft of hair, olive-green scarf-cloak over the shoulders, tattered brown trousers, bandaged forearms, belt with pouches, long thin reddish tail, bare clawed feet, short curved knife in hand, sly and nervous`
**Квалд:** `stocky anthropomorphic frog warrior, bright green skin with pale yellow belly, big round orange eyes, crossed leather straps over the chest, steel shoulder plates, green and orange kilt, tall spear with a broad steel blade in the right hand, round wooden shield in the left hand, hermit sentry, stubborn`
**Голем-шахтёр:** `huge enchanted mine-worker golem, hunched, wide shoulders, body of grey and rusty-brown stone chunks with faint violet glowing runes, big stone block helmet with curled brown horns and two small glowing orange eyes, ragged fur loincloth, heavy miner's pickaxe, heavy stone fists, slow and brutal`

### Промпты
- Лист видов: общий блок вида из 7.8, но **без** блока про 40 % головы и «NOT kawaii» (заменить на `chunky proportions as in the reference image`), + блок врага.
- Анимации — блоки из разделов 6 и 7.1 (ходьба, удар), по одной картинке на направление; «замах/удар/возврат» — по таблице выше.
  Бросок грязи (квалд): `frame 1: winding up with a clump of mud held back, frame 2: hurling the mud forward, frame 3-4: arm following through, returning to guard`.
  Бросок валуна (голем): `frame 1: lifting a huge boulder over the head, frame 2: hurling it forward, frame 3-4: arms swinging down, returning to stance`.
  Удар по земле (голем): `frame 1: raising the pickaxe, frame 2: raising it higher, frame 3: smashing it into the ground with a shockwave of dust, frame 4: pulling it back`.
  Смерть: кобольд — падает и убегает дымом (как у шашки), квалд — оседает, щит катится, голем — рассыпается грудой камней, руны гаснут.
- Негативный: как в разделе 6 + `kawaii, anime eyes, human face`.
