#!/usr/bin/env bash
# Проверка проекта настоящим Godot 4.7:
#   1) импорт проекта редактором (--import),
#   2) parse-check всех наших GDScript-файлов (--check-only),
#   3) smoke-запуск главной сцены на несколько кадров (--quit-after).
#
# Использование:
#   tools/check_project.sh [путь_к_бинарнику_godot]
# Если путь не задан — берётся $GODOT_BIN, затем просто `godot` из PATH.
# Логи складываются в build/ci-logs/ (папка игнорируется гитом).
set -uo pipefail

cd "$(dirname "$0")/.."
GODOT_BIN="${1:-${GODOT_BIN:-godot}}"
LOG_DIR="build/ci-logs"
mkdir -p "$LOG_DIR"

FAILED=0

have_timeout=0
command -v timeout >/dev/null 2>&1 && have_timeout=1

# Запускает команду с таймаутом (если coreutils timeout доступен),
# пишет объединённый вывод в лог и печатает его в консоль.
run_step() {
	local name="$1" seconds="$2"
	shift 2
	echo "======================================================================"
	echo "==> $name"
	echo "    $*"
	local status=0
	if [ "$have_timeout" -eq 1 ]; then
		timeout "$seconds" "$@" 2>&1 | tee "$LOG_DIR/${name}.log" || status=$?
	else
		"$@" 2>&1 | tee "$LOG_DIR/${name}.log" || status=$?
	fi
	if [ "$status" -ne 0 ]; then
		echo "!! Шаг '$name' завершился с кодом $status"
		FAILED=1
	fi
}

echo "Godot binary: $GODOT_BIN"
"$GODOT_BIN" --version || { echo "Не удалось запустить Godot"; exit 1; }

# 1) Импорт проекта — редактор в headless-режиме сканирует все ресурсы и
#    глобальные классы, затем завершается.
run_step "import" 300 "$GODOT_BIN" --headless --path . --import

# 2) Parse-check собственных скриптов (папку addons/ не трогаем: плагины
#    пока выключены, их скрипты движок проверяет сам при импорте).
script_index=0
while IFS= read -r -d '' file; do
	script_index=$((script_index + 1))
	run_step "script_${script_index}" 120 "$GODOT_BIN" --headless --path . --check-only --script "res://${file}"
done < <(find scripts -name '*.gd' -type f -print0 | sort -z)

# 3) Smoke-запуск: главная сцена должна прожить 30 итераций без ошибок
#    скриптов (меню, автозагрузки, загрузка ресурсов).
run_step "smoke" 120 "$GODOT_BIN" --headless --path . --quit-after 30

echo "======================================================================"
echo "Поиск фатальных маркеров ошибок в логах..."
# Godot часто завершается с кодом 0 даже при SCRIPT ERROR, поэтому
# отдельно ищем ошибки скриптов и загрузки ресурсов в текстах логов.
# Обычные ERROR системы CI не валят: в headless CI без GPU допустимы
# предупреждения драйверов; скриптовые же ошибки не допустимы.
if grep -RniE 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to load resource' "$LOG_DIR" ; then
	echo "!! В логах найдены ошибки скриптов или загрузки ресурсов (см. выше)."
	FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
	# В GitHub Actions дублируем ключевые строки логов в аннотации и summary:
	# полные логи/артефакты не всегда доступны внешним инструментам, а первые
	# строки ошибок нужны для быстрой диагностики. Локально это не включается.
	if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
		{
			echo "## Godot validation — FAILED"
			echo
			echo "Первые совпадения ошибок скриптов/ресурсов:"
			echo '```'
			grep -RniE 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to load resource|ERROR:' "$LOG_DIR" | head -80 || true
			echo '```'
		} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

		grep -RniE 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to load resource|ERROR:' "$LOG_DIR" | head -40 | while IFS= read -r line; do
			clean_line="$(printf '%s' "$line" | sed -e 's/%/%25/g' -e 's/\r/%0D/g')"
			echo "::error title=Godot validation::${clean_line}"
		done

		for log in "$LOG_DIR"/*.log; do
			[ -f "$log" ] || continue
			tail -n 5 "$log" | while IFS= read -r line; do
				clean_line="$(printf '%s' "$line" | sed -e 's/%/%25/g' -e 's/\r/%0D/g')"
				echo "::warning title=Godot log tail ${log}::${clean_line}"
			done
		done
	fi
	echo "ИТОГ: FAILED (логи: $LOG_DIR)"
	exit 1
fi
echo "ИТОГ: OK (логи: $LOG_DIR)"
