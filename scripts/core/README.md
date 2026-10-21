# scripts/core

Статус: **P0-A–E фундамент примитивов и доменного планировщика
реализован**. P0-A/B/C, P0-D и P0-E прошли отдельные hardening-gate.
Здесь лежат чистые примитивы и доменная модель без привязки к сценам и
автозагрузкам:

- `stable_id.gd` — стабильные ID контента вида `namespace:kind/name`;
- `json_value.gd` — граница JSON-safe значений и каноническая форма чисел для данных, сейвов и сети;
- `rng_streams.gd` — именованные воспроизводимые RNG-потоки;
- `world_clock.gd` — доменный календарь кампании в игровых минутах;
- `fact_log.gd` — append-only журнал авторитетных фактов мира;
- `state_hash.gd` — канонический SHA-256 хэш доменного состояния;
- `definition_registry.gd` — загрузчик/валидатор пакетов JSON-определений;
- `world_state.gd` — сериализуемая правда кампании: seed, package pins, часы/RNG/факты и runtime-сущности;
- `simulation_scheduler.gd` — детерминированный минутный планировщик систем с порядком и лимитом вызовов;
- `physics_layers.gd` — именованные константы 2D-физических слоёв.

Эта папка не является местом для всей будущей симуляции. Экология,
поселения, бой, сеть, сохранения и презентация получат собственные
доменные модули по плану `docs/tech/core_foundation_blueprint.md`.

Контракты примитивов проверяет
`tests/unit/core_foundation_test.tscn`, контракты WorldState и файлового
слоя — `tests/unit/persistence_test.tscn`, а авторитетную сессию и
планировщик — `tests/unit/session_test.tscn`; все три сцены запускаются
в CI настоящим Godot 4.7.2 через `tools/check_project.sh`. Связанные
слои описаны в `scripts/persistence/README.md`, `scripts/app/README.md`
и `scripts/net/README.md`.
