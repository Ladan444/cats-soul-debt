<#
Запуск консольного Godot с коротким выводом: полный лог — в файл, на экран — только важное
(OK/FAIL/ИТОГ/ОШИБОК/сохранено/ERROR/SCRIPT ERROR/Parse Error, без шумных предупреждений об утечках при выходе).

  powershell -File Tools/godot_run.ps1 import                       # импорт ресурсов
  powershell -File Tools/godot_run.ps1 script Tools/godot/build_world.gd      # генератор (headless)
  powershell -File Tools/godot_run.ps1 test Tools/godot/tests/world_test.gd   # тест в окне 1280x720
  powershell -File Tools/godot_run.ps1 htest Tools/godot/tests/menu_audit.gd  # тест headless
  powershell -File Tools/godot_run.ps1 export                       # сборка Builds/Windows/CatsSoulDebt.exe

Несколько шагов подряд: перечислить через запятую — import,script:Tools/godot/build_world.gd,test:Tools/godot/tests/world_test.gd
Таймаут на шаг — 600 с (-Timeout). Логи — $env:TEMP\godot_run_<n>.log.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)][string]$Mode,
    [Parameter(Position = 1)][string]$Target = "",
    [int]$Timeout = 600,
    [int]$Tail = 0
)

$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "Game\Godot_v4.7.2-stable_win64_console.exe"
$proj = Join-Path $root "Game\CatsSoulDebt"
$keep = 'OK |FAIL|ИТОГ|ОШИБОК|ШАГОВ|сохранено|участков|ERROR|SCRIPT ERROR|Parse Error|killed'
$drop = 'ObjectDB instances were leaked|resources still in use at exit|at: cleanup|at: clear \('

$steps = @()
if ($Mode.Contains(",") -or $Mode.Contains(":")) {
    foreach ($part in $Mode.Split(",")) {
        $kv = $part.Split(":", 2)
        $steps += , @($kv[0], $(if ($kv.Count -gt 1) { $kv[1] } else { "" }))
    }
} else {
    $steps += , @($Mode, $Target)
}

$n = 0
foreach ($s in $steps) {
    $n++
    $m = $s[0]; $t = $s[1]
    $abs = if ($t) { (Resolve-Path (Join-Path $root $t) -ErrorAction SilentlyContinue).Path } else { "" }
    if ($t -and -not $abs) { $abs = $t }
    switch ($m) {
        "import" { $a = @("--headless", "--path", "`"$proj`"", "--import") }
        "script" { $a = @("--headless", "--path", "`"$proj`"", "-s", "`"$abs`"") }
        "htest"  { $a = @("--headless", "--path", "`"$proj`"", "-s", "`"$abs`"") }
        "test"   { $a = @("--resolution", "1280x720", "--path", "`"$proj`"", "-s", "`"$abs`"") }
        "export" {
            $out = Join-Path $root "Builds\Windows\CatsSoulDebt.exe"
            $a = @("--headless", "--path", "`"$proj`"", "--export-release", "`"Windows Desktop`"", "`"$out`"")
        }
        default { Write-Output "неизвестный режим: $m"; exit 2 }
    }
    $log = Join-Path $env:TEMP "godot_run_$n.log"
    $p = Start-Process -FilePath $godot -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    $null = $p.WaitForExit($Timeout * 1000)
    if (-not $p.HasExited) { $p.Kill(); Write-Output "[$m $t] killed по таймауту $Timeout с" }
    Write-Output "--- $m $t (лог: $log)"
    $lines = @(Get-Content $log, "$log.err" -Encoding UTF8 -ErrorAction SilentlyContinue)
    $important = $lines | Where-Object { $_ -match $keep -and $_ -notmatch $drop }
    if ($important) { $important | Select-Object -First 60 }
    if ($Tail -gt 0) { $lines | Select-Object -Last $Tail }
}
