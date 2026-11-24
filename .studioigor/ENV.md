# Environment — Долг Кошачьей Души

VERIFIED: no

## Installed
| tool | version | why |
|---|---|---|
| Godot | 4.7.2 stable | движок и экспорт |
| Python | 3.14.8 | генераторы, тесты, инструменты |
| Pillow | актуальная | обработка спрайтов и текстур |
| Blender | 5.2 | 3D-мир и замок |
| Git | 2.x | версии и бэкап |

## Agent integrations
Blender MCP — сцены и рендеры; Godot запускается через `Tools/godot_run.ps1`; отдельного Godot MCP нет.

## Commands
RUN: Game\Godot_v4.7.2-stable_win64.exe --path Game\CatsSoulDebt
TEST: powershell -File Tools/godot_run.ps1 htest Tools/godot/tests/chapter1_test.gd
BUILD: powershell -File Tools/godot_run.ps1 export
CAPTURE: manual: снять окно сборки через PowerShell в C:\Temp\opencode
EDITOR: Game\Godot_v4.7.2-stable_win64.exe --editor --path Game\CatsSoulDebt

## Pitfalls
- Полный прогон 30 тестов идёт около 23 минут; оконные тесты нельзя запускать headless.
- Импорт и Blender — по одному процессу за раз.
