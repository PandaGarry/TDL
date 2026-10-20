# Установка/обновление плагинов в addons/ из официальных репозиториев (Windows).
# ВНИМАНИЕ: перезаписывает существующие папки плагинов — ручные правки
# внутри addons/<плагин>/ будут потеряны (мы их и не делаем, см. docs).
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

function Install-Addon($Repo, $Src, $Dst) {
    Write-Host "==> $Dst  <-  $Repo"
    $Clone = Join-Path $Tmp "repo"
    git clone --depth 1 -q "https://github.com/$Repo.git" $Clone
    $Target = Join-Path $Root "addons/$Dst"
    if (Test-Path $Target) { Remove-Item -Recurse -Force $Target }
    Copy-Item -Recurse (Join-Path $Clone $Src) $Target
    $Commit = git -C $Clone rev-parse --short HEAD
    $Date = git -C $Clone log -1 --format=%cs
    Write-Host "    commit: $Commit  ($Date)"
    Remove-Item -Recurse -Force $Clone
}

try {
    New-Item -ItemType Directory -Force -Path "addons" | Out-Null
    Install-Addon "nathanhoad/godot_dialogue_manager" "addons/dialogue_manager" "dialogue_manager"
    Install-Addon "ramokz/phantom-camera"             "addons/phantom_camera"   "phantom_camera"
    Install-Addon "derkork/godot-statecharts"        "addons/godot_state_charts" "godot_state_charts"
} finally {
    Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Готово. Обнови таблицу версий в docs/tech/addons.md и проверь проект в редакторе."
