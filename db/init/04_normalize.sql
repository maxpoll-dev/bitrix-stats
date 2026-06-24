-- ============================================================================
-- Нормализация raw → main
-- ============================================================================
-- Структура файла:
--   1. Инфраструктура: функции log_reject / parse_ts / translit / source_key.
--   2. Уровень 0  — справочники без FK-зависимостей (sources, users,
--                   pipeline_stages, companies, products).
--   3. Уровни 1–3 — contacts → deals → дочерние таблицы сделки.
--
-- Конвенция severity в журнале main.rejects:
--   warning — запись загружена, но исправлена «на месте» (NULL вместо битого
--             значения) ЛИБО это ожидаемая дедупликация.
--   error   — строка отброшена целиком из-за нарушения целостности (битый FK
--             на несуществующую сделку / товар / стадию).


-- ============================================================================
-- 1. Инфраструктура
-- ============================================================================

-- Запись в журнал отбраковки.
CREATE OR REPLACE FUNCTION main.log_reject(
    p_severity     text,
    p_source_table text,
    p_record_key   text,
    p_reason       text,
    p_raw_data     jsonb DEFAULT NULL
) RETURNS void LANGUAGE sql AS $$
    INSERT INTO main.rejects (severity, source_table, record_key, reason, raw_data)
    VALUES (p_severity, p_source_table, p_record_key, p_reason, p_raw_data);
$$;


-- Парсинг даты/времени в timestamptz.
-- В raw встречаются: ISO-8601 со смещением (2026-06-01T09:14:58+05:00),
-- DD.MM.YYYY HH24:MI (14.06.2026 09:20), YYYY/MM/DD (2026/06/15) и чистые даты.
-- Возвращает NULL, если ни один формат не подошёл (вызывающий код это логирует).
-- Наивные значения (без смещения) трактуются в часовом поясе сессии — см. ASSUMPTIONS.md.
CREATE OR REPLACE FUNCTION main.parse_ts(p_raw text)
    RETURNS timestamptz LANGUAGE plpgsql AS $$
DECLARE
    v text := nullif(btrim(p_raw), '');
BEGIN
    IF v IS NULL THEN
        RETURN NULL;
    END IF;
    BEGIN RETURN v::timestamptz;                          EXCEPTION WHEN others THEN END;
    BEGIN RETURN to_timestamp(v, 'DD.MM.YYYY HH24:MI');   EXCEPTION WHEN others THEN END;
    BEGIN RETURN to_timestamp(v, 'YYYY/MM/DD');           EXCEPTION WHEN others THEN END;
    RETURN NULL;
END;
$$;


-- Транслитерация и канонический ключ источника.
-- Кириллицу в латиницу: "Авито" → "avito". Многобуквенные сначала replace(),
-- остальное — translate() один-в-один.
CREATE OR REPLACE FUNCTION main.translit(p_raw text)
    RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT translate(
        replace(replace(replace(replace(replace(replace(replace(replace(replace(
            lower(coalesce(p_raw, '')),
        'ё', 'e'), 'ж', 'zh'), 'ч', 'ch'), 'ш', 'sh'), 'щ', 'sch'),
        'ъ', ''), 'ь', ''), 'ю', 'yu'), 'я', 'ya'),
        'абвгдезийклмнопрстуфхцыэ',
        'abvgdeziyklmnoprstufhcye'
    );
$$;

-- Канонический source_id: транслит + нижний регистр + всё не [a-z0-9] → '_'.
-- Avito/avito/AVITO/Авито → 'avito'; website/Website → 'website'.
CREATE OR REPLACE FUNCTION main.source_key(p_raw text)
    RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT nullif(
        regexp_replace(
            regexp_replace(main.translit(p_raw), '[^a-z0-9]+', '_', 'g'),
            '^_+|_+$', '', 'g'),
        ''
    );
$$;


-- ============================================================================
-- 2. Уровень 0 — справочники
-- ============================================================================
TRUNCATE main.sources, main.users, main.pipeline_stages, main.companies, main.products
    RESTART IDENTITY CASCADE;

-- sources: уникальные ключи из deals и marketing_costs.
INSERT INTO main.sources (source_id, name)
SELECT k, initcap(replace(k, '_', ' '))
FROM (
    SELECT main.source_key(source) AS k FROM raw.deals
    UNION
    SELECT main.source_key(source) AS k FROM raw.marketing_costs
) s
WHERE k IS NOT NULL;

-- users: без дефектов, только типизация.
INSERT INTO main.users (user_id, name, role, active, department, email)
SELECT user_id, name, nullif(role, '')::role_enum, active::boolean, nullif(department, ''), nullif(email, '')
FROM raw.users;

-- pipeline_stages: без дефектов, только типизация.
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success)
SELECT stage_id, pipeline_id, stage_name, sort_order::smallint, is_final::boolean, is_success::boolean
FROM raw.pipeline_stages;

-- Служебная стадия (паттерн "unknown member"): сюда маппятся битые/неизвестные
-- стадии из deals и stage_history, чтобы сделки не выпадали из воронки, а дефект
-- был виден в отчётах. sort_order=999 паркует её за реальными этапами.
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success)
VALUES ('UNKNOWN', 'sales-main', 'Неизвестная стадия', 999, false, false);

-- companies: пустые строки → NULL, дата через parse_ts. Пустое name логируем как warning.
SELECT main.log_reject('warning', 'companies', company_id, 'пустое name', to_jsonb(c))
FROM raw.companies c
WHERE nullif(c.name, '') IS NULL;

INSERT INTO main.companies (company_id, name, inn, city, industry, created_at)
SELECT company_id,
       nullif(name, ''),
       nullif(inn, ''),
       nullif(city, ''),
       nullif(industry, ''),
       main.parse_ts(created_at)
FROM raw.companies;

-- products: дедуп по sku. Приоритет — записи, на которые ссылаются в deal_products
-- (т.е. реально использованные в сделках); при равенстве — меньший product_id.
WITH ranked AS (
    SELECT p.*,
           row_number() OVER (
               PARTITION BY p.sku
               ORDER BY EXISTS (SELECT 1 FROM raw.deal_products dp WHERE dp.product_id = p.product_id) DESC,
                        p.product_id
           ) AS rn
    FROM raw.products p
)
SELECT main.log_reject('warning', 'products', product_id,
                       'дубль sku ' || sku || ': отброшен в пользу приоритетной записи', to_jsonb(r))
FROM ranked r
WHERE rn > 1;

WITH ranked AS (
    SELECT p.*,
           row_number() OVER (
               PARTITION BY p.sku
               ORDER BY EXISTS (SELECT 1 FROM raw.deal_products dp WHERE dp.product_id = p.product_id) DESC,
                        p.product_id
           ) AS rn
    FROM raw.products p
)
INSERT INTO main.products (product_id, sku, name, category, cost_price, is_active)
SELECT product_id, sku, name, nullif(category, ''), cost_price::numeric, is_active::boolean
FROM ranked
WHERE rn = 1;


-- ============================================================================
-- 3. Уровни 1–3 — сделки и связанные таблицы
-- ============================================================================
TRUNCATE main.contacts, main.deals, main.deal_products, main.payments, main.activities,
         main.stage_history, main.production_orders, main.shipments, main.marketing_costs
    RESTART IDENTITY CASCADE;


-- ---------- Уровень 1: contacts ----------
SELECT main.log_reject('warning', 'contacts', contact_id,
                       'company_id ' || company_id || ' не найден → NULL', to_jsonb(c))
FROM raw.contacts c
WHERE nullif(company_id, '') IS NOT NULL
  AND company_id NOT IN (SELECT company_id FROM main.companies);

INSERT INTO main.contacts (contact_id, company_id, name, phone, email, created_at)
SELECT contact_id,
       CASE WHEN company_id IN (SELECT company_id FROM main.companies) THEN company_id END,
       nullif(name, ''),
       nullif(phone, ''),
       nullif(email, ''),
       main.parse_ts(created_at)
FROM raw.contacts;


-- ---------- Уровень 2: deals ----------
WITH dedup AS (
    SELECT d.*,
           row_number() OVER (
               PARTITION BY deal_id
               ORDER BY main.parse_ts(updated_at) DESC NULLS LAST
           ) AS rn
    FROM raw.deals d
)
SELECT main.log_reject('warning', 'deals', deal_id,
                       'дубль deal_id: оставлена запись с последним updated_at', to_jsonb(d))
FROM dedup d WHERE rn > 1;

WITH dedup AS (
    SELECT d.*,
           row_number() OVER (PARTITION BY deal_id ORDER BY main.parse_ts(updated_at) DESC NULLS LAST) AS rn
    FROM raw.deals d
)
SELECT main.log_reject('warning', 'deals', deal_id,
           CASE
               WHEN expected_amount::numeric < 0 THEN 'отрицательный expected_amount → NULL'
               WHEN stage_id NOT IN (SELECT stage_id FROM main.pipeline_stages)
                   THEN 'неизвестная стадия ' || stage_id || ' → UNKNOWN'
               ELSE 'стадия WON без closed_at'
           END, to_jsonb(d))
FROM dedup d
WHERE rn = 1
  AND (expected_amount::numeric < 0
       OR stage_id NOT IN (SELECT stage_id FROM main.pipeline_stages)
       OR (stage_id = 'WON' AND nullif(closed_at, '') IS NULL));

WITH dedup AS (
    SELECT d.*,
           row_number() OVER (PARTITION BY deal_id ORDER BY main.parse_ts(updated_at) DESC NULLS LAST) AS rn
    FROM raw.deals d
)
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id,
                        company_id, contact_id, source_id, expected_amount, currency,
                        closed_at, lost_reason, custom_deadline)
SELECT deal_id,
       nullif(title, ''),
       main.parse_ts(created_at),
       main.parse_ts(updated_at),
       CASE WHEN stage_id IN (SELECT stage_id FROM main.pipeline_stages) THEN stage_id ELSE 'UNKNOWN' END,
       nullif(manager_id, ''),
       nullif(company_id, ''),
       nullif(contact_id, ''),
       main.source_key(source),
       CASE WHEN expected_amount::numeric < 0 THEN NULL ELSE expected_amount::numeric END,
       nullif(currency, ''),
       main.parse_ts(closed_at),
       nullif(lost_reason, ''),
       nullif(custom_deadline, '')::date
FROM dedup
WHERE rn = 1;


-- ---------- Уровень 3: deal_products ----------
SELECT main.log_reject('error', 'deal_products', deal_id || '/' || product_id,
                       'битый FK: deal_id и/или product_id отсутствует в main', to_jsonb(dp))
FROM raw.deal_products dp
WHERE deal_id NOT IN (SELECT deal_id FROM main.deals)
   OR product_id NOT IN (SELECT product_id FROM main.products);

INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount)
SELECT deal_id, product_id, quantity::smallint, unit_price::numeric, discount::numeric
FROM raw.deal_products
WHERE deal_id IN (SELECT deal_id FROM main.deals)
  AND product_id IN (SELECT product_id FROM main.products);


-- ---------- Уровень 3: payments ----------
SELECT main.log_reject('error', 'payments', payment_id,
                       'битый FK: deal_id ' || deal_id || ' отсутствует', to_jsonb(p))
FROM raw.payments p
WHERE deal_id NOT IN (SELECT deal_id FROM main.deals);

INSERT INTO main.payments (payment_id, deal_id, payment_date, amount, payment_type, status)
SELECT payment_id, deal_id, main.parse_ts(payment_date)::date, amount::numeric,
       nullif(payment_type, ''), nullif(status, '')
FROM raw.payments
WHERE deal_id IN (SELECT deal_id FROM main.deals);


-- ---------- Уровень 3: activities ----------
SELECT main.log_reject('error', 'activities', activity_id,
                       'битый FK: deal_id ' || deal_id || ' отсутствует', to_jsonb(a))
FROM raw.activities a
WHERE deal_id NOT IN (SELECT deal_id FROM main.deals);

INSERT INTO main.activities (activity_id, deal_id, activity_type, direction, subject,
                             responsible_user_id, completed, deadline_at, completed_at)
SELECT activity_id, deal_id, nullif(activity_type, ''), nullif(direction, ''), nullif(subject, ''),
       nullif(responsible_user_id, ''), completed::boolean,
       main.parse_ts(deadline_at), main.parse_ts(completed_at)
FROM raw.activities
WHERE deal_id IN (SELECT deal_id FROM main.deals);


-- ---------- Уровень 3: stage_history ----------
WITH dedup AS (
    SELECT s.*, row_number() OVER (PARTITION BY event_id ORDER BY changed_at) AS rn
    FROM raw.stage_history s
)
SELECT main.log_reject('warning', 'stage_history', event_id,
                       'дубль event_id → оставлена одна запись', to_jsonb(d))
FROM dedup d WHERE rn > 1;

SELECT main.log_reject('error', 'stage_history', event_id,
                       'битый FK: deal_id ' || deal_id || ' отсутствует', to_jsonb(s))
FROM raw.stage_history s
WHERE deal_id NOT IN (SELECT deal_id FROM main.deals);

WITH dedup AS (
    SELECT s.*, row_number() OVER (PARTITION BY event_id ORDER BY changed_at) AS rn
    FROM raw.stage_history s
)
INSERT INTO main.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id)
SELECT event_id, deal_id,
       CASE WHEN old_stage_id IN (SELECT stage_id FROM main.pipeline_stages) THEN old_stage_id
            WHEN nullif(old_stage_id, '') IS NULL THEN NULL
            ELSE 'UNKNOWN' END,
       CASE WHEN new_stage_id IN (SELECT stage_id FROM main.pipeline_stages) THEN new_stage_id
            WHEN nullif(new_stage_id, '') IS NULL THEN NULL
            ELSE 'UNKNOWN' END,
       main.parse_ts(changed_at),
       nullif(changed_by_id, '')
FROM dedup
WHERE rn = 1
  AND deal_id IN (SELECT deal_id FROM main.deals);


-- ---------- Уровень 3: production_orders ----------
SELECT main.log_reject('error', 'production_orders', production_order_id,
                       'битый FK: deal_id ' || deal_id || ' отсутствует', to_jsonb(po))
FROM raw.production_orders po
WHERE deal_id NOT IN (SELECT deal_id FROM main.deals);

INSERT INTO main.production_orders (production_order_id, deal_id, created_at,
                                    planned_finish_at, actual_finish_at, status, workshop)
SELECT production_order_id, deal_id, main.parse_ts(created_at),
       nullif(planned_finish_at, '')::date, nullif(actual_finish_at, '')::date,
       nullif(status, ''), nullif(workshop, '')
FROM raw.production_orders
WHERE deal_id IN (SELECT deal_id FROM main.deals);


-- ---------- Уровень 3: shipments ----------
INSERT INTO main.shipments (shipment_id, deal_id, planned_date, actual_date, status)
SELECT shipment_id, deal_id, nullif(planned_date, '')::date, nullif(actual_date, '')::date,
       nullif(status, '')
FROM raw.shipments
WHERE deal_id IN (SELECT deal_id FROM main.deals);


-- ---------- Уровень 3: marketing_costs ----------
INSERT INTO main.marketing_costs (cost_date, source_id, campaign, cost_amount, currency)
SELECT cost_date::date, main.source_key(source), nullif(campaign, ''),
       cost_amount::numeric, nullif(currency, '')
FROM raw.marketing_costs;