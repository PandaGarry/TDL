# Документация TDL

Карта документов. Принцип: один документ — одна тема; всё, что решено,
фиксируем здесь, а не «держим в голове». Статус каждого документа указан
в его начале. Используем точные статусы: одобрено автором, делегировано
агенту, рабочая модель, кандидат/рекомендация, проверка прототипом,
открыто автору, историческая/заменённая запись.

При конфликте сначала смотрим `production/decisions.md`, затем
`production/round12_baseline_lock.md`, сводный `design/gdd.md` и
специализированный документ. `lore/open_questions.md` и аудит раунда 11
являются историческими протоколами, а не текущим списком задач.

## С чего начать

1. [`production/decisions.md`](production/decisions.md) — подробный журнал
   одобренных решений. Для стратегических оснований H1 это источник
   истины: что принято, почему, что отвергнуто и где граница одобрения.
2. [`design/gdd.md`](design/gdd.md) — **GDD v1.0 Core Baseline:** питч,
   столпы, кор-цикл, системы, Act I, scope, Core и моддинг.
3. [`production/round12_baseline_lock.md`](production/round12_baseline_lock.md) —
   Baseline Lock: закрытые решения, стек, моддинг и критерии P0–P3.
   Аудит раунда 11 (`production/documentation_audit_round11.md`) — снимок
   состояния до этого замыкания.
4. [`design/first_valley_spring_tribes.md`](design/first_valley_spring_tribes.md) —
   **Baseline-конкретизация раундов 7–12:** весенняя долина Севары,
   средневековые адаптивные племенные поселения, вожди, 24 якорных NPC,
   одобренный RU/EN-нейминг, межпоселенческие отношения и
   динамический баланс. Социальная преемственность и распределённая
   власть — в [`design/adaptive_settlements_leadership_and_coop.md`](design/adaptive_settlements_leadership_and_coop.md)
   и [`design/leadership_succession_reputation_roles.md`](design/leadership_succession_reputation_roles.md).
5. [`design/personal_combat_and_leadership.md`](design/personal_combat_and_leadership.md) —
   принятая Baseline-модель боя C и прокачки: личный персонаж всегда,
   лидерство и отряд как социальная прогрессия; числа проверяет P3.
6. [`design/act1_hybrid_experience_concept.md`](design/act1_hybrid_experience_concept.md) —
   расширенная концепция Act I: одобренный гибрид A → C → B, партитура
   начала, циклы, NPC, живой дом, пейзажи, лор-тайны и экспедиции.
7. [`design/round6_core_loop_variants.md`](design/round6_core_loop_variants.md) —
   исторический документ трёх исходных вариантов раунда 6.
8. [`design/core_generation_and_consequences.md`](design/core_generation_and_consequences.md) —
   Core, генерация, якорные разломы, наследие, необратимость, каскад
   кризиса и арка Act I.
9. [`design/home_world_and_core_concept.md`](design/home_world_and_core_concept.md) — разбор
   выбранного направления H1 о родном мире на общем игровом ядре.
10. [`lore/world_bible.md`](lore/world_bible.md) — библия мира Baseline v1.
11. [`lore/open_questions.md`](lore/open_questions.md) — ответы автора по
   раундам исследования и исторический протокол одобрений; не текущий
   бэклог открытых вопросов.

## Дизайн (`design/`)

| Документ | О чём |
|---|---|
| [`gdd.md`](design/gdd.md) | GDD v1.0 Core Baseline: питч, столпы, кор-цикл, системы, прогрессия, Act I, scope, Core и моддинг |
| [`home_world_and_core_concept.md`](design/home_world_and_core_concept.md) | Выбранное направление H1: конечный живой дом, экспедиции через якорные разломы, общее игровое ядро и последствия между мирами |
| [`core_generation_and_consequences.md`](design/core_generation_and_consequences.md) | Раунды 3–5: Core по аналогии с The Seed, процедурная генерация, No Man’s Sky/Starfield, одобренные наследие, смерть, вымирание, каскад кризиса и Act I |
| [`round6_core_loop_variants.md`](design/round6_core_loop_variants.md) | Раунд 6: исторические три варианта ввода игрока и игрового цикла, сравнение и путь к выбранному гибриду |
| [`act1_hybrid_experience_concept.md`](design/act1_hybrid_experience_concept.md) | Одобренная структура A → C → B и её Baseline-режиссёрская разработка: начало, циклы, NPC, живой дом, пейзажи, лор и экспедиции |
| [`first_valley_spring_tribes.md`](design/first_valley_spring_tribes.md) | Раунды 7–12: Baseline-долина Севары, 10 видов, поселения, вожди, NPC и стабилизация Act I |
| [`personal_combat_and_leadership.md`](design/personal_combat_and_leadership.md) | Принятая модель боя C, телесной прокачки, уникальных техник, группы и лидерства без RTS |
| [`social_simulation_succession_and_culture.md`](design/social_simulation_succession_and_culture.md) | Раунды 8–10: характер и навыки NPC, дома, доверие/сила/влияние, кандидаты, смена вождей, упрощённое продолжение после смерти и культура без полной демографии |
| [`adaptive_settlements_leadership_and_coop.md`](design/adaptive_settlements_leadership_and_coop.md) | Раунды 9–10: поселение как адаптивная система, фоновый взрослый резерв, формы власти, история вождей и распределённая власть 1–4 игроков |
| [`leadership_succession_reputation_roles.md`](design/leadership_succession_reputation_roles.md) | Раунд 10: репутация поступков, доверие/сила/влияние, окно выборов, назначения и рост мастеров, хост-сессии и баланс автономии |

## Лор (`lore/`)

| Документ | О чём |
|---|---|
| [`open_questions.md`](lore/open_questions.md) | Исторический протокол исходного опросника и ответов автора по раундам; Baseline Lock закрыл реестр аудита A/P |
| [`world_bible.md`](lore/world_bible.md) | Мир целиком: законы, тон, темы, центральный конфликт |
| [`timeline.md`](lore/timeline.md) | Хронология событий мира и игры |
| [`factions.md`](lore/factions.md) | Фракции, организации, силы |
| [`characters.md`](lore/characters.md) | Персонажи: герой, NPC, антагонисты |
| [`locations.md`](lore/locations.md) | Локации и регионы |
| [`glossary.md`](lore/glossary.md) | Термины, имена, названия — единый словарь мира |
| [`naming_and_localization.md`](lore/naming_and_localization.md) | Раунды 8–9: одобренный оригинальный нейминг Севары, латинские мастер-формы, русская форма и конвейер RU/EN-локализации |

## Арт и звук (`art/`)

| Документ | О чём |
|---|---|
| [`art_bible.md`](art/art_bible.md) | Визуальный стиль, палитра, референсы, правила ассетов |
| [`audio_direction.md`](art/audio_direction.md) | Музыка, SFX, эмбиенс, озвучка |

## Техника (`tech/`)

| Документ | О чём |
|---|---|
| [`architecture.md`](tech/architecture.md) | Архитектура кода и сцен, автозагрузки, потоки данных |
| [`core_foundation_blueprint.md`](tech/core_foundation_blueprint.md) | Предстартовый план фундамента Core: слои, стабильные контракты расширения, инженерный контур и порядок P0 |
| [`conventions.md`](tech/conventions.md) | Именования, стиль GDScript, структура папок, гитовые договорённости |
| [`addons.md`](tech/addons.md) | Плагины: что установлено, зачем, как включать и обновлять |
| [`build_and_export.md`](tech/build_and_export.md) | Экспорт билдов, Git LFS, релизный чек-лист |

## Продакшен (`production/`)

| Документ | О чём |
|---|---|
| [`roadmap.md`](production/roadmap.md) | Этапы: концепция -> прототип -> вертикальный срез -> продакшен |
| [`backlog.md`](production/backlog.md) | Задачи и идеи «на потом» (чтобы не терялись и не расползался scope) |
| [`decisions.md`](production/decisions.md) | Журнал принятых решений: что решили, почему, какие были альтернативы |
| [`round12_baseline_lock.md`](production/round12_baseline_lock.md) | Раунд 12: Baseline Lock, готовность строить Core, стек, моддинг и P0–P3 |
| [`documentation_audit_round11.md`](production/documentation_audit_round11.md) | Раунд 11: исторический полный аудит документации до Baseline Lock |
