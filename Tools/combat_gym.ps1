<#
Арена баланса M01 («гимн боя»): изолированная сцена в res://tests/, в сборку не входит.

  powershell -File Tools/combat_gym.ps1

Слева — Рэй, манекен и руна, которая бьёт по Рэю. Справа — пульт: HP, урон, неуязвимость,
урон и интервал врага, HP манекена; DPS, пик и время добивания. Пробел — рывок, ЛКМ — удар,
Shift — бег. F6 в редакторе запускает эту же сцену.
#>
$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "Game\Godot_v4.7.2-stable_win64.exe"
$proj = Join-Path $root "Game\CatsSoulDebt"

& $godot --path $proj "res://tests/combat_gym.tscn"
