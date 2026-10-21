# scripts/net

Статус: **P0-E — транспортный шов и протокол авторитетной сессии
реализованы и прошли hardening-gate**.

## Состав

- `session_transport.gd` — абстрактный интерфейс транспорта (`host`,
  `join`, `poll`, `send_packet`, `broadcast_packet`, `disconnect_peer`,
  `close`). Переносит только непрозрачные пакеты и не знает ни о
  `WorldState`, ни о правилах игры.
- `enet_session_transport.gd` — первый адаптер транспорта поверх
  `ENetMultiplayerPeer` и собственного `SceneMultiplayer`, созданного
  через `MultiplayerAPI.create_default_interface()`. Глобальный
  multiplayer дерева сцен, RPC-пути нод и `server_relay` не
  используются.
- `session_protocol.gd` — версионированный UTF-8 JSON-протокол сообщений
  (`hello`, `welcome`, `intent`, `snapshot`, `event`, `reject`, `ping`,
  `pong`, `server_stopping`) и намерений (`move_body`,
  `interact_object`) с лимитом размера пакета и проверкой
  `JsonValue.is_safe`.
- `session_message_validator.gd` — строгая проверка семантических
  payload для `hello`, `welcome` и `snapshot`, включая совпадение версии
  игры, схемы мира, package pins, существование определений, список
  участников и `StateHash`.

## Текущие ограничения

- В P0-E репликация передаёт надёжный полный снимок маленького greybox-
  мира после авторитетных изменений. Дельты и фильтрация по интересу
  остаются задачей следующего сетевого прохода после измерения реальных
  размеров состояния.
- ENet работает по локальной сети/прямому UDP; публичный NAT traversal и
  Steam-транспорт будут подключаться за тем же `SessionTransport`.

Связанные слои: [`../app/README.md`](../app/README.md),
[`../core/README.md`](../core/README.md). Контракты проверяет
`tests/unit/session_test.tscn`.
