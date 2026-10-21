# scripts/app

Статус: **P0-E — авторитетная сессия кампании реализована и прошла
hardening-gate**. Эта папка содержит composition root одной запущенной
кампании, а не новые глобальные автозагрузки.

## Состав

- `game_session.gd` — авторитетный `Node`-координатор кампании. Собирает
  `DefinitionRegistry`, `WorldState`, `SimulationScheduler`,
  `SaveStore`, `SessionTransport` и таблицу участников. Одиночная игра и
  сетевой кооператив проходят через один и тот же хостовый конвейер
  намерений.
- `session_world_loader.gd` — загрузка активного `DefinitionRegistry`,
  проверка обязательных определений сессии, инициализация новой кампании
  с package pin, сверка pins сохранённого мира с реестром и явное
  принятие текущего pin только для мигрированных legacy-сейвов без pins.
- `session_participants.gd` — runtime-привязка участников, peer ID,
  состояния подключения и последней принятой `client_sequence`. Эти
  данные живут в сессии и не засоряют мировой сейв.
- `session_intent_processor.gd` — хостовая проверка одного намерения из
  очереди: валидность конверта, привязка участника, монотонность
  `client_sequence`, владение телом и делегирование доменного эффекта.

## Инварианты P0-E

- `GameSession` не является автозагрузкой: её создаёт сцена/тест на
  время жизни кампании.
- Клиент никогда не меняет свой зеркальный `WorldState` локально и не
  вызывает `SaveStore`/`WorldStateCodec.save_to_store`.
- Все факты мира в рамках сессии добавляются на текущей минуте
  `WorldClock`.
- Сохранение мира разрешено только на хосте и только между батчами
  намерений и шагами `SimulationScheduler`.

Связанные слои: [`../core/README.md`](../core/README.md),
[`../net/README.md`](../net/README.md),
[`../features/greybox/README.md`](../features/greybox/README.md),
[`../persistence/README.md`](../persistence/README.md). Контракты
проверяет `tests/unit/session_test.tscn`.
