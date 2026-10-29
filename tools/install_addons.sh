#!/usr/bin/env bash
# Установка/обновление плагинов в addons/ из официальных репозиториев.
# Клонирует во временную папку и копирует только папку аддона.
# ВНИМАНИЕ: перезаписывает существующие папки плагинов — ручные правки
# внутри addons/<плагин>/ будут потеряны (мы их и не делаем, см. docs).
set -euo pipefail

cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

install_addon() {
	local repo="$1" src="$2" dst="$3"
	echo "==> $dst  <-  $repo"
	git clone --depth 1 -q "https://github.com/$repo.git" "$TMP/repo"
	rm -rf "addons/$dst"
	cp -r "$TMP/repo/$src" "addons/$dst"
	echo "    commit: $(git -C "$TMP/repo" rev-parse --short HEAD)  ($(git -C "$TMP/repo" log -1 --format=%cs))"
	rm -rf "$TMP/repo"
}

mkdir -p addons
install_addon "nathanhoad/godot_dialogue_manager" "addons/dialogue_manager" "dialogue_manager"
install_addon "ramokz/phantom-camera"             "addons/phantom_camera"   "phantom_camera"
install_addon "derkork/godot-statecharts"        "addons/godot_state_charts" "godot_state_charts"

echo
echo "Готово. Обнови таблицу версий в docs/tech/addons.md и проверь проект в редакторе."
