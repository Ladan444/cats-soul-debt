<#
Пересборка мира с ручными правками автора (Tools/world_overrides.json — меню Godot «Мир: сохранить правки»):
Blender без окна собирает мир (build_world.py через blender/rebuild_entry.py), пишет glb для Godot и вид сверху
для миникарты, затем Godot импортирует ресурсы и собирает scenes/levels/world.tscn. ~3–5 минут.

  powershell -File Tools/rebuild_world.ps1            # всё
  powershell -File Tools/rebuild_world.ps1 -NoMap     # без вида сверху (быстрее; миникарта останется прежней)

Перед запуском закрой Blender, если в нём открыт мир (один процесс Blender за раз); сцену world.tscn в редакторе
Godot после пересборки переоткрой.
#>
param([switch]$NoMap)

$root = Split-Path -Parent $PSScriptRoot
$blender = "D:\SteamLibrary\steamapps\common\Blender\blender.exe"
if (-not (Test-Path $blender)) { Write-Error "Нет Blender: $blender"; exit 1 }
$entry = Join-Path $root "Tools\blender\rebuild_entry.py"
$extra = if ($NoMap) { @("--", "nomap") } else { @() }
$log = Join-Path $env:TEMP "rebuild_world_blender.log"
Write-Host "--- Blender: сборка мира, glb$(if (-not $NoMap) { ', вид сверху' }) (лог: $log)"
$t = Get-Date
& $blender -b --python $entry @extra *> $log
if (-not (Select-String -Path $log -Pattern "REBUILD_OK" -Quiet)) {
    Select-String -Path $log -Pattern "Error|Traceback" | Select-Object -First 8 | ForEach-Object { Write-Host $_.Line }
    Write-Error "Blender: сборка не завершилась, см. $log"; exit 1
}
Write-Host ("Blender: готово за {0:N0} с" -f ((Get-Date) - $t).TotalSeconds)
& powershell -File (Join-Path $root "Tools\godot_run.ps1") "import,script:Tools/godot/build_world.gd,script:Tools/godot/build_tavern.gd"   # таверна берёт из мира место своей двери
Write-Host "Готово. Переоткрой scenes/levels/world.tscn в редакторе Godot."
