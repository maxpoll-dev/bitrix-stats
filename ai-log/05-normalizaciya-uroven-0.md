# 05 — Нормализация уровня 0 + инфраструктура (db/init/04_normalize.sql)

## Промпт
> сделай нормализацию для уровня 0. реализуй функцию логирования ошибок/варнингов в таблице rejects. реализуй функцию для преобразования даты в формат postgresql. реализуй перевод строки источника в латиницу для ключа. дубли товаров — отдаём приоритет записям которые есть в deals. задокументируй

## Ответ ИИ
> В `04_normalize.sql` добавлена инфраструктура чистки и нормализация уровня 0 (`sources`, `users`, `pipeline_stages`, `companies`, `products`). Проверено прогоном на работающем контейнере `postgres`/БД `crm`.

### Инфраструктура
- **`main.rejects`** (таблица определена в `03_schema.sql`) + функция **`main.log_reject(severity, source_table, record_key, reason, raw_data)`** — единый журнал отбраковки. `raw_data jsonb` хранит исходную строку (`to_jsonb(...)`).
- **`main.parse_ts(text) → timestamptz`** — каскад форматов: нативный ISO-8601 со смещением → `DD.MM.YYYY HH24:MI` → `YYYY/MM/DD`; иначе NULL. Покрывает дефекты `14.06.2026 09:20` (D1010) и `2026/06/15` (PAY006).
- **`main.translit(text)`** — кириллица→латиница (многобуквенные `ж/ч/ш/щ/ю/я` через `replace`, остальное `translate`); **`main.source_key(text)`** — транслит + нижний регистр + не-`[a-z0-9]`→`_`. `Avito/avito/AVITO/Авито`→`avito`, `website/Website`→`website`.

### Уровень 0
- `sources` — `UNION` канонических ключей из `raw.deals` и `raw.marketing_costs`; `name` = `initcap` ключа. Результат: 6 источников.
- `users` — типизация; `role` приведён к `role_enum`.
- `pipeline_stages` — типизация (`smallint`, `boolean`).
- `companies` — пустые строки→NULL, `created_at` через `parse_ts`; пустое `name` (C205) логируется как warning.
- `products` — **дедуп по `sku`**: `row_number()` с приоритетом `EXISTS(... в raw.deal_products) DESC, product_id`. Дубль `PR006` (SKU `PNL-100`, в сделках не используется) отброшен в пользу `PR001`; отброс залогирован.

### Правки в 03_schema.sql (вынужденные)
Пользователь до этого вручную заменил `users.role` на `role_enum`, но создал enum пустым (`AS ENUM()`) — вставка любых ролей падала. Заполнил enum фактическими значениями (`sales_manager`, `production_manager`, `director`) и добавил `DROP TYPE IF EXISTS role_enum CASCADE` для идемпотентности.

### Результат прогона
sources=6, products=5 (из 6), users=5, companies=6; rejects: 2 warning (`companies/C205 пустое name`, `products/PR006 дубль sku`).

### Что проверить вручную / допущения
- `parse_ts`: наивные даты (без смещения) трактуются в TZ сессии (контейнер в UTC) — для `14.06.2026 09:20` это означает интерпретацию как UTC. Если нужно `+05:00` — зафиксировать в `ASSUMPTIONS.md` и доработать функцию.
- `role_enum`: при появлении новых ролей в данных вставка упадёт — это осознанный контроль словаря.
- Дедуп `products` по `sku`; если у дубля будут расходиться цена/категория — берётся приоритетная (использованная) запись, расхождение не мёржится.