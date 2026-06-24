# 02 — Анализ качества данных (выгрузка bitrix24)

## Промпт
> проанализируй выгрузку данных из bitrix24 подобной системы и выпиши найденные проблемы
>
> задокументируй

## Ответ ИИ
> Прочитаны все 13 CSV. Найденные проблемы по категориям, с привязкой к строкам:
>
> **1. products**
> - Дубль SKU `PNL-100`: `PR001` и `PR006` — один SKU, разные `cost_price` (1450 vs 1490), name «…дубль».
> - `PR006` не используется в `deal_products` (висячая запись).
> - `PR999` (есть в `deal_products` у D1008) отсутствует в `products` (orphan FK).
> - `PR005` (Монтаж) `cost_price = 0` — услуга, маржа = выручке.
>
> **2. Дубли (нарушение PK)**
> - `deals.D1008` — две конфликтующие строки (title, source website/Website, expected_amount 68000 vs 69000).
> - `stage_history.EVT004` — полный дубль строки.
> - `products` — дубль SKU (см. выше).
>
> **3. Битые ссылки / фантомные сделки (orphan FK)**
> - `D9999` — нет в `deals`, ссылаются `activities.A903`, `payments.PAY005`, `deal_products`, `production_orders.PO004`.
> - `D1012` — нет в `deals`, ссылается `stage_history.EVT005`.
> - `contacts.P304 → C999` — компании нет.
> - `deals.D1011.stage_id = WAIT_CLIENT` — нет в `pipeline_stages`.
> - `deal_products → PR999` — товара нет.
>
> **4. Несогласованность `source`**
> - `Avito / avito / AVITO / Авито` (кириллица), `website / Website`; в `marketing_costs` — `avito` и `AVITO`. Нужен справочник источников, иначе join сделок и затрат рассыплется.
>
> **5. Форматы дат**
> - `deals.D1010.created_at = 14.06.2026 09:20` (dd.mm.yyyy, без TZ) — остальные ISO-8601 `+05:00`.
> - `payments.PAY006.payment_date = 2026/06/15` (слэши).
> - Разная гранулярность: timestamp+TZ (`deals`, `activities`) vs только дата (`payments`, `production_orders`, `shipments`).
>
> **6. Некорректные числа**
> - `deals.D1007.expected_amount = -12000` — отрицательная сумма.
> - `payments.PAY006.amount = -5000` — отрицательный платёж.
> - `deal_products` D1001/PR003 `discount = 5000` — неясная семантика (похоже на абсолютную скидку, а не %), единица поля не задана.
>
> **7. Пропуски**
> - `deals`: `company_id` (D1006), `contact_id` (D1004/D1005/D1009/D1010), `manager_id` (D1011), `currency` (D1010); `WON` без `closed_at` (D1009).
> - `companies.C205` — пустые поля и нигде не используется.
> - `contacts.P301` — пустой email.
>
> **8. Логические / временны́е противоречия**
> - Переплата: `D1005` сумма 92000 / оплачено 100000.
> - Платёж `pending` (`PAY004`) — учитывать ли в дебиторке; `payment_type = unknown` (`PAY005`).
> - `D1003` `closed_at = 06-08`, но производство/отгрузка завершены 06-12/06-13 (факты позже закрытия).
> - `stage_history` D1001: `NEW→QUALIFICATION→PRODUCTION` — пропуск стадий; история только у D1001/D1003.
> - Просрочки к «сегодня» (2026-06-24): `PO001` без `actual_finish`, `SHP003` без `actual_date`, дедлайны D1001/D1005 в прошлом.
>
> **9. Формат полей**
> - `contacts.phone`: `+7 917 000-10-01` vs `89170003003` — разные форматы.
> - `currency` фактически всегда RUB — поле избыточно + один пропуск.