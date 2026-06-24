--
-- PostgreSQL database dump
--

\restrict cvPcRcUgvgbiSMms7rwRd2mMTCZOvMJcbbHGvbDR7QXznKyXUNHzsk3iDBnMxXD

-- Dumped from database version 16.14
-- Dumped by pg_dump version 16.14

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: main; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA main;


--
-- Name: raw; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA raw;


--
-- Name: role_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.role_enum AS ENUM (
    'sales_manager',
    'production_manager',
    'director'
);


--
-- Name: log_reject(text, text, text, text, jsonb); Type: FUNCTION; Schema: main; Owner: -
--

CREATE FUNCTION main.log_reject(p_severity text, p_source_table text, p_record_key text, p_reason text, p_raw_data jsonb DEFAULT NULL::jsonb) RETURNS void
    LANGUAGE sql
    AS $$
    INSERT INTO main.rejects (severity, source_table, record_key, reason, raw_data)
    VALUES (p_severity, p_source_table, p_record_key, p_reason, p_raw_data);
$$;


--
-- Name: parse_ts(text); Type: FUNCTION; Schema: main; Owner: -
--

CREATE FUNCTION main.parse_ts(p_raw text) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: source_key(text); Type: FUNCTION; Schema: main; Owner: -
--

CREATE FUNCTION main.source_key(p_raw text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT nullif(
        regexp_replace(
            regexp_replace(main.translit(p_raw), '[^a-z0-9]+', '_', 'g'),
            '^_+|_+$', '', 'g'),
        ''
    );
$_$;


--
-- Name: translit(text); Type: FUNCTION; Schema: main; Owner: -
--

CREATE FUNCTION main.translit(p_raw text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT translate(
        replace(replace(replace(replace(replace(replace(replace(replace(replace(
            lower(coalesce(p_raw, '')),
        'ё', 'e'), 'ж', 'zh'), 'ч', 'ch'), 'ш', 'sh'), 'щ', 'sch'),
        'ъ', ''), 'ь', ''), 'ю', 'yu'), 'я', 'ya'),
        'абвгдезийклмнопрстуфхцыэ',
        'abvgdeziyklmnoprstufhcye'
    );
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activities; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.activities (
    activity_id text NOT NULL,
    deal_id text NOT NULL,
    activity_type text,
    direction text,
    subject text,
    responsible_user_id text,
    completed boolean DEFAULT false NOT NULL,
    deadline_at timestamp with time zone,
    completed_at timestamp with time zone
);


--
-- Name: companies; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.companies (
    company_id text NOT NULL,
    name text,
    inn text,
    city text,
    industry text,
    created_at timestamp with time zone
);


--
-- Name: contacts; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.contacts (
    contact_id text NOT NULL,
    company_id text,
    name text,
    phone text,
    email text,
    created_at timestamp with time zone
);


--
-- Name: deal_products; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.deal_products (
    deal_id text NOT NULL,
    product_id text NOT NULL,
    quantity smallint NOT NULL,
    unit_price numeric(14,2) NOT NULL,
    discount numeric(14,2) DEFAULT 0 NOT NULL,
    CONSTRAINT deal_products_discount_check CHECK ((discount >= (0)::numeric)),
    CONSTRAINT deal_products_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT deal_products_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: deals; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.deals (
    deal_id text NOT NULL,
    title text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone,
    stage_id text,
    manager_id text,
    company_id text,
    contact_id text,
    source_id text,
    expected_amount numeric(14,2),
    currency text,
    closed_at timestamp with time zone,
    lost_reason text,
    custom_deadline date,
    CONSTRAINT deals_expected_amount_check CHECK ((expected_amount >= (0)::numeric))
);


--
-- Name: marketing_costs; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.marketing_costs (
    cost_id bigint NOT NULL,
    cost_date date NOT NULL,
    source_id text,
    campaign text,
    cost_amount numeric(14,2) NOT NULL,
    currency text,
    CONSTRAINT marketing_costs_cost_amount_check CHECK ((cost_amount >= (0)::numeric))
);


--
-- Name: marketing_costs_cost_id_seq; Type: SEQUENCE; Schema: main; Owner: -
--

ALTER TABLE main.marketing_costs ALTER COLUMN cost_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME main.marketing_costs_cost_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: payments; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.payments (
    payment_id text NOT NULL,
    deal_id text NOT NULL,
    payment_date date,
    amount numeric(14,2) NOT NULL,
    payment_type text,
    status text
);


--
-- Name: pipeline_stages; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.pipeline_stages (
    stage_id text NOT NULL,
    pipeline_id text NOT NULL,
    stage_name text NOT NULL,
    sort_order smallint NOT NULL,
    is_final boolean NOT NULL,
    is_success boolean NOT NULL
);


--
-- Name: production_orders; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.production_orders (
    production_order_id text NOT NULL,
    deal_id text NOT NULL,
    created_at timestamp with time zone,
    planned_finish_at date,
    actual_finish_at date,
    status text,
    workshop text
);


--
-- Name: products; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.products (
    product_id text NOT NULL,
    sku text,
    name text NOT NULL,
    category text,
    cost_price numeric(14,2),
    is_active boolean DEFAULT true NOT NULL,
    CONSTRAINT products_cost_price_check CHECK ((cost_price >= (0)::numeric))
);


--
-- Name: rejects; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.rejects (
    reject_id bigint NOT NULL,
    logged_at timestamp with time zone DEFAULT now() NOT NULL,
    severity text NOT NULL,
    source_table text NOT NULL,
    record_key text,
    reason text NOT NULL,
    raw_data jsonb,
    CONSTRAINT rejects_severity_check CHECK ((severity = ANY (ARRAY['error'::text, 'warning'::text])))
);


--
-- Name: rejects_reject_id_seq; Type: SEQUENCE; Schema: main; Owner: -
--

ALTER TABLE main.rejects ALTER COLUMN reject_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME main.rejects_reject_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: shipments; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.shipments (
    shipment_id text NOT NULL,
    deal_id text NOT NULL,
    planned_date date,
    actual_date date,
    status text
);


--
-- Name: sources; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.sources (
    source_id text NOT NULL,
    name text NOT NULL
);


--
-- Name: stage_history; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.stage_history (
    event_id text NOT NULL,
    deal_id text NOT NULL,
    old_stage_id text,
    new_stage_id text,
    changed_at timestamp with time zone NOT NULL,
    changed_by_id text
);


--
-- Name: users; Type: TABLE; Schema: main; Owner: -
--

CREATE TABLE main.users (
    user_id text NOT NULL,
    name text NOT NULL,
    role public.role_enum,
    active boolean DEFAULT true NOT NULL,
    department text,
    email text
);


--
-- Name: activities; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.activities (
    activity_id text,
    deal_id text,
    activity_type text,
    direction text,
    subject text,
    responsible_user_id text,
    completed text,
    deadline_at text,
    completed_at text
);


--
-- Name: companies; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.companies (
    company_id text,
    name text,
    inn text,
    city text,
    industry text,
    created_at text
);


--
-- Name: contacts; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.contacts (
    contact_id text,
    company_id text,
    name text,
    phone text,
    email text,
    created_at text
);


--
-- Name: deal_products; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.deal_products (
    deal_id text,
    product_id text,
    quantity text,
    unit_price text,
    discount text
);


--
-- Name: deals; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.deals (
    deal_id text,
    title text,
    created_at text,
    updated_at text,
    stage_id text,
    manager_id text,
    company_id text,
    contact_id text,
    source text,
    expected_amount text,
    currency text,
    closed_at text,
    lost_reason text,
    custom_deadline text
);


--
-- Name: marketing_costs; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.marketing_costs (
    cost_date text,
    source text,
    campaign text,
    cost_amount text,
    currency text
);


--
-- Name: payments; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.payments (
    payment_id text,
    deal_id text,
    payment_date text,
    amount text,
    payment_type text,
    status text
);


--
-- Name: pipeline_stages; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.pipeline_stages (
    pipeline_id text,
    stage_id text,
    stage_name text,
    sort_order text,
    is_final text,
    is_success text
);


--
-- Name: production_orders; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.production_orders (
    production_order_id text,
    deal_id text,
    created_at text,
    planned_finish_at text,
    actual_finish_at text,
    status text,
    workshop text
);


--
-- Name: products; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.products (
    product_id text,
    sku text,
    name text,
    category text,
    cost_price text,
    is_active text
);


--
-- Name: shipments; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.shipments (
    shipment_id text,
    deal_id text,
    planned_date text,
    actual_date text,
    status text
);


--
-- Name: stage_history; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.stage_history (
    event_id text,
    deal_id text,
    old_stage_id text,
    new_stage_id text,
    changed_at text,
    changed_by_id text
);


--
-- Name: users; Type: TABLE; Schema: raw; Owner: -
--

CREATE TABLE raw.users (
    user_id text,
    name text,
    role text,
    active text,
    department text,
    email text
);


--
-- Data for Name: activities; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.activities (activity_id, deal_id, activity_type, direction, subject, responsible_user_id, completed, deadline_at, completed_at) VALUES ('A900', 'D1001', 'call', 'outbound', 'Первичный звонок', 'U10', true, '2026-06-03 07:00:00+00', '2026-06-03 08:00:00+00');
INSERT INTO main.activities (activity_id, deal_id, activity_type, direction, subject, responsible_user_id, completed, deadline_at, completed_at) VALUES ('A901', 'D1002', 'email', 'outbound', 'КП', 'U11', true, '2026-06-04 05:00:00+00', '2026-06-04 04:40:00+00');
INSERT INTO main.activities (activity_id, deal_id, activity_type, direction, subject, responsible_user_id, completed, deadline_at, completed_at) VALUES ('A902', 'D1005', 'task', NULL, 'Проверить оплату', 'U11', false, '2026-06-07 13:00:00+00', NULL);


--
-- Data for Name: companies; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.companies (company_id, name, inn, city, industry, created_at) VALUES ('C200', 'ООО Альфа-Строй', '0278123456', 'Уфа', 'Строительство', '2026-05-20 04:00:00+00');
INSERT INTO main.companies (company_id, name, inn, city, industry, created_at) VALUES ('C201', 'ИП Гараев', '026600112233', 'Стерлитамак', 'Розница', '2026-05-21 05:20:00+00');
INSERT INTO main.companies (company_id, name, inn, city, industry, created_at) VALUES ('C202', 'ООО БашКомплект', '0277009988', 'Уфа', 'Производство', '2026-05-22 06:10:00+00');
INSERT INTO main.companies (company_id, name, inn, city, industry, created_at) VALUES ('C203', 'ООО СеверМонтаж', '1102003344', 'Нефтекамск', 'Монтаж', '2026-05-22 06:40:00+00');
INSERT INTO main.companies (company_id, name, inn, city, industry, created_at) VALUES ('C204', 'ООО ТеплоДом', '0268012345', 'Салават', 'Строительство', '2026-05-25 08:30:00+00');
INSERT INTO main.companies (company_id, name, inn, city, industry, created_at) VALUES ('C205', NULL, NULL, 'Уфа', NULL, '2026-06-01 03:10:00+00');


--
-- Data for Name: contacts; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P300', 'C200', 'Алексей Смирнов', '+7 917 000-10-01', 'smirnov@alfa.local', '2026-05-20 04:05:00+00');
INSERT INTO main.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P301', 'C200', 'Марина Кузнецова', '+7 917 000-10-02', NULL, '2026-05-20 04:07:00+00');
INSERT INTO main.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P302', 'C201', 'Рустам Гараев', '+7 927 000-20-01', 'garaev@example.local', '2026-05-21 05:30:00+00');
INSERT INTO main.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P303', 'C202', 'Елена Морозова', '89170003003', 'morozova@bash.local', '2026-05-22 06:15:00+00');
INSERT INTO main.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P304', NULL, 'Контакт без компании', '+7 927 000-40-01', 'orphan@example.local', '2026-05-30 07:00:00+00');


--
-- Data for Name: deal_products; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1001', 'PR001', 50, 2200.00, 0.00);
INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1001', 'PR003', 20, 1050.00, 5000.00);
INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1002', 'PR004', 8, 10500.00, 0.00);
INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1003', 'PR002', 80, 2600.00, 0.00);
INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1003', 'PR005', 1, 28000.00, 0.00);
INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1004', 'PR003', 60, 950.00, 0.00);
INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1005', 'PR001', 30, 2200.00, 0.00);
INSERT INTO main.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1005', 'PR005', 1, 26000.00, 0.00);


--
-- Data for Name: deals; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1001', 'Панели для склада Альфа', '2026-06-01 04:14:58+00', '2026-06-07 07:30:00+00', 'PRODUCTION', 'U10', 'C200', 'P300', 'avito', 150000.00, 'RUB', NULL, NULL, '2026-06-20');
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1002', 'Расчет дверных блоков', '2026-06-02 05:30:00+00', '2026-06-06 06:00:00+00', 'PROPOSAL', 'U11', 'C201', 'P302', 'avito', 84000.00, 'RUB', NULL, NULL, '2026-06-18');
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1003', 'Монтаж панелей БашКомплект', '2026-06-03 08:10:00+00', '2026-06-08 11:45:00+00', 'WON', 'U10', 'C202', 'P303', 'yandex_direct', 236000.00, 'RUB', '2026-06-08 11:45:00+00', NULL, '2026-06-25');
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1004', 'Поставка каркасов', '2026-06-04 03:20:00+00', '2026-06-05 04:05:00+00', 'LOST', 'U12', 'C203', NULL, 'website', 57000.00, 'RUB', '2026-06-05 04:05:00+00', 'Дорого', NULL);
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1005', 'Срочный заказ ТеплоДом', '2026-06-05 10:00:00+00', '2026-06-10 13:10:00+00', 'SHIPPED', 'U11', 'C204', NULL, 'avito', 92000.00, 'RUB', NULL, NULL, '2026-06-12');
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1006', 'Заявка без компании', '2026-06-06 07:00:00+00', '2026-06-06 07:10:00+00', 'NEW', 'U10', NULL, 'P304', 'avito', 35000.00, 'RUB', NULL, NULL, NULL);
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1007', 'Отрицательная сумма тест', '2026-06-07 04:00:00+00', '2026-06-07 04:10:00+00', 'QUALIFICATION', 'U10', 'C200', 'P301', 'phone', NULL, 'RUB', NULL, NULL, NULL);
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1008', 'Дубль сделки измененный', '2026-06-08 05:00:00+00', '2026-06-08 05:06:00+00', 'CALCULATION', 'U11', 'C201', 'P302', 'website', 69000.00, 'RUB', NULL, NULL, '2026-06-17');
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1009', 'Выиграна без даты закрытия', '2026-06-09 08:20:00+00', '2026-06-12 12:00:00+00', 'WON', 'U10', 'C203', NULL, 'referral', 125000.00, 'RUB', NULL, NULL, NULL);
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1010', 'Пустая валюта', '2026-06-14 09:20:00+00', '2026-06-14 04:40:00+00', 'CONTRACT', 'U11', 'C204', NULL, 'yandex_direct', 174000.00, NULL, NULL, NULL, '2026-06-30');
INSERT INTO main.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source_id, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1011', 'Неизвестная стадия', '2026-06-15 06:30:00+00', '2026-06-15 06:30:00+00', 'UNKNOWN', NULL, 'C202', 'P303', 'telegram', 54000.00, 'RUB', NULL, NULL, NULL);


--
-- Data for Name: marketing_costs; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.marketing_costs (cost_id, cost_date, source_id, campaign, cost_amount, currency) OVERRIDING SYSTEM VALUE VALUES (1, '2026-06-01', 'avito', 'avito_panels', 4500.00, 'RUB');
INSERT INTO main.marketing_costs (cost_id, cost_date, source_id, campaign, cost_amount, currency) OVERRIDING SYSTEM VALUE VALUES (2, '2026-06-02', 'yandex_direct', 'search_panels_ufa', 8200.00, 'RUB');
INSERT INTO main.marketing_costs (cost_id, cost_date, source_id, campaign, cost_amount, currency) OVERRIDING SYSTEM VALUE VALUES (3, '2026-06-03', 'website', 'seo', 0.00, 'RUB');
INSERT INTO main.marketing_costs (cost_id, cost_date, source_id, campaign, cost_amount, currency) OVERRIDING SYSTEM VALUE VALUES (4, '2026-06-04', 'avito', 'avito_panels', 3900.00, 'RUB');


--
-- Data for Name: payments; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY001', 'D1001', '2026-06-03', 60000.00, 'prepayment', 'paid');
INSERT INTO main.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY002', 'D1003', '2026-06-08', 236000.00, 'full', 'paid');
INSERT INTO main.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY003', 'D1005', '2026-06-06', 100000.00, 'prepayment', 'paid');
INSERT INTO main.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY004', 'D1002', '2026-06-06', 30000.00, 'prepayment', 'pending');
INSERT INTO main.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY006', 'D1010', '2026-06-15', -5000.00, 'correction', 'paid');


--
-- Data for Name: pipeline_stages; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('NEW', 'sales-main', 'Новая заявка', 10, false, false);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('QUALIFICATION', 'sales-main', 'Квалификация', 20, false, false);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('CALCULATION', 'sales-main', 'Расчет', 30, false, false);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('PROPOSAL', 'sales-main', 'КП отправлено', 40, false, false);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('CONTRACT', 'sales-main', 'Договор', 50, false, false);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('PRODUCTION', 'sales-main', 'В производстве', 60, false, false);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('SHIPPED', 'sales-main', 'Отгружено', 70, false, false);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('WON', 'sales-main', 'Успешно', 80, true, true);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('LOST', 'sales-main', 'Проиграно', 90, true, false);
INSERT INTO main.pipeline_stages (stage_id, pipeline_id, stage_name, sort_order, is_final, is_success) VALUES ('UNKNOWN', 'sales-main', 'Неизвестная стадия', 999, false, false);


--
-- Data for Name: production_orders; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.production_orders (production_order_id, deal_id, created_at, planned_finish_at, actual_finish_at, status, workshop) VALUES ('PO001', 'D1001', '2026-06-02 03:00:00+00', '2026-06-12', NULL, 'in_progress', 'Цех 1');
INSERT INTO main.production_orders (production_order_id, deal_id, created_at, planned_finish_at, actual_finish_at, status, workshop) VALUES ('PO002', 'D1003', '2026-06-05 04:00:00+00', '2026-06-10', '2026-06-12', 'done', 'Цех 2');
INSERT INTO main.production_orders (production_order_id, deal_id, created_at, planned_finish_at, actual_finish_at, status, workshop) VALUES ('PO003', 'D1005', '2026-06-01 04:00:00+00', '2026-06-08', '2026-06-14', 'done', 'Цех 1');


--
-- Data for Name: products; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR004', 'DRV-001', 'Дверной блок', 'Двери', 5200.00, true);
INSERT INTO main.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR003', 'FRM-020', 'Каркас монтажный', 'Каркасы', 720.00, true);
INSERT INTO main.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR001', 'PNL-100', 'Панель стеновая 100 мм', 'Панели', 1450.00, true);
INSERT INTO main.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR002', 'PNL-150', 'Панель стеновая 150 мм', 'Панели', 1880.00, true);
INSERT INTO main.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR005', 'SRV-INST', 'Монтаж', 'Услуги', 0.00, true);


--
-- Data for Name: rejects; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (1, '2026-06-24 18:35:16.459955+00', 'warning', 'companies', 'C205', 'пустое name', '{"inn": null, "city": "Уфа", "name": null, "industry": null, "company_id": "C205", "created_at": "2026-06-01T08:10:00+05:00"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (2, '2026-06-24 18:35:16.46482+00', 'warning', 'products', 'PR006', 'дубль sku PNL-100: отброшен в пользу приоритетной записи', '{"rn": 2, "sku": "PNL-100", "name": "Панель стеновая 100 мм дубль", "category": "Панели", "is_active": "true", "cost_price": "1490.00", "product_id": "PR006"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (3, '2026-06-24 18:35:16.604031+00', 'warning', 'contacts', 'P304', 'company_id C999 не найден → NULL', '{"name": "Контакт без компании", "email": "orphan@example.local", "phone": "+7 927 000-40-01", "company_id": "C999", "contact_id": "P304", "created_at": "2026-05-30T12:00:00+05:00"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (4, '2026-06-24 18:35:16.609092+00', 'warning', 'deals', 'D1008', 'дубль deal_id: оставлена запись с последним updated_at', '{"rn": 2, "title": "Дубль сделки", "source": "website", "deal_id": "D1008", "currency": "RUB", "stage_id": "CALCULATION", "closed_at": null, "company_id": "C201", "contact_id": "P302", "created_at": "2026-06-08T10:00:00+05:00", "manager_id": "U11", "updated_at": "2026-06-08T10:05:00+05:00", "lost_reason": null, "custom_deadline": "2026-06-17", "expected_amount": "68000.00"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (5, '2026-06-24 18:35:16.612264+00', 'warning', 'deals', 'D1007', 'отрицательный expected_amount → NULL', '{"rn": 1, "title": "Отрицательная сумма тест", "source": "phone", "deal_id": "D1007", "currency": "RUB", "stage_id": "QUALIFICATION", "closed_at": null, "company_id": "C200", "contact_id": "P301", "created_at": "2026-06-07T09:00:00+05:00", "manager_id": "U10", "updated_at": "2026-06-07T09:10:00+05:00", "lost_reason": null, "custom_deadline": null, "expected_amount": "-12000.00"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (6, '2026-06-24 18:35:16.612264+00', 'warning', 'deals', 'D1009', 'стадия WON без closed_at', '{"rn": 1, "title": "Выиграна без даты закрытия", "source": "referral", "deal_id": "D1009", "currency": "RUB", "stage_id": "WON", "closed_at": null, "company_id": "C203", "contact_id": null, "created_at": "2026-06-09T13:20:00+05:00", "manager_id": "U10", "updated_at": "2026-06-12T17:00:00+05:00", "lost_reason": null, "custom_deadline": null, "expected_amount": "125000.00"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (7, '2026-06-24 18:35:16.612264+00', 'warning', 'deals', 'D1011', 'неизвестная стадия WAIT_CLIENT → UNKNOWN', '{"rn": 1, "title": "Неизвестная стадия", "source": "telegram", "deal_id": "D1011", "currency": "RUB", "stage_id": "WAIT_CLIENT", "closed_at": null, "company_id": "C202", "contact_id": "P303", "created_at": "2026-06-15T11:30:00+05:00", "manager_id": null, "updated_at": "2026-06-15T11:30:00+05:00", "lost_reason": null, "custom_deadline": null, "expected_amount": "54000.00"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (8, '2026-06-24 18:35:16.620618+00', 'error', 'deal_products', 'D1008/PR999', 'битый FK: deal_id и/или product_id отсутствует в main', '{"deal_id": "D1008", "discount": "0", "quantity": "2", "product_id": "PR999", "unit_price": "5000.00"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (9, '2026-06-24 18:35:16.620618+00', 'error', 'deal_products', 'D9999/PR001', 'битый FK: deal_id и/или product_id отсутствует в main', '{"deal_id": "D9999", "discount": "0", "quantity": "10", "product_id": "PR001", "unit_price": "2100.00"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (10, '2026-06-24 18:35:16.625314+00', 'error', 'payments', 'PAY005', 'битый FK: deal_id D9999 отсутствует', '{"amount": "15000.00", "status": "paid", "deal_id": "D9999", "payment_id": "PAY005", "payment_date": "2026-06-09", "payment_type": "unknown"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (11, '2026-06-24 18:35:16.630184+00', 'error', 'activities', 'A903', 'битый FK: deal_id D9999 отсутствует', '{"deal_id": "D9999", "subject": "Звонок без сделки", "completed": "true", "direction": "inbound", "activity_id": "A903", "deadline_at": "2026-06-08T10:00:00+05:00", "completed_at": "2026-06-08T10:10:00+05:00", "activity_type": "call", "responsible_user_id": "U10"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (12, '2026-06-24 18:35:16.634928+00', 'warning', 'stage_history', 'EVT004', 'дубль event_id → оставлена одна запись', '{"rn": 2, "deal_id": "D1003", "event_id": "EVT004", "changed_at": "2026-06-08T16:45:00+05:00", "new_stage_id": "WON", "old_stage_id": "PROPOSAL", "changed_by_id": "U10"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (13, '2026-06-24 18:35:16.636805+00', 'error', 'stage_history', 'EVT005', 'битый FK: deal_id D1012 отсутствует', '{"deal_id": "D1012", "event_id": "EVT005", "changed_at": "2026-06-01T08:00:00+05:00", "new_stage_id": "QUALIFICATION", "old_stage_id": "NEW", "changed_by_id": "U10"}');
INSERT INTO main.rejects (reject_id, logged_at, severity, source_table, record_key, reason, raw_data) OVERRIDING SYSTEM VALUE VALUES (14, '2026-06-24 18:35:16.641717+00', 'error', 'production_orders', 'PO004', 'битый FK: deal_id D9999 отсутствует', '{"status": "planned", "deal_id": "D9999", "workshop": "Цех 3", "created_at": "2026-06-10T09:00:00+05:00", "actual_finish_at": null, "planned_finish_at": "2026-06-20", "production_order_id": "PO004"}');


--
-- Data for Name: shipments; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.shipments (shipment_id, deal_id, planned_date, actual_date, status) VALUES ('SHP001', 'D1003', '2026-06-11', '2026-06-13', 'shipped');
INSERT INTO main.shipments (shipment_id, deal_id, planned_date, actual_date, status) VALUES ('SHP002', 'D1005', '2026-06-10', '2026-06-15', 'shipped');
INSERT INTO main.shipments (shipment_id, deal_id, planned_date, actual_date, status) VALUES ('SHP003', 'D1001', '2026-06-14', NULL, 'planned');


--
-- Data for Name: sources; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.sources (source_id, name) VALUES ('phone', 'Phone');
INSERT INTO main.sources (source_id, name) VALUES ('website', 'Website');
INSERT INTO main.sources (source_id, name) VALUES ('avito', 'Avito');
INSERT INTO main.sources (source_id, name) VALUES ('referral', 'Referral');
INSERT INTO main.sources (source_id, name) VALUES ('yandex_direct', 'Yandex Direct');
INSERT INTO main.sources (source_id, name) VALUES ('telegram', 'Telegram');


--
-- Data for Name: stage_history; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT003', 'D1001', 'QUALIFICATION', 'PRODUCTION', '2026-06-07 07:30:00+00', 'U11');
INSERT INTO main.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT002', 'D1001', 'NEW', 'QUALIFICATION', '2026-06-02 06:30:00+00', 'U10');
INSERT INTO main.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT001', 'D1001', NULL, 'NEW', '2026-06-01 04:14:58+00', 'U10');
INSERT INTO main.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT004', 'D1003', 'PROPOSAL', 'WON', '2026-06-08 11:45:00+00', 'U10');


--
-- Data for Name: users; Type: TABLE DATA; Schema: main; Owner: -
--

INSERT INTO main.users (user_id, name, role, active, department, email) VALUES ('U10', 'Иван Петров', 'sales_manager', true, 'Продажи', 'ivan.petrov@example.local');
INSERT INTO main.users (user_id, name, role, active, department, email) VALUES ('U11', 'Анна Соколова', 'sales_manager', true, 'Продажи', 'anna.sokolova@example.local');
INSERT INTO main.users (user_id, name, role, active, department, email) VALUES ('U12', 'Дмитрий Волков', 'sales_manager', false, 'Продажи', 'd.volkov@example.local');
INSERT INTO main.users (user_id, name, role, active, department, email) VALUES ('U20', 'Ольга Маркова', 'production_manager', true, 'Производство', 'olga.markova@example.local');
INSERT INTO main.users (user_id, name, role, active, department, email) VALUES ('U30', 'Сергей Логинов', 'director', true, 'Руководство', 'sergey.loginov@example.local');


--
-- Data for Name: activities; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.activities (activity_id, deal_id, activity_type, direction, subject, responsible_user_id, completed, deadline_at, completed_at) VALUES ('A900', 'D1001', 'call', 'outbound', 'Первичный звонок', 'U10', 'true', '2026-06-03T12:00:00+05:00', '2026-06-03T13:00:00+05:00');
INSERT INTO raw.activities (activity_id, deal_id, activity_type, direction, subject, responsible_user_id, completed, deadline_at, completed_at) VALUES ('A901', 'D1002', 'email', 'outbound', 'КП', 'U11', 'true', '2026-06-04T10:00:00+05:00', '2026-06-04T09:40:00+05:00');
INSERT INTO raw.activities (activity_id, deal_id, activity_type, direction, subject, responsible_user_id, completed, deadline_at, completed_at) VALUES ('A902', 'D1005', 'task', NULL, 'Проверить оплату', 'U11', 'false', '2026-06-07T18:00:00+05:00', NULL);
INSERT INTO raw.activities (activity_id, deal_id, activity_type, direction, subject, responsible_user_id, completed, deadline_at, completed_at) VALUES ('A903', 'D9999', 'call', 'inbound', 'Звонок без сделки', 'U10', 'true', '2026-06-08T10:00:00+05:00', '2026-06-08T10:10:00+05:00');


--
-- Data for Name: companies; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.companies (company_id, name, inn, city, industry, created_at) VALUES ('C200', 'ООО Альфа-Строй', '0278123456', 'Уфа', 'Строительство', '2026-05-20T09:00:00+05:00');
INSERT INTO raw.companies (company_id, name, inn, city, industry, created_at) VALUES ('C201', 'ИП Гараев', '026600112233', 'Стерлитамак', 'Розница', '2026-05-21T10:20:00+05:00');
INSERT INTO raw.companies (company_id, name, inn, city, industry, created_at) VALUES ('C202', 'ООО БашКомплект', '0277009988', 'Уфа', 'Производство', '2026-05-22T11:10:00+05:00');
INSERT INTO raw.companies (company_id, name, inn, city, industry, created_at) VALUES ('C203', 'ООО СеверМонтаж', '1102003344', 'Нефтекамск', 'Монтаж', '2026-05-22T11:40:00+05:00');
INSERT INTO raw.companies (company_id, name, inn, city, industry, created_at) VALUES ('C204', 'ООО ТеплоДом', '0268012345', 'Салават', 'Строительство', '2026-05-25T13:30:00+05:00');
INSERT INTO raw.companies (company_id, name, inn, city, industry, created_at) VALUES ('C205', NULL, NULL, 'Уфа', NULL, '2026-06-01T08:10:00+05:00');


--
-- Data for Name: contacts; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P300', 'C200', 'Алексей Смирнов', '+7 917 000-10-01', 'smirnov@alfa.local', '2026-05-20T09:05:00+05:00');
INSERT INTO raw.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P301', 'C200', 'Марина Кузнецова', '+7 917 000-10-02', NULL, '2026-05-20T09:07:00+05:00');
INSERT INTO raw.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P302', 'C201', 'Рустам Гараев', '+7 927 000-20-01', 'garaev@example.local', '2026-05-21T10:30:00+05:00');
INSERT INTO raw.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P303', 'C202', 'Елена Морозова', '89170003003', 'morozova@bash.local', '2026-05-22T11:15:00+05:00');
INSERT INTO raw.contacts (contact_id, company_id, name, phone, email, created_at) VALUES ('P304', 'C999', 'Контакт без компании', '+7 927 000-40-01', 'orphan@example.local', '2026-05-30T12:00:00+05:00');


--
-- Data for Name: deal_products; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1001', 'PR001', '50', '2200.00', '0');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1001', 'PR003', '20', '1050.00', '5000');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1002', 'PR004', '8', '10500.00', '0');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1003', 'PR002', '80', '2600.00', '0');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1003', 'PR005', '1', '28000.00', '0');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1004', 'PR003', '60', '950.00', '0');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1005', 'PR001', '30', '2200.00', '0');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1005', 'PR005', '1', '26000.00', '0');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D1008', 'PR999', '2', '5000.00', '0');
INSERT INTO raw.deal_products (deal_id, product_id, quantity, unit_price, discount) VALUES ('D9999', 'PR001', '10', '2100.00', '0');


--
-- Data for Name: deals; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1001', 'Панели для склада Альфа', '2026-06-01T09:14:58+05:00', '2026-06-07T12:30:00+05:00', 'PRODUCTION', 'U10', 'C200', 'P300', 'Avito', '150000.00', 'RUB', NULL, NULL, '2026-06-20');
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1002', 'Расчет дверных блоков', '2026-06-02T10:30:00+05:00', '2026-06-06T11:00:00+05:00', 'PROPOSAL', 'U11', 'C201', 'P302', 'avito', '84000.00', 'RUB', NULL, NULL, '2026-06-18');
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1003', 'Монтаж панелей БашКомплект', '2026-06-03T13:10:00+05:00', '2026-06-08T16:45:00+05:00', 'WON', 'U10', 'C202', 'P303', 'yandex_direct', '236000.00', 'RUB', '2026-06-08T16:45:00+05:00', NULL, '2026-06-25');
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1004', 'Поставка каркасов', '2026-06-04T08:20:00+05:00', '2026-06-05T09:05:00+05:00', 'LOST', 'U12', 'C203', NULL, 'website', '57000.00', 'RUB', '2026-06-05T09:05:00+05:00', 'Дорого', NULL);
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1005', 'Срочный заказ ТеплоДом', '2026-06-05T15:00:00+05:00', '2026-06-10T18:10:00+05:00', 'SHIPPED', 'U11', 'C204', NULL, 'AVITO', '92000.00', 'RUB', NULL, NULL, '2026-06-12');
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1006', 'Заявка без компании', '2026-06-06T12:00:00+05:00', '2026-06-06T12:10:00+05:00', 'NEW', 'U10', NULL, 'P304', 'Авито', '35000.00', 'RUB', NULL, NULL, NULL);
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1007', 'Отрицательная сумма тест', '2026-06-07T09:00:00+05:00', '2026-06-07T09:10:00+05:00', 'QUALIFICATION', 'U10', 'C200', 'P301', 'phone', '-12000.00', 'RUB', NULL, NULL, NULL);
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1008', 'Дубль сделки', '2026-06-08T10:00:00+05:00', '2026-06-08T10:05:00+05:00', 'CALCULATION', 'U11', 'C201', 'P302', 'website', '68000.00', 'RUB', NULL, NULL, '2026-06-17');
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1008', 'Дубль сделки измененный', '2026-06-08T10:00:00+05:00', '2026-06-08T10:06:00+05:00', 'CALCULATION', 'U11', 'C201', 'P302', 'Website', '69000.00', 'RUB', NULL, NULL, '2026-06-17');
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1009', 'Выиграна без даты закрытия', '2026-06-09T13:20:00+05:00', '2026-06-12T17:00:00+05:00', 'WON', 'U10', 'C203', NULL, 'referral', '125000.00', 'RUB', NULL, NULL, NULL);
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1010', 'Пустая валюта', '14.06.2026 09:20', '2026-06-14T09:40:00+05:00', 'CONTRACT', 'U11', 'C204', NULL, 'yandex_direct', '174000.00', NULL, NULL, NULL, '2026-06-30');
INSERT INTO raw.deals (deal_id, title, created_at, updated_at, stage_id, manager_id, company_id, contact_id, source, expected_amount, currency, closed_at, lost_reason, custom_deadline) VALUES ('D1011', 'Неизвестная стадия', '2026-06-15T11:30:00+05:00', '2026-06-15T11:30:00+05:00', 'WAIT_CLIENT', NULL, 'C202', 'P303', 'telegram', '54000.00', 'RUB', NULL, NULL, NULL);


--
-- Data for Name: marketing_costs; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.marketing_costs (cost_date, source, campaign, cost_amount, currency) VALUES ('2026-06-01', 'avito', 'avito_panels', '4500.00', 'RUB');
INSERT INTO raw.marketing_costs (cost_date, source, campaign, cost_amount, currency) VALUES ('2026-06-02', 'yandex_direct', 'search_panels_ufa', '8200.00', 'RUB');
INSERT INTO raw.marketing_costs (cost_date, source, campaign, cost_amount, currency) VALUES ('2026-06-03', 'website', 'seo', '0.00', 'RUB');
INSERT INTO raw.marketing_costs (cost_date, source, campaign, cost_amount, currency) VALUES ('2026-06-04', 'AVITO', 'avito_panels', '3900.00', 'RUB');


--
-- Data for Name: payments; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY001', 'D1001', '2026-06-03', '60000.00', 'prepayment', 'paid');
INSERT INTO raw.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY002', 'D1003', '2026-06-08', '236000.00', 'full', 'paid');
INSERT INTO raw.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY003', 'D1005', '2026-06-06', '100000.00', 'prepayment', 'paid');
INSERT INTO raw.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY004', 'D1002', '2026-06-06', '30000.00', 'prepayment', 'pending');
INSERT INTO raw.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY005', 'D9999', '2026-06-09', '15000.00', 'unknown', 'paid');
INSERT INTO raw.payments (payment_id, deal_id, payment_date, amount, payment_type, status) VALUES ('PAY006', 'D1010', '2026/06/15', '-5000.00', 'correction', 'paid');


--
-- Data for Name: pipeline_stages; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'NEW', 'Новая заявка', '10', 'false', 'false');
INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'QUALIFICATION', 'Квалификация', '20', 'false', 'false');
INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'CALCULATION', 'Расчет', '30', 'false', 'false');
INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'PROPOSAL', 'КП отправлено', '40', 'false', 'false');
INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'CONTRACT', 'Договор', '50', 'false', 'false');
INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'PRODUCTION', 'В производстве', '60', 'false', 'false');
INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'SHIPPED', 'Отгружено', '70', 'false', 'false');
INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'WON', 'Успешно', '80', 'true', 'true');
INSERT INTO raw.pipeline_stages (pipeline_id, stage_id, stage_name, sort_order, is_final, is_success) VALUES ('sales-main', 'LOST', 'Проиграно', '90', 'true', 'false');


--
-- Data for Name: production_orders; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.production_orders (production_order_id, deal_id, created_at, planned_finish_at, actual_finish_at, status, workshop) VALUES ('PO001', 'D1001', '2026-06-02T08:00:00+05:00', '2026-06-12', NULL, 'in_progress', 'Цех 1');
INSERT INTO raw.production_orders (production_order_id, deal_id, created_at, planned_finish_at, actual_finish_at, status, workshop) VALUES ('PO002', 'D1003', '2026-06-05T09:00:00+05:00', '2026-06-10', '2026-06-12', 'done', 'Цех 2');
INSERT INTO raw.production_orders (production_order_id, deal_id, created_at, planned_finish_at, actual_finish_at, status, workshop) VALUES ('PO003', 'D1005', '2026-06-01T09:00:00+05:00', '2026-06-08', '2026-06-14', 'done', 'Цех 1');
INSERT INTO raw.production_orders (production_order_id, deal_id, created_at, planned_finish_at, actual_finish_at, status, workshop) VALUES ('PO004', 'D9999', '2026-06-10T09:00:00+05:00', '2026-06-20', NULL, 'planned', 'Цех 3');


--
-- Data for Name: products; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR001', 'PNL-100', 'Панель стеновая 100 мм', 'Панели', '1450.00', 'true');
INSERT INTO raw.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR002', 'PNL-150', 'Панель стеновая 150 мм', 'Панели', '1880.00', 'true');
INSERT INTO raw.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR003', 'FRM-020', 'Каркас монтажный', 'Каркасы', '720.00', 'true');
INSERT INTO raw.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR004', 'DRV-001', 'Дверной блок', 'Двери', '5200.00', 'true');
INSERT INTO raw.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR005', 'SRV-INST', 'Монтаж', 'Услуги', '0.00', 'true');
INSERT INTO raw.products (product_id, sku, name, category, cost_price, is_active) VALUES ('PR006', 'PNL-100', 'Панель стеновая 100 мм дубль', 'Панели', '1490.00', 'true');


--
-- Data for Name: shipments; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.shipments (shipment_id, deal_id, planned_date, actual_date, status) VALUES ('SHP001', 'D1003', '2026-06-11', '2026-06-13', 'shipped');
INSERT INTO raw.shipments (shipment_id, deal_id, planned_date, actual_date, status) VALUES ('SHP002', 'D1005', '2026-06-10', '2026-06-15', 'shipped');
INSERT INTO raw.shipments (shipment_id, deal_id, planned_date, actual_date, status) VALUES ('SHP003', 'D1001', '2026-06-14', NULL, 'planned');


--
-- Data for Name: stage_history; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT001', 'D1001', NULL, 'NEW', '2026-06-01T09:14:58+05:00', 'U10');
INSERT INTO raw.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT002', 'D1001', 'NEW', 'QUALIFICATION', '2026-06-02T11:30:00+05:00', 'U10');
INSERT INTO raw.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT003', 'D1001', 'QUALIFICATION', 'PRODUCTION', '2026-06-07T12:30:00+05:00', 'U11');
INSERT INTO raw.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT004', 'D1003', 'PROPOSAL', 'WON', '2026-06-08T16:45:00+05:00', 'U10');
INSERT INTO raw.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT004', 'D1003', 'PROPOSAL', 'WON', '2026-06-08T16:45:00+05:00', 'U10');
INSERT INTO raw.stage_history (event_id, deal_id, old_stage_id, new_stage_id, changed_at, changed_by_id) VALUES ('EVT005', 'D1012', 'NEW', 'QUALIFICATION', '2026-06-01T08:00:00+05:00', 'U10');


--
-- Data for Name: users; Type: TABLE DATA; Schema: raw; Owner: -
--

INSERT INTO raw.users (user_id, name, role, active, department, email) VALUES ('U10', 'Иван Петров', 'sales_manager', 'true', 'Продажи', 'ivan.petrov@example.local');
INSERT INTO raw.users (user_id, name, role, active, department, email) VALUES ('U11', 'Анна Соколова', 'sales_manager', 'true', 'Продажи', 'anna.sokolova@example.local');
INSERT INTO raw.users (user_id, name, role, active, department, email) VALUES ('U12', 'Дмитрий Волков', 'sales_manager', 'false', 'Продажи', 'd.volkov@example.local');
INSERT INTO raw.users (user_id, name, role, active, department, email) VALUES ('U20', 'Ольга Маркова', 'production_manager', 'true', 'Производство', 'olga.markova@example.local');
INSERT INTO raw.users (user_id, name, role, active, department, email) VALUES ('U30', 'Сергей Логинов', 'director', 'true', 'Руководство', 'sergey.loginov@example.local');


--
-- Name: marketing_costs_cost_id_seq; Type: SEQUENCE SET; Schema: main; Owner: -
--

SELECT pg_catalog.setval('main.marketing_costs_cost_id_seq', 4, true);


--
-- Name: rejects_reject_id_seq; Type: SEQUENCE SET; Schema: main; Owner: -
--

SELECT pg_catalog.setval('main.rejects_reject_id_seq', 14, true);


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (activity_id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (company_id);


--
-- Name: contacts contacts_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.contacts
    ADD CONSTRAINT contacts_pkey PRIMARY KEY (contact_id);


--
-- Name: deal_products deal_products_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deal_products
    ADD CONSTRAINT deal_products_pkey PRIMARY KEY (deal_id, product_id);


--
-- Name: deals deals_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deals
    ADD CONSTRAINT deals_pkey PRIMARY KEY (deal_id);


--
-- Name: marketing_costs marketing_costs_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.marketing_costs
    ADD CONSTRAINT marketing_costs_pkey PRIMARY KEY (cost_id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (payment_id);


--
-- Name: pipeline_stages pipeline_stages_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.pipeline_stages
    ADD CONSTRAINT pipeline_stages_pkey PRIMARY KEY (stage_id);


--
-- Name: production_orders production_orders_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.production_orders
    ADD CONSTRAINT production_orders_pkey PRIMARY KEY (production_order_id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- Name: rejects rejects_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.rejects
    ADD CONSTRAINT rejects_pkey PRIMARY KEY (reject_id);


--
-- Name: shipments shipments_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.shipments
    ADD CONSTRAINT shipments_pkey PRIMARY KEY (shipment_id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (source_id);


--
-- Name: stage_history stage_history_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.stage_history
    ADD CONSTRAINT stage_history_pkey PRIMARY KEY (event_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: idx_activities_completed_at; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_activities_completed_at ON main.activities USING btree (completed_at);


--
-- Name: idx_activities_deal; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_activities_deal ON main.activities USING btree (deal_id);


--
-- Name: idx_activities_user; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_activities_user ON main.activities USING btree (responsible_user_id);


--
-- Name: idx_contacts_company; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_contacts_company ON main.contacts USING btree (company_id);


--
-- Name: idx_deal_products_product; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_deal_products_product ON main.deal_products USING btree (product_id);


--
-- Name: idx_deals_company; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_deals_company ON main.deals USING btree (company_id);


--
-- Name: idx_deals_contact; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_deals_contact ON main.deals USING btree (contact_id);


--
-- Name: idx_deals_created_at; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_deals_created_at ON main.deals USING btree (created_at);


--
-- Name: idx_deals_manager; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_deals_manager ON main.deals USING btree (manager_id);


--
-- Name: idx_deals_source; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_deals_source ON main.deals USING btree (source_id);


--
-- Name: idx_deals_stage; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_deals_stage ON main.deals USING btree (stage_id);


--
-- Name: idx_marketing_costs_src_dt; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_marketing_costs_src_dt ON main.marketing_costs USING btree (source_id, cost_date);


--
-- Name: idx_payments_deal; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_payments_deal ON main.payments USING btree (deal_id);


--
-- Name: idx_payments_status; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_payments_status ON main.payments USING btree (status);


--
-- Name: idx_production_orders_deal; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_production_orders_deal ON main.production_orders USING btree (deal_id);


--
-- Name: idx_shipments_deal; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_shipments_deal ON main.shipments USING btree (deal_id);


--
-- Name: idx_stage_history_deal; Type: INDEX; Schema: main; Owner: -
--

CREATE INDEX idx_stage_history_deal ON main.stage_history USING btree (deal_id);


--
-- Name: activities activities_deal_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.activities
    ADD CONSTRAINT activities_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES main.deals(deal_id);


--
-- Name: activities activities_responsible_user_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.activities
    ADD CONSTRAINT activities_responsible_user_id_fkey FOREIGN KEY (responsible_user_id) REFERENCES main.users(user_id);


--
-- Name: contacts contacts_company_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.contacts
    ADD CONSTRAINT contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES main.companies(company_id);


--
-- Name: deal_products deal_products_deal_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deal_products
    ADD CONSTRAINT deal_products_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES main.deals(deal_id);


--
-- Name: deal_products deal_products_product_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deal_products
    ADD CONSTRAINT deal_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES main.products(product_id);


--
-- Name: deals deals_company_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deals
    ADD CONSTRAINT deals_company_id_fkey FOREIGN KEY (company_id) REFERENCES main.companies(company_id);


--
-- Name: deals deals_contact_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deals
    ADD CONSTRAINT deals_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES main.contacts(contact_id);


--
-- Name: deals deals_manager_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deals
    ADD CONSTRAINT deals_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES main.users(user_id);


--
-- Name: deals deals_source_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deals
    ADD CONSTRAINT deals_source_id_fkey FOREIGN KEY (source_id) REFERENCES main.sources(source_id);


--
-- Name: deals deals_stage_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.deals
    ADD CONSTRAINT deals_stage_id_fkey FOREIGN KEY (stage_id) REFERENCES main.pipeline_stages(stage_id);


--
-- Name: marketing_costs marketing_costs_source_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.marketing_costs
    ADD CONSTRAINT marketing_costs_source_id_fkey FOREIGN KEY (source_id) REFERENCES main.sources(source_id);


--
-- Name: payments payments_deal_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.payments
    ADD CONSTRAINT payments_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES main.deals(deal_id);


--
-- Name: production_orders production_orders_deal_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.production_orders
    ADD CONSTRAINT production_orders_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES main.deals(deal_id);


--
-- Name: shipments shipments_deal_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.shipments
    ADD CONSTRAINT shipments_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES main.deals(deal_id);


--
-- Name: stage_history stage_history_changed_by_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.stage_history
    ADD CONSTRAINT stage_history_changed_by_id_fkey FOREIGN KEY (changed_by_id) REFERENCES main.users(user_id);


--
-- Name: stage_history stage_history_deal_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.stage_history
    ADD CONSTRAINT stage_history_deal_id_fkey FOREIGN KEY (deal_id) REFERENCES main.deals(deal_id);


--
-- Name: stage_history stage_history_new_stage_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.stage_history
    ADD CONSTRAINT stage_history_new_stage_id_fkey FOREIGN KEY (new_stage_id) REFERENCES main.pipeline_stages(stage_id);


--
-- Name: stage_history stage_history_old_stage_id_fkey; Type: FK CONSTRAINT; Schema: main; Owner: -
--

ALTER TABLE ONLY main.stage_history
    ADD CONSTRAINT stage_history_old_stage_id_fkey FOREIGN KEY (old_stage_id) REFERENCES main.pipeline_stages(stage_id);


--
-- PostgreSQL database dump complete
--

\unrestrict cvPcRcUgvgbiSMms7rwRd2mMTCZOvMJcbbHGvbDR7QXznKyXUNHzsk3iDBnMxXD

