-- ============================================================================
-- Аналитические отчёты поверх нормализованного слоя main.
-- ============================================================================
-- Соглашения, общие для отчётов:
--   * Выручка по позициям: quantity * unit_price - discount (discount — абсолютная
--     сумма скидки на позицию). Себестоимость: quantity * products.cost_price.
--     Маржа = выручка - себестоимость. Экономика считается по deal_products, т.е.
--     только для сделок, где есть позиции (D1001–D1005); у остальных revenue=0.
--   * «Оплачено» в дебиторке = payments со status='paid' (pending не зачитывается).
--   * Точка отсчёта для дат — current_date (в БД = 2026-06-24).
--   * Стадия UNKNOWN — служебная (битые/неизвестные стадии), участвует в воронке.


-- ============================================================================
-- 1. Текущая воронка: количество и сумма сделок по стадиям
-- ============================================================================
SELECT ps.sort_order,
       ps.stage_id,
       ps.stage_name,
       count(d.deal_id)                  AS deals_count,
       coalesce(sum(d.expected_amount), 0) AS amount_total
FROM main.pipeline_stages ps
         LEFT JOIN main.deals d ON d.stage_id = ps.stage_id
GROUP BY ps.sort_order, ps.stage_id, ps.stage_name
ORDER BY ps.sort_order;


-- ============================================================================
-- 2. Продажи и маржа по менеджерам
-- ============================================================================
-- По всем сделкам менеджера (без фильтра по стадии — объём данных мал). Чтобы
-- считать только реализованные продажи, добавить условие на is_success стадии.
WITH deal_econ AS (
    SELECT dp.deal_id,
           sum(dp.quantity * dp.unit_price - dp.discount) AS revenue,
           sum(dp.quantity * p.cost_price)                AS cost
    FROM main.deal_products dp
             JOIN main.products p USING (product_id)
    GROUP BY dp.deal_id
)
SELECT u.user_id,
       u.name,
       count(d.deal_id)                                  AS deals_count,
       coalesce(sum(e.revenue), 0)                       AS revenue,
       coalesce(sum(e.revenue - e.cost), 0)              AS margin,
       round(coalesce(sum(e.revenue - e.cost), 0)
                 / nullif(sum(e.revenue), 0) * 100, 1)   AS margin_pct
FROM main.users u
         JOIN main.deals d ON d.manager_id = u.user_id
         LEFT JOIN deal_econ e ON e.deal_id = d.deal_id
GROUP BY u.user_id, u.name
ORDER BY revenue DESC;


-- ============================================================================
-- 3. Дебиторка: сумма сделки, оплаты, остаток
-- ============================================================================
-- Остаток = сумма сделки (expected_amount) − оплаченные платежи. Отрицательный
-- остаток = переплата; положительный pending показан отдельно для контекста.
WITH pay AS (
    SELECT deal_id,
           sum(amount) FILTER (WHERE status = 'paid')    AS paid,
           sum(amount) FILTER (WHERE status = 'pending') AS pending
    FROM main.payments
    GROUP BY deal_id
)
SELECT d.deal_id,
       d.stage_id,
       d.expected_amount,
       coalesce(p.paid, 0)                          AS paid,
       coalesce(p.pending, 0)                       AS pending,
       coalesce(d.expected_amount, 0) - coalesce(p.paid, 0) AS remaining
FROM main.deals d
         LEFT JOIN pay p ON p.deal_id = d.deal_id
WHERE d.expected_amount IS NOT NULL
   OR p.deal_id IS NOT NULL
ORDER BY remaining DESC;


-- ============================================================================
-- 4. Сделки с задержкой производства больше 5 дней
-- ============================================================================
-- Задержка = (факт завершения, иначе сегодня) − план завершения. Покрывает и
-- завершённые с опозданием, и ещё не завершённые, но уже просроченные заказы.
SELECT po.production_order_id,
       po.deal_id,
       po.workshop,
       po.status,
       po.planned_finish_at,
       po.actual_finish_at,
       coalesce(po.actual_finish_at, current_date) - po.planned_finish_at AS delay_days
FROM main.production_orders po
WHERE coalesce(po.actual_finish_at, current_date) - po.planned_finish_at > 5
ORDER BY delay_days DESC;


-- ============================================================================
-- 5. Сделки без активности за последние N дней
-- ============================================================================
-- N = 7 (изменить в INTERVAL ниже). Активность считается по последней дате
-- coalesce(completed_at, deadline_at). Финальные стадии (is_final) исключены —
-- закрытые сделки в догоне не нуждаются. NULL = активностей не было вовсе.
WITH last_act AS (
    SELECT deal_id, max(coalesce(completed_at, deadline_at)) AS last_activity_at
    FROM main.activities
    GROUP BY deal_id
)
SELECT d.deal_id,
       d.stage_id,
       d.manager_id,
       a.last_activity_at
FROM main.deals d
         JOIN main.pipeline_stages ps ON ps.stage_id = d.stage_id
         LEFT JOIN last_act a ON a.deal_id = d.deal_id
WHERE ps.is_final = false
  AND (a.last_activity_at IS NULL
       OR a.last_activity_at < current_date - INTERVAL '7 days')
ORDER BY a.last_activity_at NULLS FIRST;


-- ============================================================================
-- 6. Источники заявок: выручка и маржа по источникам
-- ============================================================================
-- Заявки (deals_count) и экономика по позициям сводятся с расходами на маркетинг
-- (marketing_costs) по источнику. net = маржа − расходы на маркетинг.
WITH deal_econ AS (
    SELECT dp.deal_id,
           sum(dp.quantity * dp.unit_price - dp.discount) AS revenue,
           sum(dp.quantity * p.cost_price)                AS cost
    FROM main.deal_products dp
             JOIN main.products p USING (product_id)
    GROUP BY dp.deal_id
),
     by_source AS (
         SELECT d.source_id,
                count(d.deal_id)                     AS deals_count,
                coalesce(sum(e.revenue), 0)          AS revenue,
                coalesce(sum(e.revenue - e.cost), 0) AS margin
         FROM main.deals d
                  LEFT JOIN deal_econ e ON e.deal_id = d.deal_id
         WHERE d.source_id IS NOT NULL
         GROUP BY d.source_id
     ),
     mkt AS (
         SELECT source_id, sum(cost_amount) AS marketing_cost
         FROM main.marketing_costs
         GROUP BY source_id
     )
SELECT s.source_id,
       s.name,
       coalesce(bs.deals_count, 0)              AS deals_count,
       coalesce(bs.revenue, 0)                  AS revenue,
       coalesce(bs.margin, 0)                   AS margin,
       coalesce(m.marketing_cost, 0)            AS marketing_cost,
       coalesce(bs.margin, 0) - coalesce(m.marketing_cost, 0) AS net
FROM main.sources s
         LEFT JOIN by_source bs ON bs.source_id = s.source_id
         LEFT JOIN mkt m ON m.source_id = s.source_id
ORDER BY revenue DESC, deals_count DESC;


-- ============================================================================
-- 7. Список проблем данных
-- ============================================================================
-- Сводка по журналу отбраковки (main.rejects), заполняемому при нормализации.

-- 7a. Сводка по таблицам и серьёзности.
SELECT severity, source_table, count(*) AS cnt
FROM main.rejects
GROUP BY severity, source_table
ORDER BY severity, source_table;

-- 7b. Детализация.
SELECT severity, source_table, record_key, reason
FROM main.rejects
ORDER BY severity, source_table, record_key;