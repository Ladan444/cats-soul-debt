# Пересобирает все спрайты персонажей из генераций и копирует их в игру.
# Запуск из корня проекта: powershell -File Tools/rebuild_all.ps1
# Новую генерацию добавлять в список $jobs: файл, имя результата, палитра, рост, доп. флаги.

$ErrorActionPreference = "Stop"
$env:PYTHONIOENCODING = "utf-8"
$py = "$env:LOCALAPPDATA\Programs\Python\Python314\python.exe"
$gen = "Арт/Генерации"
$out = "Арт/Обработано"

$jobs = @(
    @{ file = "1792522386678-01a15aa8-6dfc-7c57-b65c-afad8cc5f118.png"; name = "ray";              palette = "ray";    height = 48; flags = @() },
    @{ file = "1792524154458-01a15ac3-9bf5-7452-b031-8701fe45d0cb.png"; name = "ray_walk_side";    palette = "ray";    height = 48; flags = @("--anchor", "head") },
    @{ file = "1792524533948-01a15ac9-3da0-7862-bd57-6468c6ef3fb7.png"; name = "velmor";           palette = "velmor"; height = 56; flags = @("--holes") },
    @{ file = "1792525766191-01a15adc-3d06-7a4d-8467-45a7e64e25a7.png"; name = "velmor_walk_side"; palette = "velmor"; height = 56; flags = @("--holes", "--anchor", "head") },
    @{ file = "1792524628798-01a15aca-a1ad-7b7e-ad15-35f148669f26.png"; name = "liara";            palette = "liara";  height = 46; flags = @() },
    @{ file = "1792524976670-01a15ad0-1d9b-75cb-ae62-7afbc7de9484.png"; name = "liara_walk_side";  palette = "liara";  height = 46; flags = @("--anchor", "head") }
)

foreach ($j in $jobs) {
    & $py Tools/sprite_pipeline.py "$gen/$($j.file)" --name $j.name --palette $j.palette --height $j.height @($j.flags) | Select-Object -Last 1
}

foreach ($n in "ray", "velmor", "liara") {
    & $py Tools/make_placeholder_anim.py "$out/${n}_sheet.png" --palette $n --out "$out/${n}_anim.png"
    & $py Tools/set_anim_row.py "$out/${n}_walk_side_sheet.png" "$out/${n}_anim.png" --anim walk --dir side
    $dst = "Game/CatsSoulDebt/assets/sprites/$n"
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item "$out/${n}_anim.png" "$dst/${n}_anim.png" -Force
}

& $py Tools/preview_characters.py ray velmor liara
