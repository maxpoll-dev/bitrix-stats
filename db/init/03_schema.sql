-- Нормализованный слой: типизированные таблицы с PK/FK/CHECK и индексами.
-- Сюда данные приходят уже очищенными из raw (см. 04_normalize.sql):
-- дедупликация, приведение дат/чисел, нормализация source, отсев битых FK.
-- Ограничения ниже специально жёсткие — они и есть контракт чистки:
-- если 04_normalize пропустит дефект, вставка упадёт на соответствующем CHECK/FK.

CREATE SCHEMA IF NOT EXISTS main;

-- Порядок DROP — обратный созданию; CASCADE снимает зависимость от точности порядка.
DROP TABLE IF EXISTS main.marketing_costs CASCADE;
DROP TABLE IF EXISTS main.shipments CASCADE;
DROP TABLE IF EXISTS main.production_orders CASCADE;
DROP TABLE IF EXISTS main.activities CASCADE;
DROP TABLE IF EXISTS main.stage_history CASCADE;
DROP TABLE IF EXISTS main.payments CASCADE;
DROP TABLE IF EXISTS main.deal_products CASCADE;
DROP TABLE IF EXISTS main.deals CASCADE;
DROP TABLE IF EXISTS main.contacts CASCADE;
DROP TABLE IF EXISTS main.companies CASCADE;
DROP TABLE IF EXISTS main.products CASCADE;
DROP TABLE IF EXISTS main.pipeline_stages CASCADE;
DROP TABLE IF EXISTS main.users CASCADE;
DROP TABLE IF EXISTS main.sources CASCADE;

DROP TYPE IF EXISTS role_enum CASCADE;


-- ============================================================
-- Журнал отбраковки
-- ============================================================
-- Пишем всё, что отклонили или починили при загрузке: дубли, битые ссылки,
-- пустые обязательные поля, неразобранные даты. raw_data хранит исходную строку.

DROP TABLE IF EXISTS main.rejects;
CREATE TABLE main.rejects
(
    reject_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    logged_at    timestamptz NOT NULL DEFAULT now(),
    severity     text        NOT NULL CHECK (severity IN ('error', 'warning')),
    source_table text        NOT NULL,
    record_key   text,
    reason       text        NOT NULL,
    raw_data     jsonb
);


-- ============================================================
-- Уровень 0: справочники без внешних зависимостей
-- ============================================================

-- Справочник источников. source_id = канонический код ('avito', 'website', ...),
-- в который 04_normalize схлопывает Avito/avito/AVITO/Авито и website/Website.
CREATE TABLE main.sources
(
    source_id text PRIMARY KEY,
    name      text NOT NULL
);

CREATE TYPE role_enum AS ENUM ('sales_manager', 'production_manager', 'director');
CREATE TABLE main.users
(
    user_id    text PRIMARY KEY,
    name       text    NOT NULL,
    role       role_enum,
    active     boolean NOT NULL DEFAULT true,
    department text,
    email      text
);

CREATE TABLE main.pipeline_stages
(
    stage_id    text PRIMARY KEY,
    pipeline_id text     NOT NULL,
    stage_name  text     NOT NULL,
    sort_order  smallint NOT NULL,
    is_final    boolean  NOT NULL,
    is_success  boolean  NOT NULL
);

CREATE TABLE main.companies
(
    company_id text PRIMARY KEY,
    name       text,
    inn        text,
    city       text,
    industry   text,
    created_at timestamptz
);

CREATE TABLE main.products
(
    product_id text PRIMARY KEY,
    sku        text,
    name       text    NOT NULL,
    category   text,
    cost_price numeric(14, 2) CHECK (cost_price >= 0),
    is_active  boolean NOT NULL DEFAULT true
);


-- ============================================================
-- Уровень 1: зависят от справочников
-- ============================================================

CREATE TABLE main.contacts
(
    contact_id text PRIMARY KEY,
    company_id text REFERENCES main.companies (company_id),
    name       text,
    phone      text,
    email      text,
    created_at timestamptz
);


-- ============================================================
-- Уровень 2: ядро
-- ============================================================

CREATE TABLE main.deals
(
    deal_id         text PRIMARY KEY,
    title           text,
    created_at      timestamptz NOT NULL,
    updated_at      timestamptz,
    stage_id        text REFERENCES main.pipeline_stages (stage_id),
    manager_id      text REFERENCES main.users (user_id),
    company_id      text REFERENCES main.companies (company_id),
    contact_id      text REFERENCES main.contacts (contact_id),
    source_id       text REFERENCES main.sources (source_id),
    expected_amount numeric(14, 2) CHECK (expected_amount >= 0),
    currency        text,
    closed_at       timestamptz,
    lost_reason     text,
    custom_deadline date
);


-- ============================================================
-- Уровень 3: дочерние по отношению к сделке
-- ============================================================

CREATE TABLE main.deal_products
(
    deal_id    text           NOT NULL REFERENCES main.deals (deal_id),
    product_id text           NOT NULL REFERENCES main.products (product_id),
    quantity   smallint       NOT NULL CHECK (quantity > 0),
    unit_price numeric(14, 2) NOT NULL CHECK (unit_price >= 0),
    discount   numeric(14, 2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    PRIMARY KEY (deal_id, product_id)
);

CREATE TABLE main.payments
(
    payment_id   text PRIMARY KEY,
    deal_id      text           NOT NULL REFERENCES main.deals (deal_id),
    payment_date date,
    amount       numeric(14, 2) NOT NULL,
    payment_type text,
    status       text
);

CREATE TABLE main.activities
(
    activity_id         text PRIMARY KEY,
    deal_id             text    NOT NULL REFERENCES main.deals (deal_id),
    activity_type       text,
    direction           text,
    subject             text,
    responsible_user_id text REFERENCES main.users (user_id),
    completed           boolean NOT NULL DEFAULT false,
    deadline_at         timestamptz,
    completed_at        timestamptz
);

CREATE TABLE main.stage_history
(
    event_id      text PRIMARY KEY,
    deal_id       text        NOT NULL REFERENCES main.deals (deal_id),
    old_stage_id  text REFERENCES main.pipeline_stages (stage_id),
    new_stage_id  text REFERENCES main.pipeline_stages (stage_id),
    changed_at    timestamptz NOT NULL,
    changed_by_id text REFERENCES main.users (user_id)
);

CREATE TABLE main.production_orders
(
    production_order_id text PRIMARY KEY,
    deal_id             text NOT NULL REFERENCES main.deals (deal_id),
    created_at          timestamptz,
    planned_finish_at   date,
    actual_finish_at    date,
    status              text,
    workshop            text
);

CREATE TABLE main.shipments
(
    shipment_id  text PRIMARY KEY,
    deal_id      text NOT NULL REFERENCES main.deals (deal_id),
    planned_date date,
    actual_date  date,
    status       text
);

CREATE TABLE main.marketing_costs
(
    cost_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cost_date   date           NOT NULL,
    source_id   text REFERENCES main.sources (source_id),
    campaign    text,
    cost_amount numeric(14, 2) NOT NULL CHECK (cost_amount >= 0),
    currency    text
);


-- ============================================================
-- Индексы под джойны и фильтры отчётов (reports.sql)
-- ============================================================

CREATE INDEX idx_contacts_company ON main.contacts (company_id);

CREATE INDEX idx_deals_stage ON main.deals (stage_id);
CREATE INDEX idx_deals_manager ON main.deals (manager_id);
CREATE INDEX idx_deals_company ON main.deals (company_id);
CREATE INDEX idx_deals_contact ON main.deals (contact_id);
CREATE INDEX idx_deals_source ON main.deals (source_id);
CREATE INDEX idx_deals_created_at ON main.deals (created_at);

CREATE INDEX idx_deal_products_product ON main.deal_products (product_id);

CREATE INDEX idx_payments_deal ON main.payments (deal_id);
CREATE INDEX idx_payments_status ON main.payments (status);

CREATE INDEX idx_activities_deal ON main.activities (deal_id);
CREATE INDEX idx_activities_user ON main.activities (responsible_user_id);
CREATE INDEX idx_activities_completed_at ON main.activities (completed_at);

CREATE INDEX idx_stage_history_deal ON main.stage_history (deal_id);

CREATE INDEX idx_production_orders_deal ON main.production_orders (deal_id);

CREATE INDEX idx_shipments_deal ON main.shipments (deal_id);

CREATE INDEX idx_marketing_costs_src_dt ON main.marketing_costs (source_id, cost_date);