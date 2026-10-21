#!/usr/bin/env bash
# Проверка проекта настоящим Godot 4.7:
#   1) импорт проекта редактором (--import),
#   2) компиляция всех наших GDScript в контексте проекта
#      (сцена tests/smoke/project_validation.tscn),
#   3) контрактные сцены P0 foundation, persistence и authoritative session,
#   4) smoke-запуск главной сцены на несколько кадров (--quit-after).
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

# 2) Компиляция всех собственных скриптов в реальном контексте проекта.
#    ВАЖНО: `--check-only --script <file>` для этого НЕ подходит — файл
#    запускается вне обычного прогона игры, и имена автозагрузок
#    (EventBus, SaveSystem, GameManager...) компилятор не находит, хотя в
#    игре всё валидно (проверено настоящим Godot 4.7.2, см. историю CI).
#    Поэтому запускаем валидационную сцену как обычную сцену проекта:
#    автозагрузки активны, а сцена загружает каждый .gd из scripts/
#    через ResourceLoader, заставляя движок скомпилировать его по-настоящему.
run_step "validate_scripts" 180 "$GODOT_BIN" --headless --path . --scene "res://tests/smoke/project_validation.tscn" --quit-after 30

# 2b) P0 foundation tests: stable IDs, clock/RNG/FactLog/StateHash,
#     DefinitionRegistry, rebuilt InputMap and 2D physics layers.
run_step "core_foundation_tests" 180 "$GODOT_BIN" --headless --path . --scene "res://tests/unit/core_foundation_test.tscn" --quit-after 30

# 2c) P0-D persistence tests: WorldState snapshots, checksums, v0->v1
#     migration, backup rotation and recovery from corrupt current files.
run_step "persistence_tests" 180 "$GODOT_BIN" --headless --path . --scene "res://tests/unit/persistence_test.tscn" --quit-after 30

# 2d) P0-E authoritative session tests: scheduler/intents, host-only saves,
#     package-pin reconciliation and a real ENet localhost host/client pair.
#     The async network runner needs more main-loop iterations than the
#     synchronous suites; it quits itself as soon as its checks finish.
run_step "session_tests" 180 "$GODOT_BIN" --headless --path . --scene "res://tests/unit/session_test.tscn" --quit-after 1200

# 2e) P0-F greybox presentation tests: chunk hydration/dehydration, ActorView
#     and SupplyCrateView 2D physics layers, Camera2D focus, semantic InputMap
#     intents, debug overlay and networked host/client presentation sync.
run_step "presentation_tests" 180 "$GODOT_BIN" --headless --path . --scene "res://tests/unit/presentation_test.tscn" --quit-after 1200

# 2f) P0-G end-to-end acceptance tests: fixed-seed replay, simulated crash
#     during world save, corrupt JSON resilience, two-process OS.create_process
#     ENet host/client convergence, 90-second disconnect grace and BugBundle.
run_step "p0_acceptance_tests" 180 "$GODOT_BIN" --headless --path . --scene "res://tests/integration/p0_acceptance_test.tscn" --quit-after 2400

# 2g) P0-G full-season headless soak-smoke tests (3 seeds x 30 in-game days).
run_step "p0_soak_smoke_tests" 180 "$GODOT_BIN" --headless --path . --scene "res://tests/soak/p0_soak_smoke_test.tscn" --quit-after 300

# 4) Smoke-запуск: главная сцена должна прожить 30 итераций без ошибок
#    скриптов (меню, автозагрузки, загрузка ресурсов).
run_step "smoke" 120 "$GODOT_BIN" --headless --path . --quit-after 30

echo "======================================================================"
echo "Поиск фатальных маркеров ошибок в логах..."
# Godot часто завершается с кодом 0 даже при SCRIPT ERROR, поэтому
# отдельно ищем ошибки скриптов и загрузки ресурсов в текстах логов.
# Обычные ERROR системы CI не валят: в headless CI без GPU допустимы
# предупреждения драйверов; скриптовые же ошибки не допустимы.
if grep -RniE 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to load resource|PROJECT_VALIDATION_FAILED|CORE_FOUNDATION_TESTS_FAILED|PERSISTENCE_TESTS_FAILED|SESSION_TESTS_FAILED|PRESENTATION_TESTS_FAILED|P0_ACCEPTANCE_TESTS_FAILED|P0_SOAK_SMOKE_FAILED' "$LOG_DIR" ; then
	echo "!! В логах найдены ошибки скриптов или загрузки ресурсов (см. выше)."
	FAILED=1
fi

for required_pair in \
	"validate_scripts.log:PROJECT_VALIDATION_OK" \
	"core_foundation_tests.log:CORE_FOUNDATION_TESTS_OK" \
	"persistence_tests.log:PERSISTENCE_TESTS_OK" \
	"session_tests.log:SESSION_TESTS_OK" \
	"presentation_tests.log:PRESENTATION_TESTS_OK" \
	"p0_acceptance_tests.log:P0_ACCEPTANCE_TESTS_OK" \
	"p0_soak_smoke_tests.log:P0_SOAK_SMOKE_OK" ; do
	log_file="${required_pair%%:*}"
	marker="${required_pair#*:}"
	if ! grep -Fq "$marker" "$LOG_DIR/$log_file" ; then
		echo "!! В '$LOG_DIR/$log_file' отсутствует маркер успешного завершения '$marker'"
		if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
			echo "::error title=Missing test marker::${log_file} did not print ${marker}"
		fi
		FAILED=1
	fi
done

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
			grep -RniE -A1 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to load resource|PROJECT_VALIDATION_FAILED|CORE_FOUNDATION_TESTS_FAILED|PERSISTENCE_TESTS_FAILED|SESSION_TESTS_FAILED|PRESENTATION_TESTS_FAILED|ERROR:' "$LOG_DIR" | head -80 || true
			echo '```'
		} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

		grep -RniE -A1 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to load resource|PROJECT_VALIDATION_FAILED|CORE_FOUNDATION_TESTS_FAILED|PERSISTENCE_TESTS_FAILED|SESSION_TESTS_FAILED|PRESENTATION_TESTS_FAILED' "$LOG_DIR" | head -40 | while IFS= read -r line; do
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
