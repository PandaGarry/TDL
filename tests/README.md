# Тесты

## Что есть сейчас: smoke, P0 foundation, persistence и session tests

`tests/smoke/project_validation.tscn` — валидационная сцена. Запускается
как обычная сцена проекта (с активными автозагрузками) и загружает каждый
GDScript из `scripts/` через ResourceLoader: движок компилирует скрипты в
реальном контексте проекта, и CI валится на любой ошибке компиляции.

`tests/unit/core_foundation_test.tscn` — собственный лёгкий runner P0.
Он проверяет пересобранные InputMap/2D-слои, StableId, WorldClock,
RngStreams, FactLog, StateHash и DefinitionRegistry на официальном
пакете `data/core`, включая отказ на дубликатах и битых ссылках.

`tests/unit/persistence_test.tscn` — runner P0-D. Он проверяет
WorldState snapshot/restore без частичного commit, реальный package pin
из DefinitionRegistry, codec v1 и checksum, миграцию
`tests/fixtures/saves/world_v0_legacy.json`, ротацию backup, stale temp,
fallback при битом JSON/checksum и отсутствующий слот.

`tests/unit/session_test.tscn` — runner P0-E. Он проверяет
`SessionProtocol`, детерминированный `SimulationScheduler` с бюджетом и
защитой от прямого сдвига часов, соло-сессию через хостовый конвейер
намерений, отказ при несовпадении package pins, явную сверку legacy-мира
без pins и реальную пару ENet localhost host/client с двумя телами,
одним изменяемым ящиком припасов, отказом подделанного намерения,
отключением и повторным подключением гостя.

Запуск: `tools/check_project.sh [godot]`, автоматически — GitHub Actions
при каждом пуше (`.github/workflows/godot-validate.yml`, Godot 4.7.2).
CI также гоняет закреплённый gdtoolkit 4.5.0 (`gdformat --check` и
`gdlint`) по всем first-party GDScript в `scripts/` и `tests/`. После
P0-A/B/C runner дополнительно покрывает hardening-контракты: пустые
сегменты ID/ключей, циклы и глубину JSON, точный диапазон JSON integer,
string-encoded i64 состояния RNG, каноническую форму JSON-чисел и
сохранение текущего состояния при битом restore.

## Что будет позже

Тестируем не «для галочки», а системы, которые
больно ломать: сейвы и миграции формата, настройки, экономику/инвентарь
(когда появятся), чистую логику без сцен. Для H1 позднее обязательны
детерминированные симуляционные прогоны на фиксированных сидах,
soak-тесты экологии/поселений и проверка одинакового состояния хоста и
клиента; одного smoke-запуска для живого мира недостаточно.

План подключения (этап прототипа/продакшена):

1. Первый слой уже работает собственным headless runner без плагина.
   **GdUnit4 6.2.x** остаётся кандидатом на отдельный спайк перед
   сценовыми/input/mock-тестами; устанавливаем только после зелёной
   проверки на Godot 4.7.2. GUT — альтернативный fallback.
2. Тесты — в этой папке, зеркально структуре `scripts/`
   (например `tests/autoloads/test_save_system.gd`).
3. Внутрипроцессный контур P0-E уже работает в `session_test.tscn`.
   Следующий набор P0-F/G: greybox-презентация, debug overlay,
   двухпроцессный приёмочный прогон host/client и сценарии краша сейва.
   Настройки и сценовые тесты подключаются со своими срезами.
