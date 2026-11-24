# Фоторежим, камера и экранные эффекты — разведка (2026-11-17)

Что уже есть в игре: камера `diorama_camera.gd` — фиксированный offset (0, 9, 11), FOV ~30,
слежение с `follow_speed`, тряска через `h_offset/v_offset`; в настройках есть ползунки
(яркость, тряска, глитч) через `SettingRow.make_slider` и `Settings`. Атмосфера —
`AtmosphereBlender`: цвет неба/тумана, `glow_intensity`, `adjustment_saturation`,
`tonemap_exposure`, `adjustment_brightness`. **DOF/CameraAttributes нет, фоторежима нет,
пост-обработки кроме glow и adjustments нет.**

## Источники
- Godot 4.7, Environment and post-processing — что есть из коробки: glow (Bloom, Levels, Blend,
  Glow Map для «грязной линзы»), fog (depth/height, sun scatter), adjustments (BCS, 1D-градиент,
  3D LUT), SSR/SSAO/SSIL; DOF и экспозиция — отдельный ресурс `CameraAttributesPractical`
  (near/far blur, distance/transition/amount), и документация прямо называет сочетание
  near+far «tilt-shift»: https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html
- Eventide, «Photo Mode Wishlist: 7 features»: пауза + покадровый шаг, свободная камера с
  внятными границами, настоящие параметры линзы с подсказками, уборка сцены (HUD, герой,
  оружие), свет/погода/время, сетка третей и форматы кадра, быстрый интерфейс с presets:
  https://eventidegaming.com/blog/photo-mode-wishlist-features-every-game-needs
- Ghost of Yōtei, официальный разбор фоторежима: фокусное 12–300 мм, диафрагма f/1.2–f/63,
  глубина резкости, погода и время суток, 16 позиций камеры для трекингового кадра:
  https://blog.playstation.com/2025/09/24/ghost-of-yotei-photo-mode-features-detailed-tips-guide
- The Last of Us Part II, гайд Naughty Dog: как FOV и DOF работают вместе, кадровый шаг:
  https://blog.playstation.com/2020/10/27/naughty-dogs-guide-to-the-last-of-us-part-iis-photo-mode/
- Ghost of Tsushima: время, погода, ветер, анимированное окружение, галерея:
  https://blog.playstation.com/2020/07/16/ghost-of-tsushima-photo-mode-gallery-and-tips-guide/
- Game Developer: базовые приёмы фотографии в фоторежимах (свет важнее фильтров):
  https://gamedeveloper.com/art/how-to-help-players-shoot-better-in-game-photos-for-no-cost
- Миниатюрный эффект (tilt-shift, «miniature faking»): https://en.wikipedia.org/wiki/Miniature_faking

## Выводы для нас
1. **Миниатюра** в 2.5D-диораме держится на трёх вещах: наклонный кадр, узкая полоса
   резкости (near+far DOF) и сочные цвета/свет. Просто «блюр всего» убивает пиксель-арт.
   Сильнее всего работает **Y-tilt-shift**: резкая полоса по центру кадра, размытие к верху
   и низу — это шейдер поверх экрана, не только DOF камеры.
2. **DOF в Godot** бесплатен по коду (CameraAttributesPractical на камере), но на пиксель-арте
   требует осторожных значений: amount небольшой, distance/transition в метрах, проверка на
   640×360-холсте.
3. **Фоторежим** — это отдельная пауза + свободная камера + скрытый HUD + сохранение PNG.
   В Godot всё это S–M: пауза есть, `get_viewport().get_texture().get_image().save_png()`
   уже используется в тестах, камера — один Node3D.
4. **Эффекты экрана** дешевле всего делать через Environment (glow, adjustments, fog) и один
   общий post-process шейдер (виньетка, зерно, хроматика, Y-блюр). LUT-цветокор — самой
   текстурой, без кода.
5. **Осторожно:** сильный блум + блюр + зерно на пиксель-арте превращают картинку в кашу;
   эффекты по умолчанию должны быть слабыми, а сильные — в фоторежиме.
6. **Цель слабых ПК** (BACKLOG P9): всё, что включаем по умолчанию, проверять на самом
   дешёвом пресете; фоторежим может позволить себе больше, потому что игра на паузе.

## Риски
- `CameraAttributesPhysical` блокирует FOV камеры — нам нужен `Practical`.
- Шейдер с `screen_texture` ломает прозрачность/2D, если наложить его не на тот CanvasLayer:
  HUD должен оставаться вне обработки.
- Сохранение настроек камеры в `Settings` — новые ключи; старые сохранения не ломаются,
  потому что `Settings` читает с fallback.
- Скриншоты в `user://screenshots/` — вне git; в сборке путь тот же, у игрока файлы рядом
  с сохранением.
