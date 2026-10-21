# TDL

Рабочее название игры на **Godot 4.7** (GDScript). Репозиторий подготовлен
с чистого листа как аккуратный технический каркас и документальная база
пре-продакшена. Направление H1 выбрано; Baseline Lock раунда 12 собрал
**GDD v1.0 Core Baseline**, достаточный для строительства ядра. P0 уже
начат: реализованы примитивы Core и реестр JSON-данных, но игрового
прототипа и живой симуляции в коде пока нет.

> Название **TDL** — временное (унаследовано от имени репозитория).
> Настоящее название пока не выбрано и не блокирует пре-продакшен.

## Быстрый старт

1. Установить **Godot 4.7.x** (standard-версия, не .NET): https://godotengine.org/download
2. Открыть в редакторе этот репозиторий (файл `project.godot`).
3. Нажать **F5** — запустится заглушка главного меню. Это проверка, что
   проект, автозагрузки и сцены на месте; самой игры ещё нет.
4. Дальше — читать [`docs/`](docs/README.md): сначала журнал одобренных
   решений, GDD v1.0 Core Baseline и Baseline Lock раунда 12, затем
   специализированные документы. Аудит раунда 11 и протокол раундов —
   исторические источники, а не текущий список задач.

## Структура проекта

| Папка | Что внутри |
|---|---|
| `scenes/` | Сцены Godot: `main/`, `levels/`, `characters/`, `ui/` |
| `scripts/` | GDScript: `autoloads/` (глобальные системы), `components/`, `core/`, `ui/` |
| `assets/` | Арт, аудио (`music/`, `sfx/`, `ambience/`), шрифты, шейдеры |
| `resources/` | Данные Godot (`.tres`): конфиги, темы UI, диалоги |
| `addons/` | Сторонние плагины (см. [`addons/README.md`](addons/README.md)) — лежат готовыми, но **выключены** до первого использования |
| `docs/` | Дизайн (`design/`), лор (`lore/`), арт (`art/`), техника (`tech/`), продакшен (`production/`) |
| `tools/` | Служебные скрипты (установка/обновление плагинов) |
| `data/` | Версионированные пакеты определений Core (`data/core`) |
| `tests/` | Smoke и собственный P0 foundation runner; спайк GdUnit4 — перед сценовыми тестами |

## Что уже работает

Автозагрузки (порядок важен, см. `docs/tech/architecture.md`):

- **EventBus** — глобальные сигналы игрового цикла;
- **AudioManager** — шины Master/Music/SFX/Ambience, кроссфейд музыки, пул SFX;
- **SettingsManager** — настройки в `user://settings.cfg` (громкость, фулскрин, язык `ru` по умолчанию);
- **SaveSystem** — JSON-сохранения по слотам в `user://saves/`, с версией формата;
- **SceneLoader** — мгновенная и асинхронная смена сцен с прогрессом;
- **GameManager** — состояние игры (меню/игра/пауза), пауза по Esc.

Настроено: разрешение 1920×1080, stretch `canvas_items/expand`,
семантические действия ввода TDL (движение/бег/осторожный шаг, осмотр,
взаимодействие, помощь/разговор, переноска, инструменты, строительство,
образцы, отдых, команды группе, debug и пауза оболочки), 2D-физические
слои Terrain/Bodies/Structures/Items/Interactables/Hazards/Sensors/
Projectiles и renderer **GL Compatibility**. В `scripts/core/` уже лежат
StableId, JsonValue, WorldClock, RNG-потоки, FactLog, StateHash,
DefinitionRegistry и константы слоёв; первый пакет определений — в
`data/core/`.

**Проверка движком:** GitHub Actions при каждом пуше скачивает официальный
Godot **4.7.2**, проверяет сумму SHA512, импортирует проект, компилирует
все скрипты в контексте проекта, запускает P0 foundation tests и главную
сцену в headless-режиме; gdtoolkit 4.5.0 проверяет формат/линт всех
first-party GDScript в `scripts/` и `tests/`
(`.github/workflows/godot-validate.yml`, локально —
`tools/check_project.sh`).

## Статус

**Пре-продакшен завершён Baseline Lock; идёт строительство P0 Core.** Выбрано направление H1 «Родной мир на общем
игровом ядре»: открытый живой дом, кооператив 1–4, конечная экология,
якорные разломы между планетами, смертные персонажи и наследие мира.
Стратегические основания и причинная рамка одобрены в раундах 4–5;
Act I должен стабилизировать долину-убежище за целевой ориентир 20–40
часов, после чего новая беда открывает Act II. В раунде 6 автор одобрил
гибридный путь игрока A → C → B. В раунде 7 заданы весенний старт,
средневековая племенная эпоха и множество поселений; рабочая первая
долина Севары и NPC описаны в
[`docs/design/first_valley_spring_tribes.md`](docs/design/first_valley_spring_tribes.md),
а рекомендуемая модель боя — в
[`docs/design/personal_combat_and_leadership.md`](docs/design/personal_combat_and_leadership.md).
В раундах 8–10 система имён Севары создана и одобрена автором для RU/EN.
Адаптивные поселения, выбор вождя по доверию/силе/влиянию, назначения и
сессионная распределённая власть описаны в
[`docs/design/adaptive_settlements_leadership_and_coop.md`](docs/design/adaptive_settlements_leadership_and_coop.md)
и [`docs/design/leadership_succession_reputation_roles.md`](docs/design/leadership_succession_reputation_roles.md).
После раунда 10 автор подтвердил стартовые веса выборов, окно 5–7 дней и
защиту отсутствующего игрока по умолчанию. Раунд 11 провёл полный аудит.
Раунд 12 одобрил поэтапный моддинг и по делегированию автора закрыл
Baseline Lock в [`docs/production/round12_baseline_lock.md`](docs/production/round12_baseline_lock.md),
а сводная база обновлена до [`docs/design/gdd.md`](docs/design/gdd.md)
(GDD v1.0 Core Baseline).
Источник истины по одобрениям — [`docs/production/decisions.md`](docs/production/decisions.md),
план — в [`docs/production/roadmap.md`](docs/production/roadmap.md).
