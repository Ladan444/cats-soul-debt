# Резервная копия проекта в Git: рабочая папка (рабочий стол) → репозиторий автора → коммит.
# Запуск: powershell -File Tools/backup.ps1 "что сделано"
# Репозиторий: C:\Users\Ladan444\The cat's soul debt (в нём папка «The cat's soul debt GAMEDEV» — зеркало рабочей).
# Кэш Godot, сборки, редактор Godot, скриншоты и скачанные архивы OpenGameArt (1,4 ГБ; в игру идут только
# выбранные треки — assets/audio) не копируются (их же не хранит .gitignore).
# Файл в UTF-8 с BOM — иначе PowerShell 5.1 ломает кириллицу в путях.
param([string]$Message = "Резервная копия")

$src = Split-Path -Parent $PSScriptRoot
$repo = "C:\Users\Ladan444\The cat's soul debt"
$dst = Join-Path $repo "The cat's soul debt GAMEDEV"
$git = "C:\Program Files\Git\cmd\git.exe"

# /MIR — зеркало (удалённое в рабочей папке удаляется и в копии); исключения — как в .gitignore.
robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP `
    /XD ".godot" (Join-Path $src "Builds") (Join-Path $src "Арт\Скриншоты") (Join-Path $src "Арт\Ассеты\Audio\OpenGameArt") "__pycache__" `
    /XF "Godot_v*.exe" "*.blend1" "*.blend2" "*.tmp" | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Error "robocopy: код $LASTEXITCODE"; exit 1 }

& $git -C $repo add -A
$changes = (& $git -C $repo status --porcelain | Measure-Object).Count
if ($changes -eq 0) { Write-Output "Изменений нет."; exit 0 }
& $git -C $repo commit -q -m $Message
& $git -C $repo log --oneline -1
Write-Output "Файлов в коммите: $changes"
