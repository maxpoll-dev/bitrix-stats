# 04 — Нормализованная схема (db/init/03_schema.sql)

## Промпт
> проанализируй raw и дай рекомендации какие записи вынести в реляционную модель и каким проставить индекс (пример — колонка source, по ней много запросов WHERE). Далее: порядок создания таблиц, обоснование имени `dim_source` и `code UNIQUE`, как выносить категории, какие типы где использовать. Итог: «изучи db/init/01_schema_raw.sql, создай схему с типами и ключами в db/init/03_schema.sql. документируй».

## Ответ ИИ
> Создан нормализованный слой в схеме `main` поверх raw.

### Ключевые решения
- **Источники** вынесены в справочник `main.sources (source_id PK, title)`. `source_id` = канонический код (`avito`, `website`, ...), в который чистка схлопывает `Avito/avito/AVITO/Авито`, `website/Website`. На него ссылаются `deals.source_id` и `marketing_costs.source_id`. Отказались от суррогата + `code UNIQUE`: для маленького справочника проще сделать код самим PK.
- **Категории, статусы, типы** (`products.category`, `payment_type`, статусы) оставлены как `text` — отдельные справочники/enum не вводили, чтобы не плодить абстракции под фиксы.
- **Ключи** — натуральные бизнес-коды `text` (`D1001`, `U10`, `C200`, `PR001`, `PRODUCTION`). Суррогат добавлен только в `marketing_costs` (`cost_id` identity), т.к. естественного ключа в CSV нет.
- **Типы**: деньги — `numeric(14,2)`; `quantity` — `numeric(12,3)`; даты со смещением — `timestamptz`, чистые даты — `date`; флаги — `boolean`; `inn` — `text` (ведущие нули).
- **CHECK** отражают бизнес-правила и ловят дефекты: `expected_amount >= 0` (ловит D1007), `quantity > 0`, цены/скидки/затраты `>= 0`. `payments.amount` без CHECK — отрицательные значения легитимны (возврат/корректировка PAY006).
- **FK** проставлены по всем связям. `deals.stage_id` nullable → неизвестную стадию `WAIT_CLIENT` (D1011) чистка кладёт в NULL.
- **Индексы** — по всем FK-колонкам + под фильтры отчётов: `deals(stage_id/manager_id/source_id/created_at)`, `payments(deal_id,status)`, `activities(completed_at)`, `marketing_costs(source_id,cost_date)`.

### Порядок создания
0) справочники (`sources`, `users`, `pipeline_stages`, `companies`, `products`) → 1) `contacts` → 2) `deals` → 3) дочерние (`deal_products`, `payments`, `activities`, `stage_history`, `production_orders`, `shipments`, `marketing_costs`). DROP — в обратном порядке + CASCADE.

### Граница ответственности
Схема задаёт целевую структуру и жёсткие ограничения — они и есть контракт для `04_normalize.sql`. Битые FK и дефекты raw (`D9999`, `PR999`, `C999`, `D1012`, дубли `D1008`/`EVT004`, нестандартные даты `14.06.2026`, `2026/06/15`) должны быть устранены на шаге нормализации, иначе вставка упадёт на CHECK/FK.

### Что проверить вручную
- Тип `quantity` (`numeric(12,3)`) — если позиции всегда штучные, можно `integer`.
- `discount` трактуется как абсолютная сумма скидки на позицию (в данных `5000` при цене `1050` — это не процент).
- Решение по nullability `deals.stage_id`/`manager_id` и стратегия дедупа D1008 фиксируются в `ASSUMPTIONS.md`.