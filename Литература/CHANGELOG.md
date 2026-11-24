# CHANGELOG — Долг Кошачьей Души

Короткие записи о заметных изменениях. Новые — сверху. Подробности по подсистемам — `TECH_NOTES.md`.

## 2026-11-21 — камера, предпросмотр и фоторежим

### RU
Наклон, высота и приближение камеры теперь настраиваются по отдельности. Камера смотрит на Рэя, поэтому высота меняет ракурс, а не выводит героя из кадра. Появились готовые виды («Диорама», «Ближе», «Сверху», «Кинематограф») и клавиша V для переключения по кругу с плашкой названия.

Пока фокус в настройках на строке камеры или эффектов, пергамент становится полупрозрачным, пауза-блюр убирается, а камера двигается даже на паузе. Результат виден сразу, меню закрывать не нужно.

Миниатюра 0.8, вертикальное размытие 0.45, новый ползунок «Блум». Фоторежим по F2: пауза, свободная камера, форматы 16:9, 4:3, 1:1 и 9:16, сетка, скрытие Рэя, шаг кадра по F3. Снимки сохраняются в `user://screenshots/`.

Проверки: `camera_fx_test` — 58, 0 ошибок; `hud_test`, `combat_test`, `tutorial_test` — 0 ошибок.

### EN
Tilt, height and zoom are now separate camera settings. The camera aims at Ray, so height changes the angle instead of pushing him out of frame. Added ready-made views ("Diorama", "Closer", "Top", "Cinematic") and V to cycle them with a short name toast.

While a camera or effects row is focused in settings, the parchment turns translucent, the pause blur is removed, and the camera moves even while paused. The result is visible right away, no need to close the menu.

Miniature 0.8, vertical tilt-shift 0.45, new "Bloom" slider. Photo mode on F2: pause, free camera, 16:9, 4:3, 1:1 and 9:16 formats, grid, hiding Ray, frame step on F3. Shots are saved to `user://screenshots/`.

Checks: `camera_fx_test` — 58, 0 errors; `hud_test`, `combat_test`, `tutorial_test` — 0 errors.
