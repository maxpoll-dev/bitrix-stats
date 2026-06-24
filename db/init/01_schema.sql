-- Raw-слой: точная копия CSV. Все столбцы text, без ограничений и без PK,
-- чтобы загрузка не падала на дублях, битых ссылках и кривых форматах.
-- Чистка/типизация/дедуп — на следующем слое.

CREATE SCHEMA IF NOT EXISTS raw;

DROP TABLE IF EXISTS raw.deals;
CREATE TABLE raw.deals (
    deal_id          text,
    title            text,
    created_at       text,
    updated_at       text,
    stage_id         text,
    manager_id       text,
    company_id       text,
    contact_id       text,
    source           text,
    expected_amount  text,
    currency         text,
    closed_at        text,
    lost_reason      text,
    custom_deadline  text
);

DROP TABLE IF EXISTS raw.deal_products;
CREATE TABLE raw.deal_products (
    deal_id     text,
    product_id  text,
    quantity    text,
    unit_price  text,
    discount    text
);

DROP TABLE IF EXISTS raw.products;
CREATE TABLE raw.products (
    product_id  text,
    sku         text,
    name        text,
    category    text,
    cost_price  text,
    is_active   text
);

DROP TABLE IF EXISTS raw.payments;
CREATE TABLE raw.payments (
    payment_id    text,
    deal_id       text,
    payment_date  text,
    amount        text,
    payment_type  text,
    status        text
);

DROP TABLE IF EXISTS raw.companies;
CREATE TABLE raw.companies (
    company_id  text,
    name        text,
    inn         text,
    city        text,
    industry    text,
    created_at  text
);

DROP TABLE IF EXISTS raw.contacts;
CREATE TABLE raw.contacts (
    contact_id  text,
    company_id  text,
    name        text,
    phone       text,
    email       text,
    created_at  text
);

DROP TABLE IF EXISTS raw.users;
CREATE TABLE raw.users (
    user_id     text,
    name        text,
    role        text,
    active      text,
    department  text,
    email       text
);

DROP TABLE IF EXISTS raw.pipeline_stages;
CREATE TABLE raw.pipeline_stages (
    pipeline_id  text,
    stage_id     text,
    stage_name   text,
    sort_order   text,
    is_final     text,
    is_success   text
);

DROP TABLE IF EXISTS raw.stage_history;
CREATE TABLE raw.stage_history (
    event_id      text,
    deal_id       text,
    old_stage_id  text,
    new_stage_id  text,
    changed_at    text,
    changed_by_id text
);

DROP TABLE IF EXISTS raw.activities;
CREATE TABLE raw.activities (
    activity_id          text,
    deal_id              text,
    activity_type        text,
    direction            text,
    subject              text,
    responsible_user_id  text,
    completed            text,
    deadline_at          text,
    completed_at         text
);

DROP TABLE IF EXISTS raw.production_orders;
CREATE TABLE raw.production_orders (
    production_order_id  text,
    deal_id              text,
    created_at           text,
    planned_finish_at    text,
    actual_finish_at     text,
    status               text,
    workshop             text
);

DROP TABLE IF EXISTS raw.shipments;
CREATE TABLE raw.shipments (
    shipment_id   text,
    deal_id       text,
    planned_date  text,
    actual_date   text,
    status        text
);

DROP TABLE IF EXISTS raw.marketing_costs;
CREATE TABLE raw.marketing_costs (
    cost_date    text,
    source       text,
    campaign     text,
    cost_amount  text,
    currency     text
);